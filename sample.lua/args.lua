--
--
-- Usage:
--
--     lumail --load-file ./args.lua --no-curses --foo --bar
--
--


--
-- Process all arguments
--
for i, v in ipairs(ARGS) do

  -- Show it
  print("Argument " .. i .. " is " .. v)


  -- Sample handling of a real Lua-used-flag
  folder = string.match(v, "--folder=(.*)")
  if folder then
    print("Should open folder " .. folder)
  end
end
