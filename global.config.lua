--
-- The global lumail configuration-file
--
-----------------------------------------------------------------------------
-----------------------------------------------------------------------------
--
-- This is global configuration file for the lumail command-line email
-- client, which is configured solely by Lua.
--
-- The client will load two files at startup if they exist:
--
--  1.  The global configuration-file:
--
--      * /etc/lumail2/lumail2.lua
--      * /etc/lumail/lumail.lua
--
--  2.  The per-user configuration file, which is one of:
--
--      * $XDG_CONFIG_HOME/lumail/lumail.lua
--      * $XDG_CONFIG_HOME/lumail/config.lua
--      * $XDG_CONFIG_HOME/lumail/$HOSTNAME.lua
--
--      * ~/.config/lumail/lumail.lua
--      * ~/.config/lumail/config.lua
--      * ~/.config/lumail/$HOSTNAME.lua
--
--      * ~/.lumail/lumail.lua
--      * ~/.lumail/config.lua
--      * ~/.lumail/$HOSTNAME.lua
--
-- The expectation is that you will NOT EDIT this file, instead
-- you will place your own configuration in one of those locations.
--
--
-- CONFIGURATION
----------------
--
-- While you may edit this file it is recommended you do not, instead you
-- should copy the sample file `user.config.lua` into one of the locations
-- documented above, and then edit it.
--
-- If the above is too complex, or you're unsure, then this is safe:
--
--     mkdir -p ~/.lumail/lumail.lua
--     cp user.config.lua ~/.lumail/lumail.lua
--
-- Or :
--
--     mkdir -p ~/.lumail/
--     cp user.config.lua ~/.lumail/$(hostname --fqdn).lua
--
-- This will make upgrading less painful.
--
--
-- DOCUMENTATION
----------------
--
-- For reference to the lumail2 objects please see the API documentation
-- included in the file `API.md`, or browsable online at:
--
--    http://lumail.org/api/
--
--
-- Steve
-- --
--
--


--
-- Load libraries
--
Fun = require "functional"
Life = require "life"
Stack = require "stack"
keymap = require "keymap"
Progress = require "progress_bar"
Threader = require "threader"

--
-- Load libraries which directly poke functions into the global
-- namespace (bad but useful).
--
SU = require "string_utilities"
TU = require "table_utilities"

--
-- GPG support will only be present if the `mimegpg`-binary is
-- present upon the users' PATH.
--
GPG = nil
if string.path "mimegpg" then
  GPG = require "gpg"
end
Panel:append(GPG)


--
-- Setup a cache for objects.
--
cache = Cache.new()


--
-- If the user changes the index-limit we'll try to keep the same
-- maildir selected.  We do that by caching the old value here.
--
local prev_maildir = nil


--
-- This contains the messages which are currently visible.
--
-- When the user selects a Maildir, or changes the active selection
-- via the `index.limit` setting, then this set of messages will be
-- updated.
--

local global_msgs = nil


--
-- Define some utility functions
--
-----------------------------------------------------------------------------
-----------------------------------------------------------------------------


--
-- Helper to write error messages to stderr & the panel.
--
function on_error (msg)
  error_msg(msg)
  io.stderr:write(msg)
end

--
--- Append an error message to the panel.
--
-- An error indicates that an operation wasn't completed correctly.
--
function error_msg (msg)
  Panel:append("$[RED|BOLD]ERROR:$[WHITE] " .. msg)
end

--
--- Append an warning message to the panel.
--
-- A warning indicates that an operation was completed correctly but not
-- in the intended way. E.g. The deletion of all messages succeeded but
-- there weren't any messages.
--
function warning_msg (msg)
  Panel:append("$[RED]WARNING:$[WHITE] " .. msg)
end

--
--- Append an info message to the panel.
--
-- An info is printed if information should be presented to the user, which
-- he hasn't requested or as feedback on a operation he provoked.
-- E.g. The time mail sorting took. That the user aborted the sending of a message.
--
function info_msg (msg)
  Panel:append("$[YELLOW]INFO:$[WHITE] " .. msg)
end


--
-- Return the program which can be used to view/show a file which has
-- the specified MIME-type.
--
-- For example if the input is "image/jpeg" we'd expect this function
-- to return something like "display %s".
--
-- The caller is expected to replace "%s" with the name of the file
-- which is to be viewed.
--
-- Reference: https://en.wikipedia.org/wiki/Mailcap
--
function get_mime_viewer (mime_type)

  --
  -- The default viewer.
  --
  local ret = "less %s"

  -- The file we lookup values in.
  local filename = Config.get_with_default("global.mime-file", "/etc/mailcap")

  -- Return the default value if the input file doesn't exist.
  if not File:exists(filename) then
    return ret
  end

  -- HTML will probably have a graphical helper
  -- we'll skip this for now.  TODO: Fixme
  if mime_type == "text/html" then
    return ret
  end

  local f = io.input(filename)
  local line = nil

  --
  -- Remember wildcard match
  --
  local wildcard_exec

  for line in io.lines() do

    --
    -- Split the line by ";", and if that worked
    --
    local entries = string.split(line, ";")
    if #entries >= 2 then

      --
      -- The values
      --
      local type = string.trim(entries[1])
      local exec = string.trim(entries[2])

      --
      -- Wildcards like "image/*" are used if no other match was found.
      --
      if type == mime_type then
        f:close()
        return exec
      elseif type:sub(-2) == "/*" and type:sub(1, -3) == mime_type:split "/"[1] then
        wildcard_exec = exec
      end
    end
  end

  f:close()

  --
  -- We didn't find an obvious match, return wildcard match or default.
  --
  return wildcard_exec or ret
end


