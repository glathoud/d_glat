module d_glat.lib_tmpfilename;

import core.time;
import std.file;
import std.format;
import std.path;
import std.process : thisThreadID;
import std.random;
import std.stdio;

private static shared int   i_tmp = 0;
private static shared alias time_Clock = ClockType.precise;
private static shared alias time_Time  = MonoTimeImpl!(time_Clock);

string get_tmpfilename( in string extension = "", in string tmpdir = tempDir() )
{
  string ret;
  do {
    i_tmp = i_tmp + 1;
    ret = buildPath( 
		    tmpdir
		    , format( "lib_tmpfilename_%s_%d_%d_%d%s"
			      , thisThreadID, i_tmp, time_Time.currTime.ticks, uniform( 0, int.max ), extension 
			      )
		     ); 
  } while (exists( ret ));
  
  return ret;
}

