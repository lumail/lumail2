/*
 * message_lua.cc - Bindings for the CMessage C++ object.
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


#include <algorithm>
#include <cstdlib>
#include <dirent.h>
#include <fcntl.h>
#include <fstream>
#include <gmime/gmime.h>
#include <iostream>
#include <memory>
#include <sstream>
#include <string.h>
#include <string>
#include <unistd.h>
#include <unordered_map>
#include <vector>

#include "approxidate.h"
#include "file.h"
#include "global_state.h"
#include "lua.h"
#include "message.h"
#include "message_part.h"
#include "message_part_lua.h"


/**
 * @file message_lua.cc
 *
 * This file implements the trivial exporting of our CMessage class,
 * implemented in C++, to Lua.  Lua-usage looks something like this:
 *
 *<code>
 *   -- Create a message, and get the sender <br/>
 *   local m = Message.new( "/home/steve/Maildir/.foo.com/cur/foo.txt" ) <br/>
 *   local f = m:header("from") <br/>
 *</code>
 *
 */



int l_CNet_hostname(lua_State * L);


/**
 * Push a CMessage pointer onto the Lua stack.
 */
void push_cmessage(lua_State * l, std::shared_ptr<CMessage> message)
{
    CLuaLog("push_cmessage");

    /*
     * Allocate a new object.
     */
    void *ud = lua_newuserdata(l, sizeof(std::shared_ptr<CMessage>));

    if (!ud)
    {
        /* Error - couldn't allocate the memory */
        return;
    }

    /* We can't just do *(shared_ptr<...> *)ud = shared_ptr<>... since
     * it will try to call the assignment operator on the object at *ud,
     * but there isn't one (so it tries to free random junk).
     *
     * Instead, construct the new shared pointer in the memory we've just
     * allocated.
     */
    std::shared_ptr<CMessage> *udata = new(ud) std::shared_ptr<CMessage>();

    /*
     * Now that we have a valid shared_ptr pointing to nothing, we can
     * assign the final value to it.
     */
    *udata = message;

    luaL_getmetatable(l, "luaL_CMessage");
    lua_setmetatable(l, -2);
}

/**
 * Implementation for Message.new()
 */
int l_CMessage_constructor(lua_State * l)
{
    CLuaLog("l_CMessage_constructor");

    const char *name = luaL_checkstring(l, 1);

    push_cmessage(l, std::shared_ptr<CMessage>(new CMessage(name)));

    return 1;
}

/**
 * Test that the object is a std::shared_ptr<CMessage>.
 */
std::shared_ptr<CMessage> l_CheckCMessage(lua_State * l, int n)
{
    CLuaLog("l_CheckCMessage");

    void *ud = luaL_checkudata(l, n, "luaL_CMessage");

    if (ud)
    {
        /* Get a pointer to the shared_ptr object */
        std::shared_ptr<CMessage> *ud_msg = static_cast<std::shared_ptr<CMessage> *>(ud);

        /* Return a copy (of the pointer) */
        return *ud_msg;
    }
    else
    {
        /* otherwise a null pointer */
        return std::shared_ptr<CMessage>();
    }
}


/**
 * Implementation for Message:path()
 */
int l_CMessage_path(lua_State * l)
{
    CLuaLog("l_CMessage_path");

    std::shared_ptr<CMessage> foo = l_CheckCMessage(l, 1);
    lua_pushstring(l, foo->path().c_str());
    return 1;
}

/**
 * Implementation for Message:replace()
 *
 * Reread message from file.
 */
int l_CMessage_replace(lua_State * l)
{
    CLuaLog("l_CMessage_replace");

    std::shared_ptr<CMessage> msg = l_CheckCMessage(l, 1);
    if (msg)
    {
        /* Get file from lua */
        FILE *f = *(FILE**) luaL_checkudata(l, 2, LUA_FILEHANDLE);
        const int fd = fileno(f);

        /* Reread message */
        msg->populate_message(fd);
    }
    return 0;
}

/**
 * Implementation for Message:generate_message_id()
 */
int l_CMessage_generate_message_id(lua_State *L)
{
    CLuaLog("l_CMessage_generate_message_id");

    char *name = (char *)"example.org";

    /*
     * Defined in net_lua.cc
     */
    if (l_CNet_hostname(L) == 1)
    {
        name = (char *)lua_tostring(L, -1);
    }

    /*
     * Generate a new ID.
     */
    char *message_id = g_mime_utils_generate_message_id(name);
    std::string result(message_id);
    result = "<" + result + ">";
    g_free(message_id);

    lua_pushstring(L, result.c_str());
    return 1;

}

