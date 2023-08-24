module d_glat.flatmatrix.lib_octave_exec;

import core.sys.posix.signal : SIGTERM, SIGKILL;
import core.thread : Thread;
import d_glat.core_assert;
import d_glat.flatmatrix.core_matrix;
import d_glat.flatmatrix.core_octave_code;
import std.algorithm : canFind, countUntil, endsWith, filter, map;
import std.array : appender, array, join, replicate, split;
import std.conv : parse, to;
import std.datetime : dur;
import std.exception : assertThrown, basicExceptionCtors;
import std.functional : memoize;
import std.path : baseName;
import std.process : executeShell, kill, pipeShell, ProcessPipes, Redirect;
import std.range : iota;
import std.regex : matchFirst;
import std.stdio : stdout, writeln;
import std.typecons : Nullable;

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
  to write/load binary files, at the cost of having disk I/O.
  
  The Boost License applies, see file ./LICENSE

  By Guillaume Lathoud, 2023 and later
  glat@glat.info
*/

string getOctaveVersion() { return _getOctaveVersion(); }

bool isOctaveSupported() { return _isOctaveSupported(); }

alias octaveExec = octaveExecT!double;

MatrixT!T octaveExecT(T)( in MAction[] mact_arr )
// Common case: single output
{
  MatrixT!T ret;
  octaveExecT!double( mact_arr, ret );
  return ret;
}

void octaveExecT(T, A...)( in MAction[] mact_arr, ref A a )
// General case: multiple outputs
{
  auto octave_code = mact_arr.map!"a.getCode()".join("");
  scope auto output = octaveExecRaw( octave_code );

  scope oarr = output.split( "\n\n" ).map!"a.strip".filter!"0<a.length".array;

  mixin(alwaysAssertStderr(`oarr.length == a.length`, `to!string([oarr.length, a.length])`));

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

  /*
    Initial design: so we'll probably end up (1) for now pass data as
    strings (roughly fast as fast as saving/loading octave text files)
    and (2) later on add an option to write a temporary file in binary
    format containing all the variables, because of the following
    comparison:
  
    A=[1:10000]; tic; save myfile.mat A; toc; tic; save -binary mybinfile.mat; toc; quit    
    Elapsed time is 0.00434184 seconds.
    Elapsed time is 0.000286102 seconds.

    tic; load myfile.mat A; toc; quit
    Elapsed time is 0.00398898 seconds.

    tic; load mybinfile.mat A; toc; quit
    Elapsed time is 0.000192881 seconds.
  */
}


char[] octaveExecRaw( in string mCode ) { return _callOctave( mCode ); }



private: // -------------------- lower-level: summon and use octave, kill only when necessary --------------------

immutable OCTAVE = "octave";

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

static class OctaveException : Exception { mixin basicExceptionCtors; }

char[] _callOctave( in string mCode )
{
  immutable is_quit = mCode == QUIT;

  _ensureOctaveRunning();

  import std.datetime;
  auto xxx_start_time = Clock.currTime;
  
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
  
  scope auto out_app = appender!(char[]);
  bool has_error = false;
  {
    scope auto c = new char[ 1 ];
    while (true)
      {
        {
          scope auto c_out = pipes.stdout.rawRead( c );
          // writeln(mixin(_HERE_C)~": c_out: ", c_out);
          if (c_out.length < 1)
            {
              has_error = true;
              mixin(_HERE_WR_C);
              out_app.put( mixin(_HERE_C)~": strange, c_out.length == 0. Most likely an unexpected failure in the top octave loop, not supposed to happen. About to kill octave to ensure an octave restart next time." );
              break;
            }
          
          assert( c_out.length == 1);
          
          out_app.put( c_out[ 0 ] );
        }
        
        if (out_app.data.endsWith( DONE_LF ))
          {
            out_app.shrinkTo( out_app.data.length - DONE_LF.length );
            break;
          }

        if (out_app.data.endsWith( ENDERROR_LF ))
          {
            has_error = true;
            break;
          }
      }
  }

  // writeln("xxx ---------- duration:", Clock.currTime - xxx_start_time);

  // writeln(mixin(_HERE_C), ": has_error: ", has_error);
  
  has_error = has_error
    ||  out_app.data.canFind( BEGINERROR )
    ||  out_app.data.canFind( ENDERROR );

  
  // writeln(mixin(_HERE_C), ": out_app.data: ", out_app.data);
  
  if (!has_error)
    return out_app.data;

  // --- Error case

  if (!maybe_o_pipes.isNull)
    {
      _killOctave();
    }
  
  {
    auto output = out_app.data;
    char[] error;
    auto ind = output.countUntil( BEGINERROR );
    if (-1 < ind)
      {
        error  = output[ ind..$ ];
        output = output[ 0..ind ];
      }

    auto ex_str = mixin(_HERE_C)~": main octave loop correctly caught an error, (error,output)==("~error.idup~"\n,\n"~output.idup~")\n----- input to octave was:\n "~to_send~"\n";

    writeln(mixin(_HERE_C), ": ex_str: ", ex_str);
    
    throw new OctaveException( ex_str );
  }
}


void _ensureOctaveRunning()
{
  _ensureOctaveSupported();
  
  if (maybe_o_pipes.isNull)
    {
      immutable cmd = OCTAVE~" -q --persist --no-gui --no-history --no-init-file --no-line-editing --no-site-file --no-window-system --norc --eval=\"while (1); lasterror('reset'); try; s=input('','s'); if (strcmp(s,'"~QUIT~"')) break; endif; eval(s); fflush(stdout); catch; end_try_catch; if (0 < length(lasterror.message)) disp('"~BEGINERROR~"'); disp( lasterror.message ); disp( '"~ENDERROR~"'); fflush( stdout ); endif; endwhile; quit(0,'force'); \" 2>&1";

      static if (false)
        {
          writeln; // xxx
          writeln("______________________________ cmd:");
          writeln(cmd);
          writeln;
        }
      
      maybe_o_pipes = pipeShell( cmd, Redirect.all );
    }
}

void _ensureOctaveSupported()
{
  if (!_isOctaveSupported())
    throw new OctaveException( OCTAVE~" not supported on this machine/environment!" );
}



void _killOctave()
{
  // Safer to kill it to ensure a restart next time to make sure that the top loop runs
  try
    {
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
    
        Matrix C = octaveExec([ mClearAll
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
  
  writeln( "unittest passed: "~__FILE__ );
}
