/*
 * message.cc - Wrapper for a single message.
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
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <string.h>
#include <string>
#include <sstream>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>



/**
 * @file message.cc
 *
 * This file implements the CMessage class, which largely revolves
 * around parsing and manipulation.
 *
 */



#include "config.h"
#include "file.h"
#include "global_state.h"
#include "imap_proxy.h"
#include "json/json.h"
#include "lua.h"
#include "maildir.h"
#include "message.h"
#include "message_part.h"
#include "mime.h"
#include "util.h"


/*
 * Constructor.
 */
CMessage::CMessage(const std::string name, bool is_local)
{
    m_path = name;
    m_time = 0;
    m_imap = !is_local;
}


/*
 * Return the path to this message.
 */
std::string CMessage::path()
{
    if (m_imap)
        lazy_load();

    return (m_path);
}


/*
 * Update the path to the message.
 */
void CMessage::path(std::string new_path)
{
    m_path = new_path;
}


/*
 * Return the value of a given header.
 */
std::string CMessage::header(std::string name)
{
    std::unordered_map < std::string, std::string > h = headers();

    /*
     * Lower-case the header we were given.
     */
    std::transform(name.begin(), name.end(), name.begin(), tolower);

    /*
     * Lookup the value.
     */
    return (h[name]);
}


/*
 * Parse a MIME message and return an object suitable for operating
 * upon.
 */
GMimeMessage * CMessage::parse_message()
{

    /*
     * If we're an IMAP-messge then we need to ensure
     * that our file exists locally.
     */
    if (m_imap)
        lazy_load();

    int result __attribute__((unused));

    GMimeMessage * message;
    GMimeParser *parser;
    GMimeStream *stream;
    int fd;

    /*
     * The filename we'll operate upon.
     */
    std::string file = path();
    bool replaced = false;

    /*
     * There is a Lua filter which *might* return an *updated* path to
     * use.
     */
    CLua *lua = CLua::instance();

    if (lua->function_exists("message_replace"))
    {
        std::string updated = lua->function2string("message_replace", file);

        if (! updated.empty())
        {
            file = updated;
            replaced = true;
        }
    }


    if ((fd = open(file.c_str(), O_RDONLY, 0)) == -1)
    {

        std::string error = strerror(errno);
        CLua *lua = CLua::instance();

        if (CFile::exists(path()))
            lua->on_error("Failed to open the existing message file:" + path() + " " + error);
        else
            lua->on_error("Failed to open the message file - not found :" + path() + " " + error);

        if (replaced == true)
            CFile::delete_file(file);

        return (NULL);
    }

    stream = g_mime_stream_fs_new(fd);
    g_mime_stream_fs_set_owner((GMimeStreamFs*)stream, FALSE);

    parser = g_mime_parser_new_with_stream(stream);
    g_mime_parser_set_persist_stream(parser, FALSE);

    message = g_mime_parser_construct_message(parser);
    g_object_unref(stream);
    g_object_unref(parser);

    /*
     * Constructing the message failed.  So we're going to do a horrid
     * thing.
     */
    if (message == NULL)
    {

        /*
         * Close the file and retry parsing it, by opening it and
         * skipping two lines.
         */
        close(fd);
        fd = open(file.c_str(), O_RDONLY, 0);

        int newline = 2;
        int count   = 1024;
        char buf[2] = { '\0', '\0' };

        /*
         * We're skipping two lines, but if the message
         * is really malformed and contains a long
         * line, etc, we'll have an infinite loop
         * if we don't cap our attempts.
         *
         * `count` is the number of characters read,
         * and we limit that to 1024 bytes.
         *
         */
        while ((newline > 0) && (count > 0))
        {
            result = read(fd, buf, 1);

            if (buf[0] == '\n')
                newline -= 1;

            count -= 1;
        }

        /*
         * Rebuild - the key here is that `fd` is the file-descriptor
         * to the open file, and we've consumed content from it already.
         */
        stream    = g_mime_stream_fs_new(fd);

        parser    = g_mime_parser_new_with_stream(stream);
        g_mime_stream_fs_set_owner((GMimeStreamFs*)stream, FALSE);
        g_mime_parser_set_persist_stream(parser, FALSE);

        message = g_mime_parser_construct_message(parser);
        g_object_unref(stream);
        g_object_unref(parser);

    }

    if (replaced == true)
        CFile::delete_file(file);

    /*
     * We close this here explicitly to avoid a leak.
     */
    close(fd);
    return (message);
}

