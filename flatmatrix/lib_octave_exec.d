module d_glat.flatmatrix.lib_octave_exec;

public import d_glat.flatmatrix.core_octave_code;

import core.sys.posix.signal : SIGTERM, SIGKILL;
import core.thread : Thread;
import core.thread.threadbase : thread_joinAll;
import d_glat.core_assert;
import d_glat.core_string;
import d_glat.flatmatrix.core_matrix;
import std.algorithm : canFind, countUntil, endsWith, filter, map;
import std.array : appender, array, join, replicate, split;
import std.concurrency;
import std.conv : parse, to;
import std.datetime : Clock, Duration, dur, MonoTime, SysTime;
import std.exception : assertThrown, basicExceptionCtors;
import std.file;
import std.format : format;
import std.functional : memoize;
import std.path : baseName;
import std.process : execute, executeShell, kill, pipeShell, ProcessPipes, Redirect;
import std.range : iota;
import std.regex : matchFirst;
import std.stdio : stdout, writefln, writeln;
import std.string : lineSplitter, strip;
import std.typecons : Nullable;


enum OCTAVE_AUTORESTART = dur!"minutes"( 10 );

enum OCTAVE_DBG_VERBOSITY = false;

static class OctaveException : Exception { mixin basicExceptionCtors; }


/*
  Execute code in an Octave instance. Either raw (octaveExecRaw) or
  with convenience Matrix I/O (octaveExec). The Octave instance is
  started when needed, then kept alive for better performance.
  
  Tested with Octave 6.4.0

  Example of use: ./lib_regress.d
  
  Motivation: rapid prototyping. In production, for even better
  performance, it might be worth inquiring:

  - The lubeck library https://code.dlang.org/packages/lubeck

  - Integration with R
  https://dlang.org/blog/2020/01/27/d-for-data-science-calling-r-from-d/
  https://forum.dlang.org/thread/cdaoolmlvmgklxuugovh@forum.dlang.org

  - Calling GNU Octave functions in C
    https://stackoverflow.com/questions/56176203/call-gnu-octave-functions-in-c

  Implementation note: currently, data is passed as strings via
  Octave's standard input and output. A faster alternative might be
  to write/load binary files, at the cost of having disk I/O - unless
  we use a RAM disk like tmpfs to exchange files.

  
  Usage note: for (rare) Octave crashes, on some platforms
  (e.g. Ubuntu) if you don't want to wait forever, deactivate apport
  for Octave, by creating e.g. a file /etc/apport/blacklist.d/octave:

  cd /etc/apport/blacklist.d 
  cat octave
  /usr/bin/octave
  /usr/bin/octave-cli
  
  
  The Boost License applies, see file ./LICENSE
  
  By Guillaume Lathoud, 2023 and later
  glat@glat.info
*/

void checkApportBlacklistOctaveOrExit()
{
  mixin(alwaysAssertStderr( `checkApportBlacklistOctave()`, `"\n"~usageApportBlacklistOctave()`));
}


bool checkApportBlacklistOctave()
{
  scope tmp0 = executeShell( `which "`~OCTAVE~`"` );
  if (tmp0.status != 0)
    return false;

  immutable grep_cmd = `grep "`~tmp0.output.strip~`" /etc/apport/blacklist.d/octave`;

  scope tmp1 = executeShell( grep_cmd );
  if (tmp1.status != 0)
    return false;

  return tmp1.output.canFind( OCTAVE );
}


string usageApportBlacklistOctave()
{
  scope tmp0 = executeShell( `which "`~OCTAVE~`"` );
  immutable octave = tmp0.status == 0  ?  tmp0.output.strip  :  "/path/to/octave-cli<you need to install octave>";

  return `Please write/edit a file:
    /etc/apport/blacklist.d/octave
    containing the following line:
    `~octave;
}


string getOctaveVersion() { return _getOctaveVersion(); }

bool isOctaveSupported() { return _isOctaveSupported(); }

enum OCTAVE_VERBOSE_DEFAULT = true;

