--
--
-- Usage:
--
--     lumail --load-file ./screen.lua
--


Screen:clear()
print("Screen is has dimensions:" .. Screen:width() .. "x" .. Screen:height())

Screen:sleep(2)

print("Screen still has dimensions:" .. Screen:width() .. "x" .. Screen:height())
print("Screen still has dimensions:" .. Screen:width() .. "x" .. Screen:height())
print("Screen still has dimensions:" .. Screen:width() .. "x" .. Screen:height())


print(Screen:get_line())

Screen:sleep(3)
