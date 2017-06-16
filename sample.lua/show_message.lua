--
--
-- Usage:
--
--     lumail --no-curses --load-file ./show_message.lua --msg path/to/show
--

function show_message (file)

  --
  -- Ensure the file exists
  --
  if not File:exists(file) then
    print("File doesn't exist: " .. file)
    return
  end

  m = Message.new(file)

  --
  -- The headers we want to show
  --
  headers = {
    "To",
    "From",
    "Cc",
    "Subject",
    "Date",



  }

  --
  -- For each header, get it, and show it
  --
  for i, header in ipairs(headers) do
    value = m:header(header) or "[unset]"
    if value then
      print(header .. ": " .. value)
    end
  end

  --
  -- Print a newline
  --
  print ""

  --
  -- Now look for the first text/* content-type
  --
  parts = m:parts()

  shown = false
  for i, part in ipairs(parts) do
    if shown == false then

      --
      -- Get the content-type of this part.
      --
      ct = part:type()

      if string.find(ct, "text/") then
        print(part:content())
        shown = true
      end
    end
  end

  --
  -- Did we show the body?
  --
  if shown == false then
    print "Failed to show the body of the message"
  end

  --
  -- Are there any attachments?
  --
  print ""
  for i, part in ipairs(parts) do
    if part:is_attachment() then
      print("Attachment: " .. part:filename())
    end
  end
end


--
-- Iterate over the command-line arguments
--
for i, v in ipairs(ARGS) do
  local path = string.match(v, "--msg=(.*)")
  if path then
    show_message(path)
    os.exit(1)
  end
end

--
-- No exit means we had no match.
--
print "Usage: lumail --no-curses --load-file ./show_message.lua --msg=path/to/maildir/msg"
