module d_glat.core_runtime;

import core.memory : GC;
import core.runtime : defaultTraceHandler;
import core.thread : getpid;
import std.array : appender, join;
import std.conv : to;
import std.datetime : Clock;
import std.exception : enforce;
import std.format : format;
import std.process : executeShell;
import std.stdio : writeln, stdout;
import std.string : strip;

// See also: ./core_memory.d

string getStackTrace()
// Code from ARSD
// https://forum.dlang.org/post/aenumslnnxeedlrkwhaz@forum.dlang.org
{
	version(Posix) {
		// druntime cuts out the first few functions on the trace as they are internal
		// so we'll make some dummy functions here so our actual info doesn't get cut
		Throwable.TraceInfo f5() { return defaultTraceHandler(); }
		Throwable.TraceInfo f4() { return f5(); }
		Throwable.TraceInfo f3() { return f4(); }
		Throwable.TraceInfo f2() { return f3(); }
		auto stuff = f2();
	} else {
		auto stuff = defaultTraceHandler();
	}

	return stuff.toString();
}

// Usage: mixin(printMemUsageFlushC);
immutable printMemUsageFlushC = `writeln(__FILE__.split("/")[$-1] ~ "@line:" ~ to!string( __LINE__ ) ~ " getMemUsage():" ~ (("\n"~getMemUsage()).replace( "\n", "\n"~format("%-40s", (__FILE__.split("/")[$-1] ~ "@line:" ~ to!string( __LINE__ ) ~ ": ")))));`;

void printMemUsage()
{
  writeln(getMemUsage(), ", now:", Clock.currTime);
  stdout.flush;
}

string getMemUsage()
{
  scope auto app = appender!(string[]);
  
  immutable pid = getpid();
  {
    scope auto x = executeShell( "cat /proc/"~to!string(pid)~"/status  | grep VmHWM" );
    enforce( 0 == x.status );
    app.put(x.output.strip);
  }
  {
    scope auto x = executeShell( "cat /proc/"~to!string(pid)~"/status  | grep VmRSS" );
    enforce( 0 == x.status );
    app.put(x.output.strip);
  }
  scope auto stats = GC.stats; 
  app.put( "stats.usedSize: "~getHumanStrOfSize( stats.usedSize )~", stats.freeSize: "~getHumanStrOfSize( stats.freeSize ));
  app.put( "" );
  
  return app.data.join( '\n' );
}

string getHumanStrOfSize(T)( T n ) pure
{
  return format("%d (%,3?d)", n, '_', n );
}


unittest
{
  import std.algorithm;
  import std.path;
  import std.range;
  import std.stdio;

  enum verbose = true;

  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );


  mixin(printMemUsageFlushC);

  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
