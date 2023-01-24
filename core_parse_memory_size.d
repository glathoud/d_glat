/**
 By Guillaume Lathoud
 glat@glat.info
 
 Distributed under the Boost License, see file ./LICENSE
*/
module d_glat.core_parse_memory_size;

import std.algorithm : canFind, countUntil, endsWith, sort;
import std.array : array;
import std.conv : to;
import std.datetime : dur, Duration;
import std.exception : enforce;
import std.math : round;
import std.regex : matchFirst, matchAll;
import std.stdio;
import std.uni : toUpper;

immutable ulong[string] nbytes_of_abbr;
immutable string[] abbr_order;

shared static this()
{
  // https://en.wikipedia.org/wiki/Megabyte

  nbytes_of_abbr[ "KB" ] = 1_000UL;
  nbytes_of_abbr[ "MB" ] = 1_000_000UL;
  nbytes_of_abbr[ "GB" ] = 1_000_000_000UL;
  nbytes_of_abbr[ "TB" ] = 1_000_000_000_000UL;

  {
    immutable kib = nbytes_of_abbr[ "KIB" ] = nbytes_of_abbr[ "K" ] = 1024UL;
    ulong tmp = kib;
    nbytes_of_abbr[ "MIB" ] = nbytes_of_abbr[ "M" ] = (tmp *= kib);
    nbytes_of_abbr[ "GIB" ] = nbytes_of_abbr[ "G" ] = (tmp *= kib);
    nbytes_of_abbr[ "TIB" ] = nbytes_of_abbr[ "T" ] = (tmp *= kib);
  }

  abbr_order = nbytes_of_abbr.keys.dup
    .sort!((a,b) => a.length == b.length  ?  a > b  :  a.length > b.length)
    .array.idup;
}

long parse_memory_size( in string s_in )
{
  immutable s = s_in.toUpper;

  foreach (abbr; abbr_order)
    {
      if (s.endsWith( abbr ))
        {
          immutable n_0 = to!long( s[0..$-abbr.length]);
          return n_0 * nbytes_of_abbr[ abbr ];
        }
    }

  // Default (without unit): assume in bytes
  return to!long( s );
}

unittest
{
  import std.stdio;
  import std.path;

  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  immutable verbose = false;

  if (verbose)
    writeln(parse_memory_size( "1K" ));
  
  assert( parse_memory_size( "1K" ) == 1024UL );
  assert( parse_memory_size( "2M" ) == 2UL * 1024UL * 1024UL );
  assert( parse_memory_size( "3G" ) == 3UL * 1024UL * 1024UL * 1024UL );
  assert( parse_memory_size( "4T" ) == 4UL * 1024UL * 1024UL * 1024UL * 1024UL);

  assert( parse_memory_size( "1KiB" ) == 1024UL );
  assert( parse_memory_size( "2MiB" ) == 2UL * 1024UL * 1024UL );
  assert( parse_memory_size( "3GiB" ) == 3UL * 1024UL * 1024UL * 1024UL );
  assert( parse_memory_size( "4TiB" ) == 4UL * 1024UL * 1024UL * 1024UL * 1024UL);

  assert( parse_memory_size( "1KB" ) == 1000UL );
  assert( parse_memory_size( "2MB" ) == 2_000_000UL );
  assert( parse_memory_size( "3GB" ) == 3_000_000_000UL );
  assert( parse_memory_size( "4TB" ) == 4_000_000_000_000UL );

  assert( parse_memory_size( "987654321" ) == 987654321UL );
}
