/*
 * statuspanel.cc - Display/Maintain our status-panel.
 *
 * This file is part of lumail - http://lumail.org/
 *
 * Copyright (c) 2016 by Steve Kemp.  All rights reserved.
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


#include <algorithm>
#include "statuspanel.h"

/**
 * The status-panel.
 */
CStatusPanel::CStatusPanel()
{
    g_status_bar = 0;
    g_status_bar_window = 0;

    init(6);
}

CStatusPanel::~CStatusPanel()
{
    cleanup();
}

void CStatusPanel::cleanup()
{
    if (g_status_bar != 0)
    {
        del_panel(g_status_bar);
        g_status_bar = 0;
    }

    if (g_status_bar_window != 0)
    {
        delwin(g_status_bar_window);
        g_status_bar_window = 0;
    }
}

void CStatusPanel::init(int rows)
{
    cleanup();
    m_hidden = false;
    int x, y;

    /*
     * Size of panel
     */
    int cols = CScreen::width();

    /*
     * Create the window.
     */
    x = 0;
    y = CScreen::height() - rows;
    g_status_bar_window = newwin(rows, cols, y, x);

    /*
     * Set the content of the status-bar
     */
    m_height = rows;

    if (title.empty())
        title = std::string("Status Panel");

    if (m_text.empty())
    {
        /*
         * Hack - released versions have a fully qualified version
         */
        std::string name = LUMAIL_VERSION;

        if (name.substr(0, 6) != "lumail")
        {
            name = "lumail [" + name + "]";
        }

        m_text.push_back("$[WHITE|BOLD]" + name + "$[WHITE] by Steve Kemp");
        m_text.push_back("Toggle panel via 'TAB'.  Exit via 'Q'.  Eval via ':'.");
    }

    /* Attach the panel to the window. */
    g_status_bar = new_panel(g_status_bar_window);
    show_panel(g_status_bar);
    m_hidden = false;
    draw();
}


/**
 * Height of the panel.
 */
int CStatusPanel::height()
{
    return (m_height);
}

/**
 * Show the panel.
 */
void CStatusPanel::show()
{
    init(m_height);
    m_hidden = false;
}

void CStatusPanel::hide()
{
    cleanup();
    m_hidden = true;
}

/**
 * Is the panel hidden?
 */
bool CStatusPanel::hidden()
{
    return (m_hidden == true);
}

/**
 * Draw the panel.
 */
void CStatusPanel::draw()
{
    /*
     * Handle resize events
     */
    static int old_x = 0;
    static int old_y = 0;


    /*
     * If we don't have a status-bar at the moment
     * we can't do anything.
     */
    if (m_hidden == true)
        return;


    int x;
    int y;
    getmaxyx(g_status_bar_window, y, x);

    if ((x != old_x) || (y != old_y))
    {
        wresize(g_status_bar_window, y, x);
    }


    CScreen *s = CScreen::instance();
    int width = CScreen::width();

    /*
     * Show the title, and the last two lines of the text.
     */
    if (! title.empty())
    {
        int result __attribute__((unused));

        /*
         * Last two false variables are:
         *
         *  enable scroll: false
         *  enable wrap: false
         */
        result = s->draw_single_line(1, 1, title, g_status_bar_window, false, false);
    }


    if (m_text.size() > 0)
    {
        /*
         * Reverse the lines of text, and draw until we've exceeded
         * our height.
         */
        std::vector<std::string> tmp = m_text;
        std::reverse(tmp.begin(), tmp.end());

        int i = 0;

        while (i < (m_height - 3 - 1))
        {
            std::string text;

            if (i < (int)tmp.size())
                text = tmp.at(i);
            else
                text = "";


            /*
             * Last two false variables are:
             *
             *  enable scroll: false
             *  enable wrap: false
             */
            s->draw_single_line((m_height - 2 - i), 1, text, g_status_bar_window, false, false);
            i++;
        }
    }

    /*
     * Select white, and draw a box.
     */
    wattron(g_status_bar_window, COLOR_PAIR(1));
    box(g_status_bar_window, 0, 0);
    mvwaddch(g_status_bar_window, 2, 0, ACS_LTEE);
    mvwhline(g_status_bar_window, 2, 1, ACS_HLINE, width - 2);
    mvwaddch(g_status_bar_window, 2, width - 1, ACS_RTEE);

}

void CStatusPanel::set_title(std::string new_title)
{
    title = new_title ;
    draw();
}

std::string CStatusPanel::get_title()
{
    return title;
}

/**
 * Remove all text.
 */
void CStatusPanel::reset()
{
    m_text.clear();
    draw();
}

/**
 * Add a line of text to the display.
 */
void CStatusPanel::add_text(std::string line)
{
    m_text.push_back(line);
    draw();
}

/**
 * Get the text we're displaying.
 */
std::vector<std::string> CStatusPanel::get_text()
{
    return (m_text);
}