MatrixT!T octaveExecT(T)( in MAction[] mact_arr, in bool verbose = OCTAVE_VERBOSE_DEFAULT )
// Common case: single output
{
  scope char[][] oarr_warning;
  return octaveExecT!double( mact_arr, oarr_warning, verbose );
}

MatrixT!T octaveExecT(T)( in MAction[] mact_arr, ref char[][] oarr_warning
                          , in bool verbose = OCTAVE_VERBOSE_DEFAULT
                          , in size_t n_retry = 0 // in case of a (rare) Octave crash. Use if `mact_arr` implements an idempotent process
                          , in Duration timeout = Duration.zero // 0 means deactivated
                          )
// Common case: single output+warning output
{
  MatrixT!T ret;
  doOctaveExecT!double( mact_arr, oarr_warning, verbose, n_retry, timeout, ret );
  return ret;
}

void octaveExecNoOutputT(T)( in MAction[] mact_arr
                             , in bool verbose = OCTAVE_VERBOSE_DEFAULT
                             , in size_t n_retry = 0 // in case of a (rare) Octave crash. Use if `mact_arr` implements an idempotent process
                             , in Duration timeout = Duration.zero // 0 means deactivated
                             )
// No output
{
  writeln(mixin(_HERE_C)~": timeout: ", timeout);
  
  scope char[][] oarr_warning;
  octaveExecNoOutputT!double( mact_arr, oarr_warning, verbose, n_retry, timeout );
}

void octaveExecNoOutputT(T)( in MAction[] mact_arr, ref char[][] oarr_warning
                             , in bool verbose = OCTAVE_VERBOSE_DEFAULT
                             , in size_t n_retry = 0 // in case of a (rare) Octave crash. Use if `mact_arr` implements an idempotent process
                             , in Duration timeout = Duration.zero // 0 means deactivated
                             )
// No output
{
  doOctaveExecT!double( mact_arr, oarr_warning, verbose, n_retry, timeout );
}

private enum _PROFILE = false;

private enum _init_vtC = q{
  static if (_PROFILE)
    {
      MonoTime start_time;
      long     prev_msecs = 0;
      if (verbose) start_time = MonoTime.currTime;
    }
};

private enum _vtC = q{
  static if (_PROFILE)
    {
      if (verbose)
        {
          auto _at_msecs = (MonoTime.currTime - start_time).total!"msecs";
          auto _d_prev   = _at_msecs - prev_msecs;
          prev_msecs = _at_msecs;
          writeln(__FILE__.split("/")[$-1]/*~"@line:" ~ to!string( __LINE__ )*/~" : "~format( "d:%s (at:%s) msecs", _d_prev, _at_msecs ));
        }
    }
};

void doOctaveExecT(T, A...)
  ( in MAction[] mact_arr, ref char[][] oarr_warning, in bool verbose, in size_t n_retry
    , in Duration timeout // 0 means deactivated
    , ref A a)