/**
 * Populate the headers and MIME-Parts caches.
 */
void CMessage::populate_message() {

    GMimeMessage *msg = parse_message();

    if (msg == NULL)
    {
        CLua *lua = CLua::instance();
        lua->on_error("Failed to populate message :" + path());
        return;
    }

    const char *name;
    const char *value;

    /*
     * Prepare to iterate.
     */
    GMimeHeaderList *ls   = GMIME_OBJECT(msg)->headers;
    GMimeHeaderIter *iter = g_mime_header_iter_new();

    if (g_mime_header_list_get_iter(ls, iter)
            && g_mime_header_iter_first(iter))
    {
        while (g_mime_header_iter_is_valid(iter))
        {
            /*
             * Get the name + value.
             */
            name = g_mime_header_iter_get_name(iter);
            value = g_mime_header_iter_get_value(iter);

            /*
             * Downcase the name.
             */
            std::string nm(name);
            std::transform(nm.begin(), nm.end(), nm.begin(), tolower);


            /*
             * Decode the value.
             */
            char * decoded = g_mime_utils_header_decode_text(value);
            m_headers[nm] = decoded;
            free(decoded);

            if (!g_mime_header_iter_next(iter))
                break;
        }
    }

    g_mime_header_list_clear(ls);
    g_mime_header_iter_free(iter);

    /* Parse into MIME-Parts */

    GMimeObject *mime_part = g_mime_message_get_mime_part(msg);

    if (!mime_part)
        return;

    m_parts.push_back(part2obj(mime_part));

    g_object_unref(msg);
}


/*
 * Return all header-names, and their values.
 */
std::unordered_map < std::string, std::string > CMessage::headers()
{
    /*
     * If we've cached these then return that copy.
     */
    if (m_headers.size() == 0)
        populate_message();

    return (m_headers);
}


/*
 * Destructor: If we've parsed any MIME-parts then free them here.
 */
CMessage::~CMessage()
{
    m_parts.clear();
}


/*
 * Retrieve the current flags for this message.
 */
std::string CMessage::get_flags()
{
    if (m_imap)
        return m_imap_flags;

    std::string flags = "";
    std::string pth = path();

    if (pth.empty())
        return (flags);

    size_t
    offset = pth.find(":2,");

    if (offset != std::string::npos)
        flags = pth.substr(offset + 3);

    /*
     * Sleazy Hack.
     */
    if (pth.find("/new/") != std::string::npos)
        flags += "N";


    /*
     * Sort the flags, and remove duplicates
     */
    std::sort(flags.begin(), flags.end());
    flags.erase(std::unique(flags.begin(), flags.end()), flags.end());

    return flags;
}


/*
 * Set the flags for this message.
 */
void CMessage::set_flags(std::string new_flags)
{
    /*
     * Sort the flags.
     */
    std::string flags = new_flags;
    std::sort(flags.begin(), flags.end());
    flags.erase(std::unique(flags.begin(), flags.end()), flags.end());

    /*
     * Get the current ending position.
     */
    std::string cur_path = path();
    std::string dst_path = cur_path;

    size_t offset = std::string::npos;

    if ((offset = cur_path.find(":2,")) != std::string::npos)
    {
        dst_path = cur_path.substr(0, offset);
        dst_path += ":2,";
        dst_path += flags;
    }
    else
    {
        dst_path = cur_path;
        dst_path += ":2,";
        dst_path += flags;
    }

    if (cur_path != dst_path)
    {
        CFile::move(cur_path, dst_path);
        path(dst_path);
    }
}


/*
 * Set IMAP-flags - these are set at creation time.
 */
void CMessage::set_imap_flags(std::string flags)
{
    /*
     * Sort the flags, and remove duplicates
     */
    std::sort(flags.begin(), flags.end());
    flags.erase(std::unique(flags.begin(), flags.end()), flags.end());

    m_imap_flags = flags;

    /*
     * Update our mtime so that the cache is flushed.
     */
    m_time += 1;

    /*
     * Increase the modification time of the parent folder too.
     */
    m_parent->bump_mtime();

}


/*
 * Add a flag to a message.
 *
 * Return true if the flag was added, false if already present.
 */
bool CMessage::add_flag(char c)
{
    std::string flags = get_flags();

    size_t offset = std::string::npos;

    /*
     * If the flag was missing, add it.
     */
    if ((offset = flags.find(c)) == std::string::npos)
    {
        flags += c;
        set_flags(flags);
        return true;
    }
    else
        return false;
}