/**
 * Implementation for Message:header()
 */
int l_CMessage_header(lua_State * l)
{
    CLuaLog("l_CMessage_header");

    std::shared_ptr<CMessage> foo = l_CheckCMessage(l, 1);

    /* Get the header. */
    const char *str = luaL_checkstring(l, 2);
    CLuaLog("l_CMessage_header(" + std::string(str) + ")");
    std::string result = foo->header(str);

    /* set the retulr */
    lua_pushstring(l, result.c_str());
    return 1;

}

/**
 * Implementation for Message:headers()
 */
int l_CMessage_headers(lua_State * l)
{
    CLuaLog("l_CMessage_headers");

    /*
     * Get the headers.
     */
    std::shared_ptr<CMessage> foo = l_CheckCMessage(l, 1);
    std::unordered_map < std::string, std::string > headers = foo->headers();


    /*
     * Create the table.
     */
    lua_newtable(l);

    for (auto it = headers.begin(); it != headers.end(); ++it)
    {
        std::string name = it->first;
        std::string value = it->second;

        lua_pushstring(l, name.c_str());

        if (!value.empty())
            lua_pushstring(l, value.c_str());
        else
            lua_pushstring(l, "[EMPTY]");

        lua_settable(l, -3);
    }

    return (1);
}

/**
 * Implementation for Message:mark_read()
 */
int l_CMessage_mark_read(lua_State *l)
{
    CLuaLog("l_CMessage_mark_read");

    std::shared_ptr<CMessage> foo = l_CheckCMessage(l, 1);
    foo->mark_read();
    return 0;
}

/**
 * Implementation for Message:mark_unread()
 */
int l_CMessage_mark_unread(lua_State *l)
{
    CLuaLog("l_CMessage_mark_unread");

    std::shared_ptr<CMessage> foo = l_CheckCMessage(l, 1);
    foo->mark_unread();
    return 0;
}

/**
 * Implementation for Message:mtime()
 */
int l_CMessage_mtime(lua_State *l)
{
    CLuaLog("l_CMessage_mtime");

    std::shared_ptr<CMessage> foo = l_CheckCMessage(l, 1);
    int m_time = foo->get_mtime();

    lua_pushnumber(l, m_time);
    return 1;
}

/**
 * Implementation for Message:parts()
 *
 * Return an array of CMessagePart objects to Lua.  These can be inspected
 * as the user wishes.
 *
 * **NOTE**: CMessagePart is *NOT* creatable via Lua.  This is a good thing.
 *
 */
int l_CMessage_parts(lua_State * l)
{
    CLuaLog("l_CMessage_parts");

    std::shared_ptr<CMessage> foo = l_CheckCMessage(l, 1);

    /*
     * Get the parts, and count.
     */
    std::vector<std::shared_ptr<CMessagePart>> parts = foo->get_parts();

    lua_createtable(l, parts.size(), 0);
    int i = 0;

    for (std::vector<std::shared_ptr<CMessagePart>>::iterator it = parts.begin();
            it != parts.end(); ++it)
    {
        std::shared_ptr<CMessagePart> cur = (*it);
        push_cmessagepart(l, cur);
        lua_rawseti(l, -2, i + 1);
        i++;
    }

    return 1;
}

/**
 * Implementation for CMessage:add_attachments()
 */
int l_CMessage_add_attachments(lua_State * l)
{
    CLuaLog("l_CMessage_add_attachments");

    std::shared_ptr<CMessage> foo = l_CheckCMessage(l, 1);
    std::vector<std::string> files;

    if (lua_istable(l, 2))
    {
        lua_pushnil(l);

        while (lua_next(l, -2))
        {
            const char *entry = lua_tostring(l, -1);
            files.push_back(entry);
            lua_pop(l, 1);
        }
    }

    if (lua_isstring(l, 2))
    {
        const char *entry = lua_tostring(l, 2);
        files.push_back(entry);
    }

    if (files.size() > 0)
        foo->add_attachments(files);

    return 0;
}

/**
 * Implementation for CMessage:ctime()
 */