// General case: multiple outputs
{
  mixin(_init_vtC);
  
  auto octave_code = mact_arr.map!"a.getCode()".join('\n'); // xxx \n

  mixin(_vtC);
  
  scope auto output = octaveExecRaw( octave_code, verbose, n_retry, timeout );

  mixin(_vtC);
  
  scope oarr_0 = output.split( "\n\n" ).map!"a.strip".filter!"0<a.length".array;

  oarr_warning = oarr_0.filter!`a.toLower.startsWith("warning:")`.array;
  scope oarr   = oarr_0.filter!`!a.toLower.startsWith("warning:")`.array;

  if (0 < oarr_warning.length)
    {
      if (verbose)
        {
          foreach (i_warning, warning; oarr_warning)
            {
              stderr.flush;
              stderr.writeln;
              stderr.writeln(__FILE__.split("/")[$-1]~"@line:"~to!string(__LINE__)~":i_warning:"
                             ~to!string(i_warning)~":\n"~warning);
              stderr.flush;
            }
        }
    }
  
  mixin(alwaysAssertStderr(`oarr.length == a.length`
                           , `to!string([oarr.length, a.length])~'\n'~output.idup`));

  mixin(_vtC);

  foreach (k, ref one; a)
    {
      scope auto o = oarr[ k ];
      immutable ind = o.countUntil( '\n' );
      mixin(alwaysAssertStderr!`0 <= ind`);
      scope auto size_str = o[ 0..ind ]~' ';
      scope auto data_str = o[ ind+1..$ ]~' ';

      immutable nrow = parse!size_t( size_str );
      size_str = size_str[ 1..$ ]; // space
      immutable ncol = parse!size_t( size_str );
      
      one.setDim( [nrow, ncol] );

      auto data = one.data;
      immutable n = data.length;
      foreach (i; 0..n)
        {
          while (data_str[ 0 ] == ' '  ||  data_str[ 0 ] == '\n')
            data_str = data_str[ 1..$ ];
          
          data[ i ] = parse!T( data_str );
        }
    }

  mixin(_vtC);
  
  /*
    Initial design: so we'll probably end up (1) for now pass data as
    strings (roughly fast as fast as saving/loading octave text files)
    and (2) later on add an option to write a temporary file in binary
    format containing all the variables, because of the following
    comparison:

    octave -q
  
    A=[1:10000]; tic; save myfile.mat A; toc; tic; save -binary mybinfile.mat; toc; quit    
    Elapsed time is 0.00434184 seconds.
    Elapsed time is 0.000286102 seconds.

    tic; load myfile.mat A; toc; quit
    Elapsed time is 0.00398898 seconds.

    tic; load mybinfile.mat A; toc; quit
    Elapsed time is 0.000192881 seconds.  (/ 0.00398898 0.000192881) ; 20.6

    % Another comparison

    A=[1:5080800]; tic; save myfile.mat A; toc; tic; save -binary mybinfile.mat; toc; quit    
    Elapsed time is 2.32702 seconds.
    Elapsed time is 0.0386701 seconds.

    tic; load myfile.mat A; toc; quit
    Elapsed time is 1.99817 seconds.

    tic; load mybinfile.mat A; toc; quit
    Elapsed time is 0.0266678 seconds.  (/ 1.99817 0.0266678) ; 74.9
    
    ---------- tmpfs
    
    Now let us compare with "fake" disk accesses, i.e. a RAM disk
    mounted via tmpfs:

    mkdir /tmp/tmpfs
    sudo mount -t tmpfs -o uid=gl -o gid=gl tmpfs /tmp/tmpfs

    cd /tmp/tmpfs

    octave -q

    A=[1:10000]; tic; save myfile.mat A; toc; tic; save -binary mybinfile.mat; toc; quit    
    Elapsed time is 0.00434995 seconds.  # similar, but at least spares disk I/O
    Elapsed time is 8.89301e-05 seconds. # (/ 0.000286102 8.89301e-05) ; 3.2x speed + spares disk I/O
    
    tic; load myfile.mat A; toc; quit  
    Elapsed time is 0.00397897 seconds.  # similar, but at least spares disk I/O

    tic; load mybinfile.mat A; toc; quit
    Elapsed time is 0.000158072 seconds. # (/ 0.000192881 0.000158072) ; 1.2x speed + sparse disk I/O

    % Another comparison

    A=[1:5080800]; tic; save myfile.mat A; toc; tic; save -binary mybinfile.mat; toc; quit    
    Elapsed time is 2.20873 seconds.
    Elapsed time is 0.029743 seconds.   # similar speed

    tic; load myfile.mat A; toc; quit
    Elapsed time is 2.03506 seconds.   # similar speed
    
    tic; load mybinfile.mat A; toc; quit
    Elapsed time is 0.0280299 seconds.  # similar speed
    

    # cleanup in bash

    cd
    sudo umount /tmp/tmpfs
    rmdir  /tmp/tmpfs

    ---------- ramfs

    mkdir /tmp/ramfs
    sudo mount -t ramfs ramfs /tmp/ramfs
    
    cd /tmp/ramfs
    sudo chmod a+rwx .

    ... similar speed result as tmpfs (expectable, but good to check).

    # cleanup in bash

    cd
    sudo umount /tmp/ramfs
    rmdir  /tmp/ramfs

  */
}


