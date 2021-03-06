/*
 * lumail2.cc - Application entry-point.
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


#include <iostream>
#include <gmime/gmime.h>
#include <getopt.h>

#include "config.h"
#include "file.h"
#include "global_state.h"
#include "history.h"
#include "imap_proxy.h"
#include "input_queue.h"
#include "logger.h"
#include "lua.h"
#include "maildir.h"
#include "message.h"
#include "message_part.h"
#include "mime.h"
#include "screen.h"
#include "statuspanel.h"
#include "tests.h"
#include "util.h"

/*
 * External flag for getopt - when set we can ignore unknown
 * argument errors.
 */
extern int opterr;

void run_all_tests()
{
    CuString *output = CuStringNew();
    CuSuite *suite = CuSuiteNew();

    CuSuiteAddSuite(suite, coloured_string_getsuite());
    CuSuiteAddSuite(suite, config_getsuite());
    CuSuiteAddSuite(suite, directory_getsuite());
    CuSuiteAddSuite(suite, file_getsuite());
    CuSuiteAddSuite(suite, history_getsuite());
    CuSuiteAddSuite(suite, input_queue_getsuite());
    CuSuiteAddSuite(suite, lua_getsuite());
    CuSuiteAddSuite(suite, statuspanel_getsuite());
    CuSuiteAddSuite(suite, util_getsuite());

    CuSuiteRun(suite);
    CuSuiteSummary(suite, output);
    CuSuiteDetails(suite, output);
    printf("%s\n", (char *) output->buffer);
}

/*
 * The entry point to our code.
 */
int main(int argc, char *argv[])
{
    /*
     * Initiate mime.
     */
    g_mime_init(GMIME_ENABLE_RFC2047_WORKAROUNDS);

    /*
     * Parse command-line arguments
     */
    int c;

    /*
     * Flags/things set by the command-line arguments.
     */
    std::vector < std::string > load;
    bool curses = true;


    /*
     * The default load-path is set at compile-time, here we
     * ensure that it is used.
     */
    CLua *instance        = CLua::instance();
    std::string load_path = LUMAIL_LUAPATH;
    instance->append_to_package_path(load_path  + "/?.lua");
    load_path = "";


    /*
     * Loading our global configuration file: legacy
     */
    if (CFile::exists("/etc/lumail2/lumail2.lua"))
        load.push_back("/etc/lumail2/lumail2.lua");

    /*
     * Loading our global configuration file: new
     */
    if (CFile::exists("/etc/lumail/lumail.lua"))
        load.push_back("/etc/lumail/lumail.lua");


    /*
     * Parse our arguments.
     */
    while (1)
    {
        /* ignore unknown arguments. */
        opterr = 0;

        static struct option long_options[] =
        {
            {"no-curses", no_argument, 0, 'c'},
            {"no-defaults", no_argument, 0, 'd'},
            {"load-file", required_argument, 0, 'l'},
            {"load-path", required_argument, 0, 'p'},
            {"test", no_argument, 0, 't'},
            {"version", no_argument, 0, 'v'},
            {0, 0, 0, 0}
        };

        /* getopt_long stores the option index here. */
        int option_index = 0;

        c = getopt_long(argc, argv, "l:p:cdtv", long_options, &option_index);

        /* Detect the end of the options. */
        if (c == -1)
            break;

        switch (c)
        {
        case 'c':
            curses = false;
            break;

        case 'd':
            load.clear();
            break;

        case 'l':
            load.push_back(optarg);
            break;

        case 'p':
            load_path = optarg;
            break;

        case 't':
            run_all_tests();
            return 0;
            break;

        case 'v':
            std::cout << "Lumail2 " << LUMAIL_VERSION << std::endl;
            return 0;
            break;
        }
    }


    /*
     * If any additional load-path was added, then append it.
     */
    if (! load_path.empty())
    {
        instance->append_to_package_path(load_path + "/?.lua");
    }


    /*
     * Pass our command-line arguments to Lua.
     */
    instance->set_args(argv, argc);

    /*
     * If we're supposed to use curses then set it up.
     */
    CScreen *screen = CScreen::instance();

    if (curses == true)
        screen->setup();


    /*
     * This is annoying - we have to instantiate our singletons here.
     *
     * We MUST do this before we load any configuration files because
     * otherwise our listeners will not run, which means that things
     * like `global.history`, despite being defined in the lumail2.lua
     * file, will not get broadcast, and the setting will be worthless.
     *
     */
    {
        CGlobalState *global = CGlobalState::instance();
        global->update("there.is.no.match.here", NULL);

        /*
         * Launch time in seconds past the epoch.
         */
        CConfig *config = CConfig::instance();
        config->set("global.launched", time(NULL));
    }

    /*
     * Load any named script file(s) we're supposed to load.
     */
    if (!load.empty())
    {

        for (std::string filename : load)
        {
            if (CFile::exists(filename))
                instance->load_file(filename);
            else
            {
                screen->teardown();
                std::cerr << "File doesn't exist: " << filename << std::endl;
                return -1;
            }
        }
    }

    /*
     * Run the event-loop and terminate once that finishes.
     */
    if (curses == true)
    {
        screen->run_main_loop();
        screen->teardown();
    }


    /*
     * Cleanup: Delete the config-values.
     */
    CConfig *config = CConfig::instance();
    config->remove_all();

    /*
     * Cleanup: Kill the imap-proxy
     */
    CIMAPProxy *proxy = CIMAPProxy::instance();
    proxy->terminate();

    /*
     * Now we terminate all our singletons in an aim
     * to explicitly free memory and make leak-detection
     * simpler.
     */
    config->destroy_instance();
    proxy->destroy_instance();

    CHistory::instance()->destroy_instance();
    CGlobalState::instance()->destroy_instance();
    CInputQueue::instance()->destroy_instance();
    CStatusPanel::instance()->destroy_instance();
    CScreen::instance()->destroy_instance();
    CMime::instance()->destroy_instance();
    CLua::instance()->destroy_instance();
    CLogger::instance()->destroy_instance();

    /*
     * Close GMime.
     */
    g_mime_shutdown();

    return 0;
}
