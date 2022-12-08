module d_glat.core_runtime;

import core.memory : GC;
import core.runtime : defaultTraceHandler;
import core.thread : getpid;
import std.array : appender, join;
import std.conv : to;
import std.exception : enforce;
import std.process : executeShell;
import std.stdio : writeln, stdout;
import std.string : strip;

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

void printMemUsage()
{
  writeln(getMemUsage());
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
  app.put( "stats.usedSize: "~to!string( stats.usedSize )~", stats.freeSize: "~to!string( stats.freeSize ));
  app.put( "" );

  return app.data.join( '\n' );
}
