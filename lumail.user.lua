--
-- This is the per-user configuration file for lumail.
--
-- To make it active copy it to either:
--
--   ~/.lumail/lumail.lua
--   ~/.luamil/$(hostname --fqdn).lua
--
-- Changes here will override the defaults which are loaded by the
-- global configuration file (/etc/lumail/lumail.lua).
--
-- It is *highly* recommended you follow this approach, because this
-- will ensure that upgrades do not trash your edits.
--
-- If there are omissions where per-user configuration makes it impossible
-- to configure things as you wish they are bugs, and should be reported
-- as such.
--
--


--
-- NOTE: If you wish you may re-declare any global configuration functions
--       in this file, or remap keybindings.
--
-- For example I like to use `ctrl-w` to exit the client:
--
keymap['global']['^W'] = 'os.exit(1)'


--
-----------------------------------------------------------------------------

--
-- The following line enables *experimental* conversion of message-bodies
-- to UTF-8.
--
-- You might require this to be enabled if you receive mail in foreign
-- character-sets.  It should be harmless when enabled, but character-sets,
-- encoding, and similar, are scary and hard.  If you see garbled text,
-- unreadable emails, or similar problems with displaying message-bodies
-- comment it out as a first step in isolating the problem.
--
Config:set("global.iconv", 1)


--
-- The following flag configures our index-mode to only format
-- messages which are visible.
--
-- This is a huge performance boost if you have thousands of messages
-- in a folder, OR if you're using IMAP.
--
-- The downside is that searching through messages "/" and `?`,
-- will break, as items off-screen won't be formatted.
--
Config:set("index.fast", 1)

--
-- Get our home-directory, as this is often used.
--
local HOME = os.getenv "HOME"

--
-- The default Maildir location is ~/Maildir
--
if Directory:exists(HOME .. "/Maildir") then
  Config:set("maildir.prefix", HOME .. "/Maildir")
else
  warning_msg"No $[WHITE|BOLD]Maildir$[WHITE] prefix found!"
end

--
-- NOTE: You could also set an array of prefixes, which will be
-- merged and sorted.
--
-- Config:set( "maildir.prefix", { "/home/steve/Maildir", "/tmp/Maildir" } )
--


--
-- When sending mails a copy of the outgoing message will
-- be archived in the "sent" folder.
--
-- Here we configure the location of that sent-folder.
--
local def_save = HOME .. "/Maildir/sent-mail"
if Directory:is_maildir(def_save) then
  Config:set("global.sent-mail", def_save)
else
  warning_msg "No sent-mail folder defined!"
end


--
-- Setup our MTA, the command which actually sends the mail.
--
if File:exists "/usr/lib/sendmail" then
  Config:set("global.mailer", "/usr/lib/sendmail -t")
elseif File:exists "/usr/sbin/sendmail" then
  Config:set("global.mailer", "/usr/sbin/sendmail -t")
else
  warning_msg "No sendmail binary found!"
end

--
-- Setup our default editor, for compose/reply/forward operations.
--
Config:set("global.editor", "vim  +/^$ ++1 '+set tw=72'")

--
-- Setup our default From: address.
--
Config:set("global.sender", "Some User <steve@example.com>")

--
-- Unread messages/maildirs are drawn in red.
--
Config:set("colour.unread", "red")

--
-- Save persistent history of our input in the named file.
--
-- Create ~/.lumail/history/ if missing
--
if not Directory:exists(HOME .. "/.lumail/history") then
  Directory:mkdir(HOME .. "/.lumail/history")
end

--
-- Write our history to ~/.lumail/history/$HOSTNAME.
--
Config:set("global.history", HOME .. "/.lumail/history/" .. Net:hostname())


--
-- Configure a cache-prefix, and populate it
--
Config:set("cache.prefix", HOME .. "/.lumail/cache")


