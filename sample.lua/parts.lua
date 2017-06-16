--
--
-- Usage:
--
--     lumail --no-curses --load-file ./parts.lua
--


function show_folder (path)

  folder = Maildir.new(path)
  print("\nFolder : " .. folder:path())

  --
  --  Pick the first message from the folder.
  --
  messages = folder:messages()
  random_message = messages[1]

  --
  -- Get the MIME-parts.
  --
  parts = random_message:parts()
  print("The message " .. random_message:path() .. " has " .. #parts .. " MIME-parts")

  --
  -- Output a summary of the MIME-parts.
  --
  for i = 1, #parts do
    entry = parts[i]
    print("Content-Type of part " .. i .. "  is " .. entry:type())
    if entry:is_attachment() then
      print("\tThis is an attachment - with filename : " .. entry:filename())
    end

  end

  --
  -- Repeat that, in a different way, just to prove it works.
  --
  print "Repeating that information:"
  for k, v in ipairs(parts) do
    print("\t" .. v:type())
    if v:is_attachment() then
      print("\t\tThis is an attachment - with filename : " .. v:filename())
    end

    --
    -- If we're handing the simple-folder then show the message.
    --
    if string.find(folder:path(), "simple") then
      print(v:content())
    end

  end
end


--
-- Load the maildirs from beneath the pwd.
--
folders = get_maildirs "./Maildir/"

--
-- Show some details.
--
for k, v in ipairs(folders) do
  print("We found a folder - " .. v:path() .. " which is number " .. k)
  print("\tThere are " .. v:total_messages() .. " total messages in " .. v:path())
  print("\tThere are " .. v:unread_messages() .. " unread messages in " .. v:path())

end


--
--  Show both of the folders - NOTE the second one will have the message
--  output too.
--
show_folder "./Maildir/simple"
show_folder "./Maildir/attachment"