char[] octaveExecRaw( in string mCode, in bool verbose = false, in size_t n_retry = 0, in Duration timeout = Duration.zero )
{
  return _callOctave( mCode, verbose, n_retry, timeout );
}



private: // -------------------- lower-level: summon and use octave, kill only when necessary --------------------

immutable OCTAVE = "octave-cli";

string _getOctaveVersion() { mixin(alwaysAssertStderr!`_isOctaveSupported()`); return _octaveVersion;}

alias _isOctaveSupported = memoize!_isOctaveSupportedImpl;

string _octaveVersion;
bool _isOctaveSupportedImpl()
{
  auto tmp = executeShell( OCTAVE~" --version" );

  if (tmp.status != 0  ||  tmp.output.matchFirst( r"\bGNU Octave\b" ).empty)
    return false;

  auto c = tmp.output.matchFirst( r"\bversion ([\d\.]+)\b" );
  if (c.empty)
    return false;

  _octaveVersion = c[ 1 ];
  return true;
}

alias _isSystemdRunSupported = memoize!_isSystemdRunSupportedImpl;
bool _isSystemdRunSupportedImpl()
{
  auto tmp = executeShell( "systemd-run --version" );
  if (tmp.status != 0  ||  tmp.output.matchFirst( r"\bsystemd\b" ).empty)
    return false;

  return true;
}
  




Nullable!ProcessPipes maybe_o_pipes;

static ~this() { //mixin(_HERE_WR_C);
  if (!maybe_o_pipes.isNull) {
    try
      _callOctave(QUIT);
    catch (OctaveException)
      {}
    
    /*executeShell("pkill octave"); // oh well...
      Thread.sleep( 250.dur!"msecs" );
      executeShell("pkill -9 octave"); // oh well...
    */
  }
  //  mixin(_HERE_WR_C);
}

immutable DONE = "__._lib_octave_exec:DONE_.__";
immutable DONE_LF = DONE~'\n';

immutable BEGINERROR    = "__._lib_octave_exec:BEGINERROR_.__";
immutable BEGINERROR_LF = BEGINERROR~'\n';
immutable ENDERROR    = "__._lib_octave_exec:ENDERROR_.__";
immutable ENDERROR_LF = ENDERROR~'\n';

immutable QUIT = "__.<lib_octave_exec:QUIT>.__";

