module d_glat.flatmatrix.lib_jsonbin;

public import d_glat.flatmatrix.core_matrix;

/*
  Jsonbin wrapper around a flat matrix: one metadata JSON string +
  the data itself as a flat matrix computations.
  
  By Guillaume Lathoud, 2019
  glat@glat.info
  
  Boost Software License version 1.0, see ../LICENSE
*/

import core.memory;
import d_glat.core_assert;
import d_glat.core_file;
import d_glat.core_gzip;
import d_glat.core_memory;
import d_glat.core_runtime;
import d_glat.lib_file_copy_rotate;
import std.algorithm;
import std.bitmanip;
import std.conv;
import std.datetime;
import std.exception : enforce;
import std.file;
import std.json;
import std.range;
import std.stdio;
import std.string : strip;
import std.system;

alias Jsonbin = JsonbinT!double;

immutable COMPRESSION      = "compression";
immutable COMPRESSION_GZIP = "gzip";
immutable COMPRESSION_NONE = "none";

/*
  Implementation note: we preferred here a `class` over a `struct`
  to better deal with the following use case: parallel processing
  of big data chunks (e.g. 100MB or 300MB).

  As of 2019-11, using a class in that use case led to unnecessarily
  high usage of memory, including *after* the usage (sort of
  "stable" memory leak), at least with LDC 1.10. This is probably
  due to the compiler optimization keeping some local storage
  for the `struct` created innerhalb from each function.

  Guillaume Lathoud
*/

class JsonbinT( T )
{
  string    j_str;
  MatrixT!T m;

  // --- API: constructor

  this() { } // empty init
  
  this( in string j_str, MatrixT!T m )
    {
      this.j_str = j_str;
      this.m     = m;
    }

  // --- API: methods
  
  bool isEmpty() const @safe pure nothrow
  {
    return 0 == m.data.length;
  }

  
  JSONValue j() const @safe pure 
  {
    return parseJSON( j_str );
  }

  ubyte[] toUbytes( in string compression = COMPRESSION_NONE ) const @trusted
    {
      auto app = appender!(ubyte[]);

      // First line: JSON
      
      app.put( cast( ubyte[] )( j_str.dup ) );
      app.put( '\n' );

      // Second line: <type>:<dim>
      // e.g. "double:[123456,10]
      
      app.put( cast( ubyte[] )( (T.stringof~':'~to!string(m.dim)).dup ) ); 
      app.put( '\n' );

      // Third line: compression

      app.put( cast(ubyte[])( (COMPRESSION~':'~compression.idup).dup ) );
      
      while( !(0 == (app.data.length+1) % T.sizeof) )
        app.put( ' ' ); // Some padding for alignment
      
      app.put( '\n' );
      
      // We always save the data in littleEndian format
  
      auto m_data = m.data;

      const uncompressed_data = (){
        version (LittleEndian)
        {
          return cast( ubyte[] )( m_data.dup );
        }
        else
          {
            version (BigEndian)
            {
              ubyte[] ubytes = new ubyte[ m_data.length * (T.sizeof) ];
              size_t index = 0;
              foreach (d; m_data)
              ubytes.write!(T, Endian.littleEndian)( d, &index );
              
              return ubytes;
            }
            else
              {
                static assert( false, "Jsonbin.toUbytes: Unsupported endianness" );
              }
          }
      }();

      switch (compression)
        {
        case COMPRESSION_GZIP:
          app.put( gzip( uncompressed_data ) );
          break;

        case COMPRESSION_NONE:
          app.put( uncompressed_data );
          break;

        default:
          mixin(alwaysAssertStderr( `false`, `"Jsonbin.toUbytes: Unsupported compression: "~compression` ));
        }

      return app.data;
    }

  // --- API: Operators overloading

  override bool opEquals( Object other ) const pure nothrow @safe @nogc
  {
    if (auto jb_other = cast(typeof(this))( other ))
      {
        return this.j_str == jb_other.j_str
          &&  this.m == jb_other.m;
      }
    else
      {
        return false;
      }
  }