/*
 * Does this message possess the given flag?
 */
bool CMessage::has_flag(char c)
{
    /*
     * Flags are upper-case.
     */
    c = toupper(c);

    if (get_flags().find(c) != std::string::npos)
        return true;
    else
        return false;
}

/*
 * Remove a flag from a message.
 *
 * Return true if the flag was removed, false if it wasn't present.
 */
bool CMessage::remove_flag(char c)
{
    c = toupper(c);

    std::string current = get_flags();

    /*
     * If the flag is not present, return.
     */
    if (current.find(c) == std::string::npos)
        return false;

    /*
     * Remove the flag.
     */
    std::string::size_type k = 0;

    while ((k = current.find(c, k)) != current.npos)
        current.erase(k, 1);

    set_flags(current);

    return true;
}

/*
 * Is this message new?
 */
bool CMessage::is_new()
{
    /*
     * A message is new if:
     *
     * It has the flag "N".
     * It does not have the flag "S".
     */
    if ((has_flag('N')) || (!has_flag('S')))
        return true;

    return false;
}


/*
 * Mark a message as unread.
 *
 * If this message is stored on a remote IMAP-server we handle
 * that specially.
 */
void CMessage::mark_unread()
{
    /*
     * If we're an IMAP message we need to send a message over our
     * Unix-domain-socket to carry out the action.
     */
    if (m_imap)
    {
        /**
         * We need to have both the name of the folder, and the ID
         * of the message.
         */
        std::string folder = m_parent->path();
        std::string id     = std::to_string(m_imap_id);


        /*
         * Send the command.
         */
        std::string cmd = "mark_unread " + id + " " + folder + "\n";

        /*
         * Get the output.
         */
        CIMAPProxy *proxy = CIMAPProxy::instance();
        std::string out  = proxy->read_imap_output(cmd);

        /*
         * Remove `S` flag from m_imap_flags since these are
         * not updated in real-time.
         */
        if (m_imap_flags.find('S') != std::string::npos)
        {
            std::string::size_type k = 0;

            while ((k = m_imap_flags.find('S', k)) != m_imap_flags.npos)
                m_imap_flags.erase(k, 1);
        }

        /*
         * Add `N` flag, if not present.
         */
        if (m_imap_flags.find('N') == std::string::npos)
            m_imap_flags += "N";

        /*
         * Update our mtime so that the cache is flushed.
         */
        m_time += 1;

        /*
         * Increase the modification time of the parent folder too.
         */
        m_parent->bump_mtime();

        int c = m_parent->unread_messages();
        c += 1;
        m_parent->set_unread(c);

        return;

    }

    if (has_flag('S'))
        remove_flag('S');
}

/*
 * Mark a message as read.
 *
 * If this message is stored on a remote IMAP-server we handle
 * that specially.
 */
void CMessage::mark_read()
{
    /*
     * If we're an IMAP message we need to send a message over our
     * Unix-domain-socket to carry out the action.
     */
    if (m_imap)
    {
        /**
         * We need to have both the name of the folder, and the ID
         * of the message.
         */
        std::string folder = m_parent->path();
        std::string id     = std::to_string(m_imap_id);


        /*
         * Send the command.
         */
        std::string cmd = "mark_read " + id + " " + folder + "\n";

        /*
         * Get the output.
         */
        CIMAPProxy *proxy = CIMAPProxy::instance();
        std::string out  = proxy->read_imap_output(cmd);

        /*
         * Remove `N` flag from m_imap_flags since these are
         * not updated in real-time.
         */
        if (m_imap_flags.find('N') != std::string::npos)
        {
            std::string::size_type k = 0;

            while ((k = m_imap_flags.find('N', k)) != m_imap_flags.npos)
                m_imap_flags.erase(k, 1);
        }

        /*
         * Add `S` flag, if not present.
         */
        if (m_imap_flags.find('S') == std::string::npos)
            m_imap_flags += "S";

        /*
         * Update our mtime so that the cache is flushed.
         */
        m_time += 1;

        /*
         * Increase the modification time of the parent folder too.
         */
        m_parent->bump_mtime();

        int c = m_parent->unread_messages();
        c -= 1;

        if (c < 0)
            c = 0;

        m_parent->set_unread(c);

        return;
    }

    /*
     * Get the current path, and build a new one.
     */
    std::string c_path = path();
    std::string n_path = "";

    size_t offset = std::string::npos;

    /*
     * If we find /new/ in the path then rename to be /cur/
     */
    if ((offset = c_path.find("/new/")) != std::string::npos)
    {
        /*
         * Path component before /new/ + after it.
         */
        std::string before = c_path.substr(0, offset);
        std::string after  = c_path.substr(offset + strlen("/new/"));

        n_path = before + "/cur/" + after;

        if (rename(c_path.c_str(), n_path.c_str())  == 0)
        {
            path(n_path);
            add_flag('S');
        }
    }
    else
    {
        /*
         * The file is new, but not in the new folder.
         *
         * That means we need to remove "N" from the flag-component of the path.
         *
         */
        remove_flag('N');
        add_flag('S');
    }
}


