/*
 * message.h - A class for handling a single message.
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


#pragma once


#include <memory>
#include <string>
#include <unordered_map>
#include <vector>
#include <gmime/gmime.h>

class CMaildir;

/*
 * Forward declaration of class.
 */
class CMessagePart;



/**
 *
 * This is the C++ object which represents an email message.
 *
 * The lua binding is modelled after this class structure too.
 *
 */
class CMessage
{
public:
    /**
     * Constructor.
     */
    CMessage(const std::string name, bool is_local = true);

    /**
     * Destructor.
     */
    ~CMessage();

    /**
     * Is this message a local one?
     */
    bool is_maildir();


    /**
     * Is this message an IMAP one?
     */
    bool is_imap();


    /**
      * Get the path of this message.
      */
    std::string path();

    /**
     * Update the path to the message.
     */
    void path(std::string new_path);

    /**
     * Get the value of the given header.
     */
    std::string header(std::string name);

    /**
     * Get all headers, and their values.
     */
    std::unordered_map < std::string, std::string > headers();

    /**
     * Retrieve the current flags for this message.
     */
    std::string get_flags();

    /**
     * Set the flags for this message.
     */
    void set_flags(std::string new_flags);

    /**
     * Set IMAP-flags - these are set at creation time.
     */
    void set_imap_flags(std::string flags);

    /**
     * Set the IMAP message ID of this message
     */
    void set_imap_id(int n)
    {
        m_imap_id = n;
    };


    /**
     * Add a flag to a message.
     */
    bool add_flag(char c);

    /**
     * Does this message possess the given flag?
     */
    bool has_flag(char c);

    /**
     * Remove a flag from a message.
     */
    bool remove_flag(char c);

    /**
     * Is this message new?
     */
    bool is_new();

    /**
     * Mark a message as unread.
     *
     * If this message is stored on a remote IMAP-server we handle
     * that specially.
     */
    void mark_unread();

    /**
     * Mark a message as read.
     *
     * If this message is stored on a remote IMAP-server we handle
     * that specially.
     */
    void mark_read();

    /**
     * Remove this message.
     *
     * If this message is stored on a remote IMAP-server we handle
     * that specially.
     */
    bool unlink();

    /**
     * Parse the message into MIME-parts, if we've not already done so.
     *
     * The parts are returned as a vector of CMessagePart objects, each
     * of which could contain nested children.
     */
    std::vector<std::shared_ptr<CMessagePart>> get_parts();


    /**
     * Add the named file as an attachment to this message.
     */
    void add_attachments(std::vector<std::string> attachments);

    /**
     * Get the parent object - this is only used for IMAP-based messages.
     *
     * We store the parent such that we can find which folder this message
     * came from, which is required if we want to change the flags, or delete
     * the message.
     */
    std::shared_ptr<CMaildir> parent();


    /**
     * Set the parent object - this is only used for IMAP-based messages.
     *
     * We store the parent such that we can find which folder this message
     * came from, which is required if we want to change the flags, or delete
     * the message.
     */
    void parent(std::shared_ptr<CMaildir> owner);

    /**
     * Retrieve the last modification time of our message.
     */
    int get_mtime();

private:

    /**
     * Load our IMAP-based body, lazily.
     */
    void lazy_load();

    /**
     * Parse a MIME message and return an object suitable for operating
     * upon.
     */
    GMimeMessage * parse_message();

    /**
     * Populate the headers and MIME-Parts caches.
     */
    void populate_message();

    /**
     * Convert a message-part from the MIME message to a CMessagePart object.
     */
    std::shared_ptr<CMessagePart> part2obj(GMimeObject *part);

private:

    /**
     * The last modification time of our message.
     */
    int m_time;

    /**
     * The path on-disk to the message.
     */
    std::string m_path;

    /**
     * Cached message-headers from this mail.
     */
    std::unordered_map < std::string, std::string > m_headers;

    /**
     * Cached MIME-parts to this message.
     */
    std::vector<std::shared_ptr<CMessagePart>> m_parts;

    /**
     * Is this message stored in IMAP?
     */
    bool m_imap;

    /**
     * The flags retrieved from IMAP
     */
    std::string m_imap_flags;

    /**
     * The IMAP ID
     */
    int m_imap_id;

    /**
     * The parent folder.
     */
    std::shared_ptr<CMaildir> m_parent;
};



/**
 * This is a utility-type which contains a list of messages, as
 * a vector.
 */
typedef std::vector <std::shared_ptr <CMessage > > CMessageList;
