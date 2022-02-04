/**
 By Guillaume Lathoud
 glat@glat.info
 
 Distributed under the Boost License, see file ./LICENSE
*/
module d_glat.core_glob;

public import std.file : SpanMode;

import d_glat.core_assert;
import std.array : appender;
import std.conv : to;
import std.file : dirEntries, exists;
import std.path : baseName, dirName;

shared static GLOB_JPG = "*.[jJ][pP][gG]";


string dirOneMaybe
  ( in string fullpathglob, in SpanMode spanMode = SpanMode.shallow, in bool followSymlink = false )
// Returns "" if file not found, a non-empty string if exactly one
// file found, throw an exception of more than one file found.
{
  return dirOne!/*maybe:*/true( dirName( fullpathglob ), baseName( fullpathglob ), spanMode, followSymlink );
}

string dirOneMaybe
( in string path, in string glob, in SpanMode spanMode = SpanMode.shallow, in bool followSymlink = false )
// Returns "" if file not found, a non-empty string if exactly one
// file found, throw an exception of more than one file found.
{
  return dirOne!/*maybe:*/true( path, glob, spanMode, followSymlink );
}

  

string dirOne(bool maybe = false)
  ( in string fullpathglob, in SpanMode spanMode = SpanMode.shallow, in bool followSymlink = false )
{
  return dirOne!maybe( dirName( fullpathglob ), baseName( fullpathglob ), spanMode, followSymlink );
}


string dirOne(bool maybe = false)
  ( in string path, in string glob, in SpanMode spanMode = SpanMode.shallow, in bool followSymlink = false )
{
  auto sa = dirSA( path, glob, spanMode, followSymlink );

  mixin(alwaysAssertStderr
        (maybe  ?  `sa.length <= 1`  :  `sa.length == 1`,
         `"sa.length must be "~(maybe? "<=one" : "one")~", got: "~to!string( sa.length )~", sa:"~to!string( sa )`
         ));

  static if (maybe)
    return 0 < sa.length  ?  sa[ 0 ]  :  "";
  else
    return sa[ 0 ];
}


string[] dirSA( in string path, in string glob, in SpanMode spanMode = SpanMode.breadth, in bool followSymlink = false )
// Extract a dirEntries result, and convert it to an array of strings
// http://www.digitalmars.com/d/archives/digitalmars/D/bugs/Issue_7138_New_Can_t_call_array_on_dirEntries_34691.html
// 
// In most cases `foreach( name ; dirEntries( ... ))` is enough.
// `dirSA` is ONLY only if you really need the array of strings.
{
  if (!exists( path ))
    return [];

  auto app = appender!(string[]);

  // Speed: Try to access the string `name` directly with the hope
  // *not* to trigger (L)Stat in `DirIterator` (see std.file).
  foreach (string name; dirEntries( path, glob, spanMode, followSymlink ))
    app.put( name );

  return app.data;
}

string[] dirSA( in string fullpathglob, in SpanMode spanMode = SpanMode.breadth, in bool followSymlink = false ) 
// shortcut for use cases without depth
{
  return dirSA( dirName( fullpathglob ), baseName( fullpathglob ), spanMode, followSymlink );
}


unittest
{
  import std.stdio;
  import std.path;

  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  immutable verbose = false;

  import core.thread;
  import d_glat.core_file;
  import std.conv;
  import std.datetime;
  import std.file;
  import std.random;
  
  {
    
    auto tmpdn = buildPath( tempDir, "lfcr_"~to!string(uniform(0L,long.max))~"_"~to!string(Clock.currTime.stdTime) );
    ensure_dir_exists( tmpdn );

    if (verbose)
      writeln("tmpdn: ", tmpdn, " ", exists( tmpdn ));

    // create several files

    std.file.write( buildPath( tmpdn, "a.save-0" ), "aaa" );
    std.file.write( buildPath( tmpdn, "a.save-1" ), "aaa 1" );
    std.file.write( buildPath( tmpdn, "a.save-2" ), "aaa 2" );
    std.file.write( buildPath( tmpdn, "a.save-3" ), "aaa 3" );

    string f4 = buildPath( tmpdn, "a.save-4" );
    std.file.write( f4, "aaa 4" );

    std.file.write( buildPath( tmpdn, "a.save-5" ), "aaa 5" );

    auto arr_0 = dirSA( buildPath( tmpdn, "a.save-*" ) );

    if (verbose)
      {
        writeln;
        writeln( "arr_0: ", arr_0 );
      }

    assert( arr_0.length == 6 );
    
    Thread.sleep(dur!("msecs")(250));
    
    // delete one

    std.file.remove( f4 );
    
    // test

    auto arr_1 = dirSA( buildPath( tmpdn, "a.save-*" ) );

    if (verbose)
      {
        writeln;
        writeln( "arr_1: ", arr_1 );
      }

    assert( arr_1.length == 5 );

    // cleanup
    
    std.file.rmdirRecurse( tmpdn );

    if (verbose)
      writeln("tmpdn: ", tmpdn, " ", exists( tmpdn ));
    
    assert( !exists( tmpdn ) );
  }


  writeln( "unittest passed: ", baseName( __FILE__ ) );
}