char[] _callOctave( in string mCode
                    , in bool verbose = false
                    , in size_t n_retry = 0
                    , in Duration timeout = Duration.zero // 0 means no timeout
                    )
{
  mixin(_init_vtC);

  immutable is_quit = mCode == QUIT;

  _ensureOctaveRunning();

  mixin(_vtC);
  
  scope auto pipes = maybe_o_pipes.get;

  static if (false)
    {
      pipes.stdin.rawWrite(r"disp('"~DONE~r"');\n");
      pipes.stdin.flush();
    }
  else
    {
      scope auto to_send = is_quit  ?  QUIT~'\n'  :  (mCode~";;;;\n"~"disp('"~DONE~"');\n");
      pipes.stdin.rawWrite( to_send );
    }

  pipes.stdin.flush();

  if (is_quit)
    {
      char[] ret;
      return ret;
    }
  
  mixin(_vtC);

  // in a separate thread so that we can implement timeout

  {
    auto pp_ptr = cast(ulong)( &pipes );
    auto this_tid = thisTid;
    // writefln("caller  pp_ptr %d  this_tid %s", pp_ptr, this_tid );
  
    _maybe_octave_communication_worker.get.send( pp_ptr, this_tid );
  }
   
  char[] octave_result;
  immutable received = (){
    if (Duration.zero < timeout)
      {
        return receiveTimeout( timeout
                               , (string message) {
                                 static if (OCTAVE_DBG_VERBOSITY) writeln(mixin(_HERE_C), ": message receive in spite of timeout : ", message);
                                 octave_result = message.dup;
                               }
                               );
      }
    else
      {
        receive( (string message) {
            static if (OCTAVE_DBG_VERBOSITY) writeln(mixin(_HERE_C), ": message received : ", message);
            octave_result = message.dup;
          } );
        return true;
      }
  }();

  if (verbose  ||  !received)
    writeln(mixin(_HERE_C), ": received (false may indicate a timeout): ", received);

  // Make sure to restart Octave once in a while, so as to avoid
  // triggering rare bugs.

  if (!received // timeout
      ||  (!_maybe_last_octave_start_sysTime.isNull
           &&  OCTAVE_AUTORESTART < (Clock.currTime - _maybe_last_octave_start_sysTime.get)
           )
      )
    {
      _maybe_last_octave_start_sysTime.nullify;
      _killOctave( verbose );
      _ensureOctaveRunning();
    }
    
  // Error detection
  
  bool has_error = !received
    ||  octave_result.canFind( BEGINERROR )
    ||  octave_result.canFind( ENDERROR );


  mixin(_vtC);

  // writeln(mixin(_HERE_C), ": octave_result: ", octave_result);
  
  if (!has_error)
    return octave_result;

  // --- Error case

  if (!maybe_o_pipes.isNull)
    {
      if (verbose)
        writeln(mixin(_HERE_C), ": pid:", maybe_o_pipes.get.pid.processID);
      
      _killOctave( verbose );
    }

  if (verbose)
    writeln(mixin(_HERE_C), ": has_error: ", has_error);

  mixin(_vtC);

  {
    auto output = received  ?  octave_result  :  (BEGINERROR~" received:"~to!string(received)~" probably timeout ("~to!string(timeout)~")").dup;
    char[] error;
    auto ind = output.countUntil( BEGINERROR );
    if (-1 < ind)
      {
        error  = output[ ind..$ ];
        output = output[ 0..ind ];
      }

    auto ex_str = mixin(_HERE_C)~": main octave loop correctly caught an error, (error,output)==("~error.idup~"\n,\n"~output.idup~")\n----- input to octave was:\n "~to_send~"\n";

    writeln(mixin(_HERE_C), ": ex_str: ", ex_str); stdout.flush;

    if (0 < n_retry)
      {
        _killOctave( verbose ); // in case Octave is in a repetitively buggy situation
        return _callOctave( mCode, verbose, n_retry - 1, timeout );
      }
    else
      {
        throw new OctaveException( mixin(_HERE_C)~":[exhausted n_retry]: "~ex_str );
      }
  }
}

void octaveReceiverFunc()
{
  while (true)
    {
      auto msg = receiveOnly!(ulong, Tid);
      scope pp_ptr     = msg[ 0 ];
      scope caller_tid = msg[ 1 ];

      if (pp_ptr == 0UL)
        break; // my work is finished
      
      
      auto pipes = cast(ProcessPipes*)( pp_ptr ); // ugly but okay, only once per main thread
      scope auto out_app = appender!(char[]);
      {
        scope auto c = new char[ 1 ];
        while (true)
          {
            {
              scope auto c_out = pipes.stdout.rawRead( c );
              // writeln(mixin(_HERE_C)~": c_out: ", c_out);
              if (c_out.length < 1)
                {
                  mixin(_HERE_WR_C);
                  out_app.put( mixin(_HERE_C)~": strange, c_out.length == 0. Most likely an unexpected failure in the top octave loop, not supposed to happen. About to kill octave to ensure an octave restart next time." );
                  out_app.put( '\n' );
                  out_app.put( mixin(_HERE_C)~": "~ENDERROR_LF );
                  break;
                }
          
              assert( c_out.length == 1);
          
              out_app.put( c_out[ 0 ] );
            }
        
            mixin(_vtC);
        
            if (out_app.data.endsWith( DONE_LF ))
              {
                out_app.shrinkTo( out_app.data.length - DONE_LF.length );
                break;
              }

            if (out_app.data.endsWith( ENDERROR_LF ))
              break;
          }
      }
      auto tosend = out_app.data.idup;

      caller_tid.send( tosend );
    }
}

