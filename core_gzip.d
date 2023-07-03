module d_glat.core_gzip;

import d_oa_common.lib_oa_tmpfilename;
import std.array;
import std.conv;
import std.file;
import std.process;
import std.range;
import std.stdio;
import std.zlib;

ubyte[] gunzip( in ubyte[] data )
{
  auto app = appender!(ubyte[]);

  auto U = new UnCompress( HeaderFormat.gzip );
  app.put( cast( ubyte[] )( U.uncompress( data ) ) );
  app.put( cast( ubyte[] )( U.flush() ) );
  
  return app.data;
  
  // Old code below
  // 
  // zlib and gzip formats differ (headers), hence the `47`
  // http://www.digitalmars.com/d/archives/digitalmars/D/Trouble_with_std.zlib_140855.html
  //
  // (else we could create an `Uncompress` instance with
  // HeaderFormat.gzip)
  //
  // return cast( ubyte[] )( uncompress( zdata_0, 0, 47 ) );
}

ubyte[] gunzip( in void[] data )
{
  return gunzip( cast( ubyte[] )( data ) );
}


// Consider using `std.string.representation` in some use cases.

private bool _tried_shell = false, _use_shell = false, _checking_stability = false;

class _GzipLock {}; shared auto _gzipLock = new _GzipLock;

ubyte[] gzip(bool also_disk = true)( in ubyte[] data )
{
  static if (also_disk) // for big data, often, disk faster - but when multiprocess/multithreading, rather not
    {
      immutable MIN_LENGTH_FOR_SHELL_GZIP = 100 * 1024L;
  
      if (MIN_LENGTH_FOR_SHELL_GZIP <= data.length  &&  (_use_shell  ||  !_tried_shell))
        {
          if (!_tried_shell  &&  !_checking_stability)
            {
              _checking_stability = true;
          
              // First time, check as well that always the same output
              // (useful for hashing etc.). Normally the '-n' option of
              // gzip should be enough for that, but checking is safer.

              immutable s = "A la claire fontaine, m'en allant promener, j'ai trouve l'eau si claire, que je m'y suis baigne.";
          
              const d_1 = cast(ubyte[])( s.replicate( 2 + (MIN_LENGTH_FOR_SHELL_GZIP / s.length) ) );
              mixin(_asrt!`MIN_LENGTH_FOR_SHELL_GZIP < d_1.length`);

              const out_1 = gzip!also_disk( d_1 );

              if (_tried_shell  &&  _use_shell)
                {
                  const d_2 = cast(ubyte[])( s.replicate( 2 + (MIN_LENGTH_FOR_SHELL_GZIP / s.length) ) );
                  mixin(_asrt!`MIN_LENGTH_FOR_SHELL_GZIP < d_2.length`);
              
                  const out_2 = gzip!also_disk( d_2 );

                  _tried_shell = true;
                  _use_shell   = out_1 == out_2;
                  if (!_use_shell)
                    {
                      stderr.writeln( "For some reason, gzip() output non deterministic - even if we passed the '-n' option. Falling back onto the (likely slower) D implementation." );
                      stderr.flush;
                    }
                }

              _checking_stability = false;
            }

          // Tried with pipeShell, but blocking on big files, hence the
          // present solution using a temporary file.
          if (_tried_shell  &&  _use_shell  ||  _checking_stability)
            {
              try
                {
                  immutable tmpfn = get_tmpfilename( "d_oa_common.core_gzip" );
                  std.file.write( tmpfn, data );

                  // -n important: do not save the tmpfn into the file, to try to guarantee always same output
                  auto tmp = executeShell("gzip -n \""~tmpfn~"\"");

                  // Detect errors.
                  if (0 != tmp.status)
                    {
                      throw new Exception ( "d_glat_priv.core_gzip.gzip: error returned by the shell. Falling back onto slower D implementation. Error caught: " ~ to!string(tmp.output) );
                    }

                  // Read output
                  auto outfn = tmpfn~".gz";
                  auto ret = cast(ubyte[])( std.file.read( outfn ) );
                  std.file.remove( outfn );

                  synchronized( _gzipLock )
                  {
                    if (!_tried_shell)
                      {
                        _tried_shell = true;
                        _use_shell   = true;
                      }
                  }

                  return ret; // Success. Done!
                }
              catch ( Throwable t )
                {
                  stderr.writeln( "d_glat_priv.core_gzip.gzip failed to use the shell. Falling back onto slower D implementation.");
                  stderr.flush;
                  synchronized( _gzipLock )
                  {
                    _tried_shell = true;
                    _use_shell   = false;
                  }
                }
            }
        }
    }
  
  auto app = appender!(ubyte[]);
  auto   C = new Compress( 9, HeaderFormat.gzip );
  app.put( cast( ubyte[] )( C.compress( data ) ) );
  app.put( cast( ubyte[] )( C.flush() ) );

  return app.data;
}

ubyte[] gzip(bool also_disk = true)( void[] data )
{
  return gzip!also_disk( cast( ubyte[] )( data ) );
}
