module d_glat.lib_multiprocess;

public import std.process;

import core.thread;
import d_glat.core_assert;
import d_glat.core_parse_duration;
import std.algorithm : any, all, filter, map;
import std.array : array;
import std.conv;
import std.datetime : Clock, dur;
import std.exception : assumeUnique, enforce;
import std.format;
import std.math : ceil;
import std.path : baseName;
import std.range : appender, array, enumerate, iota;
import std.stdio;
import std.traits;

/*
  Multiprocess tools for parallel processing. 
  
  Context: "old-style" multiprocess alternative to multithreading,
  where we distribute many independent actions across processes, then
  wait for them to be complete. 

  Reason: useful alternative to multithreading foreach..parallel,
  when the compiler leads to unexplicable low CPU usage (the
  compiled executable thinks threads have to wait for each other,
  where they don't), and you have tried to fix everything you could.

  Side benefit: when processes are done, you are sure the memory is
  fully freed.

  The Boost License applies to this file, see ./LICENSE

  glat@glat.info
  2020
 */

immutable ubyte MP_DEFAULT_RESTART_CODE = 111;

void multiprocess_start_and_restart_and_wait_success_or_exit
(alias spawner_0/*delegate | string | string[]*/
 , ubyte restart_code = MP_DEFAULT_RESTART_CODE
 , bool fail_early = true
 )
  ( in size_t n_processes, in string error_msg_prefix, in string rampup = ""
    , in bool verbose = true )
/*
  `rampup`: optional progressive rampup e.g. "30s" or "1m" or
  "0.75m" or "45s" => at the very beginning, start 1 process, then
  wait for `rampup` time, then start the 2nd process, then wait,
  etc.
  
  This is useful when the first minutes, each process has a
  "warm-up" time where it consumes quite a bit of memory, then later
  on "cruises" with little memory. That way we can maximize our use
  of CPUs for long tasks, without running out of RAM right away.
 */
{
  auto spawner = spawner_function!spawner_0();
  assert(isCallable!spawner);

  immutable prefix_c = q{__FILE__ ~ "@line:" ~ to!string( __LINE__ ) ~ ":("~error_msg_prefix~")"};
  
  // Optional progressive rampup
  
  auto rampup_dur = 0 < rampup.length  ?  parse_duration( rampup )  :  Duration.zero;
  
  auto earlier_start_of_k_part = (){

    auto t = Clock.currTime();

    return iota( n_processes ).map!((k_part) {
        if (0 < k_part)
          t += rampup_dur;
        
        return t;
      })
    .array.assumeUnique;
  }();
  
  // Main loop

  auto pid_arr = new Pid[ n_processes ];
  
  while (true)
    {
      auto now = Clock.currTime;

      // start/restart as needed
      foreach (k_part; 0..n_processes)
        {
          if (now < earlier_start_of_k_part[ k_part ]) // when using `rampup`
            {
              assert( 0 < k_part );
              continue;
            }
          
          if (pid_arr[ k_part ] is null)
            {
              if (verbose)
                {
                  stdout.writeln;
                  stdout.writeln( mixin(prefix_c)~" about to (re)start k_part:", k_part );
                  stdout.writeln;
                  stdout.flush;
                }
              
              pid_arr[ k_part ] = spawner( k_part );
            }
        }
      
      // sleep a bit

      Thread.sleep(dur!"msecs"( 13 ));

      // check for restart and/or failures

      auto twr_non_null = pid_arr.filter!"a !is null".map!tryWait.enumerate;
      
      auto failed_arr  =
        twr_non_null.filter!("a.value.terminated  &&  a.value.status != 0  &&  a.value.status != "~to!string(restart_code))
        .array;
      
      auto restart_arr =
        twr_non_null.filter!("a.value.terminated  &&  a.value.status == "~to!string(restart_code))
        .array;

      static if (fail_early)
        multiprocess_fail_early( error_msg_prefix, pid_arr, failed_arr );

      foreach (ref x; restart_arr)
        pid_arr[ x.index ] = null;

      {
        // specific to the rampup use case
        immutable has_not_started_all_yet = pid_arr.any!"a is null";

        // all use cases
        immutable has_not_finished_all_yet =
          0 < restart_arr.length  ||  !(twr_non_null.all!"a.value.terminated");
        
        if (has_not_started_all_yet  ||  has_not_finished_all_yet)
          continue;
      }
      
      // done
      
      if (verbose)
        {
          stdout.writeln;
          stdout.writeln( mixin(prefix_c)~ " failed_arr:  ", to!string( failed_arr ) );
          stdout.writeln( mixin(prefix_c)~ " restart_arr: ", to!string( restart_arr ) );
          stdout.writeln( mixin(prefix_c)~ " n_failed: ", failed_arr.length
                         , ", n_restart: ", restart_arr.length );
          stdout.writeln;
          stdout.flush;
        }

      if (0 < failed_arr.length) // Note: only reached in the `fail_early==false` case
        {
          stderr.writeln;
          stderr.writeln( mixin(prefix_c)~ " failed_arr:  ", to!string( failed_arr ) );
          stderr.writeln( mixin(prefix_c)~ " note that a -9 (247) exit code should denote a lack of available RAM" );
          stderr.writeln;
          stderr.flush;
        }
      
      break;
    }
}