private Nullable!SysTime _maybe_last_octave_start_sysTime;
private Nullable!Tid     _maybe_octave_communication_worker;
void _ensureOctaveRunning()
{
  _ensureOctaveSupported();

  if (maybe_o_pipes.isNull)
    {
      _maybe_last_octave_start_sysTime = Clock.currTime;

      // try not to let octave eat the whole system and indirectly kill us 
      immutable maybe_s_prefix = _isSystemdRunSupported()
        ?  "systemd-run -q --scope -p CPUQuota=200% -p MemoryMax=20% -p MemoryHigh=17% -p MemorySwapMax=0% --user "
        :  ""
        ;
      
      immutable cmd = maybe_s_prefix~OCTAVE~" -q --persist --no-gui --no-history --no-init-file --no-line-editing --no-site-file --no-window-system --norc --eval=\"octave_core_file_limit( 0 ); crash_dumps_octave_core( 0 ); sighup_dumps_octave_core( 0 ); sigterm_dumps_octave_core( 0 ); while (1); lasterror('reset'); try; s=input('','s'); if (strcmp(s,'"~QUIT~"')) break; endif; eval(s); fflush(stdout); catch; end_try_catch; if (0 < length(lasterror.message)) disp('"~BEGINERROR~"'); disp( lasterror.message ); disp( '"~ENDERROR~"'); fflush( stdout ); endif; endwhile; quit(0,'force'); \" 2>&1";

      maybe_o_pipes = pipeShell( cmd, Redirect.all );

      // Try to ensure that in an Out Of Memory case, these octave
      // children processes will be killed first.
      
      {
        scope s_pid = to!string(maybe_o_pipes.get.pid.processID);

        // First grab the list of PIDs
        scope const c_pid_list = (){
          scope tmp = executeShell( mixin(_tli!`ps ax --format pid,ppid | grep ${s_pid} | grep -v grep`) );
          mixin(alwaysAssertStderr(`tmp.status == 0`, `to!string(tmp.status)~':'~tmp.output`));

          scope auto c_pid_app = appender!(string[]);
          c_pid_app.put( s_pid );
          
          foreach (line; tmp.output.lineSplitter)
          {
            scope auto tt = line.strip.split( ' ' ).map!"a.strip".filter!"0<a.length".array;
            if (1 < tt.length  &&  tt[ 1 ] == s_pid)
              c_pid_app.put( tt[ 0 ] );
          }    

          return c_pid_app.data;
        }();

        // Second increase their OOM score => more chances that they will be killed first
        foreach (ref c_pid; c_pid_list)
          {
            immutable cmd_oom = mixin(_tli!"choom -p ${c_pid} -n 1000");
            
            scope tmp = executeShell( cmd_oom );
            
            mixin(alwaysAssertStderr(`tmp.status == 0`,`to!string(tmp.status)~':'~tmp.output`));
          }
      }
      
      _maybe_octave_communication_worker = spawn( &octaveReceiverFunc ); 
    }
}

void _ensureOctaveSupported()
{
  if (!_isOctaveSupported())
    throw new OctaveException( OCTAVE~" not supported on this machine/environment!" );
}



void _killOctave( in bool verbose = false )
{
  // Cut the communication first
  if (!_maybe_octave_communication_worker.isNull)
    {
      _maybe_octave_communication_worker.get.send( /*means work_is_done:*/0UL, thisTid );
      _maybe_octave_communication_worker.nullify;
    }

  // Safer to kill it to ensure a restart next time to make sure that the top loop runs
  try
    {
      // first make sure it is running
      if (!maybe_o_pipes.isNull)
        {
          scope s_pid = to!string(maybe_o_pipes.get.pid.processID);

          if (verbose)
            writeln(mixin(_HERE_C)~":s_pid:"~s_pid);
          
          auto tmp = executeShell("ps --no-headers -Aq "~s_pid);
          mixin(alwaysAssertStderr(`tmp.status == 0`, `to!string(tmp)` ));

          if (verbose)
            writeln(mixin(_HERE_C)~":tmp:"~to!string( tmp ));
          
          if (!tmp.output.canFind( s_pid )
              ||  tmp.output.canFind( "<defunct>" ))
            {
              if (verbose)
                {
                  writeln( "lib_octave_exec: could not find Octave process by pid "~s_pid
                           ~", it probably crashed/died/exited prematurely."
                           ~" Taking that into account." );
                }
              maybe_o_pipes.nullify;
            }

          _maybe_last_octave_start_sysTime.nullify;
        }

      if (!maybe_o_pipes.isNull)
        _callOctave(QUIT);
    }
  catch (OctaveException oe)
    {
      writeln( mixin(_HERE_C)~": _killOctave: unexpectedly caught an exception: "~to!string( oe ));

      if (!maybe_o_pipes.isNull)
        {
          writeln( mixin(_HERE_C)~": _killOctave....................... not quite there yet" );
             
          kill( maybe_o_pipes.get.pid );
          maybe_o_pipes.nullify;
        }
    }

  if (!maybe_o_pipes.isNull)
    maybe_o_pipes.nullify;
}