  string date_transform_fun
    ( in size_t i_dim, in size_t i_data
      , in size_t ind, in double value )
  // Example `transform_fun` for `toString` to display dates as
  // strings. Rough, simple implementation, but it does the job.
  {
    immutable TIME_ZONE_CET = PosixTimeZone.getTimeZone( "posix/Europe/Berlin" );

    immutable TIME_0_HNSECS =
      SysTime( DateTime( 1970, 1, 1 ), TIME_ZONE_CET ).stdTime();

    immutable long HNSECS_OF_MS   = cast( long )( 1e4 );


  
    if (value > 6146377961.0) // arbitrary far past: 1970-03-13
      {
        // So we suspect `value` to be a date in ms.  In your own
        // implementation you could use `i_dim` to select a given
        // column, which you know contains dates expressed in ms.
        
        return SysTime
          (
           TIME_0_HNSECS + HNSECS_OF_MS * cast(long)( value )
           , TIME_ZONE_CET
           )
          .toISOExtString;
      }
    else
      {
        return to!string( value );
      }  
  }


  
  override string toString() const
  {
    MaybeMSTT!T maybe_mstt;
    return _toString( maybe_mstt );
  }

  string toString( MatrixStringTransformfunT!T transform_fun ) const
  {
    MaybeMSTT!T maybe_mstt = transform_fun;
    return _toString( maybe_mstt );
  }

  private string _toString( MaybeMSTT!T maybe_mstt ) const
  {
    auto app = appender!(char[]);
    this.toString( (carr) { foreach (c; carr) app.put( c ); }
                  , maybe_mstt
                  );
    auto ret = app.data.idup;
    app.clear;
    return ret;
  }

  void toString(scope void delegate(const(char)[]) sink) const
  {
    MaybeMSTT!T maybe_mstt;
    _toString( sink, maybe_mstt );
  }

  void toString
    (scope void delegate(const(char)[]) sink
     , MatrixStringTransformfunT!T transform_fun
     ) const
  {
    MaybeMSTT!T maybe_mstt = transform_fun;
    _toString( sink, maybe_mstt );
  }
  
  void _toString
    (scope void delegate(const(char)[]) sink
     , MaybeMSTT!T maybe_mstt
     ) const
  {
    sink( "JsonbinT!"~T.stringof~":{\n" );

    immutable tab = "  ";

    sink( tab~`j_str: "`~j_str~`"`~'\n' );

    sink( tab~`, m: ` );

    m.toString( sink, tab, maybe_mstt );
    
    sink( "}\n" );
  }

};



JsonbinT!T jsonbin_of_filename_or_copy
(T = double, string prefix = ".save-")
( in string filename, bool verbose = true )
{
  string error_msg;
  auto ret =
    Action_of_filename_or_copy!(/*only_meta:*/false,T,prefix)
    ( filename, error_msg, verbose );

  mixin(alwaysAssertStderr(`0 == error_msg.length`,`error_msg`));
  
  return ret;
}

JsonbinT!T jsonbinmeta_of_filename_or_copy
(T = double, string prefix = ".save-")
( in string filename, bool verbose = true )
{
  string error_msg;
  auto ret =
    Action_of_filename_or_copy!(/*only_meta:*/true,T,prefix)
    ( filename, error_msg, verbose );

  mixin(alwaysAssertStderr(`0 == error_msg.length`,`error_msg`));
  
  return ret;
}



JsonbinT!T jsonbin_of_filename_or_copy
(T = double, string prefix = ".save-")
( in string filename, ref string error_msg, bool verbose = true )
{
  return Action_of_filename_or_copy!(/*only_meta:*/false,T,prefix)
    ( filename, error_msg, verbose );
}

JsonbinT!T jsonbinmeta_of_filename_or_copy
(T = double, string prefix = ".save-")
( in string filename, ref string error_msg, bool verbose = true )
{
  return Action_of_filename_or_copy!(/*only_meta:*/true,T,prefix)
    ( filename, error_msg, verbose );
}



JsonbinT!T Action_of_filename_or_copy
( bool only_meta
  , T = double
  , string prefix = ".save-"
  )