/*
 * Convert a message-part from the MIME message to a CMessagePart object.
 */
std::shared_ptr<CMessagePart> CMessage::part2obj(GMimeObject *part)
{
    /*
     * This is used to enable/disable conversion of character
     * sets.
     */
    CConfig *config = CConfig::instance();
    int iconv       = config->get_integer("global.iconv", 0);

    /*
     * Get the content-type of this part.
     */
    GMimeContentType *ct = g_mime_object_get_content_type(part);

    /*
     * Get the content-type as a string, along with the charset.
     */
    const char *charset = g_mime_content_type_get_parameter(ct, "charset");
    gchar *type         = g_mime_content_type_to_string(ct);


    /*
     * Get the filename of this part, if any.  We try to look for
     * both `filename` and `name`.
     */
    char *aname = (char *) g_mime_object_get_content_disposition_parameter(part, "filename");

    if (aname == NULL)
        aname = (char *) g_mime_object_get_content_type_parameter(part, "name");

    /*
     * Holder for the content
     */
    GMimeStream *mem = g_mime_stream_mem_new();

    if (GMIME_IS_MULTIPART(part) || GMIME_IS_MESSAGE_PARTIAL(part))
    {
        /* NOP */
    }
    else if (GMIME_IS_MESSAGE_PART(part))
    {

        /*
         * Populate `mem` with the data.
         */
        GMimeMessage *msg = g_mime_message_part_get_message(GMIME_MESSAGE_PART(part));
        g_mime_object_write_to_stream(GMIME_OBJECT(msg), mem);

        /*
         * We explicitly don't free this message here, because this
         * will be done by the caller.
         *
         * g_object_unref(msg);
         *
         *  https://github.com/lumail/lumail2/issues/292
         *
         */

    }
    else
    {
        /*
         * Populate `mem` with the data.
         */
        GMimeDataWrapper *content = g_mime_part_get_content_object(GMIME_PART(part));
        g_mime_data_wrapper_write_to_stream(content, mem);
    }

    /*
     * NOTE: by setting the owner to FALSE, it means unreffing the
     * memory stream won't free the GByteArray data.
     */
    g_mime_stream_mem_set_owner(GMIME_STREAM_MEM(mem), FALSE);


    /*
     * Now we have `res` which is a byte-array of the part's content.
     *
     * We also have the content-type.
     */
    GByteArray *res = g_mime_stream_mem_get_byte_array(GMIME_STREAM_MEM(mem));

    /*
     * The actual data from the array, and the size of that data.
     */
    char *adata = (char *) res->data;
    size_t len = (res->len);

    if (iconv == 1)
    {
        /*
         * Now we'll try to conver the text to UTF-8, but we
         * only do that if the content is:
         *
         *   text/plain
         *   not UTF-8 already.
         */

        if ((g_mime_content_type_is_type(ct, "text", "plain")) &&
                (charset != NULL) &&
                (strcmp(charset, "utf-8") != 0) &&
                (strcmp(charset, "UTF-8") != 0))
        {
            iconv_t cv = g_mime_iconv_open("UTF-8", charset);
            char *converted = g_mime_iconv_strndup(cv, (const char *) adata, len);

            if (converted != NULL)
            {
                /*
                 * If that succeeded then update our byte-array.
                 *
                 * This might causes problems in free.  We should check.
                 */
                size_t conv_len = strlen(converted);
                adata = (char*)malloc(conv_len + 1);

                memcpy(adata, converted, conv_len + 1);
                len = (size_t)conv_len;
                g_free(converted);
            }

        }
    }

    std::shared_ptr<CMessagePart> ret;

    /*
     * If it is an attachment we'll add it.
     */
    if (aname)
    {
        ret = std::shared_ptr<CMessagePart> (new CMessagePart(type, aname, adata, len));
    }
    else
    {
        /*
         * Here we store it, but not as an attachment.
         */
        ret = std::shared_ptr<CMessagePart> (new CMessagePart(type, "", adata, len));
    }

    /* If this is a multipart part, then add its children. */
    if (GMIME_IS_MULTIPART(part))
    {
        /*
         * Count the children.
         */
        int n = g_mime_multipart_get_count((GMimeMultipart *) part);

        /*
         * For each child .. add the part.
         */
        for (int i = 0; i < n; i++)
        {
            GMimeObject *subpart = g_mime_multipart_get_part((GMimeMultipart *) part, i);

            /*
             * Create the child - set the parent.
             */
            std::shared_ptr<CMessagePart> child = part2obj(subpart);
            child->set_parent(ret);

            /*
             * Now add the child to the parent.
             */
            ret->add_child(child);
        }
    }

    /*
     * Unref the memory & type.
     */
    free(type);
    g_object_unref(mem);

    return ret;
}

