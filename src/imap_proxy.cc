/*
 * imapproxy.cc - Manage our IMAP-proxy
 *
 * This file is part of lumail - http://lumail.org/
 *
 * Copyright (c) 2015 by Steve Kemp.  All rights reserved.
 *
 **
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 2 dated June, 1991, or (at your
 * option) any later version.
 *
 * On Debian GNU/Linux systems, the complete text of version 2 of the GNU
 * General Public License can be found in `/usr/share/common-licenses/GPL-2'
 */


#include <cstdlib>
#include <fcntl.h>
#include <memory>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/un.h>
#include <unistd.h>


#include "config.h"
#include "file.h"
#include "imap_proxy.h"
#include "statuspanel.h"


CIMAPProxy::CIMAPProxy()
{
    m_child = -1;
}


/*
 * Destructor
 */
CIMAPProxy::~CIMAPProxy()
{
    terminate();
}


/*
 * Terminate the child we've launched.
 */
void CIMAPProxy::terminate()
{
    if (m_child != -1)
    {
        kill(m_child, SIGKILL);
        m_child = -1;
    }
}



/*
 * Launch the child, if not already running.
 */
void CIMAPProxy::launch()
{
    size_t unused __attribute__((unused));

    if (m_child == -1)
    {
        /*
         * Get the path to the proxy
         */
        CConfig *config = CConfig::instance();
        std::string path = config->get_string("imap.proxy");

        if (path.empty())
            path = "/etc/lumail/perl.d/imap-proxy" ;


        /*
         * If the proxy exists then we can launch it, if not we'll
         * error.
         */
        if (CFile::exists(path))
        {
            CStatusPanel *panel = CStatusPanel::instance();
            panel->add_text("Launching IMAP proxy " + path);

            m_child = fork();

            if (m_child == 0)
            {
                unused = execl(path.c_str(), CFile::basename(path).c_str(), NULL);
            }

            sleep(1.0);
        }
        else
        {
            CStatusPanel *panel = CStatusPanel::instance();
            panel->add_text("IMAP proxy not found at " + path);
            return;
        }
    }
}


/*
 * Read a string from our IMAP proxy, launching it first
 * if required.
 */
std::string CIMAPProxy::read_imap_output(std::string cmd)
{
    int sockfd;
    sockaddr_un addr;
    size_t unused __attribute__((unused));
    std::string result = "";

    /*
     * Launch the child.
     */
    launch();


    sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    addr.sun_family = AF_UNIX;

    /*
     * Use ~/.imap.sock as the path.
     */
    std::string path = getenv("HOME");
    path += "/.imap.sock";

    strcpy(addr.sun_path, path.c_str());

    if (connect(sockfd, (sockaddr*)&addr, sizeof(addr)) < 0)
    {
        return ("Connection failed!");
    }

    unused = write(sockfd, cmd.c_str(), cmd.length());

    char buf[65535];
    int rval;

    do
    {
        bzero(buf, sizeof(buf));

        if ((rval = read(sockfd, buf, sizeof(buf) - 1)) < 0)
        {
            // Failure
        }
        else if (rval == 0)
        {
            // End.
        }
        else
        {
            result += buf;
        }
    }
    while (rval > 0);

    close(sockfd);
    return (result);
}
