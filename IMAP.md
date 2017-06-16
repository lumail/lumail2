Lumail IMAP Support
===================


Using Lumail with IMAP
----------------------

Assuming you have the required dependencies present, which are covered
below, then you can configure your instance of lumail to use a remote
IMAP server via the following settings:

     --[[ Defaults ]]
     Config:set( "imap.cache", HOME .. "/.lumail/imap.cache" )
     Config:set( "imap.proxy", "/etc/lumail/perl.d/imap-proxy" )
     Config:set( "index.sort", "none" )
     Config:set( "index.fast", "1" )

     --[[ Account details ]]
     Config:set( "imap.server",   "imaps://imap.gmail.com/" )
     Config:set( "imap.username", "username" )
     Config:set( "imap.password", "password" )


How IMAP Works
--------------

All IMAP operations are carried out by talking to a persistent
program `imap-proxy` which connects to the remote IMAP server
and also listens upon a Unix domain-socket.

When Lumail wishes to perform an action, such as listing the remote
folders, it will open a connection to the domain-socket, send the
request, and read the reply.

Lumail will launch the proxy-process when necessary, and it will
read the connection-details via environmental variables.

If you prefer you can launch the proxy manually:

     export imap_username=steve
     export imap_password=bob
     export imap_server=imaps://imap.example.com

     perl /etc/lumail/perl.d/imap-proxy --verbose

With this running you can then launch Lumail.


IMAP Dependencies
-----------------

Ensure you have the required dependencies:

     apt-get install libnet-imap-client-perl libjson-perl