( in string filename, ref string error_msg, bool verbose = true )
{
  JsonbinT!T ret =
    jsonbin_of_filename!(T, only_meta)( filename, error_msg );

  if (0 < error_msg.length)
    {
      if (verbose)
        {
          stderr.writeln( "Action_of_filename_or_copy: failed on the main filename '"~filename~"' with error '"~error_msg~"' => about to try to find a fallback that work." );
        }
      
      auto fallback_arr = file_copy_fetch!prefix( filename ).sort;
      
      foreach_reverse (fallback; fallback_arr) // try latest first
        {
          ret = jsonbin_of_filename!(T, only_meta)
            ( fallback, error_msg );
          
          if (0 < error_msg.length)
            {
              if (verbose)
                {
                  stderr.writeln( "Action_of_filename_or_copy: failed on a fallback as well: '"~fallback~"' with error '"~error_msg~"'");
                }
            }
          else
            {
              assert( 0 == error_msg.length );

              if (verbose)
                {
                  stderr.writeln("Action_of_filename_or_copy: successfuly used the fallback: '"~fallback~"'");
                }
              
              break; // Worked!
            }
        }
    } 

  return ret;
}


JsonbinT!T jsonbinmeta_of_filename( T = double )( in string filename ) 
{
  return jsonbin_of_filename!(T,/*only_meta:*/true)( filename );
}

JsonbinT!T jsonbinmeta_of_filename( T = double )
( in string filename, ref string error_msg )
{
  return jsonbin_of_filename!(T,/*only_meta:*/true)( filename, error_msg );
}



JsonbinT!T jsonbin_of_filename( T = double, bool only_meta = false )( in string filename ) 
{
  string error_msg;
  auto ret = jsonbin_of_filename!(T, only_meta)( filename, error_msg );

  mixin(alwaysAssertStderr(`0 == error_msg.length`
                           ,`"jsonbin_of_filename: failed on filename '"~filename~"' with error '"~error_msg~"'"`));
  
  return ret;
}

JsonbinT!T jsonbin_of_filename( T = double, bool only_meta = false )
( in string filename, ref string error_msg )
{
  if (!exists( filename ))
    {
      JsonbinT!T jb_empty;
      error_msg = "jsonbin_of_filename[error_msg]: could not find filename "~filename;
      return jb_empty;
    }

  auto data = cast( ubyte[] )( std.file.read( filename ) );

  // Two possibilities to compress: whole file (automatic from the
  // ".gz" filename extension), or only data part (explicit from
  // `compression_type == COMPRESSION_GZIP`)
  if (filename.endsWith( ".gz" ))
    data = gunzip( data );
  
  return jsonbin_of_ubytes!(T, only_meta)( data, error_msg );
}

JsonbinT!T jsonbin_of_ubytes( T = double, bool only_meta = false )( in ubyte[] cdata )
{
  
  return jsonbin_of_chars!(T, only_meta)( cast( char[] )( cdata ) );
}

JsonbinT!T jsonbin_of_ubytes( T = double, bool only_meta = false )
( in ubyte[] cdata, ref string error_msg )
{
  
  return jsonbin_of_chars!(T, only_meta)( cast( char[] )( cdata ), error_msg );
}

JsonbinT!T jsonbin_of_chars( T = double, bool only_meta = false )( in char[] cdata )
{
  string error_msg;

  auto ret = jsonbin_of_chars!(T, only_meta)( cdata, error_msg );

  mixin(alwaysAssertStderr(`0 == error_msg.length`,`error_msg`));
  
  return ret;
}

JsonbinT!T jsonbin_of_chars( T = double, bool only_meta = false )
( in char[] cdata, ref string error_msg ) 
// `0 < error_msg.length` if and only if failed.
{
  error_msg = "";

  size_t   index = 0;
  string   j_str;
  size_t[] dim;
  string   compression;

  jsonbin_read_chars_meta!T( cdata
                             , index 
                             , j_str, dim, compression );

  static if (only_meta)
    {
      return new JsonbinT!T( j_str, Matrix( dim, 0 ) );
    }
  else
    {
      auto data = jsonbin_read_chars_rest!T( cdata, index, compression
                                             , error_msg );
      
      if (0 == error_msg.length  &&  data.length != dim.reduce!`a*b`)
        {
          error_msg = "invalid data.length "~to!string(data.length)
            ~", does not match dim "~to!string(dim)
            ~", typically from a corrupt/truncated file";
          return new JsonbinT!T();
        }
      
      return new JsonbinT!T( j_str, Matrix( dim, data ) );
    }
}