--
-- Helper function to ensure that if anything calls `os.exit`
-- we reset the screen neatly, etc.
--
function os.exit (code)
  if type(on_exit) == "function" then
    on_exit()
  end


  --
  -- Get the cache-prefix
  --
  local dir = Config:get "cache.prefix"
  if dir then
    --
    -- Ensure the directory exists.
    --
    if not Directory:exists(dir) then
      Directory:mkdir(dir)
    end

    --
    -- Now write the cache beneath it.
    --
    local file = dir .. "/" .. Config:get "global.version"
    cache:save(file)
  end

  --
  -- Empty the cache, to avoid leaks, if it exists.
  --
  -- (Why wouldn't it?)
  --
  if cache then
    cache:empty()
  end

  --
  -- Finally exit.
  --
  Screen:exit()
end


--
-- Given a line add the given colour to it - removing any
-- existing colour, unless that colour is "UNREAD".
--
-- For example an input line such as "Bob" will be made red
-- like so:
--
--      local out = colour_line( "Bob", "red" )
--      print( out )
--
-- The result is:
--
--      $[red]Bob
--
-- If the input was "$[blue]Bob" then the blue would be stripped and
-- updated, but if the input is "$[UNREAD]Bob" it will be left alone.
--
function colour_line (line, colour)
  local c, r = string.match(line, "^%$%[([a-zA-Z]*)%](.*)$")
  if c and r then
    c = c:lower()
    if c ~= "unread" then
      line = "$[" .. colour .. "]" .. r
    end
    return line
  end
  line = "$[" .. colour .. "]" .. line
  return line
end


--
-- Return the contents of the named file.
--
function File.contents (path)
  local f = io.open(path, "rb")
  if f then
    local content = f:read "*all"
    f:close()
    return content
  else
    return ("Error reading file: " .. file)
  end
end


--
-- If this function is defined it will be invoked any time
-- a configuration-key has its value changed.
--
-- The single argument will be the name of the key which has
-- been updated - the value can be retrieved via Config:get, but
-- remember that the value might be a string, an integer, or a table.
--
function Config.key_changed (name, old)

  --
  -- Obsolete setting?
  --
  if name == "message.cache" then
    warning_msg "The configuration key 'message.cache' is obsolete!"
    return
  end

  --
  -- If the cache-prefix has changed load the cache
  --
  if name == "cache.prefix" then
    local cache_prefix = Config:get "cache.prefix"
    local file = cache_prefix .. "/" .. Config:get "global.version"
    if file and File:exists(file) then
      info_msg("Loading cache " .. file)
      cache:load(file)
    end
    return
  end

  --
  -- If index.limit changes then we must flush our message cache.
  --
  if name == "index.limit" then
    global_msgs = nil
    return
  end

  --
  -- If the index-limit changes then we'll try to preserve the
  -- previously selected maildir.
  --
  if name == "maildir.limit" then

    -- Get the current index, if that fails we're done
    local x = Config.get_with_default("maildir.current", -1)
    if x == -1 then
      return
    end

    -- Get all known maildirs - filtered by the limit which was
    -- PREVIOUSLY in place, using the value of old.
    local m = maildirs(old)

    -- Now we can find the folder at the point
    if m and (x + 1 <= #m) then
      prev_maildir = m[x + 1]:path()
    end
  end


  --
  -- If the sorting method has changed we need to resort our messages.
  --
  -- NOTE: We explicitly avoid re-reading the maildir, so we're
  -- just changing the order of the existing messages not refreshing
  -- them 100%.
  --
  if name == "index.sort" then
    global_msgs = sort_messages(global_msgs)
    return
  end
end


--
-- Given a key toggle the setting of that key from
-- true -> false, and vice-versa.
--
function Config.toggle (name)

  local current = Config:get(name)
  if current == nil then
    current = 0
  end

  if (current == 1) or (current == "1") then
    current = 0
  else
    current = 1
  end

  Config:set(name, current)
end


--
-- Configuration values are retrieved/set via Config:get() and Config:set().
--
-- There is no built-in way of getting a value with a default, so we
-- define a helper here to do the necessary thing.
--
function Config.get_with_default (key, default)
  local value = Config:get(key)
  if value == nil then
    value = default
  end

  return value
end


--
-- Change the global mode, preserving the previous one
-- on a stack, to allow undoing.
--
do
  local mode_stack = Stack.new()

  -- Change to a new mode
  function change_mode (new_mode)

    -- Get the current mode
    local current = Config:get "global.mode"

    -- No change?  Return
    if current == new_mode then
      return
    end

    -- Record the previous mode, and change.
    mode_stack:push(current)
    Config:set("global.mode", new_mode)
  end

  -- Restore to the previous mode
  function previous_mode ()
    local prev = mode_stack:pop()
    if prev == nil then
      prev = "maildir"
    end
    Config:set("global.mode", prev)
  end
end


--
-- Get the current message.  If the user is in message-mode then
-- this is literally the currently selected message.
--
-- If the user is in index-mode then this is the message under the
-- current selection
--
function Message.at_point ()

  local mode = Config:get "global.mode"

  if mode == "message" then
    return (Global:current_message())
  end
  if mode == "index" then

    -- Get the list of messages, and the current offset
    -- that'll let us find the message.
    local offset = Config.get_with_default("index.current", 0)
    local msgs = get_messages()

    if not msgs then
      error_msg "There are no messages!"
      return nil
    end
    return msgs[offset + 1]
  end

  return nil
end

--
-- Count the number of attachments a message has.
--
function Message.count_attachments (msg)

  local parts = mimeparts2table(msg)
  local count = 0

  for i, o in ipairs(parts) do
    if o['filename'] ~= nil and o['filename'] ~= "" then
      count = count + 1
    end
  end

  return count
end


--
-- Get the creation-date of the message, in seconds past the epoch.
--
-- We can cheat here by looking at the filename.  If that fails then
-- we parse the message by looking for the `Delivery-Date` and `Date`
-- headers.
--
function Message:to_ctime ()
  local p = self:path()

  --
  -- Lookup value in the cache, if we can.
  --
  if cache:get(p .. "to_ctime") then
    return (tonumber(cache:get(p .. "to_ctime")))
  end


  --
  -- Look for the ctime in the message filename.
  --
  local f = File:basename(p)
  local num = string.match(f, "^([0-9]+)%.")
  if num then
    -- Set the value in the cache, and return it.
    cache:set(p .. "to_ctime", num)
    return (tonumber(num))
  end

  --
  -- Otherwise parse the Received-Date + Date headers.
  --
  local seconds = self:ctime()

  -- Set the value in the cache, and return it.
  cache:set(p .. "to_ctime", seconds)
  return seconds
end


--
-- Sort the specified table of message-objects.
--
-- We expect that users might wish to define their own sorting methods
-- so this function is intentionally open:
--
--   Lookup the value of the sort-method (via `index.sort`).
--
--   Call the function compare_by_$METHOD to do the comparison.
--
-- If there is no `compare_by_foo` method then we return the table
-- unsorted.
--
function sort_messages (input)
  local method = Config:get "index.sort"
  if method == "none" then
    return input
  end

  --
  -- Sorting a non-table?  That's a failure
  --
  if type(input) ~= "table" then
    return input
  end

  -- this global list is used in index_view to indent each message
  threads_indentation = {}

  --
  -- Handle thread sorting and indentation
  --
  if method == "threads" then
    local t_start = os.time()
    local res = {}
    res, threads_indentation = Threader.thread(input)
    local t_end = os.time()
    Panel:append("Sort method $[WHITE|BOLD]" .. method .. "$[WHITE] took $[WHITE|BOLD]" .. (t_end - t_start) .. "$[WHITE] seconds with " .. "$[WHITE|BOLD]" .. #input .. "$[WHITE] messages")

    return res
  else
    --
    -- If the method is `file` we'll invoke `compare_by_file`, etc.
    --
    local func = "compare_by_" .. method

    --
    -- Is the desired sort-method defined?
    --
    if _G[func] and (type(_G[func]) == "function") then

      --
      -- If there is record the time, do the sort, and record the time again
      --
      local t_start = os.time()
      table.sort(input, _G[func])
      local t_end = os.time()

      -- Now show how long it took.
      Panel:append("Sort method $[WHITE|BOLD]" .. method .. "$[WHITE] took $[WHITE|BOLD]" .. (t_end - t_start) .. "$[WHITE] seconds with " .. "$[WHITE|BOLD]" .. #input .. "$[WHITE] messages")

    else
      --
      -- There is no defined `compare_by_$foo` function.
      --
      error_msg("Unknown sorting method " .. method)
    end
  end
  return input
end


--
-- Compare two messages, based upon the modification-time of their filenames.
--
-- We make sure we compare numbers, as these might have been cached and
-- saved as strings.
--
-- Invoked when `index.sort` is set to `file`.
--
-- NOTE: We use mtime here, rather than ctime, as the former won't change
-- when a file is renamed. See #251 for details.
--
function compare_by_file (a, b)
  Progress:step "Sorting messages"


  local a_path = a:path()
  local a_time = cache:get("compare_by_file" .. a_path)

  if a_time == nil then
    a_time = File:stat(a_path)['mtime']
    cache:set("compare_by_file" .. a_path, a_time)
  end


  local b_path = b:path()
  local b_time = cache:get("compare_by_file" .. b_path)

  if b_time == nil then
    b_time = File:stat(b_path)['mtime']
    cache:set("compare_by_file" .. b_path, b_time)
  end

  return tonumber(a_time) < tonumber(b_time)
end


--
-- Compare two messages, based upon their date-headers.
--
-- We make sure we compare numbers, as these might have been cached and
-- saved as strings.
--
-- Invoked when `index.sort` is set to `date`.
--
function compare_by_date (a, b)
  Progress:step "Sorting messages"


  local a_path = a:path()
  local a_date = cache:get("compare_by_date" .. a_path)

  if a_date == nil then
    a_date = a:to_ctime()
    cache:set("compare_by_date" .. a_path, a_date)
  end

  local b_path = b:path()
  local b_date = cache:get("compare_by_date" .. b_path)

  if b_date == nil then
    b_date = b:to_ctime()
    cache:set("compare_by_date" .. b_path, b_date)
  end

  --
  -- Actually compare
  --
  return tonumber(a_date) < tonumber(b_date)
end

--
-- Compare two messages, based upon their From-headers.
--
-- Invoked when `index.sort` is set to `from`.
--
function compare_by_from (a, b)
  Progress:step "Sorting messages"

  local a_path = a:path()
  local a_from = cache:get("compare_by_from" .. a_path)

  if a_from == nil then
    a_from = a:header "From":lower()
    cache:set("compare_by_from" .. a_path, a_from)
  end

  local b_path = b:path()
  local b_from = cache:get("compare_by_from" .. b_path)

  if b_from == nil then
    b_from = b:header "From":lower()
    cache:set("compare_by_from" .. b_path, b_from)
  end
  return (a_from < b_from)
end

--
-- Compare two messages, based upon subject-header.
--
-- Invoked when `index.sort` is set to `subject`.
--
function compare_by_subject (a, b)
  Progress:step "Sorting messages"

  local a_path = a:path()
  local a_sub = cache:get("compare_by_subject" .. a_path)

  if a_sub == nil then
    a_sub = a:header "Subject":lower()
    cache:set("compare_by_subject" .. a_path, a_sub)
  end

  local b_path = b:path()
  local b_sub = cache:get("compare_by_subject" .. b_path)

  if b_sub == nil then
    b_sub = b:header "Subject":lower()
    cache:set("compare_by_subject" .. b_path, b_sub)
  end
  return (a_sub < b_sub)
end


--
-- Utility method to change the sorting method, and flush our caches
--
function sorting_method (value)
  if value then
    Config:set("index.sort", value)
  end
  return (Config:get "index.sort")
end


--
-- Return our maildirs
--
function maildirs (limit)

  --
  -- Get all maildirs
  --
  local all = Global:maildirs()

  --
  -- The return value.
  --
  local ret = {}

  --
  -- Filter them according to the limit - if we don't have a limit
  -- then use the global-one.
  --
  if not limit then
    limit = Config.get_with_default("maildir.limit", "all")
  end

  if limit == "all" then
    --
    -- All
    --
    for i, o in ipairs(all) do
      table.insert(ret, o)
    end
  elseif limit == "new" then
    --
    -- New
    --
    for i, o in ipairs(all) do
      local unread = o:unread_messages()
      if unread > 0 then
        table.insert(ret, o)
      end
    end
  elseif limit == "today" then
    --
    -- Today
    --
    local time = os.time()
    local today = time - (60 * 60 * 24)

    for i, o in ipairs(all) do
      -- get modification-time of the maildir
      local mtime = o:mtime()

      -- if it was within the past 24 hours then add it
      if mtime > today then
        table.insert(ret, o)
      end
    end
  else
    --
    -- "Pattern"
    --
    for i, o in ipairs(all) do
      local fmt = o:format()
      if string.find(fmt, limit) then
        table.insert(ret, o)
      end
    end
  end

  --
  -- Sort them, case-insensitively
  --
  table.sort(ret, function (a, b)
      return a:path():lower() < b:path():lower()
    end)

  Config:set("maildir.max", #ret)
  return ret
end

--
-- Return the appropriate set of messages:
--
--  1.  Get all messages.
--
--  2.  Apply our index.limit.
--
--  3.  Sort them.
--
function get_messages ()

  --
  -- If we have a cached selection then we'll return it
  --
  if global_msgs then
    return global_msgs
  end

  global_msgs = {}

  --
  -- Otherwise fetch all the current messages.
  --
  local msgs = Global:current_messages()

  --
  -- How many steps do we expect to update for our progress-bar?
  --
  local steps = math.floor(#msgs / Screen:width())
  if steps == 0 then
    steps = 1
  end

  --
  -- Now apply any limit which should be present.
  --
  -- Valid limits are:
  --
  --   All      -> All messages.
  --   New      -> All messages which are unread.
  --   Today    -> Show messages arrived today.
  --  "pattern" -> All messages matching the given pattern.
  --
  local limit = Config.get_with_default("index.limit", "all")

  if limit == "all" then
    --
    -- "All"
    --
    --  This could be simplified to the following:
    --     global_msgs = msgs
    --
    for i, o in ipairs(msgs) do
      -- Bump our progress-bar
      if math.fmod(i, steps) then
        Progress:show_percent(i, #msgs)
      end

      table.insert(global_msgs, o)
    end
  elseif limit == "new" then
    --
    -- "New"
    --
    for i, o in ipairs(msgs) do
      -- Bump our progress-bar
      if math.fmod(i, steps) then
        Progress:show_percent(i, #msgs)
      end

      -- If the message is new add it.
      if o:is_new() then
        table.insert(global_msgs, o)
      end
    end

  elseif limit == "attach" then

    --
    -- Messages with attachments.
    --
    for i, o in ipairs(msgs) do
      -- Bump our progress-bar
      if math.fmod(i, steps) then
        Progress:show_percent(i, #msgs)
      end

      -- If there are attachments add the message.
      if Message.count_attachments(o) > 0 then
        table.insert(global_msgs, o)
      end
    end

  elseif limit == "today" then
    --
    -- "Today"
    --
    local time = os.time()
    local today = time - (60 * 60 * 24)

    for i, o in ipairs(msgs) do
      -- Bump our progress-bar
      if math.fmod(i, steps) then
        Progress:show_percent(i, #msgs)
      end

      -- get the creation-date of the message
      local ctime = o:to_ctime()

      -- if it was within the past 24 hours then add it
      if ctime > today then
        table.insert(global_msgs, o)
      end
    end
  else
    --
    -- "Pattern"
    --
    for i, o in ipairs(msgs) do
      -- Bump our progress-bar
      if math.fmod(i, steps) then
        Progress:show_percent(i, #msgs)
      end

      local fmt = o:format()
      if string.find(fmt, limit) then
        table.insert(global_msgs, o)
      end
    end
  end

  --
  -- Sort and return the set
  --
  global_msgs = sort_messages(global_msgs)
  return global_msgs
end


--
--  Get the `parts` of a message as a table, handling all sub-parts too.
--
--  This uses the nested function, insert_parts, which will recursively
-- call itself to handle any children-parts.
--
--  This function is used to create the display in attachment-mode,
-- as well as for viewing/saving the various MIME-parts.
--
function mimeparts2table (msg)

  local t = {}

  --
  -- Nested function.
  --
  -- Insert each part into the specified table, along with
  -- the children (recursively).
  --
  function insert_parts (tbl, parts)
    for i, o in ipairs(parts) do

      -- Count the existing parts.
      local c = #tbl

      -- Build up the entry of each part
      local tmp = {
        count = c,
        filename = o:filename(),
        object = o,
        size = o:size(),
        type = o:type():lower(),



      }

      -- Insert the entry.
      table.insert(tbl, tmp)

      -- Now add the children of this part.
      insert_parts(tbl, o:children())
    end
  end

  --
  -- Call our (nested) function with the top-level parts of the
  -- message.  In turn this will result in expansion.
  --
  insert_parts(t, msg:parts())
  return t
end


--
-- Simple utility function to test if the given message is
-- new, or unread.
--
function Message:is_new ()
  local flags = self:flags()

  -- If it has the [N]ew-flag then it is new.
  if string.find(flags, "N") then
    return true
  end

  -- If it has the [S]een-flag then it is not new.
  if not string.find(flags, "S") then
    return true
  end

  return false
end


--
-- Return a suitable signature to use for the outgoing mail.
--
-- This is based on the domain of the senders' email-address.
--
-- ~/.signature will be used if nothing else is found.
--
function Message.generate_signature ()
  --
  -- The sender of our mail.
  --
  local sender = Config:get "global.sender"

  --
  -- Get the home directory, if this fails we'll return an empty sig.
  --
  home = os.getenv "HOME"
  if home == nil or home == "" then
    return ""
  end

  -- strip anything except the address, by looking between: <>
  -- i.e. "Steve Kemp" <steve@example.com> becomes steve@example.com
  sender = string.match(sender, "<(.*)>") or sender

  -- get the domain, lowercase it.
  domain = string.sub(sender, string.find(sender, "@") + 1)
  domain = string.lower(domain)

  -- Look for the domain-file ~/.sigs/$domain
  file = home .. "/.sigs/" .. domain
  if File:exists(file) then
    return (File.contents(file))
  end

  --
  -- Fallback to ~/.signature if present
  --
  if File:exists(home .. "/.signature") then
    return (File.contents(home .. "/.signature"))
  end

  return ""
end


--
-- Compose a new message.
--
function Message.compose ()

  -- Get some details
  local to = Screen:get_address "To:"
  if to == nil or to == "" then
    return
  end
  local subject = Screen:get_line "Subject:"
  if subject == nil or subject == "" then
    subject = "No subject"
  end

  -- Get a temporary file, and opening it for writing
  local tmp = os.tmpname()
  local file = assert(io.open(tmp, "w"))

  --
  -- Populate the header variables
  --
  local from = Config:get "global.sender"
  local msgid = Message:generate_message_id()
  local date = os.date "%a, %d %b %Y %H:%M:%S %z"

  -- Write out a header
  header = [[To: ${to}
From: ${from}
Subject: ${subject}
Message-ID: ${msgid}
Date: ${date}

${sig}
]]

  file:write(string.interp(header, {
        to = to,
        from = from,
        subject = subject,
        msgid = msgid,
        date = date,
        sig = Message.generate_signature(),



      }))

  file:close()

  --
  -- This is a table of the attachment filenames the user is
  -- going to add to the outgoing mail.
  --
  attachments = {}

  local run = true

  -- Open the editor
  Screen:execute(Config:get "global.editor" .. " " .. tmp)

  -- GPG options
  local encrypt = ""
  if GPG ~= nil then
    -- Get the default options
    encrypt = GPG.defaults(to)
  end

  while run do

    -- Once the editor quits ask for an action
    Screen:clear()
    local a = Screen:prompt("Send mail : (y)es, (n)o, re-(e)dit, (g)pg, or (a)dd an attachment?", "yYnNeEaAgG")

    --
    -- GPG options.
    --
    if (a == "g") or (a == "G") then

      -- Is GPG enabled?
      if GPG == nil then
        warning_msg "GPG support disabled!"
      else
        encrypt = GPG.prompt(encrypt)
      end
    end

    if (a == "e") or (a == "E") then
      -- Re-edit.
      Screen:execute(Config:get "global.editor" .. " " .. tmp)
    end

    if (a == "y") or (a == "Y") then

      -- If the user has added attachments then process them
      if #attachments > 0 then
        amsg = Message.new(tmp)
        amsg:add_attachments(attachments)
      end

      --
      -- If the user has encryption options then do the necessary
      --
      if encrypt ~= "" then
        tmp = GPG.replace_mail(tmp, encrypt, to)
      end

      -- Allow transformations to occur before sending the message.
      if type(on_message_send) == "function" then
        on_message_send(tmp)
      end

      -- Send the mail.
      os.execute(Config:get "global.mailer" .. " < " .. tmp)
      info_msg "Message sent"

      -- Allow transformations to occur after sending the message.
      if type(on_message_sent) == "function" then
        on_message_sent(tmp)
      end

      --
      -- Now we need to save a copy of the outgoing message.
      --
      Message.archive_outgoing(tmp)

      run = false
    end

    if (a == 'n') or (a == 'N') then
      -- Abort
      info_msg "Sending aborted!"
      run = false
    end

    if (a == 'a') or (a == 'A') then
      -- Add attachment
      path = Screen:get_path "Attachment path:"
      if File:exists(path) then
        table.insert(attachments, path)
      end
    end

  end

  --
  -- Remove the temporary-file
  --
  if File:exists(tmp) then
    os.remove(tmp)
  end
end


--
-- Reply to the current message.
--
-- This literally just replies to the sender of the message,
-- any CC'd addresses are dropped.
--
function Message.reply ()
  -- `False` means don't include the CC's
  Message.send_reply(false)
end


--
-- Reply to the current message, keeping all CC'd addresses.
--
function Message.reply_all ()
  -- `True` means keep the CC's.
  Message.send_reply(true)
end


--
-- Reply to the message at the point, either keeping
-- or dropping CC'd addresses
--
function Message.send_reply (include_cc)

  -- The message we're going to work on.
  local msg = Message.at_point()

  -- Failed to find a mesage?
  if not msg then
    error_msg "Failed to find message!"
    return
  end

  -- Get the text of a message.
  local txt = message_view(msg)

  -- Strip colours.
  txt = strip_colour(txt)

  -- Get a temporary file, and opening it for writing
  local tmp = os.tmpname()
  local file = assert(io.open(tmp, "w"))

  --
  -- Work out who we should be replying to.
  --
  local to = msg:header "Reply-To"
  if to == nil or to == "" then
    to = msg:header "From"
  end

  --
  -- Are we going to change the recipient?
  --
  if type(on_get_recipient) == "function" then

    --
    -- Call the user-hook.  If it returns a non-nil
    -- response that's the new recipient.
    --
    local result = on_get_recipient(to, msg)
    if result then
      to = result
    end
  end

  --
  -- Get the subject of the message.
  --
  local subject = msg:header "Subject"
  if (subject == nil) or (subject == "") then
    subject = "No subject"
  end

  --
  -- Will the user want to clean it?
  --
  if type(on_clean_subject) == "function" then
    subject = on_clean_subject(subject)
  else

    --
    -- Default to removing any "Re:"-prefix(es) from the subject.
    --
    while string.find(subject, "^[rR][eE]:") do
      subject = string.gsub(subject, "^[rR][eE]:", "")
      subject = string.trim(subject)
    end
  end

  --
  -- Get any CC'd addresses if we're supposed to do so.
  --
  local cc = ""
  if include_cc then

     -- Get the recipient(s) + CCs as one string
     h_to = msg:header( "To" )
     h_cc = msg:header("Cc" )

     x = h_to .. "," .. h_cc

     -- Now we have a table of recipients
     recip = string.split( x , "," )

     -- Remove dupes
     local hash = {}
     local res = {}
     for _,v in ipairs(recip) do
        -- strip leading/trailing whitespace
        v = string.trim(v)
        if (not hash[v]) then

           -- Ignore our self
           if ( v ~= Config:get "global.sender" ) then
              res[#res+1] = v
              hash[v] = true
           end
        end
     end

     -- Sort the table
     table.sort(res, function (a, b)
                   return a:lower() < b:lower()
                     end)

     -- Now we can join them back via ","
     cc = ""
     for _,v in ipairs(res) do
        cc = cc .. v .. ", "
     end

     -- Delete the trailing comma.
     cc = (cc:gsub(", $", ""))
  end

  -- Add prefix to the subject.
  subject = "Re: " .. subject

  -- Write out a header
  header = [[To: ${to}
Cc: ${cc}
From: ${from}
Subject: ${subject}
Date: ${date}
Message-ID: ${msgid}
In-Reply-To: ${source_id}
References: ${references}

]]

  --
  -- Get the Message-ID of the message we're replying to.
  --
  -- This should be <bla.blah.blah> but I've seen some horrors.
  --
  local src_id = msg:header "Message-ID"
  local references = msg:header "References" or ""
  if src_id then
    src_id = string.match(src_id, "(<.*>)") or src_id

    -- Only referencing the single message
    if references == "" then
      references = src_id
    else
      -- Append the source to the existing references.
      references = references .. " " .. src_id
    end
  end


  file:write(string.interp(header, {
        to = to,
        cc = cc,
        from = Config:get "global.sender",
        subject = subject,
        source_id = src_id,
        references = references,
        msgid = Message:generate_message_id(),
        date = os.date "%a, %d %b %Y %H:%M:%S %z",



      }))

  --
  -- Header to the message
  --
  local reply = Config.get_with_default("global.reply-header", "")

  --
  -- If one is set then use it.
  --
  -- The value can use any value from the message, e.g:
  --
  -- Config:set( "global.reply-header", "${from} wrote:" )
  --
  if reply ~= "" then
    -- The headers from the messages will be available
    local headers = msg:headers()

    --
    -- Populate "email" and "name" is distinct values, based
    -- upon the from: header.
    --
    headers['email'] = string.match(headers['from'], "<(.*)>") or h['from']
    headers['name'] = string.match(headers['from'], "(.*)<(.*)>") or h['from']
    if headers['email'] then
      headers['email'] = string.trim(headers['email'])
    end
    if headers['name'] then
      headers['name'] = string.trim(headers['name'])
    end

    -- Format the header appropriately.
    local line = string.interp(reply, headers)
    file:write(line .. "\n")
  end

  --
  -- We don't want to include the header in the massage,
  -- just the text of the body.
  --
  local in_header = true
  for i, l in ipairs(txt) do
    if in_header then
      if l == "" then
        in_header = false
      end
    else
      file:write("> " .. l .. "\n")
    end
  end

  -- Append a signature
  file:write "\n"
  file:write(Message.generate_signature())
  file:close()

  --
  -- This is a table of the attachment filenames the user is
  -- going to add to the outgoing mail.
  --
  attachments = {}

  local run = true

  -- Open the editor
  Screen:execute(Config:get "global.editor" .. " " .. tmp)

  -- GPG options
  local encrypt = ""
  if GPG ~= nil then
    encrypt = GPG.defaults(to)
  end

  while run do

    -- Once the editor quits ask for an action
    Screen:clear()
    local a = Screen:prompt("Send mail : (y)es, (n)o, re-(e)dit, (g)pg, or (a)dd an attachment?", "yYnNeEaAgG")

    --
    -- GPG options.
    --
    if (a == "g") or (a == "G") then

      -- Is GPG enabled?
      if GPG == nil then
        warning_msg "GPG support disabled!"
      else
        encrypt = GPG.prompt(encrypt)
      end
    end

    if (a == "e") or (a == "E") then
      -- Re-edit.
      Screen:execute(Config:get "global.editor" .. " " .. tmp)
    end

    if (a == "y") or (a == "Y") then

      -- If the user has added attachments then process them
      if #attachments > 0 then
        amsg = Message.new(tmp)
        amsg:add_attachments(attachments)
      end

      --
      -- If the user has encryption options then do the necessary
      --
      if encrypt ~= "" then
        tmp = GPG.replace_mail(tmp, encrypt, to)
      end

      -- Allow transformations to occur before sending the message.
      if type(on_message_send) == "function" then
        on_message_send(tmp)
      end

      -- Send the mail.
      os.execute(Config:get "global.mailer" .. " < " .. tmp)
      info_msg("Reply sent to " .. to)

      -- Allow transformations to occur after sending the message.
      if type(on_message_sent) == "function" then
        on_message_sent(tmp)
      end
      --
      -- Since we've sent the message we need to add the "(R)eplied"
      -- flag on the source message.
      --
      local cf = msg:flags()
      if not string.find(cf, "R") then
        cf = cf .. "R"
        msg:flags(cf)
      end

      --
      -- Now we need to save a copy of the outgoing message.
      --
      Message.archive_outgoing(tmp)

      run = false
    end

    if (a == "n") or (a == "N") then
      -- Abort
      info_msg "Reply aborted!"
      run = false
    end

    if (a == 'a') or (a == 'A') then
      -- Add attachment
      path = Screen:get_path "Attachment path:"
      if File:exists(path) then
        table.insert(attachments, path)
      end
    end

  end

  --
  -- Remove the temporary-file
  --
  if File:exists(tmp) then
    os.remove(tmp)
  end
end


--
-- Save a message
--
function Message.archive_outgoing (msg_path)

  --
  -- Save globally.
  --
  local sent = Config:get "global.sent-mail"
  if sent then
    local msent = Maildir.new(sent)
    local tmp_msg = Message.new(msg_path)
    msent:save_message(tmp_msg)
  end
end


--
-- Delete the current message.
--
function Message.delete (self)

  -- The Message we want to delete.
  local msg = self or Message.at_point()

  -- If there is no message we have nothing to do.
  if not msg then
    error_msg "Failed to find message!"
    return
  end

  --
  -- WARNING: index.current is 0 based!
  --
  local msg_index = Config.get_with_default("index.current", 0) + 1

  -- Delete the message.
  msg:unlink()

  -- Delete the message from the cache.
  table.remove(global_msgs, msg_index)

  local mode = Config:get "global.mode"

  if mode == "message" then
    -- select next message
    if msg_index <= (#global_msgs) then
      Global:select_message(global_msgs[msg_index])
    end

  elseif mode == "index" then
    -- if deleting the last message move the selection down.
    if msg_index >= (#global_msgs) then
      Config:set("index.current", #global_msgs - 1)
    end
  end
end

--
--- Trash the current Message
--
-- Move the current message to the Trash maildir before deleting it
--

function Message.trash(self)

  -- The Message we want to delete.
  local msg = self or Message.at_point()

  -- If there is no message we have nothing to do.
  if not msg then
    error_msg "Failed to find message!"
    return
  end

  -- Move message to trash.
  local trash = Config.get_with_default("global.trash-mail", nil)
  if trash and trash ~= Global:current_maildir():path() then
    Message.save(trash)
  end

  -- Delete the original message.
  msg:delete()
end


--
-- Forward the current message
--
function Message.forward ()

  -- The message we're going to work on.
  local msg = Message.at_point()

  -- Failed to find a message?
  if not msg then
    error_msg "Failed to find message!"
    return
  end

  local to = Screen:get_address "Forward to:"
  if to == nil or to == "" then
    return
  end

  -- Get the text of a message.
  local txt = message_view(msg)

  -- Strip colours.
  txt = strip_colour(txt)

  -- Write it out to to a temporary file
  local tmp = os.tmpname()
  local file = assert(io.open(tmp, "w"))

  -- Write out a header
  -- Write out a header
  header = [[To: ${to}
From: ${from}
Subject: Fwd: ${subject}
Message-ID: ${msgid}
Date: ${date}

Begin forwarded message.

]]

  local from = Config:get "global.sender"
  local subject = msg:header "Subject"

  file:write(string.interp(header, {
        from = from,
        to = to,
        subject = subject,
        msgid = Message:generate_message_id(),
        date = os.date "%a, %d %b %Y %H:%M:%S %z",



      }))


  for i, l in ipairs(txt) do
    file:write("> " .. l .. "\n")
  end

  -- Append the signature
  file:write "\n"
  file:write(Message.generate_signature())
  file:close()

  --
  -- This is a table of the attachment filenames the user is
  -- going to add to the outgoing mail.
  --
  attachments = {}

  local run = true

  -- Open the editor
  Screen:execute(Config:get "global.editor" .. " " .. tmp)

  -- GPG options
  local encrypt = ""
  if GPG ~= nil then
    encrypt = GPG.defaults(to)
  end

  while run do

    -- Once the editor quits ask for an action
    Screen:clear()
    local a = Screen:prompt("Forward mail : (y)es, (n)o, re-(e)dit, (g)pg, or (a)dd an attachment?", "yYnNeEaAgG")

    --
    -- GPG options.
    --
    if (a == "g") or (a == "G") then

      -- Is GPG enabled?
      if GPG == nil then
        warning_msg "GPG support disabled!"
      else
        encrypt = GPG.prompt(encrypt)
      end
    end

    if (a == "e") or (a == "E") then
      -- Re-edit.
      Screen:execute(Config:get "global.editor" .. " " .. tmp)
    end

    if (a == "y") or (a == "Y") then

      -- If the user has added attachments then process them
      if #attachments > 0 then
        amsg = Message.new(tmp)
        amsg:add_attachments(attachments)
      end

      --
      -- If the user has encryption options then do the necessary
      --
      if encrypt ~= "" then
        tmp = GPG.replace_mail(tmp, encrypt, to)
      end

      -- Allow transformations to occur before sending the message.
      if type(on_message_send) == "function" then
        on_message_send(tmp)
      end

      -- Send the mail.
      os.execute(Config:get "global.mailer" .. " < " .. tmp)
      info_msg "Message forwarded"

      -- Allow transformations to occur after sending the message.
      if type(on_message_sent) == "function" then
        on_message_sent(tmp)
      end

      --
      -- Now we need to save a copy of the outgoing message.
      --
      Message.archive_outgoing(tmp)

      run = false
    end

    if (a == "n") or (a == "N") then
      -- Abort
      info_msg "Forwarding aborted!"
      run = false
    end

    if (a == 'a') or (a == 'A') then
      -- Add attachment
      path = Screen:get_path "Attachment path:"
      if File:exists(path) then
        table.insert(attachments, path)
      end
    end
  end

  --
  -- Remove the temporary-file
  --
  if File:exists(tmp) then
    os.remove(tmp)
  end
end


--
-- Toggle the new/old status of a message.
--
function Message.toggle ()

  -- The message we're going to work on.
  local msg = Message.at_point()

  if not msg then
    error_msg "Failed to find a message"
    return
  end

  --
  -- Toggle the status.
  --
  if msg:is_new() then
    msg:mark_read()
  else
    msg:mark_unread()
  end
end


--
-- Save a copy of the current message elsewhere.
--
function Message.save (dest)

  -- The message we're going to work on.
  local msg = Message.at_point()

  if not msg then
    error_msg "Failed to find a message"
    return
  end

  --
  -- Are we using IMAP?
  --
  local imap = true

  --
  -- Get the IMAP configuration-values
  --
  local i_s = Config.get_with_default("imap.server", "")
  local i_u = Config.get_with_default("imap.username", "")
  local i_p = Config.get_with_default("imap.password", "")

  --
  -- If any of them is empty then we're not using IMAP
  --
  if (i_s == "") or (i_u == "") or (i_p == "") then
    imap = false
  end

  --
  -- Is there a parameter ?
  --
  if not dest then

    --
    -- Prompt differently based on which storage is in-use.
    --
    if imap then

      --
      -- Prompt for the IMAP folder.
      --
      dest = Screen:get_line "Copy to IMAP folder:"

    else

      -- Get the default destination
      --
      local prefix = Config:get "maildir.prefix"
      local location = os.getenv "HOME"

      --
      -- If we have a prefix which is a string then use it.
      --
      if type(prefix) == "string" then
        location = prefix
      elseif type(prefix) == "table" then
        --
        -- If we have multiple values set then use the first.
        --
        location = prefix[1]
      end

      --
      -- Prompt for destination
      --
      dest = Screen:get_line("Copy to local maildir:", location)


      --
      -- Does the destination exist, as a maildir?
      --
      if not Directory:is_maildir(dest) then

        --
        -- Directory doesn't exist - see if we should create it
        --
        local answer = Screen:prompt("Directory doesn't exist.  Create it? [Y/N]", "yYNn")

        if (answer == 'y') or (answer == 'Y') then
          Maildir:create(dest)
        else
          info_msg "Refusing to save to missing-maildir"
          return
        end
      end

    end

    --
    -- Nothing entered?  Abort.
    --
    if dest == nil or dest == "" then
      info_msg "Copy aborted"
      return
    end
  end


  --
  -- Create a new helper for the destination
  --
  local dest_f = Maildir.new(dest)

  --
  -- Save the message-there.
  local ret = dest_f:save_message(msg)

  if ret then
    info_msg("Message copied to " .. dest)
  else
    error_msg "Message save failed."
  end
end


--
-- Utility function to open the Maildir with the given name.
--
-- This matches against the path, literally, and the first match wins.
--
-- A literal match means we don't use either PCRE regular expressions
-- or Lua regular expressions.  That means you don't need to escape
-- any special characters.
--
function Maildir.select (desired, change_mode_too)

  -- Get the maildirs
  local folders = maildirs()

  -- For each one .. see if it matches
  for index, object in ipairs(folders) do

    local path = object:path()
    if string.ends(path, desired) then

      -- Select the maildir, to make it current.
      Global:select_maildir(object)

      -- And update the current selection.
      Config:set("maildir.current", index - 1)

      -- If we're supposed to change mode, do so.
      if change_mode_too then

        change_mode "index"

        -- Flush the cached message-list
        global_msgs = nil

        -- Invoke the per-user hook, if present.
        if type(on_folder_changed) == "function" then
          on_folder_changed(object)
        end
      end

      -- The first match wins, so we return after updating.
      return

    end
  end
end



--
-- This function saves the MIME part under the cursor to the named path.
--
-- If the function succeeds it returns the MIME object, otherwise it
-- returns false.
--
function write_mime_part( path )

  --
  -- Get the currently highlighted attachment-offset
  --
  local mode = Config:get "global.mode"
  local cur  = Config.get_with_default(mode .. ".current", 0)

  --
  -- Get the current message, and then the parts.
  --
  local msg = Global:current_message()
  if not msg then
     warning_msg "There is no currently selected message!"
     return false
  end

  -- Parse the MIME parts into an ordered list.
  local out = mimeparts2table(msg)

  -- Get the part we should view
  local found = out[cur + 1]

  --  If we found the part.
  if found then

     -- Open the file for writing
     local file = assert(io.open(path, "w"))

     -- save the content there
     file:write(found['object']:content())
     file:close()

     return found
  else
     warning_msg "Failed to find MIME-part!"
     return false
  end
end


--
-- This function is called by pressing `s` in attachment-mode
--
function save_mime_part ()
   -- Prompt for local-path
   local output = Screen:get_path("Save to:")

   -- Ensure we got a path.
   if output == nil or output == "" then
      info_msg "Attachment saving aborted!"
      return
   end

   -- Write out the part
   if ( write_mime_part( output ) ) then
      info_msg("Wrote attachment to " .. output)
   else
      warning_msg( "Failed to write attachment" )
   end
end


--
-- This function is called by pressing `SPACE`/`ENTER` in attachment-mode
--
function view_mime_part (cmd)

   --
   -- Generate a temporary file to write the attachment to
   --
   local tmp = os.tmpname()

   --
   -- Write it out and test for success
   --
   local obj = write_mime_part( tmp )
   if ( obj == false ) then
      warning_msg( "Failed to write out object")
      return
   end

   -- Get the MIME-type of the attachment
   local mime = obj['type']:lower()

   -- Lookup the viewer to use, if not specified.
   if (not cmd) or (cmd == "") then
      cmd = get_mime_viewer(mime)
   end

   -- Replace "%s" with the filename, and run the command
   cmd = string.gsub(cmd, "%%s", tmp)

   -- Execute it
   Screen:execute(cmd)

   -- Remove the file
   os.remove(tmp)
end


--
-- Remove a colour-prefix from the given string.
--
-- Our drawing code allows lines to be different coloured based upon
-- a prefix.  So for example the text "$[RED]I like Helsinki" would be
-- drawn as "I like Helsinki", in the colour red.
--
-- This function removes any existing colour prefixes.
--
function strip_colour (input)

  --
  -- If we've been given a table of input then
  -- process each line.
  --
  if type(input) == "table" then

    ret_val = {}

    for o, p in ipairs(input) do

      while string.find(p, "^$[^]]+]") do
        p = string.gsub(p, "^$[^]]+]", "")
      end

      table.insert(ret_val, p)
    end

    return ret_val
  end

  --
  -- Handling a single string
  --
  while string.find(input, "^$[^]]+]") do
    input = string.gsub(input, "^$[^]]+]", "")
  end
  return input
end


--
-- This function takes a table of lines, and will iterate over
-- every line, updating the strings if we find a match on the
-- regular expressions contained in the colour-table
--
function add_colours (lines, mode)

  --
  -- Get the table of colours for the mode
  -- if it doesn't exist then abort.
  --
  local colour_table = _G['colour_table']
  if not colour_table then
    return lines
  end
  if not colour_table[mode] then
    return lines
  end

  local ret = {}


  --
  -- Iterate over the input-table
  --
  for index, line in ipairs(lines) do
    --
    -- Iterate over the colours
    --
    for regexp, colour in pairs(colour_table[mode]) do

      if string.match(line, regexp) then
        line = colour_line(line, colour)
      end
    end

    table.insert(ret, line)
  end

  return ret
end


--
-- This function returns the output which is displayed in attachment-mode
--
-- Attachment mode is entered by pressing `A` when a message is open.
--
function attachment_view ()
  local result = {}

  --
  -- Get the parts from within the current message
  --
  local msg = Global:current_message()
  if not msg then
    return {
      "No message selected!",



    }
  end

  --
  -- Parse the mime-types to a table
  --
  local out = mimeparts2table(msg)

  --
  -- Fetch the format-string
  --
  local format = Config.get_with_default("attachment.format", "[${4|number}] ${6|size} - ${25|type} - ${filename}")


  for i, o in ipairs(out) do

    local output = (string.interp(format, {
        number = o["count"] + 1,
        size = o["size"] or "",
        type = o["type"] or "",
        filename = o["filename"] or "",



      }))
    table.insert(result, output)
  end

  result = add_colours(result, 'attachment')
  return result
end


--
-- This function formats a single message for display in index-mode,
-- it is called by the `index_view()` function defined next.
--
function Message:format (thread_indent, index)
  local path = self:path()
  local time = self:mtime()

  --
  -- Cache key is conditional on the sort-method,
  -- the index-format, and the path of the message.
  --
  -- That means changing any of them will flush the cached value.
  --
  local ckey = path .. "message:" .. Config.get_with_default("index.sort", "index.sort") .. Config.get_with_default("index.format", "index.format") .. time

  -- Do we have this cached?  If so return it
  if cache:get(ckey) then
    return (cache:get(ckey))
  end

  if not thread_indent then
    thread_indent = ""
  end

  --
  -- Basics from the message
  --
  local flags     = self:flags()
  local subject   = self:header "Subject"
  local sender    = self:header "From"
  local recipient = self:header "To"
  local date      = self:header "Date"
  local id        = self:header "Message-ID"

  --
  -- Try to parse out sender into "email" + "name".
  --
  local email = string.match(sender, "<(.*)>") or sender
  local name = string.gsub(sender, "<(.*)>", "")
  if name:len() < 1 then
    name = sender
  end

  --
  -- Again for recipient.
  --
  local recipient_email = string.match(recipient, "<(.*)>") or recipient
  local recipient_name = string.gsub(recipient, "<(.*)>", "")
  if recipient_name:len() < 1 then
    recipient_name = recipient_name
  end

  --
  -- Compatibility updates
  --
  local sender_email = email
  local sender_name  = name

  --
  -- The user might have a filter-function to cleanup
  -- the name of the sender.
  --
  -- (This is mostly to handle transforming a string
  -- such as "Steve Kemp (via Twitter)" into "Steve Kemp")
  --
  if type(on_clean_name) == "function" then
    name = on_clean_name(name)
  end

  --
  -- Get the message-flags - these flags are informational, and
  -- unrelated to the flags a message might have.
  --
  --   A => Message has attachments.
  --   S => Message is signed.
  --
  local m_flags = ""
  local parts = mimeparts2table(self)
  local a_count = 0
  for i, o in ipairs(parts) do
    if o['type'] == "text/x-gpg-output" then
      m_flags = m_flags .. "S"
    end
    if o['filename'] ~= nil and o['filename'] ~= "" then
      a_count = a_count + 1
    end
  end
  if a_count > 0 then
    m_flags = "A" .. m_flags
  end


  --
  -- The format-string we use for display.
  --
  local format = Config.get_with_default("index.format", "[${4|flags}] ${2|message_flags} - ${20|sender} - ${indent}${subject}")

  --
  -- Format this message for display
  --
  local output = (string.interp(format, {
      flags           = flags,
      message_flags   = m_flags,
      sender          = sender,
      sender_name     = sender_name,
      sender_email    = sender_email,
      email           = email,           -- depreciated
      name            = name,            -- depreciated
      indent          = thread_indent,
      subject         = subject,
      number          = index,
      date            = date,
      id              = id,
      recipient       = recipient,
      recipient_name  = recipient_name,
      recipient_email = recipient_email,
    }))

  --
  -- If the message is unread then show it in the "unread" colour
  --
  if self:is_new() then
    output = "$[UNREAD]" .. output
  end

  -- Update the cache.
  cache:set(ckey, output)

  return output
end


--
-- This function displays the screen when in `index`-mode.
--
-- It fetches the list of current messages, and calls `Message:format()`
-- on each one.
--
-- As an optimization, primarily useful for large Maildirs, or when
-- using IMAP we can instead elect to only format the visible messages
-- if the setting `index.fast` is enabled.
--
function index_view ()
  local result = {}

  -- Get the available messages.
  local messages = get_messages()

  if (messages == nil) or (#messages == 0) then
    Screen:draw(10, 10, "There are no visible messages.")
    return result
  end

  -- Get the current offset
  local mode = Config:get "global.mode"
  local cur = tonumber(Config.get_with_default("index.current", 0))

  --
  -- If the current line is bigger than the count of messages
  -- then something has gone wrong.
  --
  if cur >= #messages then
    cur = #messages - 1
  end

  -- Find the height of the screen.
  local height = Screen:height()

  -- The minimum message number we're going to format
  local min = cur - height
  if min < 0 then
    min = 0
  end

  -- The maximum message-number we're going to format.
  local max = cur + height

  -- Are we optimizing?
  local fast = Config.get_with_default("index.fast", 0)
  for offset, object in ipairs(messages) do

    local str = "INVISIBLE"

    -- If optimizing
    if fast ~= 0 then

      --
      -- Only show the message if it will fit on the screen
      --
      if (offset >= min) and (offset < max) then
        str = object:format(threads_indentation[object], offset)
      else
        str = "INVISIBLE - Outside the viewport!"
      end
    else
      -- Else format all entries
      str = object:format(threads_indentation[object], offset)
    end

    table.insert(result, str)
  end

  --
  -- Update the colours
  --
  result = add_colours(result, 'index')
  return result
end


--
-- This function shows our keybindings, both globally and for each mode.
--
function keybinding_view ()
  --
  -- The output we'll display.
  --
  output = {}

  --
  -- If we have globals
  --
  local globals = keymap['global']
  local jump_range = {}
  if globals then
    table.insert(output, "$[RED]Global Keybindings")
    table.insert(output, "\n")

    for i, o in pairs(table.sorted_keys(globals)) do

      -- Skip global bindings for "jump(N)", because there
      -- will be approximately 1000 of them!
      if not string.match(globals[o], "^jump") then
        local entry = string.format("   %10s -> %s", o, globals[o])
        table.insert(output, entry)
      else
        local line_number = tonumber(globals[o]:match "%d+")
        if #jump_range == 0 then
          jump_range = {
            line_number,
            line_number,

          }
        elseif line_number > jump_range[2] then
          jump_range[2] = line_number
        elseif line_number < jump_range[1] then
          jump_range[1] = line_number
        end
      end
    end
    if #jump_range == 2 then
      jump_range = string.format("%d-%d", jump_range[1], jump_range[2])
      local jump_entry = string.format("   %10s -> jump(N)", jump_range)
      table.insert(output, jump_entry)
    end
  end

  for i, mode in pairs(table.sorted_keys(keymap)) do
    if mode and (mode ~= "global") then
      local bind = keymap[mode]
      table.insert(output, "\n\n")
      table.insert(output, "$[BLUE]Keybindings for " .. mode .. "-mode")
      table.insert(output, "\n")
      if table.size(bind) > 0 then
        for i, o in pairs(table.sorted_keys(bind)) do
          local entry = string.format("   %10s -> %s", o, bind[o])
          table.insert(output, entry)
        end
      else
        table.insert(output, "      NONE.")
      end
    end
  end

  output = add_colours(output, 'keybindings')
  return output
end


--
-- Functions related to life-view
--
do
  -- If we don't have life enabled, then create some.
  if not life then
    life = Life.new(Screen:width(), Screen:height())
    life:random()
  end

  -- Don't output anything for display.  The C++ code will then
  -- call its `on_idle()` function to display things directly.
  function life_view ()
    output = {}
    return output
  end
end

--
-- This function returns the output which is displayed in `lua`-mode.
--
function lua_view ()
  --
  -- The output we'll display.
  --
  output = {}

  --
  -- Show the version of Lua/LuaJit.
  --
  local lver = ""
  if jit then
    lver = jit.version
  else
    lver = _VERSION
  end
  lver = "$[RED]<$[GREEN|BOLD]" .. lver .. "$[RED]>"


  --
  -- Show the version of lumail & lua.
  --
  table.insert(output, "$[RED]This $[GREEN]is $[YELLOW|UNDERLINE|BOLD]Lumail$[CYAN|NORMAL] version $[BLUE|BOLD]" .. Config:get "global.version" .. " " .. lver)
  table.insert(output, "")

  table.insert(output, "$[RED]This RED - and not $[#GREEN]!")
  table.insert(output, "")

  --
  -- Test UTF-8
  --
  table.insert(output, "This line is for UTF-8 testing $[RED]«ÜßÄ$€»$[CYAN]‹ÅåÄäÖö›")
  table.insert(output, "")

  table.insert(output, "This line is for testing line-wrapping:  123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 ")
  table.insert(output, "")
  --
  -- Now show the current maildir, message, etc.
  --
  local mode = Config:get "global.mode"
  table.insert(output, "The current mode is")
  table.insert(output, "$[YELLOW]\t" .. mode)

  table.insert(output, "Valid modes are:")
  for i, o in ipairs(Global:modes()) do
    table.insert(output, "\t" .. o)
  end

  table.insert(output, "The currently selected maildir is")
  local md = Global:current_maildir()
  if md then
    table.insert(output, "$[RED]\t" .. md:path())
  else
    table.insert(output, "$[RED]\tUNSET")
  end

  table.insert(output, "The currently selected message is")
  local msg = Global:current_message()
  if msg then
    table.insert(output, "$[RED]\t" .. msg:path())
  else
    table.insert(output, "$[RED]\tUNSET")
  end

  --
  -- Now add all the current keys
  --
  table.insert(output, "")
  table.insert(output, "The following configuration-values have been set:")
  for k, v in ipairs(Config:keys()) do
    val = Config:get(v)
    table.insert(output, "\t" .. v .. " <" .. type(val) .. ">")

    if type(val) == "string" then
      table.insert(output, "$[YELLOW]\t\t" .. val)
    end
    if type(val) == "number" then
      table.insert(output, "$[YELLOW]\t\t" .. val)
    end
    if type(val) == "table" then
      for o, p in ipairs(val) do
        table.insert(output, "$[YELLOW]\t\t" .. p)
      end
    end
  end

  --
  -- And return the text.
  --
  return output
end


--
-- Show all the output from the panel.
--
-- This is more useful than it sounds because the panel is not scrollable
-- nor can you add line-wrapping, but the panel-mode allows both those
-- things.
--
function panel_view ()
  local result = Panel:text()
  result = add_colours(result, 'panel')
  return result
end

--
-- Create a maildir if it doesn't exist
--
function Maildir:create (path)

  Directory:mkdir(path)
  Directory:mkdir(path .. "/cur")
  Directory:mkdir(path .. "/new")
  Directory:mkdir(path .. "/tmp")
end


--
-- This method returns the text which is displayed when a maildir is
-- to be show in maildir-mode.
--
-- The actual output of maildir-mode is generated by `maildir_view`
-- which is defined below.
--
function Maildir:format (index)
  local path = self:path()
  local time = self:mtime()
  local trunc = Config.get_with_default("maildir.truncate", 0)
  local src = "maildir"

  --
  -- If we're a remote IMAP Maildir then we cache that based on the
  -- server-name.
  --
  -- This allows the user to switch IMAP-servers/accounts without
  -- any problem
  if self:is_imap() then
    src = "imap"
    src = src .. Config.get_with_default("imap.server", "localhost")
    src = src .. Config.get_with_default("imap.username", "username")
  end

  --
  -- The cache-key is based upon
  --
  --   1.   The type of folder (maildir vs. IMAP)
  --   1.5. The value of `maildir.truncate`.
  --   2.   The path to the folder.
  --   3.   The format-string.
  --   4.   The mtime of the directory.
  --
  -- This means if any of them change we flush the cache
  --
  local ckey = path .. "maildir:" .. trunc .. src .. time .. Config.get_with_default("maildir.format", "maildir.format")

  -- Do we have this cached?  If so return it
  if cache:get(ckey) then
    return (cache:get(ckey))
  end

  local total = self:total_messages()
  local unread = self:unread_messages()

  --
  -- Path might be truncated, via "p".
  --
  if trunc ~= 0 then

    --
    -- Work out which prefix the maildir is beneath, and strip it
    --
    local prefix = Config:get "maildir.prefix"

    --
    -- Simple case first - if there is only a single maildir prefix
    -- then we just truncate.
    --
    if type(prefix) == "string" then
      path = string.sub(path, prefix:len() + 2)
      if path == nil or path == "" then
        path = "INBOX"
      end
    end

    --
    -- Otherwise we need to test each one.
    --
    if type(prefix) == "table" then
      for index, pre in ipairs(prefix) do
        local poss = string.sub(path, 0, pre:len())
        if poss == pre then
          path = string.sub(path, pre:len() + 2)
          if path == nil or path == "" then
            path = "INBOX"
          end
        end
      end
    end
  end

  --
  -- The format-string we use for display.
  --
  local format = Config.get_with_default("maildir.format", "[${05|unread}/${05|total}] - ${path}")

  --
  -- Format this maildir for display
  --
  local output = (string.interp(format, {
      total = total,
      unread = unread,
      number = index,
      path = path,



    }))

  --
  -- If there are unread messages then show it in the unread-colour.
  --
  if unread > 0 then
    output = "$[UNREAD]" .. output
  end

  -- update the cache
  cache:set(ckey, output)

  return output
end


--
-- This method returns the text which is displayed in maildir-view
--
-- It retrieves the list of Maildirs, and calls `Maildir:format` on
-- each one.
--
function maildir_view ()
  local result = {}

  -- Get the maildirs
  local folders = maildirs()

  -- If we had an old selection in-place then try to
  -- preserve that.
  if prev_maildir then
    info_msg("Trying to select " .. prev_maildir)
    Maildir.select(prev_maildir, false)
    prev_maildir = nil
  end

  if (folders == nil) or (#folders == 0) then
    Screen:draw(10, 10, "There are no visible folders.")
    return result
  end

  -- For each one add the output
  for index, object in ipairs(folders) do
    local str = object:format(index)
    table.insert(result, str)
  end

  --
  -- Update the colours
  --
  result = add_colours(result, 'maildir')
  return result
end


--
-- Given a line of text escape any colour-definitions
--
-- The formatting of colours that lumail uses is very
-- simple, the following is an example:
--
--   $[RED]This is red $[GREEN]This is green.
--
-- To display this text literally we'd add "#" to the name
-- of the colour, so for example you might have this:
--
--   $[#PINK]This is actually white - the "#" escapes it.
--
-- To escape the value of any formatting that might be in the
-- message body we thus turn this:
--
--   $[GREEN]Green $[Blue]Blue
--
-- to this:
--
--   $[#GREEN]Green $[#BLUE]Blue
--
--
function escape_message_colours (txt)
  txt = string.gsub(txt, "$%[([a-zA-Z|])", "$[#%1")
  return txt
end


--
-- This method returns the text which is displayed in message-mode.
--
-- First of all the current-message is retrieved, then that is
-- formatted into an array of lines which are displayed to the user.
--
-- The scrolling is handled on the C++ side.
--
function message_view (msg)

  --
  -- If we're called in `message`-mode then we'll not have an
  -- argument, so we need to find the message.
  --
  if not msg then
    msg = Global:current_message()
  end

  if not msg then
    return {
      "No message selected!",



    }
  end

  --
  -- Change the message to being read, if it is new.
  --
  if msg:is_new() then
    msg:mark_read()
  end

  local output = ""

  --
  -- We will either show "some" headers, or all headers.
  --
  -- The user may choose to view all headers by pressing `H`,
  -- which will invoke:
  --
  --     Config.toggle( "message.headers" );
  --
  local full_headers = Config.get_with_default("message.headers", 0)

  --
  -- The headers we want to see if not full.
  --
  headers = {
    "To",
    "From",
    "Cc",
    "Subject",
    "Date",



  }

  if full_headers ~= 0 then
    info_msg "Showing all headers"
    --
    -- Show all headers
    --
    local all_headers = msg:headers()
    local sorted_headers = {}

    for n, v in pairs(all_headers) do
      table.insert(sorted_headers, n)
    end

    table.sort(sorted_headers)

    for index, name in pairs(sorted_headers) do
      local value = all_headers[name]
      if value then
        output = output .. name .. ": " .. value .. "\n"
      end
    end
  else

    --
    -- Just show the small list.
    --
    for i, header in ipairs(headers) do
      value = msg:header(header) or "[unset]"
      if value then
        output = output .. header .. ": " .. value .. "\n"
      end
    end
  end

  --
  -- Does the message contain attachments?
  --
  -- If so add a pseudo-header to show the count of same.
  --
  local a_count = Message.count_attachments(msg)
  if a_count > 0 then
    output = output .. "$[BLUE]Attachments: " .. a_count .. "\n"
  end

  --
  -- Is there any GPG-signature?
  --
  local parts = mimeparts2table(msg)
  for i, o in ipairs(parts) do
    if o['type'] == "text/x-gpg-output" then
      local gpg = o['object']:content()
      for ii, oo in pairs(string.to_table(gpg)) do
        output = output .. "$[RED]" .. oo .. "\n"
      end
    end
  end

  --
  -- Add newline after the header-area.
  --
  output = output .. "\n"

  --
  -- Now we're going to build up the body of the mail.
  --
  -- We'll either show the first or ALL parts of the appropriate
  -- type, and we prefer "text/plain" to "text/html", but will
  -- display the latter if that is all we have.
  --
  -- We'll store the parts in a table keyed on the MIME-type
  --
  local content = {}

  --
  -- Are we displaying the first, or all parts?
  --
  local all = Config.get_with_default("message.all_parts", 0)

  --
  -- If we're going to show all parts do we append new parts
  -- or prepend them?
  --
  local cat = Config.get_with_default("message.prepend", 0)

  --
  -- Process each MIME-part of the message to find the body.
  --
  local parts = mimeparts2table(msg)
  for i, part in ipairs(parts) do

    -- Content-Type
    local ct = part['type']:lower()

    -- Size
    local sz = part['size']

    -- Content
    local con = part['object']:content()

    -- If this is a text/BLAH part, which is not empty.
    if (string.find(ct, "text/")) and (sz > 0) then

      -- If we're showing all parts ..
      if all == 1 then
        if content[ct] then
          -- There is existing content.
          if cat == 0 then
            -- Prepend the new part.
            content[ct] = con .. content[ct]
          else
            -- Append the new part.
            content[ct] = content[ct] .. con
          end
        else
          content[ct] = con
        end
      else
        -- Only store the content if we didn't find a part already.
        if content[ct] == nil then
          content[ct] = con
        end
      end
    end

  end


  --
  -- Did we show the body?
  --
  local txt = content["text/plain"] or content["text/html"] or "Failed to find suitable text/plain or text/html content."

  --
  -- Escape the colours in the body
  --
  txt = escape_message_colours(txt)

  --
  -- Now add to the body.
  --
  output = output .. txt

  --
  -- The command output is now split into rows.
  --
  local result = string.to_table(output)

  --
  -- Update the colours
  --
  result = add_colours(result, 'message')
  return result
end


--
-- Define some functions which are bound to keys, to move around, etc.
--
-----------------------------------------------------------------------------


--
-- Read input, and evaluate it as lua.
--
function read_eval ()
  local txt = Screen:get_lua ":"

  if txt == nil or txt == "" then
    return
  end

  loadstring(txt)()
end


--
-- Read input, and evaluate it as a shell-command.
--
function read_execute ()
  local cmd = Screen:get_line "!"

  if cmd == nil or cmd == "" then
    return
  end

  os.execute(cmd)
end


--
-- Allow navigation - Selection of a maildir, or message.
--
function select ()
  local mode = Config:get "global.mode"
  local cur = Config.get_with_default(mode .. ".current", 0)

  if mode == "maildir" then
    local folders = maildirs()
    local folder = folders[cur + 1]

    if folder == nil then
      error_msg "There is nothing to select!"
      return
    end

    --
    -- Select the folder and flush the message-cache.
    --
    Global:select_maildir(folder)
    global_msgs = nil

    --
    -- Call the user-function, if it exists.
    --
    if type(on_folder_changed) == "function" then
      on_folder_changed(folder)
    else
      --
      -- Just show the folder we selected and the number of messages.
      --
      local size = #get_messages()
      if size == 1 then
        info_msg("Selected " .. folder:path() .. " with 1 message.")
      else
        info_msg("Selected " .. folder:path() .. " with " .. size .. " messages.")
      end
    end

    --
    -- Change to the index-mode, so we can see the messages in
    -- the folder.
    --
    change_mode "index"
    return
  end

  if mode == "index" then
    --
    -- Get the messages
    --
    local msgs = get_messages()

    --
    -- Get the current offset.
    --
    local msg = msgs[cur + 1]

    if msg == nil then
      info_msg "There is nothing to select!"
      return
    end

    --
    -- Now select
    --
    Global:select_message(msg)
    change_mode "message"

    --
    -- Call the user-function, if it exists.
    --
    if type(on_message_changed) == "function" then
      on_message_changed(msg)
    end
    return
  end
end


--
-- Jump to the first entry in the current-mode.
--
function first ()
  local mode = Config:get "global.mode"
  Config:set(mode .. ".current", 0)
end


--
-- Jump to the last entry in the current-mode.
--
-- We could always set this to jump to the maximum
-- line, but doing so would result in an empty display
-- in the case of viewing a message, or viewing lua-mode.
--
-- We handle that by scrolling until the last line is *visible*
-- rather than selected.
--
function last ()
  local mode = Config:get "global.mode"
  local max = Config:get(mode .. ".max")

  --
  -- Some modes we special case such that jumping to the end
  -- doesn't mean showing only the last line - but making the
  -- last line visible.
  --
  if mode ~= "message" and mode ~= "lua" and mode ~= "panel" and mode ~= "keybinding" then
    Config:set(mode .. ".current", max - 1)
    return
  end

  --
  -- For these two remaining modes we want to jump
  -- such that the end of the display is visible
  -- but not selected.
  --

  -- Get the current offset.
  local cur = Config:get(mode .. ".current")

  -- Jump to the end of the display
  cur = max - Screen:height()

  -- Account for the panel
  if Panel:visible() then
    cur = cur + Panel:height()
  end

  -- Bound the values.
  if cur > max then
    cur = max
  end
  if cur < 0 then
    cur = 0
  end

  -- And finally update them
  Config:set(mode .. ".current", cur)
end


--
-- Left/Right scrolling
--
function left ()
  local x = Config.get_with_default("global.horizontal", 0)

  if x > 0 then
    x = x - 1
  end

  Config:set("global.horizontal", x)
end


--
-- Left/Right scrolling.
--
function right ()
  local x = Config.get_with_default("global.horizontal", 0)

  x = x + 1

  Config:set("global.horizontal", x)
end


--
-- Allow searching for the next line containing a match.
--
-- This function might need some care to understand:
--
--  * The mail-client is a modal editor.
--  * You're always in one mode, stored in "Config:get("global.mode")".
--  * Each mode displays the output of the lua-function $mode_view()
--  * This function returns a table of lines.
--  * There are also "current-offset" and "max-size" variables for these tables.
--  * We can use this to dynamically invoke the right mode, and iterate.
--
--
do

  --
  -- This is the value that the user entered previously, and is
  -- the default if nothing is entered again.
  --
  local search_text = ''

  function find (offset)

    -- Get the search pattern.
    local pattern = Screen:get_line "/:"

    -- If the user didn't enter anything then use the previous
    -- input, if any.
    if pattern == nil or pattern == "" then
      pattern = search_text
    end

    -- Pattern is lower-cased to make searches case-insensitive.
    pattern = pattern:lower()

    -- Save for next time.
    search_text = pattern

    -- Get the global mode.
    local mode = Config:get "global.mode"

    -- Use that to get the lines we're currently displaying
    loadstring("out = " .. mode .. "_view()")()

    --
    -- We know the current offset is stored in
    -- the variable $mode.current
    --
    -- We know the maximum offset is stored in the
    -- variable $mode.max
    --
    local cur = Config.get_with_default(mode .. ".current", 0)
    local max = Config:get(mode .. ".max")

    --
    -- We'll keep track of how many times we've moved forward
    -- to avoid looping indefinitely.
    --
    local count = -1
    cur = cur + 1

    --
    -- Start searching from the current-position
    --
    while count < max do

      cur = cur + offset
      if cur > max then
        cur = 1
      end
      if cur < 1 then
        cur = max
      end

      -- Get the current entry
      local line = out[cur]

      if line then
        line = line:lower()
        if string.match(line, pattern) then
          Config:set(mode .. ".current", (cur - 1))
          return
        end
      end
      count = count + 1
    end

    warning_msg("No match found for $[WHITE|BOLD]" .. pattern)
  end
end


--
-- Scroll the current mode down - by manipulating the "current" offset
-- for the current mode.
--
-- Page is a boolean which means:
--
--   false -> Move a single line
--   true  -> Move a single page.
--
function next (page)

  local mode = Config:get "global.mode"
  local max = Config:get(mode .. ".max")
  local cur = Config.get_with_default(mode .. ".current", 0)

  local offset = 1

  if page then
    if Panel:visible() then
      offset = Screen:height() - Panel:height() - 1
    else
      offset = Screen:height() - 1
    end
  end

  if cur + offset < (max - 1) then
    cur = cur + offset
  else
    cur = max - 1
  end

  if cur >= max then
    cur = max
  end

  Config:set(mode .. ".current", cur)
end


--
-- Scroll the current mode up - by manipulating the "current" offset
-- for the current mode.
--
--
-- Page is a boolean which means:
--
--   false -> Move a single line
--   true  -> Move a single page.
--
function prev (page)
  local mode = Config:get "global.mode"
  local cur = Config.get_with_default(mode .. ".current", 0)

  local offset = 1

  if page then
    if Panel:visible() then
      offset = Screen:height() - Panel:height() - 1
    else
      offset = Screen:height() - 1
    end
  end

  if cur - offset > 0 then
    cur = cur - offset
  else
    cur = 0
  end
  Config:set(mode .. ".current", cur)
end


--
-- Jump to the given offset, in a mode-agnostic fashion.
--
-- Although this only really makes sense in those modes where
-- you have a highlight (i.e. non-simple modes).
--
function jump (offset)
  local mode = Config:get "global.mode"
  local max = Config:get(mode .. ".max")
  if offset <= max then
    Config:set(mode .. ".current", offset - 1)
  end
end


--
-- Scroll to the next maildir containing unread messages, or message
-- which is unread.
--
function next_unread ()

  --
  -- This function only works in maildir or index modes.
  --
  local mode = Config:get "global.mode"
  if (mode ~= "index") and (mode ~= "maildir") then
    return
  end


  --
  -- We know the current offset is stored in `$mode.current`.
  --
  -- We know the maximum offset is stored in `$mode.max`.
  --
  local cur = Config.get_with_default(mode .. ".current", 0)
  local max = Config:get(mode .. ".max")

  --
  -- We'll keep track of how many times we've moved forward
  -- to avoid looping indefinitely.
  --
  local count = -1
  cur = cur + 1


  -- Get the maildirs/messages we'll operate upon.
  local objs

  if mode == "index" then
    objs = get_messages()
  elseif mode == "maildir" then
    objs = maildirs()
  end

  --
  -- Start searching from the current-position
  --
  while count < max do

    -- Bump to the next position, wrapping appropriately.
    cur = cur + 1
    if cur > max then
      cur = 1
    end
    if cur < 1 then
      cur = max
    end

    -- Does this position show an unread "thing" ?
    local unread = false

    if mode == "maildir" then
      -- A maildir is unread if it contains non-read messages.
      local folder = objs[cur]
      if folder and folder:unread_messages() > 0 then
        unread = true
      end
    elseif mode == "index" then
      -- A message is unread if .. it is unread!
      local msg = objs[cur]
      if msg and msg:is_new() then
        unread = true
      end
    end

    -- If we found an unread thing, then select it
    -- and return - first match wins.
    if unread then
      Config:set(mode .. ".current", (cur - 1))
      return
    end

    count = count + 1
  end

  warning_msg "There are no new items to select"
end


--
-- Toggle the panel height between "small" and "large".
--
function panel_size_toggle ()
  local h = Panel:height()

  if h == 6 then
    h = 16
  else
    h = 6
  end

  Panel:height(h)
end


--
-- This function jumps to the previous message, if possible.
--
-- It is only called when viewing a single message.
--
function prev_message ()

  -- Get the messages, and sort.
  local msgs = get_messages()

  -- Get the current offset
  local cur = Config.get_with_default("index.current", 0)

  if cur > 0 then
    cur = cur - 1
    Global:select_message(msgs[cur + 1])
    Config:set("index.current", cur)
  end
end

--
-- This function jumps to the next message, if possible.
--
-- It is only called when viewing a single message.
--
function next_message ()

  -- Get the messages, and sort.
  local msgs = get_messages()

  -- Get the current offset + max
  local cur = Config.get_with_default("index.current", 0)
  local max = Config:get "index.max"

  if cur < (max - 1) then
    cur = cur + 1
    Global:select_message(msgs[cur + 1])
    Config:set("index.current", cur)
  end
end


--
-- Define some utility functions for operating on all visible
-- messages.
--
-- NOTE: These are not bound to any key by default.
--
-----------------------------------------------------------------------------


--
-- Mark all messages as having been read.
--
function mark_all_read ()
  local msgs = get_messages()
  if msgs and #msgs > 0 then
    Fun.object_map('mark_read', msgs)
  else
    warning_msg "There are no messages"
  end
end

--
-- Mark all messages as having NOT been read.
--
function mark_all_new ()
  local msgs = get_messages()
  if msgs and #msgs > 0 then
    Fun.object_map('mark_unread', msgs)
  else
    warning_msg "There are no messages"
  end
end

--
-- Delete all messages.
--
function delete_all ()
  local msgs = get_messages()
  if msgs and #msgs > 0 then
    Fun.object_map("delete", msgs)
  else
    warning_msg "There are no messages"
  end
end


--
-- Define some call-backs which are implemented at various times.
--
-----------------------------------------------------------------------------

--
-- Completion system for Screen:get_line
--
-----------------------------------------------------------------------------
--
-- For better completion results the completion function uses contexts.
-- A context is a function named complete_context, which produces the completion
-- options for this specific situation. Multiple contexts can be set at once.
-- A context function is called with the whole line buffer and is
-- responsible to find the right completion position and completions for its
-- context. It has to return the token its completions are based on and a table
-- of the actual completions.
--
-- The following three contexts are available:
--  * address: completing email addresses calling a external program specified in
--             the config option "complete.addressbookcmd".
--  * path: complete file paths.
--  * lua: complete lua code including lumail's objects.
--
-- To extend the completions add a function handling your custom context.
-- And activate it using set_completion_context("your_context") before the use
-- of Screen:get_line.
--
-- For Example: To add environment variables to shell command completion define
-- this function:
--
--function complete_shell(buffer)
--  local ret = {}
--  local token = buffer:match(".*%${([^}]*)$")
--
--  local handle = io.popen("env | cut -d '=' -f 1")
--  local env_vars = handle:read("*a"):to_table()
--  handle:close()
--
--  for _, var in ipairs(env_vars) do
--    if var:match("^" .. token) then
--      table.insert(ret, var)
--    end
--  end
--  return token, ret
--end
--
-- And activate it for read_execute like this:
--do
--  local _read_execute = read_execute
--  read_execute = function()
--    set_completion_context("shell")
--    _read_execute()
--  end
--end
--
-- An already existing context can be extended in a similar way.
-- To add the email address of your mother to the completions do:
--
--do
--  local _complete_address = complete_address
--  complete_address = function(buffer)
--    -- get old completions
--    local token, ret = _complete_address(buffer)
--    -- add mothers mail
--    table.insert(ret, "mother@domain.com")
--    return token, ret
--  end
--end


do
  --
  -- Table to hold the completion contexts.
  --
  local completion_context = {}

  function set_completion_context(...)
    completion_context = {}
    for i,v in ipairs({...}) do
      completion_context[v] = true
    end
  end

  --
  --- Entry point for the TAB-Completion system for Screen:get_line.
  --
  -- This function is called with the buffer Screen:get_line holds. It
  -- calls the functions for the specified contexts and collects their
  -- completions. After the user chose one completion the buffer is
  -- build with the completion and returned.
  --
  function on_complete (line)
    -- The possible completions.
    local completions = {}

    -- The tokens we complete on.
    local tokens = {}

    -- Index mapping completions to their token.
    local index = {}

    --
    -- Collect all possible completions and their tokens by calling
    -- the context complete functions.
    --
    local i = 1
    for context, _ in pairs(completion_context) do
      local func = _G["complete_"..context]
      if func then
        local token, options = func(line)

        table.insert(tokens, token)

        for _, option in ipairs(options) do
          table.insert(completions, option)
          -- Build our index.
          index[option] = i
        end
      else
        warning_msg("Unknown completion context: \"" .. context .. "\"")
      end
    end

    -- No completion possible
    if #completions == 0 then
      return ""
    end

    local choice = Screen:choose_string(completions)
    if choice ~= "" then
      -- Build the buffer to return
      local token = tokens[index[choice]]
      return line:sub(0, #line-#token) .. choice
    else
      return line
    end
  end

  --
  -- Prompt for a path.
  --
  Screen["get_path"] = function(self, prompt)
    set_completion_context("path")
    return Screen:get_line(prompt)
  end

  --
  -- Prompt for an address.
  --
  Screen["get_address"] = function(self, prompt)
    set_completion_context("address")
    return Screen:get_line(prompt)
  end

  --
  -- Prompt for lua code.
  --
  Screen["get_lua"] = function(self, prompt)
    set_completion_context("lua")
    return Screen:get_line(prompt)
  end
end

--
--- Complete addresses using an external addressbook.
--
-- The completion is done after the last white space.
--
-- The output of the external addressbook should contain one
-- email address per line.
--
function complete_address(buffer)
  local ret = {}

  -- Find the token to complete on.
  -- Our token starts at the last space char in buffer.
  local token_pos = (buffer:reverse():find("%s"))
  local token = ""
  if token_pos then
    token = buffer:sub(#buffer - token_pos + 2)
  else
    token = buffer
  end

  local cmd = Config:get("complete.addressbookcmd")

  -- Check if cmd is set
  if not cmd then
    return token, ret
  end

  local handle = io.popen(cmd .. " \"".. token .. "\"")
  local stdout = handle:read("*a")
  handle:close()

  local function insert_mailaddr(line)
    -- include @ to make sure we match the email address
    local mailaddr = line:match("([^%s]*@[^%s]*)%s")
    if mailaddr then
      table.insert(ret, mailaddr)
    end
  end

  -- get emails from output
  stdout:gsub("(.-)\r?\n", insert_mailaddr)

  return token, ret
end

--
--- Complete lua code.
--
-- The completion is done after last occurence of ( ' " or space in the buffer.
--
function complete_lua(buffer)
  local ret = {}

  -- Find the token to complete on.
  local token_pos = (buffer:reverse():find("[(\"'%s]"))
  local token = ""
  if token_pos then
    token = buffer:sub(#buffer - token_pos + 2)
  else
    token = buffer
  end

  --
  -- Add in our local objects.
  --
  local objs = {}
  objs["Config:"] = Config
  objs["Directory:"] = Directory
  objs["File:"] = File
  objs["Global:"] = Global
  objs["Log:"] = Log
  objs["Maildir:"] = Maildir
  objs["Message:"] = Message
  objs["Net:"] = Net
  objs["Panel:"] = Panel
  objs["Screen:"] = Screen

  for name, object in pairs(objs) do
    for key, _ in pairs(object) do
      -- TODO escape token
      if not string.match(key, "^_") and string.match(name .. key, "^" .. token) then
        table.insert(ret, name .. key)
      end
    end
  end

  --
  -- Add in all user-defined functions.
  --
  for k, _ in pairs(_G) do
    if string.match(k, "^" .. token) then
      table.insert(ret, k)
    end
  end

  return token, ret
end

--
--- Complete paths.
--
-- The completion is done on the whole buffer.
--
function complete_path(buffer)
  local ret = {}

  local token = buffer

  --
  -- If the token starts with "~" then replace that with
  -- the users' home-directory.
  --
  if string.sub(token, 0, 1) == "~" then
    token = string.sub(token, 2)
    token = os.getenv "HOME" .. token

  --
  -- If the token doesn't start with '/' it is a relative path
  -- and we have to make it absolute.
  --
  elseif not string.match(token, "^/") then
    -- get pwd
    local handle = io.popen("pwd")
    local pwd = handle:read("*a"):sub(0, -2) --strip new line
    handle:close()
    token = pwd .. "/" .. token
  end

  --
  -- Get the last directory in the token.
  --
  -- Default to / if we can't find one.
  --
  dir = string.match(token, "^(.*)/")
  if dir == "" then
    dir = "/"
  end

  --
  -- If the directory exists then add all the entries to the completion-set.
  --
  if Directory:exists(dir) then
    entries = Directory:entries(dir)
    for i, v in ipairs(entries) do
      if string.match(v, "^" .. token) then
        if Directory:exists(v) then
          v = v .. "/"
        end
        table.insert(ret, v)
      end
    end
  end
  return buffer, ret
end

--
-- Handle timers
--
-----------------------------------------------------------------------------
--
-- In the past we'd expect users to override "on_idle()" to invoke
-- the scheduling of "stuff", but this proved to be complex because
-- it meant that all releases which touched this code would require
-- rewriting.
--
-- We already had some magic for keeping state, so this was improved
-- and now you can define arbitrary functions that will be invoked
-- on regular schedule just via their name.
--
-- So, for example, define the function `on_XX()` in your personal
-- configuration file.
--
-- Assuming XX is a number then the function will be invoked at that
-- frequency.  So `on_1()` will be invoked every second, `on_2()` every
-- two seconds, etc.
--
-- As a concrete example this runs every five minutes:
--
--   function on_300()
--     Panel:append( "I'm called every five minutes" )
--   end
--
-- The only caveat here is that you can only define one function
-- for any given frequency.
--
--
do

  --
  -- Table to hold the idle-timers the user has defined.
  --
  --  Key: The number of seconds between invocations.
  --
  --  Val: A hash containing the function to invoke, and the last time
  --       it was invoked.
  --
  local idle_timers = nil


  function on_idle ()

    --
    -- Initialize our callback-table, if it is empty.
    --
    if idle_timers == nil then

      -- Ensure the timer-list is a table.
      idle_timers = {}

      -- Get the current time
      local now = os.time()

      -- Loop over all the things in the global scope.
      for n, o in pairs(_G) do

        -- Is it a function?
        if type(o) == "function" then

          -- Is the name of the function "on_NNN" ?
          local period = string.match(n, "^on%_(%d+)$")
          if period then
            -- Save the result away.
            idle_timers[period] = {
              callback = o,
              last = now,



            }
          end
        end
      end
    end

    --
    -- Now we're in the routine that will run every second.
    --
    ct = os.time()

    -- Iterate over our timer-table
    for i, o in pairs(idle_timers) do

      -- Get the function to invoke.
      local func = idle_timers[i]['callback']

      -- Get the last time this function was last called.
      local last = idle_timers[i]['last']

      -- If the threshold has passed then..
      if (tonumber(ct) - tonumber(last)) >= tonumber(i) then
        -- Update the last-called time
        idle_timers[i]['last'] = ct
        -- Invoke the function.
        func()
      end
    end
  end

  --
  -- End of closure.
  --
end


--
-- This function is invoked before a message is sent.
--
-- function on_message_send(path)
--
--   -- Read the recipient of the message
--   local m  = Message.new(path)
--   local to = m:header("To")
--   to       = string.match(to, "<(.*)>") or to
--
--   -- Here we could update our outgoing mail-agent to use msmtp
--   local mta = "/usr/bin/msmtp -a blah " .. to
--   Config:set( "global.mailer", mta )
--   Panel:append( "Mailer set to " .. mta )
-- end


--
-- This function, if it is defined, is invoked just after a message
-- is sent.
--
-- function on_message_sent(path)
-- end


--
-- Utility function to show what a key is bound to.
--
-- Bound to "?" in keybinding-mode.
--
function show_key_binding ()
  local c = Screen:get_char "Input key?"
  if c == nil or c == "" then
    return
  end

  --
  -- Lookup per-mode value.
  --
  local mode = Config:get "global.mode"

  if keymap[mode] and keymap[mode][c] then
    Panel:append(c .. " is bound to " .. keymap[mode][c])
    return
  end

  --
  -- Lookup global mode.
  --
  if keymap['global'][c] then
    Panel:append(c .. " is bound to " .. keymap['global'][c])
    return
  end
  Panel:append(c .. " is not bound to anything")
end




--
-- Handle legacy setups
--
if ( Directory:exists( "/etc/lumail2/perl.d" ) ) then
   info_msg( "WARNING: Obsolete directory detected /etc/lumail2/perl.d" )
   info_msg( "Please see: https://lumail.org/install/#upgrade" )
end
if ( Directory:exists( "/etc/lumail2/lib" ) ) then
   info_msg( "WARNING: Obsolete directory detected /etc/lumail2/perl.d" )
   info_msg( "Please see: https://lumail.org/install/#upgrade" )
end

--
-- Now load our per-user configuration files
--
-- This is divided into two parts:
--
--  * Legacy files which will be removed in the future.
--
--  * New/Current files which are the preferred location for
--    user configuration.
--
local legacy_config = {}
local current_config = {}

-- Hostname-specific lua file.
local hostname = Net:hostname() .. ".lua"

table.insert( legacy_config,
              File:expand( "$HOME/.lumail2/lumail2.lua" ) )
table.insert( legacy_config,
              File:expand( "$HOME/.lumail2/config.lua" ) )
table.insert( legacy_config,
              File:expand( "$HOME/.lumail2/" .. hostname ) )

--
-- preferred/new/modern config-location
--
table.insert( legacy_config,
              File:expand( "$XDG_CONFIG_HOME/lumail/lumail.lua" ) )
table.insert( legacy_config,
              File:expand( "$XDG_CONFIG_HOME/lumail/config.lua" ) )
table.insert( legacy_config,
              File:expand( "$XDG_CONFIG_HOME/lumail/" .. hostname ) )
table.insert( current_config,
              File:expand( "$HOME/.config/lumail/lumail.lua" ) )
table.insert( current_config,
              File:expand( "$HOME/.config/lumail/config.lua" ) )
table.insert( current_config,
              File:expand( "$HOME/.config/lumail/" .. hostname ) )
table.insert( current_config,
              File:expand( "$HOME/.lumail/lumail.lua" ) )
table.insert( current_config,
              File:expand( "$HOME/.lumail/config.lua" ) )
table.insert( current_config,
              File:expand( "$HOME/.lumail/" .. hostname ) )


--
--  Handle the loading of legacy config
--
local warned = false

for i, o in ipairs(legacy_config) do
   if ( File:exists( File:expand( o ) ) ) then
      dofile( File:expand( o ) )
      if ( not warned ) then
         warning_msg( "Loading legacy config file - " .. o )
         warning_msg( "See: https://lumail.org/getting-started/" )
         warned = true
      end
   end
end
for i, o in ipairs(current_config) do
   if ( File:exists( File:expand( o ) ) ) then
      dofile( File:expand( o ) )
   end
end


--
--   Handle any command-line arguments
--
-----------------------------------------------------------------------------

for index, arg in ipairs(ARGS) do

  --
  -- Look for --folder=foo
  --
  local folder = string.match(arg, "--folder=(.*)")
  if folder then
    Config:set("maildir.limit", "all")
    Maildir.select(folder, true)
  end

end