void multiprocess_start_and_wait_success_or_exit
(alias spawner/*delegate | string | string[]*/, bool fail_early = true)
  ( in size_t n_processes, in string error_msg_prefix )
// Convenience wrapper
{
  auto pid_arr = multiprocess_start!spawner( n_processes );
  multiprocess_wait_success_or_exit!fail_early( pid_arr, error_msg_prefix );
}

auto multiprocess_start_and_wait
(alias spawner/*delegate | string | string[]*/, bool fail_early = true)
  ( in size_t n_processes )
// Convenience wrapper
{
  auto pid_arr = multiprocess_start!spawner( n_processes );
  return multiprocess_wait!fail_early( pid_arr );
}

auto multiprocess_start(alias spawner_0/*delegate | string | string[]*/)( in size_t n_processes )
/* Returns an array of Pid

   --- Example of use:

   auto outfilename_app = appender!(string[]);

   void spawner( in size_t k_part )
   {
     immutable outfilename = format( "/tmp/my_multiprocess.main_pid_%d.part_%d", thisProcessID, k_part );
     outfilename_app.put( outfilename );
     return spawner( [ "doer.exe", "--outfilename="~outfilename ] ); // could also use pipes
   }

   immutable n_processes = min( n_todo, n_cpu );
   auto pid_arr = multiprocess_start!spawner( n_processes );
   
   immutable error_msg_prefix = "My multiprocess:";
   multiprocess_wait_success_or_exit( pid_arr, error_msg_prefix );

   immutable outfilename_arr = outfilename_app.data;
   // now read individual outputs  from outfilename_arr
   */
{
  auto spawner = spawner_function!spawner_0();

  assert(isCallable!spawner);

  auto pid_app = appender!(Pid[]);
  foreach (k_part; 0..n_processes)
    {
      auto sub_pid = spawner( k_part );
      
      pid_app.put( sub_pid );
    }
  
  return pid_app.data;
}



auto spawner_function(alias  spawner/*delegate | string | string[]*/)()
// Returns a function: (in size_t k_part) => Pid
{
  static if (isCallable!spawner)
    {
      return &spawner;
    }
  else if (typeof(spawner).stringof == "string")
    {
      return spawner_function!([spawner]);
    }
  else if (isArray!(typeof(spawner)))
    {
      return &(spawner_function_of_array!spawner);
    }
  else
    {
      mixin(alwaysAssertStderr(`false`,`"Unsupported spawner type: "~(typeof(spawner).stringof)`));
    }
}

auto spawner_function_of_array(alias array_of_string)()
// Returns a function: (in size_t k_part) => Pid
{
  return &sfoa;

  auto sfoa( in size_t k_part )
  {
    return spawnProcess( array_of_string.map!(s => format( s, k_part )).array );
  }
}


void multiprocess_wait_success_or_exit(bool fail_early = true)
  ( Pid[] pid_arr, in string error_msg_prefix )
{
  auto failed_arr = multiprocess_wait!fail_early( pid_arr );
  multiprocess_fail_early( error_msg_prefix, pid_arr, failed_arr );
}

void multiprocess_fail_early(T)( in string error_msg_prefix, Pid[] pid_arr, in T[] failed_arr )
 {
  if (0 < failed_arr.length)
    {
      writeln("multiprocess_wait_success_or_exit: failed_arr.length: ", failed_arr.length); stdout.flush; // xxx
  
      immutable msg = error_msg_prefix~' '~to!string( failed_arr.map!(x => format("index:%d, pid:%s, output:%s",x.index,pid_arr[ x.index ].processID, x.value)) )~"  Note that a -9 (247) exit code should denote a lack of available RAM.";

      stderr.writeln( baseName(__FILE__)~": "~msg ); stderr.flush;

      // one fails => stop all remaining processes
      foreach (ind, ref pid; pid_arr)
        {
          if (!failed_arr.any!(x => x.index == ind))
            {
              stderr.writeln( "multiprocess_wait_success_or_exit: about to kill -9 pid: ", pid.processID ); stderr.flush;
              kill( pid, 9 );
            }
        }

      stderr.writeln( "multiprocess_wait_success_or_exit: about to voluntarily crash" ); stderr.flush;
      mixin(alwaysAssertStderr(`false`,`msg`));
    }
}

auto multiprocess_wait(bool fail_early = true)( Pid[] pid_arr )
// Returns an array of `(index,value)` of the Pids that failed, if any.
{
  while (true)
    {
      auto twr = pid_arr.map!tryWait.enumerate;

      //writeln("xxx lib_multiprocess: fail_early: ", fail_early);
      
      static if (fail_early)
        {{
          auto failed_arr = twr.filter!"a.value.terminated  &&  a.value.status != 0".array;

          if (0 < failed_arr.length)
            {
              writeln("xxx lib_multiprocess (fail_early) failed_arr.length: ", failed_arr.length );
              writeln("xxx lib_multiprocess (fail_early) failed_arr: ", failed_arr);
              
              return failed_arr;
            }
          }}
      
      if (twr.all!"a.value.terminated")
        {
          auto failed_arr = twr.filter!"a.value.status != 0".array;
          
          return failed_arr;
        }
      else
        {
          Thread.sleep(dur!"msecs"( 13 ));
        }
    }

  assert( false, "never reached" );
}

unittest
{
  import std.stdio;

  writeln("youpi!");
}
