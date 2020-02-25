/**
 By Guillaume Lathoud
 glat@glat.info
 
 Distributed under the Boost License, see file ./LICENSE
*/
module d_glat.core_glob;

public import std.file : SpanMode;

import std.algorithm : map;
import std.array : array;
import std.file : dirEntries, exists;
import std.path : baseName, dirName;

shared static GLOB_JPG = "*.[jJ][pP][gG]";

string[] dirSA( string path, string glob, SpanMode spanMode = SpanMode.breadth, bool followSymlink = false )
// Extract a dirEntries result, and convert it to an array of strings
// http://www.digitalmars.com/d/archives/digitalmars/D/bugs/Issue_7138_New_Can_t_call_array_on_dirEntries_34691.html
// 
// In most cases `foreach( name ; dirEntries( ... ))` is enough.
// `dirSA` is ONLY only if you really need the array of strings.
{
  if (!exists( path ))
    return [];
  
  auto dE = dirEntries( path, glob, spanMode, followSymlink );
  return ( map!`cast( string )a`( dE ) ).array;
}

string[] dirSA( in string fullpathglob, SpanMode spanMode = SpanMode.breadth, bool followSymlink = false ) 
{
  return dirSA( dirName( fullpathglob ), baseName( fullpathglob ), spanMode, followSymlink );
}

unittest{}
