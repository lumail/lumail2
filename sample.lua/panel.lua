--
--
-- Usage:
--
--     lumail --load-file ./panel.lua
--
--
-- Once loaded execute the lua-prompt by typing ":" and enter
-- "date()" or "hostname()".
--


function show_command_output (title, cmd)
  Panel:title("Output of running '" .. cmd .. "'")

  local handle = io.popen(cmd)
  local result = handle:read "*a"
  handle:close()

  Panel:append(title)
  Panel:append("\t" .. result)

  if Panel:visible() == false then
    Panel:show()
  end
end


function date ()
  show_command_output("The date is:", "date")
end

function hostname ()
  show_command_output("This host has hostname:", "hostname")
end
