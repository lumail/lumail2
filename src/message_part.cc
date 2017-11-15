/*
 * message_part.cc - Wrapper for MIME-parts.
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
#include <string>
#include <vector>
#include <stdlib.h>

#include "message_part.h"



/*
 * Constructor.
 */
CMessagePart::CMessagePart(std::string type, std::string filename,
                           void *content, size_t content_length)
{
    m_parent         = nullptr;
    m_type           = type;
    m_filename       = filename;
    m_content        = NULL;
    m_content_length = 0;
    m_need_gpg       = false;

    if ((content_length > 0) && (content != NULL))
    {
        m_content = content;
        m_content_length = content_length;
    }

    /*
     * To allow users to make use of the MIME type more easily
     * we'll only store it as lower-case.
     */
    std::transform(m_type.begin(), m_type.end(), m_type.begin(), ::tolower);

}

/*
 * Destructor.
 */
CMessagePart::~CMessagePart()
{
    if (m_content != NULL)
    {
        free(m_content);
        m_content = NULL;
        m_content_length = 0;
    }

    if (m_children.size() > 0)
        m_children.clear();

}

/*
 * Get the content-type of the MIME-part.
 */
std::string CMessagePart::type()
{
    return (m_type);
}

/*
 * Get the filename - only makes sense for "is_attachment() == true".
 */
std::string CMessagePart::filename()
{
    return (m_filename);
}


/*
 * Is this an attachment?
 */
bool CMessagePart::is_attachment()
{
    return (m_filename.empty() == false);
}


/*
 * Get the content.
 */
void * CMessagePart::content()
{
    return (m_content);
}

/*
 * Get the length of the content.
 */
size_t CMessagePart::content_size()
{
    return (m_content_length);
}


/*
 * Get the children of this part, if any.
 */
std::vector<std::shared_ptr<CMessagePart>> CMessagePart::children()
{
    return (m_children);
}

/*
 * Add a child to this part.
 */
void CMessagePart::add_child(std::shared_ptr<CMessagePart> child)
{
    m_children.push_back(child);
}


/*
 * Set the parent to this part.
 */
void CMessagePart::set_parent(std::shared_ptr<CMessagePart> parent)
{
    m_parent = parent;
}

/*
 * Get the parent of this part, which may be null.
 */
std::shared_ptr<CMessagePart> CMessagePart::get_parent()
{
    return (m_parent);
}
