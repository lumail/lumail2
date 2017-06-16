Sample Lua Code
---------------

The code in this directory is designed to be useful as demonstrations of some of the
facilities that Lumail offers.

For further notes on what facilities are available please consult the `API.md` file,
in the parent-directory.

Usage
-----

There are two classes of code here:

* Code that uses the console GUI.
* Code that does not.

If the code makes use of `print` you will know it is not designed to be run within the console TUI that lumail offers, in that case the code should be loaded:

    lumail --no-curses --load-file $filename

If the code is designed to run inside Lumail then do so via:

    lumail --load-file $filename

