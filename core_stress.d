module d_glat.core_stress;

import std.datetime;
import std.path;
import std.random;
import std.stdio;

/*
  Do some waste work. Useful to fake work, where we suspect the real
  work to lead to suboptimal multithreading performance. 

  Also useful for multithreading issues (more for actual buggy behaviour):
  ./lib_threadlog.d

  The Boost license applies to this file, see ./LICENSE

  Guillaume Lathoud, 2020
  glat@glat.info
 */

double stress(string duration_type /*e.g. "msecs" "usecs" "seconds" ...*/)
  ( in size_t lower_duration, in size_t higher_duration_in = 0, in bool verbose = true )
{
  scope immutable higher_duration = 0 < higher_duration_in  ?  higher_duration_in  :  lower_duration;
  
  scope immutable begin = Clock.currTime;
  
  scope immutable dur = dur!duration_type( lower_duration == higher_duration
                                           ?  lower_duration
                                           :  uniform( lower_duration, higher_duration ) );
  
  double whatever = 0.0;
  while (Clock.currTime - begin < dur)
    whatever += uniform01;
  
  if (verbose)
    writefln( "\n%s: whatever: %f, duration: %s %s", baseName(__FILE__), whatever, (Clock.currTime - begin).total!duration_type, duration_type );
  
  return whatever;
}
