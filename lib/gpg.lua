--
-- Decrypt the message into a temporary file and return its path.
--
local decrypt = function(path)
  --
  -- Do we have the binary we want?
  --
  if string.path "mimegpg" ~= "" then
    local out = os.tmpname()
    os.execute("mimegpg -d -c -- --batch < " .. path .. " > " .. out)
    return out
  else
    return ""
  end
end

--
-- This is a function which is inserted into the *MIDDLE*
-- of a message parsing operation.
--
-- This means you CANNOT call `parts()` or similar, on a constructed
-- message, because if you do you'll end up in a never-ending recursive
-- loop.
--
-- The only thing you can do is *replace* the contents of the body
-- if you wish.
--
-- This function allows the caller to modify the message _before_ it
-- is parsed, and the way this is done is to replace the file that
-- is operated upon.
--
-- In short :
--
--  * This function is called with the path to the message, on-disk.
--
--  * This function may return "" to leave things as-is.
--
-- OR
--
--  * This function may generate and return a filename.  That file
--    will be operated upon instead of the input message, and once
--    parsed will be deleted.
--
--
-- So if you wanted to do something crazy, like read only upper-case
-- messages, you could do that by running:
--
--   function message_replace(path)
--     local out = "/tmp/blah"
--     os.execute( "tr '[a-z]' '[A-Z]' <" .. path .. " >" .. out )
--     return( out )
--   end
--
--
_G['message_replace'] = function (path)

  --
  --  If the file doesn't reference GPG then we're OK to return
  -- early.
  --
  local found = false

  --
  -- We're going to invoke `mimegpg` and that will EITHER decrypt
  -- OR verify.
  --
  -- So we need to accept both kinds of messages here.
  --
  for line in io.lines(path) do
    if (line == "-----BEGIN PGP SIGNATURE-----") or (line == "-----BEGIN PGP MESSAGE-----") then
      found = true
    end
  end

  if found == false then
    return ""
  end
  return decrypt(path)
end


--
-- GPG module
--
local gpg = {}

gpg.decrypt = decrypt

--
-- Return the arguments for mimegpg
--  s/S = sign
--  e/E = encrypt
--  b/B = sign and encrypt
--  n/Everything else = nothing
--
gpg.mimegpg_args = function(switch)
  if (switch == "s") or (switch == "S") then
    return "-s"
  elseif (switch == "e") or (switch == "E") then
    return "-E -- --batch -r ${recipient} --trust-model always"
  elseif (switch == "b") or (switch == "B") then
    return"-s -E -- --batch -r ${recipient} --trust-model always"
  else
    return ""
  end
end

--
--- Return the default gpg options depending on the config value "gpg.mode"
--
--  "always":
--    Set the gpg options to always encrypt and sign by default.
--  "auto":
--    Check if the recipient uses pgp and only if he/she does,
--    sign and encrypt the mail without user interaction.
--
gpg.defaults = function(recipient)
  local mode = Config.get_with_default("gpg.mode", "")
  if mode == "" then
    return ""
  elseif mode == "always" then
    return gpg.mimegpg_args("b")
  elseif mode == "auto" then
    -- Check if a key is available for the recipients mail address
    recipient = recipient:match("<(.*)>") or recipient
    local has_gpg = os.execute(string.format("gpg --list-keys | grep -q '%s'", recipient))
    if has_gpg then
      return gpg.mimegpg_args("b")
    else
      return ""
    end
  else
    -- TODO Is this output legit in a library ???
    error_msg("GPG mode:" .. mode .. " is unknown")
    return ""
  end
end

--
-- Prompt for gpg options
--
gpg.prompt = function(options)
  choice = Screen:prompt("(c)ancel, (n)othing, (s)ign, (e)ncryt, or (b)oth?", "nNcCsSeEbB")
  if (choice == "c") or (choice == "C") then
    return options
  else
    return gpg.mimegpg_args(choice)
  end
end

--
-- Invoke mimegpg and replace the mail with its output
--
gpg.replace_mail = function(mail, options, recipient)
  local tmp = os.tmpname()

  -- Build up the command.
  local cmd = "mimegpg " .. options .. "< " .. mail .. " > " .. tmp

  -- Replace the recipient, if present.
  cmd = string.interp(cmd, { recipient = recipient:match("<(.*)>") or recipient, })

  -- Run the command.
  -- TODO capture and present stderr.
  if os.execute(cmd) then
    -- Replace the mail with our temporary file.
    os.remove(mail)
    return tmp
  else
    error_msg("GPG: mimegpg failed")
    -- Mimegpg failed. Clean up our tmp file and return the old mail
    os.remove(tmp)
    return mail
  end

end

return gpg