--
-- Set the default sorting method.  Valid choices are:
--
--  `file`   - Use the mtime of the files in the maildir.
--  `date`   - Read the `Date` header of the message(s) - slower than the
--             above method, but works on IMAP too.
--  `subject` - Sort by subject.
--  `from`    - Sort by sender.
--  `threads` - Sort in threads.
--
--  If the sort method is set to `threads` two extra configuration values are used:
--
--    * `threads.output`: It specify the signs used to visually group a thread.
--                        It must be in the format <indent>;<root-sign>;<sign>'.
--
--                        For example:
--                        Config:set("threads.output", " ;`;-> "), which is the
--                        default results in output like this:
--
--                        Message A
--                        `-> Child A.A
--                         `-> Child A.A.A
--                        `-> Child A.B
--                        Message B
--                        -> Child C.A without available parent C
--
--    * `threads.sort`: It specified how the threads are ordered. All sorting
--                      methods are valid except `threads`.
--
--
sorting_method "file"

--
--  IMAP setup
--
--  The previous configuration set Lumail to read Maildirs
-- beneath ~/Maildir/
--
--  If you prefer you can load mail from a remote IMAP server
-- to do that set the following values appropriately
--
--
--   -- Setup defaults
--   Config:set( "imap.cache", HOME .. "/.lumail/imap.cache" )
--   Config:set( "index.sort", "none" )
--   Config:set( "index.fast", "1" )
--
--   -- The proxy-program we're using
--   Config:set( "imap.proxy", "/etc/lumail/perl.d/imap-proxy" )
--
--   -- Now setup login-details
--   Config:set( "imap.server",   "imaps://imap.gmail.com/" )
--   Config:set( "imap.username", "gmail.username" )
--   Config:set( "imap.password", "pass.word.here" )
--
--  IMAP support is still a little experimental, and for more details
-- you should consult the `IMAP.md` file which comes with lumail.
--


--
-- This table contains colouring information, it is designed to allow
-- the user to override the colours used in the display easily.
--
colour_table = {}

--
-- Create a per-mode map for each known mode.
--
for i, o in ipairs(Global:modes()) do
  colour_table[o] = {}
end


--
-- Setup our colours - for Maildir-mode
--
colour_table['maildir'] = {
  ['Automated'] = 'yellow|underline',
  ['lists'] = 'green|bold',
}

-- Setup our colours - for index-mode
colour_table['index'] = {
  ['Steve'] = 'blue',
  ['Ian'] = 'blue',
}

-- Setup our colours - for a message
colour_table['message'] = {
  -- headers
  ['^Subject:'] = 'yellow',
  ['^Date:'] = 'yellow',
  ['^From:'] = 'yellow',
  ['^To:'] = 'yellow',
  ['^Cc:'] = 'yellow',
  ['^Sent:'] = 'yellow',

  -- quoting, and nested quoting.
  ['^>%s*>%s*'] = 'green',
  ['^>%s*[^>%s]'] = 'blue',
  ['^>%s$'] = 'blue',
}


--
-- Finally we might want to tweak the way that mail-folders, message-lists
-- and attachment-views are displayed.
--
-- Each of these views uses a simple template which is expanded for each
-- entry.  The defaults are set in the main `lumail.lua` configuration file
-- and are as follows.
--
--
-- Attachment mode - shows attachments for messages:
--
--  Config:set( "attachment.format",
--              "[${4|number}] ${6|size} - ${25|type} - ${filename}" )
--
--  Options include:
--
--   number      -> The attachment number.
--   size        -> The attachment size, in bytes.
--   type        -> The MIME-type of the attachment.
--   filename    -> The attachment filename.
--
--
-- Index mode - which shows the list of messages:
--
--  Config:set( "index.format",
--             "[${4|flags}] ${2|message_flags} - ${20|sender} - ${indent}${subject}" )
--
--  Options include:
--
--   date          -> The message date.
--   flags         -> The local flags.
--   id            -> Message-ID.
--   indent        -> Nesting character(s) for the display of threads.
--   message_flags -> The message-content flags (has attachment? is signed?).
--   number        -> The message number.
--   sender        -> The sender of the message: "Bob Smith <bob@example.com>"
--     email         -> bob@example.com
--     name          -> Bob Smith
--   subject       -> The message subject.
--
--
--  Maildir mode - the list of folders.
--
--   Config:set( "maildir.format",
--               "${number} [${05|unread}/${05|total}] - ${path}" )
--
--
--  Options include:
--
--     number  -> The folder number
--     path    -> The path the folder represents.
--     total   -> The total number of messages in the folder.
--     unread  -> The number of unread messages in the folder.
--
--
