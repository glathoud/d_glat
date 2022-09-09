/**
 By Guillaume Lathoud
 glat@glat.info
 
 Distributed under the Boost License, see file ./LICENSE
*/
module d_glat.core_parse_duration;

import std.algorithm : canFind, countUntil;
import std.conv : to;
import std.datetime : dur, Duration;
import std.exception : enforce;
import std.math : round;
import std.regex : matchFirst, matchAll;


immutable string parse_duration_units = "hms";

Duration parse_duration( in string in_s )
{
  auto ret = Duration.zero;

  immutable error_msg = "core_parse_duration: unsupported s string \""~in_s~"\"."
    ~` Supported: "23.0s" (seconds), "0.74m" (minutes), "1.57h" (hours)`
    ~`, "1h30", "1h30m", "2m37", "2m37s", "1h30m26s"`;

  enforce( 0 < in_s.length, error_msg );

  alias units = parse_duration_units;
  
  char next_unit_after( in string u )
  {
    immutable ind = units.countUntil( u );
    enforce( 0 <= ind  &&  ind+1 < units.length, error_msg );
    return units[ 1 + ind ];
  }
  
  {
    immutable s = units.canFind( in_s[ $-1 ] )
      ?  in_s

      : // Autocomplete last unit, if missing: "1h40" => "1h40m"
      in_s ~ next_unit_after( in_s.matchFirst( r"([a-z])[^a-z]+$")[ 1 ] )
      ;
    
    foreach (c; s.matchAll( r"[^a-z]*[a-z]"))
      {
        auto a = c[ 0 ];
        
        immutable x = to!double( a[0..$-1] );
        switch (a[$-1])
          {
          case 's': ret += dur!"nsecs"( cast(long)( round( x *    1.0e9 ) ) );
            break;
            
          case 'm': ret += dur!"nsecs"( cast(long)( round( x *   60.0e9 ) ) );
            break;
            
          case 'h': ret += dur!"nsecs"( cast(long)( round( x * 3600.0e9 ) ) );
            break;

          default: enforce( false, error_msg );
          }
      }
  }
  
  return ret;
}

unittest
{
  import std.stdio;
  import std.path;

  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  immutable verbose = false;

  assert( parse_duration( "0m" ) == Duration.zero );

  assert( parse_duration( "2h" ) == 2.dur!"hours" );
  assert( parse_duration( "2h37" ) == 2.dur!"hours" + 37.dur!"minutes" );
  assert( parse_duration( "3m" ) == 3.dur!"minutes" );
  assert( parse_duration( "4s" ) == 4.dur!"seconds" );
  assert( parse_duration( "2h3m4s" ) == 2.dur!"hours" + 3.dur!"minutes" + 4.dur!"seconds" );
  assert( parse_duration( "2h3m4" ) == 2.dur!"hours" + 3.dur!"minutes" + 4.dur!"seconds" );

  assert( parse_duration( "2.5h3.75m4.031s" )
          == 2.dur!"hours" + 30.dur!"minutes"
          + 3.dur!"minutes" + 45.dur!"seconds"
          + 4.dur!"seconds" + 31.dur!"msecs" );

  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}