void jsonbin_write_to_filename(T)( in JsonbinT!T jb, in string filename, in string compression_type = COMPRESSION_NONE )
{
  ensure_file_writable_or_exit( filename, /*ensure_dir:*/true );

  // Two possibilities to compress: whole file (automatic from the
  // ".gz" filename extension), or only data part (explicit from
  // `compression_type == COMPRESSION_GZIP`)

  if (filename.endsWith( ".gz" ))
    {
      std.file.write( filename, gzip( jb.toUbytes( compression_type ) ) );
    }
  else if (compression_type == COMPRESSION_GZIP)
    {
      std.file.write( filename, jb.toUbytes( compression_type ) );
    }
  else if (compression_type == COMPRESSION_NONE)
    {
      // Special implementation to spare the GC
      jsonbin_write_uncompressed_to_file!T( jb, File( filename, "wb" ) );
    }
  else
    {
      mixin(alwaysAssertStderr(`false`,`"Not supported: "~compression_type`));
    }
}

void jsonbin_write_uncompressed_to_file(T)( in JsonbinT!T jb, File file )
{
  // Code duplicated w.r.t. `toUbytes`
  // Reason: spare the GC
  
  // First line: JSON
  
  file.write( jb.j_str );
  file.write( '\n' );
  
  // Second line: <type>:<dim>
  // e.g. "double:[123456,10]
  
  file.write( T.stringof~':'~to!string(jb.m.dim) );
file.write( '\n' );

  // Third line: compression
  
  file.write( COMPRESSION~':'~COMPRESSION_NONE );
  
  while( !(0 == (file.tell+1) % T.sizeof) )
    file.write( ' ' ); // Some padding for alignment
      
  file.write( '\n' );
      
  // We always save the data in littleEndian format
  
  auto m_data = jb.m.data;
  
  version (LittleEndian)
  {
    file.rawWrite( cast( ubyte[] )( m_data ) );
  }
  else
    {
      version (BigEndian)
      {
        ubyte[] ubytes = new ubyte[ m_data.length * (T.sizeof) ];
        size_t index = 0;
        foreach (d; m_data)
          file.rawWrite!(T, Endian.littleEndian)( d, &index );
        
        return ubytes;
      }
      else
        {
          static assert( false, "jsonbin_write_uncompressed_to_file: Unsupported endianness" );
        }
    } 
}


/* --------------------------------------------------

 Low-level API

 Usually not needed, but maybe interesting when having issues with
 the GC.

*/

T[] jsonbindata_of_filename_or_copy
( T = double
  , string prefix = ".save-"
  )
( in string filename, ref string error_msg
  , ref string j_str, ref size_t[] dim
  , bool verbose = true )
{
  auto ret =
    jsonbindata_of_filename!T( filename, error_msg
                               , j_str, dim
                               , verbose
                               );

  if (0 < error_msg.length)
    {
      if (verbose)
        {
          stderr.writeln( "jsonbindata_of_filename_or_copy: failed on the main filename '"~filename~"' with error '"~error_msg~"' => about to try to find a fallback that work." );
        }
      
      auto fallback_arr = file_copy_fetch!prefix( filename ).sort;
      
      foreach_reverse (fallback; fallback_arr) // try latest first
        {
          ret = jsonbindata_of_filename!T
            ( fallback, error_msg
              , j_str, dim
              , verbose
              );
          
          if (0 < error_msg.length)
            {
              if (verbose)
                {
                  stderr.writeln( "jsonbindata_of_filename_or_copy: failed on a fallback as well: '"~fallback~"' with error '"~error_msg~"'");
                }
            }
          else
            {
              assert( 0 == error_msg.length );

              if (verbose)
                {
                  stderr.writeln("jsonbindata_of_filename_or_copy: successfuly used the fallback: '"~fallback~"'");
                }
              
              break; // Worked!
            }
        }
    } 

  return ret;
}


T[] jsonbindata_of_filename
(T = double)
( in string filename, ref string error_msg
  , ref string j_str, ref size_t[] dim
  , bool verbose = true )
