/**
 By Guillaume Lathoud
 glat@glat.info
 
 Distributed under the Boost License, see file ./LICENSE
*/
module d_glat.core_file;

import core.stdc.stdlib : exit;
import std.conv : octal, to;
import std.datetime.systime : SysTime;
import std.file : exists, getAttributes, getTimes, getSize, isDir, isFile, mkdirRecurse, isSymlink, readLink;
import std.path : absolutePath, baseName, buildPath, buildNormalizedPath, dirName, isAbsolute;
import std.process : executeShell;
import std.regex : regex, splitter;
import std.stdio : stdout, stderr, writefln, writeln;
import std.string : splitLines, strip;
import std.typecons : Nullable;

immutable BASENAME_MAXLENGTH = 254;  // 255 generally works with linux filesystems, but then many bash commands still don't work ("filename too long", they say), hence: 254

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
  scope auto dirAttr = getAttributes( out_dirName );
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

struct MaybeExistingFilenameSet
{
  bool           available;
  size_t[string] size_of_filename;
};

immutable EmptyExistingFilenameSet = MaybeExistingFilenameSet( false );


bool exists_non_empty( in string filename )
{
  return exists_non_empty( filename
                           , /*efs_knows_all: whatever, efs empty anway*/false
                           , EmptyExistingFilenameSet
                           );
}

bool exists_non_empty( in string filename
                       , in bool efs_knows_all, in MaybeExistingFilenameSet existing_filename_set )
/*
  Useful to detect e.g. a file that was not completely written
  before electrical current was lost, which abruptly stopped the
  computer.
 */
{
  // If provided, check the assoc array
  
  if (existing_filename_set.available)
    {
      if (scope auto p = filename in existing_filename_set.size_of_filename)
        return 0 < *p; // *p supposed to be == getSize( filename )
      
      if (efs_knows_all)
        return false;
    }

  // Fallback: disk access
  
  return exists( filename )  &&  0 < getSize( filename );
}


SysTime get_modification_time( in string filename )
{
  scope SysTime accessTime;
  SysTime modificationTime;
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


import std.file : getAvailableDiskSpace;

size_t getUsedDiskSpace( in string path )
// Does what it says at `path` (if isDir(path)) else at
// `dirName(path)` (e.g. if isFile(path)), and returns a number of
// bytes.
{
  immutable dir = absolutePath( isDir( path )  ?  path  :  dirName( path ) );
  immutable cmd = `du -b --max-depth=0 "`~dir~`"`;
  scope auto tmp = executeShell( cmd );
  if (tmp.status != 0)
    {
      immutable msg = `getUsedDiskSpace failed on path: "`~path~`". cmd:"`~cmd~`" returned `
        ~`status:`~to!string(tmp.status)~` and output:`~to!string(tmp.output);

      stdout.writeln( msg ); stdout.flush;
      stderr.writeln( msg ); stderr.flush;
      assert( false, msg );
    }

  return to!size_t( tmp.output.splitter( regex( `\s` ) ).front.strip ); 
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
