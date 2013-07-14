/**
 * file.cc - Simple file primitives.
 *
 * This file is part of lumail: http://lumail.org/
 *
 * Copyright (c) 2013 by Steve Kemp.  All rights reserved.
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
#include <iostream>
#include <fstream>
#include <algorithm>
#include <iterator>
#include <cstdlib>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>


#include "debug.h"
#include "file.h"

#ifndef FILE_READ_BUFFER
# define FILE_READ_BUFFER 16384
#endif



/**
 * Test if a file exists.
 */
bool CFile::exists( std::string path )
{
    struct stat sb;

    if ((stat(path.c_str(), &sb) == 0))
        return true;
    else
        return false;
}


/**
 * Is the given file executable?
 */
bool CFile::executable( std::string path )
{
    struct stat sb;

    /**
     * Fail to stat?  Then not executable.
     */
    if (stat(path.c_str(), &sb) < 0)
        return false;

    /**
     * If directory then not executable.
     */
    if (S_ISDIR(sb.st_mode))
        return false;

    /**
     * Otherwise check the mode-bits
     */
    if ((sb.st_mode & S_IEXEC) != 0)
        return true;
    return false;
}


/**
 * Is the given path a directory?
 */
bool CFile::is_directory(std::string path)
{
    struct stat sb;

    if (stat(path.c_str(), &sb) < 0)
      return 0;

    return (S_ISDIR(sb.st_mode));
}


/**
 * Copy a file.
 */
void CFile::copy( std::string src, std::string dst )
{

#ifdef LUMAIL_DEBUG
    std::string dm = "CFile::copy(\"";
    dm += src ;
    dm += "\",\"";
    dm += dst;
    dm += "\");";
    DEBUG_LOG( dm );
#endif

    std::ifstream isrc(src, std::ios::binary);
    std::ofstream odst(dst, std::ios::binary);

    std::istreambuf_iterator<char> begin_source(isrc);
    std::istreambuf_iterator<char> end_source;
    std::ostreambuf_iterator<char> begin_dest(odst);

    std::copy(begin_source, end_source, begin_dest);

    isrc.close();
    odst.close();
}

/**
 * Move a file.
 */
bool CFile::move( std::string src, std::string dst )
{
#ifdef LUMAIL_DEBUG
    std::string dm = "CFile::move(\"";
    dm += src ;
    dm += "\",\"";
    dm += dst;
    dm += "\");";
    DEBUG_LOG( dm );
#endif

    return( rename( src.c_str(), dst.c_str() ) == 0 );
}

/**
 * Send the contents of a file to the given command, via popen.
 */
bool CFile::file_to_pipe( std::string src, std::string cmd )
{

#ifdef LUMAIL_DEBUG
    std::string dm = "CFile::file_to_pipe(\"";
    dm += src ;
    dm += "\",\"";
    dm += cmd;
    dm += "\");";
    DEBUG_LOG( dm );
#endif

    char buf[FILE_READ_BUFFER] = { '\0' };
    ssize_t nread;

    FILE *file = fopen( src.c_str(), "r" );
    if ( file == NULL )
        return false;

    FILE *pipe = popen( cmd.c_str(), "w" );
    if ( pipe == NULL )
        return false;

    /**
     * While we read from the file send to pipe.
     */
    while( (nread = fread( buf, sizeof(char), sizeof buf-1, file) ) > 0 )
    {
        char *out_ptr = buf;
        ssize_t nwritten;

        do
        {
            nwritten = fwrite(out_ptr, sizeof(char), nread, pipe);

            if (nwritten >= 0)
            {
                nread -= nwritten;
                out_ptr += nwritten;
            }
        } while (nread > 0);

        memset(buf, '\0', sizeof(buf));
    }

    pclose( pipe );
    fclose( file );

    return true;
}