/*
 * Parse the message into MIME-parts, if we've not already done so.
 */
std::vector<std::shared_ptr<CMessagePart> >CMessage::get_parts()
{
    /*
     * If we've already parsed then return the cached results.
     *
     * A message can't/won't change under our feet.
     */
    if (m_parts.size() == 0)
        populate_message();

    return (m_parts);
}



/*
 * Remove this message.
 *
 * If this message is stored on a remote IMAP-server we handle
 * that specially.
 */
bool CMessage::unlink()
{
    int result __attribute__((unused));

    /*
     * If we're an IMAP message we need to send a message over our
     * Unix-domain-socket to carry out the action.
     */
    if (m_imap)
    {

        /**
         * We need to have both the name of the folder, and the ID
         * of the message.
         */
        std::string folder = m_parent->path();
        std::string id     = std::to_string(m_imap_id);

        /*
         * Send the command.
         */
        std::string cmd = "delete_message " + id + " " + folder + "\n";

        /*
         * Get the output.
         */
        CIMAPProxy *proxy = CIMAPProxy::instance();
        std::string out  = proxy->read_imap_output(cmd);

        /*
         * Increase the modification time of the parent folder.
         */
        m_parent->bump_mtime();

        CGlobalState *global = CGlobalState::instance();
        global->update_messages();
        return true;
    }

    bool ret = CFile::delete_file(path());

    CGlobalState *global = CGlobalState::instance();
    global->update_messages(true);
    return ret;
}


/*
 * Is this message a local one?
 */
bool CMessage::is_maildir()
{
    return (!m_imap);
}


/**
 * Is this message an IMAP one?
 */
bool CMessage::is_imap()
{
    return (m_imap);
}


/*
 * Update our on-disk email to add the specified files as attachments.
 */
