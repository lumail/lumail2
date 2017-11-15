/*
 * message_part.h - A class for dealing with MIME parts.
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
#include <vector>


/**
 * This is the C++ object which represents a MIME-part from a message.
 */
class CMessagePart
{

public:

    /**
     * Constructor.
     */
    CMessagePart(std::string type, std::string filename, void *content, size_t content_length);

    /**
     * Destructor
     */
    ~CMessagePart();

    /**
     * Get the content-type of the MIME-part.
     */
    std::string type();

    /**
     * Get the filename - only makes sense for "is_attachment() == true".
     */
    std::string filename();

    /**
     * Is this an attachment?
     */
    bool is_attachment();

    /**
     * Get the content.
     */
    void *content();

    /**
     * Get the length of the content.
     */
    size_t content_size();

    /**
     * Get the children of this part, if any.
     */
    std::vector<std::shared_ptr<CMessagePart>> children();

    /**
     * Add a child to this part.
     */
    void add_child(std::shared_ptr<CMessagePart> child);

    /**
     * Set the parent to this part.
     */
    void set_parent(std::shared_ptr<CMessagePart> parent);

    /**
     * Get the parent of this part, which may be null.
     */
    std::shared_ptr<CMessagePart> get_parent();

    /**
     * Does this part need gpg ?
     */
    bool need_gpg() { return m_need_gpg; }

    /**
     * Set m_need_gpg
     */
    void need_gpg(bool b) {  m_need_gpg = b; }


private:

    /**
     * The content-type of this part.
     */
    std::string m_type;

    /**
     * The filename of this part, if it is an attachment.  If not it will
     * be unset.
     */
    std::string m_filename;

    /**
     * The actual content of this MIME-part
     */
    void *m_content;

    /**
     * The length of this MIME-part's content.
     */
    size_t m_content_length;

    /**
     * Children of this part.
     */
    std::vector<std::shared_ptr<CMessagePart>> m_children;

    /**
     * Parent of this part.
     */
    std::shared_ptr<CMessagePart> m_parent;

    /**
     * Is this part a signature or encrypted  ?
     */
    bool m_need_gpg;
};