private:
enum _HERE_C=`baseName(__FILE__)~':'~to!string(__LINE__)`;
enum _HERE_WR_C=`{writeln(`~_HERE_C~`);stdout.flush;}`;



unittest  // --------------------------------------------------
{
  import std.math : approxEqual;
  import std.conv : to;
  import std.datetime : Clock;
  import std.stdio;
  import std.path : baseName;
  import std.string : strip;
  
  enum verbose = false;
  
  writeln;
  writeln( "unittest starts: "~__FILE__~", isOctaveSupported():", isOctaveSupported()
           , (isOctaveSupported() ? ", Octave version:"~getOctaveVersion() : "")
           );

  {
    const tmp = executeShell( "which "~OCTAVE );
    assert( (0 == tmp.status) == isOctaveSupported() );
  }

  if (isOctaveSupported())
    {
      
      
      foreach (i; 0..4)
        {
          {
            if (verbose) mixin(_HERE_WR_C);

            auto start_time = Clock.currTime;
            auto observed = octaveExecRaw( "clear all; disp(1+2+3+5+8);" );
            if (verbose) writeln(mixin(_HERE_C), ": duration: ", Clock.currTime - start_time);
            immutable expected = "19\n";
            if (verbose)
              {
                writeln("observed: ", observed);
                writeln("expected: ", expected);
                stdout.flush;
              }
            assert( observed == expected );
          }
    
          {
            if (verbose) mixin(_HERE_WR_C);
            auto start_time = Clock.currTime;
            auto observed = octaveExecRaw( "clear all; disp(1+2+3+5+8);disp('abcd');" );
            if (verbose) writeln(mixin(_HERE_C), ": duration: ", Clock.currTime - start_time);
            immutable expected = "19\nabcd\n";
            if (verbose)
              {
                writeln("observed: ", observed);
                writeln("expected: ", expected);
                stdout.flush;
              }
            assert( observed == expected );
          }
        } // for loop

      {
        if (verbose) mixin(_HERE_WR_C);
        assertThrown!OctaveException( octaveExecRaw( "clear all; unknown+undefined+whatever;" ) );
      }

      {
        if (verbose) mixin(_HERE_WR_C);
        assertThrown!OctaveException( octaveExecRaw( "clear all; unknown+undefined+whatever;" ) );
      }

      {
        if (verbose) mixin(_HERE_WR_C);
        assertThrown!OctaveException( octaveExecRaw( "clear all; just - &&&&//// bad ra_-ndom..syntax" ) );
      }

      foreach (i; 0..8)
        {
          {
            if (verbose) mixin(_HERE_WR_C);

            auto start_time = Clock.currTime;
            auto observed = octaveExecRaw( "clear all; disp(1+2+3+5+8);" );
            if (verbose) writeln(mixin(_HERE_C), ": duration: ", Clock.currTime - start_time);
            immutable expected = "19\n";
            if (verbose)
              {
                writeln("observed: ", observed);
                writeln("expected: ", expected);
                stdout.flush;
              }
            assert( observed == expected );
          }
    
          {
            if (verbose) mixin(_HERE_WR_C);
            auto start_time = Clock.currTime;
            auto observed = octaveExecRaw( "clear all; disp(1+2+3+5+8);disp('abcd');" );
            if (verbose) writeln(mixin(_HERE_C), ": duration: ", Clock.currTime - start_time);
            immutable expected = "19\nabcd\n";
            if (verbose)
              {
                writeln("observed: ", observed);
                writeln("expected: ", expected);
                stdout.flush;
              }
            assert( observed == expected );
          }
        } // for loop



      {
        if (verbose) mixin(_HERE_WR_C);
        auto start_time = Clock.currTime;

        immutable s = "01234"~("-".replicate(1_000_000))~"56789";
        auto observed = octaveExecRaw( "disp(\""~s~"\");" );
        if (verbose) writeln(mixin(_HERE_C), ": duration: ", Clock.currTime - start_time);
        immutable expected = s~'\n';
        if (verbose)
          {
            writeln("observed[0..100]: ", observed[0..100]);
            writeln("expected[0..100]: ", expected[0..100]);
            writeln("observed[$-100..$]: ", observed[$-100..$]);
            writeln("expected[$-100..$]: ", expected[$-100..$]);
            writeln("observed == expected:", observed == expected);
            writeln("observed.length", observed.length);
            writeln("expected.length", expected.length);
            stdout.flush;
          }
        assert( observed == expected );
      }
    
    
      {
        if (verbose) mixin(_HERE_WR_C);
        auto start_time = Clock.currTime;

        immutable s = "01234"~("-".replicate(1_000_000))~"56789";
        auto observed = octaveExecRaw( "s=\""~s~"\";disp(length(s));" );
        if (verbose) writeln(mixin(_HERE_C), ": duration: ", Clock.currTime - start_time);
        immutable expected = to!string(s.length)~'\n';
        if (verbose)
          {
            writeln("observed: ", observed);
            writeln("expected: ", expected);
            stdout.flush;
          }
        assert( observed == expected );
      }


      {
        if (verbose) mixin(_HERE_WR_C);
        auto start_time = Clock.currTime;

        immutable arr = iota(1000).array;
        immutable s = mstr_of_arr(arr);
        auto observed = octaveExecRaw( "s="~s~";disp(length(s));" );
        if (verbose) writeln(mixin(_HERE_C), ": duration: ", Clock.currTime - start_time);
        immutable expected = to!string(arr.length)~'\n';
        if (verbose)
          {
            writeln("observed: ", observed);
            writeln("expected: ", expected);
            stdout.flush;
          }
        assert( observed == expected );
      }

      {
        if (verbose) mixin(_HERE_WR_C);
        auto start_time = Clock.currTime;

        immutable arr = iota(10000).array;
        immutable s = mstr_of_arr(arr);
        if (verbose) writeln(mixin(_HERE_C)~": s.length: ", s.length);
        if (verbose) writeln(mixin(_HERE_C)~": s[0..100]: ", s[0..100]);
        auto observed = octaveExecRaw( "s="~s~";disp(length(s));" );
        if (verbose) writeln(mixin(_HERE_C), ": duration: ", Clock.currTime - start_time);
        immutable expected = to!string(arr.length)~'\n';
        if (verbose)
          {
            writeln("observed: ", observed);
            writeln("expected: ", expected);
            stdout.flush;
          }
        assert( observed == expected );
      }

      {
        if (verbose) mixin(_HERE_WR_C);

        auto A = Matrix( [0,3], [ 1.2, 3.4,  5.6,
                                  7.8, 9.01, 2.34] );

        auto B = Matrix( [0,3], [ 100.0, 200.0, 300.0,
                                  400.0, 500.0, 600.0] );
    
        Matrix C = octaveExecT!double([ mClearAll
                                        , mSet( "A", A )
                                        , mSet( "B", B )
                                        , mExec( "C = A + B;" )
                                        , mPrintMatrix( "C" )
                                        ]);

        const C_expected = direct_add( A, B );

        if (verbose)
          {
            writeln("C: ", C);
            writeln("C_expected: ", C_expected);
          }
        assert( C.approxEqual( C_expected, 1e-7 ) ); 
      }
    }

  _killOctave( verbose );
  
  writeln( "unittest passed: "~__FILE__ );
}
