--
-- lumail.lua - Init file for lumail.
--


--
-- The single mandatory setting is the prefix for the
-- maildir hierarchy.
--
set_maildir( os.getenv( "HOME" ) .. "/Maildir" );

--
-- Show all folders by default
--
sidebar_limit( "all" );


--
-- This function is called when the client launches.
--
-- You might use something like this, usefully:
--
--    os.execute( "imapsync ..." );
--
function on_start()
   msg("I've started" );
end


--
-- Show the version
--
function show_version()
   msg("This is lumail version " .. VERSION );
end


--
-- This function is called when the client exits.
--
-- It could be used to do many things..
--
function on_exit()
   print("print: on_exit");
   io.write( "io.write: on_exit\n")
   io.write("The global mode is: '" .. global_mode() .. "'.\n");
   io.write("The limit is " .. sidebar_limit() .. "\n" );
end


--
-- This function is called when the client is idle.
--
-- You might run something like:
--
--   if the current-time is a multiple of five-minutes
--     os.execute("imapsync ..")
--
-- You might prefer to call fetchmail, or similar.
--
function on_idle()
   msg( "I am the lua function 'on_idle' - " .. os.date() .. "\n")
end


--
-- Switch to the index-view mode.
--
function index()
   global_mode( "index" );
   clear();
end

--
-- Switch to the maildir-mode.
--
function maildir()
   global_mode( "maildir" );
   clear();
end

--
-- When in maildir-mode show all folders.
--
function all_folders()
   sidebar_limit( "all" );
   clear();
end

--
-- When in maildir-mode show all folders which contain unread messages.
--
function new_folders()
   sidebar_limit( "new" );
   clear();
end

--
-- When in maildir-mode show all folders which have a path matching the given pattern.
--
function livejournal_folders()
   sidebar_limit( "livejournal.2" );
   clear();
end

--
-- Now setup keymaps for the different modes.
--
-- The same keypress might do different things in different modes,
-- which is one of the advantages of a modal-client.
--
--
--  TODO: Should there be a global-keymap?  For example:
--
--   keymap['q'] = 'exit()';
--
keymap = {}
keymap['index']   = {}
keymap['message'] = {}
keymap['maildir'] = {}

--
-- globally exit
--
keymap['index']['q']   = "exit()"
keymap['message']['q'] = "exit()"
keymap['maildir']['q'] = "exit()"

--
-- REPL-like-mode.
--
keymap['index'][':']   = "loadstring(prompt(\":\"))();";
keymap['message'][':'] = "loadstring(prompt(\":\"))();";
keymap['maildir'][':'] = "loadstring(prompt(\":\"))();";

--
-- Execute a shell command.
--
keymap['index']['!']   = "exec(prompt(\":\"));";
keymap['message']['!'] = "exec(prompt(\":\"));";
keymap['maildir']['!'] = "exec(prompt(\":\"));";

--
-- Show the client version
--
keymap['maildir']['v'] = 'show_version()'
keymap['index']['v']   = 'show_version()'
keymap['message']['v'] = 'show_version()'

--
-- Move to Maildir-mode
--
keymap['index']['M']   = 'maildir()';
keymap['message']['M'] = 'maildir()';
keymap['maildir']['M'] = 'maildir()';

--
-- Move to Index-mode
--
keymap['index']['I']   = 'index()';
keymap['message']['I'] = 'index()';
keymap['maildir']['I'] = 'index()';



--
-- Toggle display of folders
--
keymap['maildir']['a'] = 'all_folders()'
keymap['maildir']['n'] = 'new_folders()'
keymap['maildir']['l'] = 'livejournal_folders()'

