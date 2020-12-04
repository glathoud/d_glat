module d_glat.lib_multiprocess;

public import std.process;

import core.thread;
import d_glat.core_assert;
import std.algorithm : any, all, filter, map;
import std.conv;
import std.format;
import std.path : baseName;
import std.range : appender, array, enumerate;
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


auto multiprocess_start(alias spawner/*delegate | string | string[]*/)( in size_t n_processes )
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
  static if (isCallable!spawner)
    {
      auto pid_app           = appender!(Pid[]);
      auto ibou_filename_app = appender!(string[]);
      
      foreach (k_part; 0..n_processes)
        {
          auto sub_pid = spawner( k_part );
          
          pid_app.put( sub_pid );
        }
      
      return pid_app.data;
    }
  else if (typeof(spawner).stringof == "string")
    {
      return multiprocess_start!([spawner])( n_processes );
    }
  else if (isArray!(typeof(spawner)))
    {
      return multiprocess_start!
        (k_part => spawnProcess( spawner.map!(s => format( s, k_part )).array ))
        ( n_processes );
    }
  else
    {
      mixin(alwaysAssertStderr(`false`,`"Unsupported spawner type: "~(typeof(spawner).stringof)`));
    }
}


void multiprocess_wait_success_or_exit(bool fail_early = true)
  ( Pid[] pid_arr, in string error_msg_prefix )
{
  auto failed_arr = multiprocess_wait!fail_early( pid_arr );
  
  if (0 < failed_arr.length)
    {
      writeln("multiprocess_wait_success_or_exit: failed_arr.length: ", failed_arr.length); stdout.flush; // xxx
  
      immutable msg = error_msg_prefix~' '~to!string( failed_arr.map!(x => format("index:%d, pid:%s, output:%s",x.index,pid_arr[ x.index ].processID, x.value)) );

      stderr.writeln( baseName(__FILE__)~": "~msg ); stderr.flush;

      // one fails => stop all remaining processes
      foreach (ind,pid; pid_arr)
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