// Reads everything but does NOT create a Jsonbin instance, instead
// returns each piece of information separately.
{
  immutable string CATCH_CODE = q{
      error_msg = "jsonbindata_of_filename (filename:"~filename~") caught RangeError: "~to!string(e);
      T[] ret;
      return ret;
  };

  try
    {
      auto cdata = cast(char[])( std.file.read( filename ) );
      
      size_t index = 0;
      string compression;
      jsonbin_read_chars_meta!T( cdata
                                 , index
                                 , j_str, dim, compression );
      
      
      return jsonbin_read_chars_rest!T
        ( cdata, index, compression
          , error_msg );
    }
  catch (core.exception.RangeError e) { mixin(CATCH_CODE); }
  catch (object.Exception e) { mixin(CATCH_CODE); }
}

void jsonbin_read_chars_meta( T )
  ( in char[] cdata
    , /*input/output*/ref size_t index
    , /*outputs:*/ref string j_str, ref size_t[] dim, ref string compression 
    )
// Low-level access to metadata, `index` is updated.
{
  // First line: json

  immutable i = index + cdata[ index..$ ].countUntil( '\n' );
  j_str = cdata[ index..i ].idup;
  index = i+1;
    
  // Second line: data type (e.g. "double"), and matrix dimensions
    
  immutable j_0   = index + cdata[ index..$ ].countUntil( '\n' );
  const     s_arr = cdata[ index..j_0 ].split( ':' );
  index = j_0 + 1;

  enforce( s_arr.length == 2 );
    
  immutable s_T   = s_arr[ 0 ].idup;
  if (s_T != T.stringof)
    {
      writeln( "jsonbin_read_chars_meta: s_T:        ", s_T );
      writeln( "jsonbin_read_chars_meta: T.stringof: ", T.stringof );
    }

  enforce( s_T == T.stringof, s_T );
    
  immutable s_dim = s_arr[ 1 ].idup;
    
  dim = to!(size_t[])( s_dim.strip );

  // Third line: "compression:gzip|none|..."
    
  immutable j_1     = index + cdata[ index..$ ].countUntil( '\n' );
  const     s_arr_1 = cdata[ index..j_1 ].split( ':' );
  index = j_1 + 1;
  
  enforce( s_arr_1.length == 2, to!string( s_arr_1 ) );
    
  immutable s_1_compressionstring = s_arr_1[ 0 ].idup;
  enforce( s_1_compressionstring == COMPRESSION );
    
  compression = s_arr_1[ 1 ].idup.strip;
}

T[] jsonbin_read_chars_rest(T)( in char[] cdata, in size_t index, in string compression
                                , ref string error_msg
                                )
// Low-level access to data starting at `index`.
{
  // Rest: binary data, compression or not

  auto rest       = (){
    auto tmp = cast( ubyte[] )( cdata[ index..$ ] );
    switch (compression)
      {
      case COMPRESSION_NONE:
        return tmp;

      case COMPRESSION_GZIP:
        return gunzip( tmp );

      default:
        mixin(alwaysAssertStderr(`false`, `"jsonbin_of_chars: Unsupported compression: "~compression` ));
      }
    assert( false, "bug" );
  }();

  // We always saved the data in littleEndian format

  T[] data;

  immutable must_be_zero = rest.length % T.sizeof;
  if (0 != must_be_zero)
    {
      error_msg = "corrupt or truncated data, cannot cast or peek, details: endian == Endian.littleEndian: "~to!string( endian == Endian.littleEndian )~", rest.length: "~to!string( rest.length )~", T.sizeof: "~to!string( T.sizeof )~", %: "~to!string( must_be_zero );
    }
  else
    {
      version (LittleEndian)
        {
          data = cast( T[] )( rest );
        }
      else
        {
          immutable n = rest.length / T.sizeof;
          data = new T[ n ];
          size_t q = 0;
          foreach (k; 0..n)
            data[ k ] = rest.peek!(T, Endian.littleEndian)( &q );
        }
    }
  return data;
}
 



