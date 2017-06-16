--
--
-- Usage:
--
--     lumail --load-file ./mime_type.lua --no-curses
--
--


--
-- For each file
--
local files = {
  "/etc/passwd",
  "/etc/motd",
  "/bin/ls",



}

--
-- Show the file + type
--
for i, o in ipairs(files) do
  if File:exists(o) then
    print(string.format("%64s - %32s", o, MIME.type(o)))
  end
end
