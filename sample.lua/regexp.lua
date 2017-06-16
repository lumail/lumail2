--
--
-- Usage:
--
--     lumail --no-curses --load-file ./regexp.lua
--


--
-- Simple match
--
local res = Regexp:match("[kh]emp$", "Steve Kemp")
if res == true then
  print "OK 1"
end

--
-- Failing match
local res = Regexp:match("Lamp", "Steve Kemp")
if res == false then
  print "OK 2"
end

local tab = Regexp:match("([0-9]+).([0-9]+).([0-9]+).([0-9]+)", "1.22.333.444")

if type(tab) == "table" then
  print "OK 3"
  for i, o in ipairs(tab) do
    print("\tCapture Group " .. i .. " contains " .. o)
  end
end