int l_CMessage_ctime(lua_State * l)
{
    std::shared_ptr<CMessage> foo = l_CheckCMessage(l, 1);

    /*
     * Look for `Delivery-Date`, then `Date`.  If neither
     * is present we're screwed.
     */
    std::string rd = foo->header("Delivery-Date");

    if (rd.empty())
        rd = foo->header("Date");

    if (rd.empty())
    {
        lua_pushnumber(l, 0);
        return 1;
    }

    /*
     * Convert the result to a date.
     */
    struct timeval t;

    if (0 ==  approxidate(rd.c_str(), &t))
        lua_pushnumber(l, t.tv_sec);
    else
        lua_pushnumber(l, 0);

    return 1;
}

/**
 * Implementation for CMessage:flags()
 */
int l_CMessage_flags(lua_State * l)
{
    CLuaLog("l_CMessage_flags");

    std::shared_ptr<CMessage> foo = l_CheckCMessage(l, 1);

    /*
     * Are we setting the flags?
     */
    if (lua_gettop(l) >= 2)
    {
        const char *update = luaL_checkstring(l, 2);
        foo->set_flags(update);
    }

    /*
     * Now get the flags
     */
    lua_pushstring(l, foo->get_flags().c_str());
    return 1;
}

/**
 * Destructor.
 */
int l_CMessage_destructor(lua_State * l)
{
    CLuaLog("l_CMessage_destructor");

    void *ud = luaL_checkudata(l, 1, "luaL_CMessage");

    if (ud)
    {
        /* Get a pointer to the shared_ptr object */
        std::shared_ptr<CMessage> *ud_msg = static_cast<std::shared_ptr<CMessage> *>(ud);

        /* We need to destruct the pointer in place; it will decrement
         * the reference count as usual.  After this the user data object
         * becomes just plain memory again. */
        ud_msg->~shared_ptr<CMessage>();
    }

    return 0;
}

/**
 * Equality-test - this is bound to the Lua meta-method `__eq` such that two
 * messages may be tested for equality.
 *
 * Two messages-objects are considered identical if they refer to the
 * same message file on-disk.
 */
int l_CMessage_equality(lua_State * l)
{
    CLuaLog("l_CMessage_equality");

    std::shared_ptr<CMessage> one = l_CheckCMessage(l, 1);
    std::shared_ptr<CMessage> two = l_CheckCMessage(l, 2);

    if (one->path() == two->path())
        lua_pushboolean(l , 1);
    else
        lua_pushboolean(l , 0);

    return 1;
}

/**
 * Implementation for CMessage:unlink()
 */
int l_CMessage_unlink(lua_State * l)
{
    CLuaLog("l_CMessage_unlink");

    std::shared_ptr<CMessage> foo = l_CheckCMessage(l, 1);

    if (foo)
        foo->unlink();

    /**
     * Update our global-state to reflect the fact that
     * a message has been deleted.
     */
    CGlobalState *global = CGlobalState::instance();
    global->set_message(NULL);
    global->update_messages();

    return 0;
}

/**
 * Register the global `Message` object to the Lua environment, and
 * setup our public methods upon which the user may operate.
 */
void InitMessage(lua_State * l)
{
    luaL_Reg sFooRegs[] =
    {
        {"__eq", l_CMessage_equality},
        {"__gc", l_CMessage_destructor},
        {"add_attachments", l_CMessage_add_attachments},
        {"ctime", l_CMessage_ctime},
        {"flags", l_CMessage_flags},
        {"generate_message_id", l_CMessage_generate_message_id},
        {"header", l_CMessage_header},
        {"headers", l_CMessage_headers},
        {"mark_read", l_CMessage_mark_read},
        {"mark_unread", l_CMessage_mark_unread},
        {"mtime", l_CMessage_mtime},
        {"new", l_CMessage_constructor},
        {"parts", l_CMessage_parts},
        {"path", l_CMessage_path},
        {"replace", l_CMessage_replace},
        {"unlink", l_CMessage_unlink},
        {NULL, NULL}
    };
    luaL_newmetatable(l, "luaL_CMessage");

#if LUA_VERSION_NUM == 501
    luaL_register(l, NULL, sFooRegs);
#elif LUA_VERSION_NUM == 502 || LUA_VERSION_NUM == 503
    luaL_setfuncs(l, sFooRegs, 0);
#else
#error We are only tested under Lua 5.1, 5.2, or 5.3.
#endif

    lua_pushvalue(l, -1);
    lua_setfield(l, -1, "__index");
    lua_setglobal(l, "Message");
}
