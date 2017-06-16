
[![Build Status](https://travis-ci.org/lumail/lumail.png)](https://travis-ci.org/lumail/lumail)
[![license](https://img.shields.io/github/license/lumail/lumail.svg)]()


lumail
=======

This repository contains the `lumail` console-based email client, with fully integrated scripting provided by Lua.

This is the second version of lumail which has been written, learning the lessons from the [initial version](https://github.com/lumail/lumail).  With this codebase:

* The C++ core, and Lua scripting support, is much more consistent.
* More parts of the core have been pushed to Lua.
    * To allow customization.
    * To allow flexibility.

The project is perpetually a work in-progress, but despite that the client is functional, stable, reliable and robust:

* All the obvious operations may be carried out:
     * Viewing folder-hierarchies.
     * Viewing the contents of a folder.
     * Reading emails.
     * Replying to emails.
     * Forwarding emails.
     * Composing fresh emails.
     * Deleting emails.
     * Scripting, transforming, and customizing the various display modes.

Each of the operations works against both local-maildir hierarchies, and [remote IMAP servers](IMAP.md).


User-Interface
--------------

The user-interface should be broadly familiar to users of previous, legacy, project. If you're new to the project the following screencast shows what it looks
like and gives a hint of how it can be used:

* https://asciinema.org/a/chdqz6tb4vt9p3ifp32g4musa

It should be noted that __all__ of the display-modes are created/maintained by
Lua code, which means it is possible for you to customize most of the views
you can see, via pure Lua code.

Because this is a modal-application you're always in one of a fixed number
of modes:

* `maildir`-mode
    * Allows you to see a list of message-folders.
* `index`-mode
    * Allows you to view a list of messages.
    * i.e. The contents of a folder.
* `message`-mode
    * Allows you to view a single message.
    * `attachment`-mode is related, allowing you to view the attachments associated with a particular message.
* `lua`-mode.
    * This mode displays diagnostics and other internal details.
* `keybinding`-mode.
    * Shows you the keybindings which are in-use.
    * Press `H` to enter this mode, and `q` to return from it.


Building Lumail
----------------

The core of the project relies upon a small number of libraries:

* lua 5.2.
* libmagic, the file-identification library.
* libgmime-2.6, the MIME-library.
* libncursesw, the console input/graphics library.


### Linux

Upon a Debian GNU/Linux host, running the Jessie (stable) release, the following command is sufficient to install the required dependencies:

     apt-get install build-essential libgmime-2.6-dev liblua5.2-dev libmagic-dev libncursesw5-dev libpcre3-dev make pkg-config


With the dependencies installed you should find the code builds cleanly with:

    $ make

The integrated test-suite can be executed by running:

    $ make test


### OS X

Make sure Xcode is installed and you probably want a package manager like [brew](http://brew.sh/) to install the required dependencies:

     brew install lua gmime libmagic ncurses pkg-config

The code can then be built as follows:

    $ PKG_CONFIG_PATH=/usr/local/Cellar/ncurses/6.0_1/lib/pkgconfig make


Installation and Configuration
------------------------------

Running `make install` will install the binary, the libraries that we bundle, and the perl-utilities which are required for IMAP-operation.

If you wish to install manually copy:

* The contents of `lib/` to `/etc/lumail/lib`.
* The contents of `perl.d` to `/etc/lumail/perl.d`.

**NOTE**: If you wish to use IMAP you'll need to install the two perl modules `JSON` and `Net::IMAP::Client`.  Upon a Debian GNU/Linux system this can be done
via:

     apt-get install libnet-imap-client-perl libjson-perl

Once installed you'll want to create your own personal configuration file.

To allow smooth upgrades it is __recommended__ you do not edit the global configuration file `/etc/lumail/lumail.lua`.  Instead you should copy the sample user-configuration file into place:

      $ mkdir ~/.lumail/
      $ cp lumail.user.lua ~/.lumail/lumail.lua

If you prefer you can name your configuration file after the hostname of the local system - this is useful if you store your dotfiles under revision control, and share them:

      $ mkdir ~/.lumail/
      $ cp lumail.user.lua ~/.lumail/$(hostname --fqdn).lua

The defaults in [the per-user configuration file](lumail.user.lua) should be adequately documented, but in-brief you'll want to ensure you set at least the following:

     -- Set the location of your Maildir folders, and your sent-folder
     Config:set( "maildir.prefix", os.getenv( "HOME" ) .. "/Maildir/" );
     Config:set( "global.sent-mail", os.getenv( "HOME" ) .. "/Maildir/sent/" )

     -- Set your outgoing mail-handler, and email-address:
     Config:set( "global.mailer", "/usr/lib/sendmail -t" )
     Config:set( "global.sender", "Some User <steve@example.com>" )

     -- Set your preferred editor
     Config:set( "global.editor", "vim  +/^$ ++1 '+set tw=72'" )

Other options are possible, and you'll find if you wish to [use IMAP](IMAP.md) you need some more options.  If you wish to use encryption you should also read the [GPG notes](GPG.md).



Running from `git`-checkout
---------------------------

If you wish to run directly from a git-checkout you'll need to add some
command-line flags to change the behaviour:

* Change the location from which Lua libraries are fetched.
* Disable the loading of the global configuration-files.

This can be achieved like so:

     $ ./lumail --load-path=$(pwd)/lib/ --no-default --load-file ./lumail.lua --load-file ./lumail.user.lua



Using Lumail
-------------

By default you'll be in the `maildir`-mode, and you can navigate with `j`/`k`, and select items with `ENTER`.

For a quick-start you can use the following bindings:

* `TAB` - Toggle the display of the status-panel.
   * The panel displays brief messages when "things" happen.
   * `P` - Toggle the size of the panel.
   * `ctrl-p` enters you into a mode were you can view/scroll through past messages.
* `H` - Shows the keybindings which are configured.
* `M` - See your list of folders.
* `q` - Always takes you out of the current mode and into the previous one.
   * Stopping at the folder-list (`maildir`-mode).
* `Q` - Exit.


Further Notes
-------------

* [API Documentation](API.md).
   * Documents the Lua classes.
* [Contributor Guide](CONTRIBUTING.md).
* [Notes on IMAP](IMAP.md).
* [Notes on GPG Support](GPG.md).
* [Notes on implementation & structure](HACKING.md).
   * See also the [experiments repository](https://github.com/lumail/experiments) where some standalone code has been isolated for testing/learning purposes.


Steve
--
