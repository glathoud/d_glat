/**
 By Guillaume Lathoud
 glat@glat.info
 
 Distributed under the Boost License, see file ./LICENSE
*/
module d_glat.core_file;

import core.stdc.stdlib : exit;
import std.conv : octal;
import std.file : exists, getAttributes, isDir, isFile, mkdirRecurse;
import std.path : baseName, dirName;
import std.stdio : stderr, writefln, writeln;

void ensure_dir_exists( in string dir_name )
{
  if (!exists( dir_name ))
    {
      mkdirRecurse( dir_name );
    }
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
