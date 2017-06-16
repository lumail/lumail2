--
--
-- Usage:
--
--     lumail --no-curses --load-file ./config.lua
--


--
-- Test a string-value
--
function test_string ()

  orig = Config:get "steve"
  if orig then
    print("ERROR - Unset value is non-nil: " .. orig)
  else
    print "Value is nil without setting it"
  end

  Config:set("name", "Steve Kemp")
  print("After setting a value retrieval works " .. Config:get "name")
end


--
-- Test getting/setting a table.
--
function test_table ()

  flowers = {
    "rose",
    "daisy",
    "tulip",



  }

  print "Our table contains:"
  for k, v in ipairs(flowers) do
    print("\t" .. v)
  end

  --
  -- Set the table value
  --
  Config:set("flowers", flowers)

  --
  -- Retrieve the values
  --
  out = Config:get "flowers"
  print "After retrieving our table has:"
  for k, v in ipairs(out) do
    print("\t" .. v)
  end
end


test_table()
test_string()


--
-- Define a notification function, this will get invoked
-- when future keys are updated.
--
function Config.key_changed (name)
  print("The value was changed of the key : " .. name)
  print("\tNew value: " .. Config:get(name))
end
print "\n"

--
-- I like a good pie - note that the configuration holder stores
-- integers only, and will truncate our float.
--
Config:set("π", 3.14159265359)
print("π is " .. Config:get "π" .. " (truncated to integer.  Oops!)")

--
-- I like watching the names change.
--
Config:set("name", "Steve Kemp")
Config:set("name", "Bob Smith")

--
-- Finally show the names of each of the keys which we set.
--
print "\n"
for k, v in ipairs(Config:keys()) do
  print("We've set the configuration-key with name " .. v)

  val = Config:get(v)

  print("\tThis has type '" .. type(val) .. "'")

end
