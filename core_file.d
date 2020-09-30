/**
 By Guillaume Lathoud
 glat@glat.info
 
 Distributed under the Boost License, see file ./LICENSE
*/
module d_glat.core_file;

import core.stdc.stdlib : exit;
import std.conv : octal;
import std.datetime.systime : SysTime;
import std.file : exists, getAttributes, getTimes, getSize, isDir, isFile, mkdirRecurse, isSymlink, readLink;
import std.path : baseName, buildPath, buildNormalizedPath, dirName, isAbsolute;
import std.stdio : stderr, writefln, writeln;
import std.typecons : Nullable;

bool ensure_dir_exists( in string dir_name )
// Return `true` if the dir already existed, otherwise, create it
// and return `false`.
{
  immutable ret = exists( dir_name );
  
  if (!ret)
    mkdirRecurse( dir_name );
  
  return ret;
}


void ensure_file_writable_or_exit( in string outfilename, in bool ensure_dir = false )
{
  auto out_dirName = dirName( outfilename );

  if (ensure_dir)
    {
      ensure_dir_exists( out_dirName );
    }
  
  
  if (!exists( out_dirName ))
    {
      stderr.writefln( "Output: Directory does not exists: %s", out_dirName );
      exit( -1 );
    }
  if (!isDir( out_dirName ))
    {
      stderr.writefln( "Output: Not a directory: %s", out_dirName );
      exit( -1 );
    }
  auto dirAttr = getAttributes( out_dirName );
  if (!(dirAttr & octal!200))
    {
      stderr.writefln( "Output: Directory does not have user-write permission: %s", out_dirName );
      exit( -1 );
    }
  if (exists( outfilename )  &&  !isFile( outfilename ))
    {
      stderr.writefln( "Output: Already exists, but is not a file: %s", outfilename );
      exit( -1 );
    }
  if (exists( outfilename )  &&  !(octal!200 & getAttributes( outfilename )))
    {
      stderr.writefln( "Output: File already exists, but does not have user-write permission: %s", outfilename );
      exit( -1 );
    }
}

bool exists_non_empty( in string filename )
{
  Nullable!(bool[string]) existing_filename_set;
  existing_filename_set.nullify();

  return exists_non_empty( filename, existing_filename_set );
}



bool exists_non_empty( in string filename, in Nullable!(bool[string]) existing_filename_set )
/*
  Useful to detect e.g. a file that was not completely written
  before electrical current was lost, which abruptly stopped the
  computer.
 */
{
  return (existing_filename_set.isNull  ?  exists( filename )  :  (null != (filename in existing_filename_set)))
    &&  0 < getSize( filename );
}


SysTime get_modification_time( in string filename )
{
  

  SysTime accessTime, modificationTime;
  getTimes(filename, accessTime, modificationTime);

  return modificationTime;
}


string resolve_symlink( in string maybe_symlink )
{
  

  if (!maybe_symlink.isSymlink)
    return maybe_symlink; // not a symlink

  auto target = maybe_symlink.readLink;
  if (isAbsolute( target ))
    return target; // absolute symlink

  // relative symlink

  return buildPath( maybe_symlink.dirName, target ).buildNormalizedPath;
}



ubyte[] ubytedata_of_little_endian_ushortdata( in ushort[] ushortdata )
{
  ulong n = ushortdata.length;
  ubyte[] ret = new ubyte[ n << 1 ];

  int j = 0;
  for (int i = 0; i < n; i++)
    {
      ushort us = ushortdata[ i ];
      ret[ j++ ] = us & 0xFF;
      ret[ j++ ] = (us >> 8)  & 0xFF;
    }
  return ret;
}
