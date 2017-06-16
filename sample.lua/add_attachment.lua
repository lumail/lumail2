--
--
-- Usage:
--
--     lumail --load-file ./add_attachment.lua --no-curses
--
--


--
-- Create a new message-file on-disk
--
local path = "msg.txt"
local file = assert(io.open(path, "w"))

--
-- The content we'll write
--
header = [[To:Steve Kemp<steve@example.com>
From: Steve Kemp <steve@example.net>
Subject: This is a test


I like cakes.

Steve
--
]]

--
-- Write it out
--
file:write(header)
file:close()


--
-- Now we'll create a Message object with that file
--
msg = Message.new(path)

--
-- Add an some attachments
--
local files = {
  "/etc/passwd",
  "/etc/motd",
  "/bin/ls",



}
msg:add_attachments(files)

--
-- Now we're done, show the result
--
os.execute("less " .. msg:path())