void CMessage::add_attachments(std::vector<std::string> attachments)
{
    GMimeMessage *message;
    GMimeParser  *parser;
    GMimeStream  *stream;
    int fd;
    int result __attribute__((unused));

    /*
     * If there are no attachments return.
     */
    if (attachments.size() < 1)
        return;

    if ((fd = open(m_path.c_str(), O_RDONLY, 0)) == -1)
    {
        CLua *lua = CLua::instance();
        lua->on_error("Failed to open the message:" + m_path);
        return;
    }

    stream = g_mime_stream_fs_new(fd);

    parser = g_mime_parser_new_with_stream(stream);
    g_object_unref(stream);

    message = g_mime_parser_construct_message(parser);
    g_object_unref(parser);


    GMimeMultipart *multipart;
    GMimePart *addition;
    GMimeDataWrapper *content;

    /*
     * Create a new multipart message.
     */
    multipart = g_mime_multipart_new();
    GMimeContentType *type;

    /*
     * Handle the mime-type.
     */
    type = g_mime_content_type_new("multipart", "mixed");
    g_mime_object_set_content_type(GMIME_OBJECT(multipart), type);


    GMimeContentType *new_type;
    GMimeObject *mime_part;

    mime_part = g_mime_message_get_mime_part(message);
    new_type = g_mime_content_type_new_from_string("text/plain; charset=UTF-8");
    g_mime_object_set_content_type(mime_part, new_type);

    /*
     * first, add the message's toplevel mime part into the multipart
     */
    g_mime_multipart_add(multipart, g_mime_message_get_mime_part(message));

    /*
     * now set the multipart as the message's top-level mime part
     */
    g_mime_message_set_mime_part(message, (GMimeObject*) multipart);

    /*
     * For each attachment ..
     */
    for (std::string name : attachments)
    {
        int ad;

        if ((ad = open(name.c_str(), O_RDONLY)) == -1)
            return;

        stream = g_mime_stream_fs_new(ad);

        /*
         * the stream isn't encoded, so just use DEFAULT
         */
        content = g_mime_data_wrapper_new_with_stream(stream, GMIME_CONTENT_ENCODING_DEFAULT);

        g_object_unref(stream);

        /*
         * Find the MIME-type of the file.
         */
        CMime *mime = CMime::instance();
        std::string ctype = mime->type(name);

        /*
         * Here we use the mime-type we've returned and set that for the
         * attachment.
         */
        addition = g_mime_part_new();
        GMimeContentType *a_type = g_mime_content_type_new_from_string(ctype.c_str());
        g_mime_part_set_content_object(addition, content);
        g_mime_object_set_content_type((GMimeObject *)addition, a_type);
        g_object_unref(content);

        /*
         * set the filename.
         */
        g_mime_part_set_filename(addition, CFile::basename(name).c_str());

        /*
         * Here we use base64 encoding.
         *
         * NOTE: if you want to get really fancy, you could use
         * g_mime_part_get_best_content_encoding()
         * to calculate the most efficient encoding algorithm to use.
         */
        g_mime_part_set_content_encoding(addition, GMIME_CONTENT_ENCODING_BASE64);

        /*
         * Add the attachment to the multipart
         */
        g_mime_multipart_add(multipart, (GMimeObject*)addition);
        g_object_unref(addition);
    }

    /*
     * now that we've finished referencing the multipart directly (the message still
     * holds it's own ref) we can unref it.
     */
    g_object_unref(multipart);

    /*
     * Output the updated message.  First pick a tmpfile.
     *
     * NOTE: We must use a temporary file.  If we attempt to overwrite the
     * input file we'll get corruption, due to GMime caching.
     */
    CConfig *config     = CConfig::instance();
    std::string tmp_dir = config->get_string("global.tmpdir", "/tmp");
    std::string tmp_pat = tmp_dir + "/lumail2XXXXXXXX";
    char *tmp_file      = strdup(tmp_pat.c_str());

    result = mkstemp(tmp_file);

    /*
     * Write out the updated message.
     */
    FILE *f = NULL;

    if ((f = fopen(tmp_file, "wb")) == NULL)
    {
        free(tmp_file);
        close(fd);
        return;
    }

    GMimeStream *ostream = g_mime_stream_file_new(f);
    g_mime_object_write_to_stream((GMimeObject *) message, ostream);
    g_object_unref(ostream);
    g_object_unref(message);
    /*
     * Now rename the temporary file over the top of the input
     * message.
     */
    CFile::copy(tmp_file, m_path);
    CFile::delete_file(tmp_file);

    if (m_parts.size() > 0)
        m_parts.clear();

    close(fd);
    free(tmp_file);
}


/**
 * Get the parent object.
 */
std::shared_ptr<CMaildir> CMessage::parent()
{
    return (m_parent);
}

/**
 * Set the parent object.
 */
void CMessage::parent(std::shared_ptr<CMaildir> owner)
{
    m_parent = owner;
}


/*
 * Retrieve the last modification time of our message.
 */
int CMessage::get_mtime()
{
    if (m_imap == false)
    {
        std::string our_path = path();

        struct stat sb;

        if (stat(our_path.c_str(), &sb) < 0)
            return 1;
        else
            return sb.st_mtime;
    }

    return (m_time);
}


/*
 * Load our IMAP-based body, lazily.
 */
void CMessage::lazy_load()
{
    if (! CFile::exists(m_path))
    {
        /*
         * Fetch our body
         */
        std::string cmd = "get_message " ;
        cmd += std::to_string(m_imap_id);
        cmd += " ";
        cmd += m_parent->path();
        cmd += "\n";

        /*
         * Get the output.
         */
        CIMAPProxy *proxy = CIMAPProxy::instance();
        std::string out  = proxy->read_imap_output(cmd);

        /*
         * Write to disk.
         */
        std::fstream fs;
        fs.open(m_path,  std::fstream::out | std::fstream::app);
        fs << out;
        fs.close();

    }
}
