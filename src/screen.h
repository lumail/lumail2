/*
 * screen.h - Our main application class.
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


/*
 * Only include this header one time.
 */
#pragma once


#include <cursesw.h>
#include <panel.h>
#include <string>
#include <unordered_map>
#include <vector>

#include "singleton.h"
#include "observer.h"



/**
 *
 * This is the base-class for our virtual views.
 *
 * View modes are registered at run-time via `CScreen::register_view`,
 * which allows them to be instantiated dynamically.
 *
 * Each view mode is responsible for drawing its output to the screen,
 * almost certainly via `CScreen::draw_text_lines()`, but it is free
 * to do other things.
 */
class CViewMode
{
public:
    /**
     * Virtual Destructor.
     */
    virtual ~CViewMode() {};

    /**
      * Allow our virtual mode to draw its own display.
      */
    virtual void draw() = 0;

    /**
     * It might be useful to have the virtual modes have
     * an idle function to update things.
     */
    virtual void on_idle() = 0;

};



/**
 *
 * This class contains simple functions relating to the screen-handling.
 *
 * Although the class is called `CScreen` it might easily have been called
 * `CLumail`, as most of the logic that is implemented in the C++ part of
 * the codebase is in this class.
 *
 * The class is generally responsible for handling input, updating state,
 * and drawing the display.
 *
 * This class also implements the observer-pattern, responding to
 * changes in the `CConfig` class.
 *
 */
class CScreen : public Singleton<CScreen>, public Observer
{

public:
    /**
     * Constructor.
     */
    CScreen();

    /**
     * Destructor.
     */
    virtual ~CScreen();

    /**
     * Register a view mode.
     *
     * The name will be the name of the mode, as seen by lua, and the
     * implementation will be a class derived from CViewMode.
     */
    void register_view(std::string name, CViewMode *impl);

    /**
     * Return all registered view-modes.
     */
    std::vector<std::string> view_modes();

    /**
     * This method is called when a configuration key changes,
     * via our observer implementation.
     */
    void update(std::string key_name, CConfigEntry *old);


public:

    /**
     * Setup the `curses` environment.
     */
    void setup();

    /**
     * Tear down `curses`.
     */
    void teardown();

    /**
     * Run our event loop - which means polling for keyboard input,
     * responding to that received, and redrawing the screen.
     */
    void run_main_loop();

    /**
     * Exit our main event-loop.
     */
    void exit_main_loop();

    /**
     * Return the width of the screen, in columns.
     */
    static int width();

    /**
     * Return the height of the screen, in lines.
     *
     * **NOTE**: This doesn't take any account of the state of the
     * status-panel.
     */
    static int height();

    /**
     * Clear the screen - if refresh_screen is set to true we'll trigger
     * a refresh of the screen via curses.
     */
    void clear(bool refresh_screen = true);

    /**
     * Redraw the screen, via the currently active mode.
     */
    void redraw();

    /**
     * Delay for the given period.
     */
    void sleep(int seconds);

    /**
     * Choose a single item from a small selection.
     *
     * Used by TAB-completion.
     */
    std::string choose_string(std::vector<std::string> choices);

    /**
     * Show a message and read a single character of input.
     *
     * Faux input may be consumed via our CInputQueue object.
     */
    std::string get_char(std::string prompt);

    /**
     * Read a line of input via the status-line.
     *
     * History is handled via our `CHistory` singleton, and faux input
     * may be consumed via our CInputQueue object.
     */
    std::string get_line(std::string prompt, std::string input = "");

    /**
     * Show a message and return only a valid keypress from a given set.
     *
     * Faux input may be consumed via our CInputQueue object.
     */
    std::string prompt_chars(std::string prompt, std::string valid);

    /**
     * Execute a program, resetting the screen first.
     */
    void execute(std::string program);

    /**
     * Execute a program, resetting the screen first.
     *
     * This variant returns the `stdout` of the command run.
     */
    std::string execute_read_stdout(std::string program);

    /**
     * Is the given character a multi-key prefix?
     */
    bool is_prefixed_key(const char *key);

    /**
     * Execute a function from the global keymap.
     */
    bool on_keypress(std::string key);

    /**
     * Draw an array of lines to the screen, highlighting the current line.
     *
     * This is used by our view-classes, as a helper.
     *
     * If `simple` is set to true then we display the lines in a  simplified
     * fashion - with no selection, and no smooth-scrolling.
     */
    void draw_text_lines(std::vector<std::string> lines, int selected, int max, bool simple = false);

    /**
     * Draw a single text line, paying attention to our colour strings.
     *
     * **NOTE**: This function is grossly inefficient, although functional.
     *
     * The return value is the number of characters drawn.
     */
    int draw_single_line(int row, int col_offset, std::string text, WINDOW * screen, bool enable_scroll, bool enable_wrap);


    /**
     * Draw a single piece of text, allowing colours too.
     */
    void draw_text(int x, int y, std::string text, bool update = false);

private:

    /**
     * Get the colour-pair for the given name.
     */
    int get_colour(std::string name);

    /**
     * Convert ^I -> TAB, etc.
     */
    const char *lookup_key(int c);

private:

    /**
     * Are we (still) in the event-loop?
     */
    bool m_running;

    /**
     * This map contains a mapping between a given mode-name and the
     * virtual class which implements its display.
     *
     * All display-classes are derived from CViewMode so that we can
     * refer to them in this generic/interface way.
     */
    std::unordered_map < std::string, CViewMode * >m_views;

    /**
     * A lookup-map of colour-pairs, which are used for drawing
     * coloured text on the screen.
     *
     * See `get_colour` for the accessor used to access this map.
     */
    std::unordered_map < std::string, int >m_colours;

private:

    /**
     * The segment of the screen the highlighted row is within.
     *
     * Used by `draw_text_lines`.
     */
    enum vectorPosition
    {
        TOP,
        MIDDLE,
        BOTTOM,
        NONE
    };

};


/*
 * Allow registration of a view mode, via a macro.
 */
#ifndef REGISTER_VIEW_MODE
#define REGISTER_VIEW_MODE(name,klass) \
    class klass##Factory { \
    public: \
        klass##Factory() \
        { \
           CScreen *x = CScreen::instance(); \
           x->register_view(#name, (CViewMode *)new klass);     \
        } \
    }; \
    static klass##Factory global_##klass##Factory;
#endif