unittest  // ------------------------------
{
  import std.stdio;

  writeln;
  writeln( "unittest starts: "~__FILE__ );

  immutable verbose = false;

  import std.algorithm;
  import std.conv;
  import std.datetime;
  import std.file;
  import std.math;
  import std.path;

  immutable string tmp_filename = buildPath
    ( std.file.tempDir
      , baseName( __FILE__ )~".tmpfile4unittest.jsonbin."~to!string( Clock.currStdTime )
      );

  immutable string tmp_filename_gz = tmp_filename~"_gz";

  if (verbose)
    {
      writeln(tmp_filename);
      writeln(tmp_filename_gz);
    }

  if (exists( tmp_filename ))    std.file.remove( tmp_filename );
  if (exists( tmp_filename_gz )) std.file.remove( tmp_filename_gz );

  immutable string j_str = `{abcd:1234,efgh:{xyz:"qrst"}}`;

  immutable m_code = q{
    auto m = Matrix( [ 0, 3 ]
                     , [ 1.234, 2.3456, 20.123,
                         17.123, -12.3, 0.0,
                         5.0, 6.0, 7.0,
                         8.0, 9.0, 11.0,
                         -12.34, +2.65, -123.456
                         ]
                     );
  };
  
  {
    mixin(m_code);

    const jb0 = new Jsonbin( j_str, m );

    const ubytes = jb0.toUbytes();

    auto jb1 = jsonbin_of_ubytes( ubytes );

    assert( jb0.j_str == jb1.j_str );
    assert( jb0.m == jb1.m );
    assert( jb0 == jb1 );

    if (verbose)
      {
        writeln( jb0 );
      }

  }


  {
    mixin(m_code);

    const jb0 = new Jsonbin( j_str, m );

    const ubytes = jb0.toUbytes( COMPRESSION_NONE );

    auto jb1 = jsonbin_of_ubytes( ubytes );

    assert( jb0.j_str == jb1.j_str );
    assert( jb0.m == jb1.m );
    assert( jb0 == jb1 );

    if (verbose)
      {
        writeln( jb0 );
      }

  }


  {
    mixin(m_code);

    const jb0 = new Jsonbin( j_str, m );

    const ubytes = jb0.toUbytes( COMPRESSION_GZIP );

    auto jb1 = jsonbin_of_ubytes( ubytes );

    assert( jb0.j_str == jb1.j_str );
    assert( jb0.m == jb1.m );
    assert( jb0 == jb1 );

    if (verbose)
      {
        writeln( jb0 );
      }

  }


  immutable size_t sz0 = () {
    
    mixin(m_code);

    const jb0 = new Jsonbin( j_str, m );

    jsonbin_write_to_filename( jb0, tmp_filename, COMPRESSION_NONE );
    
    auto jb1 = jsonbin_of_filename( tmp_filename );

    assert( jb0.j_str == jb1.j_str );
    assert( jb0.m == jb1.m );
    assert( jb0 == jb1 );

    if (verbose)
      {
        writeln( jb0 );
      }

    return std.file.getSize( tmp_filename );
  }();

  immutable size_t sz1 = () {

    mixin(m_code);

    const jb0 = new Jsonbin( j_str, m );

    jsonbin_write_to_filename( jb0, tmp_filename_gz, COMPRESSION_GZIP );
    
    auto jb1 = jsonbin_of_filename( tmp_filename_gz );

    assert( jb0.j_str == jb1.j_str );
    assert( jb0.m == jb1.m );
    assert( jb0 == jb1 );

    if (verbose)
      {
        writeln( jb0 );
      }

    return std.file.getSize( tmp_filename_gz );
  }();

  if (verbose)
    {
      writeln( "sz0: ", sz0 );
      writeln( "sz1: ", sz1 );
    }

  assert( sz0 > sz1 );

  {
    const jbe = jsonbinmeta_of_filename( tmp_filename );
    assert( jbe.j_str == j_str );
    
    mixin(m_code);
    assert( jbe.m.dim == m.dim );
  }

  {
    const jbe = jsonbinmeta_of_filename( tmp_filename_gz );
    assert( jbe.j_str == j_str );
    
    mixin(m_code);
    assert( jbe.m.dim == m.dim );
  }

  
  if (exists( tmp_filename ))    std.file.remove( tmp_filename );
  if (exists( tmp_filename_gz )) std.file.remove( tmp_filename_gz );
  
  writeln( "unittest passed: "~__FILE__ );
}
