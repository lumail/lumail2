--
--
-- Usage:
--
--     lumail --load-file ./net.lua --no-curses
--
--


--
-- Show the hostname
--
print("The hostname of this system is " .. Net:hostname())
print("Random Message-ID: " .. Message:generate_message_id())
