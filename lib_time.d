module d_glat.lib_time;

import std.array;
import std.datetime;
import std.format;
import std.math;
import std.stdio;


const long TIME_0_HNSECS;
immutable TimeZone TIME_ZONE;
immutable TimeZone TIME_ZONE_GMT;

immutable long HNSECS_OF_MS   = cast( long )( 1e4 );
immutable long HNSECS_OF_SECS = cast( long )( 1e7 );

shared static this() 
{
  // writeln( PosixTimeZone.getInstalledTZNames().join( "\n" ) );

  TIME_ZONE_GMT = PosixTimeZone.getTimeZone( "GMT" );

  TIME_0_HNSECS =
    SysTime( DateTime( 1970, 1, 1 ), TIME_ZONE_GMT ).stdTime();
  
  TIME_ZONE = TIME_ZONE_GMT;
}


string get_utc_str_of_timems( in long timems )
{
  return get_utc_str( get_sys_time_of_utc_ms( timems ) );
}

SysTime get_sys_time_of_utc_ms( long delta_time_ms ) pure @safe nothrow
{
  return SysTime( TIME_0_HNSECS + HNSECS_OF_MS * delta_time_ms
                  , TIME_ZONE );
}

string get_utc_str( in SysTime sys_time )
{
  return sys_time.toISOExtString;
}

