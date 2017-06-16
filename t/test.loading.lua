--
-- Configure a sane load-path
--
package.path = package.path .. ";t/?.lua;../lib/?.lua;lib/?.lua"

--
-- Require our unit-testing framework.
--
luaunit = require 'luaunit'

--
-- Mocked opbjects
--
ARGS = {}
Cache = {}
Config = {}
File = {}
Global = {}
Maildir = {}
Message = {}
Net = {}
Panel = {}
Screen = {}

--
-- Mocked functions
--
function Config:get (x)
  return nil
end
function Cache:new ()
  return false
end
function File:exists ()
  return false
end
function Global:modes ()
  return {
    "index",
    "maildir",
    "message",
    "keybinding",
    "life",
    "attachment",


  }
end
function Net:hostname ()
  return "foo.bar.local"
end
function Panel:append (txt)
end
function Screen:height ()
  return 25
end
function Screen:width ()
  return 80
end
function Screen:exit ()
end


--
-- Load our main configuration file.
--
-- This is actually the test - we're looking for references to
-- other libraries failing, syntax errors, etc.
--
local loaded_lua = require "lumail"


--
-- This is really a NOP - we're just pleased we could load
-- the library in the previous section
--
function TestLumail ()
  --
  -- So we're running
  --
  luaunit.assertIsTrue(loaded_lua)

  --
  -- Test some functions exist.
  --
  luaunit.assertIsFunction(attachment_view)
  luaunit.assertIsFunction(index_view)
  luaunit.assertIsFunction(lua_view)
  luaunit.assertIsFunction(lua_view)
  luaunit.assertIsFunction(maildir_view)
  luaunit.assertIsFunction(message_view)
  luaunit.assertIsFunction(panel_view)
end


--
-- Run the tests
--
os.exit(luaunit.LuaUnit.run())
