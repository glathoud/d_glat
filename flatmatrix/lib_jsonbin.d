module d_glat.flatmatrix.lib_jsonbin;

public import d_glat.flatmatrix.core_matrix;

/*
  Jsonbin wrapper around a flat matrix: one metadata JSON string +
  the data itself as a flat matrix computations.
  
  By Guillaume Lathoud, 2019
  glat@glat.info
  
  Boost Software License version 1.0, see ../LICENSE
*/

import d_glat.core_file;
import d_glat.core_gzip;
import d_glat.lib_file_copy_rotate;
import std.algorithm;
import std.bitmanip;
import std.conv;
import std.exception : enforce;
import std.file;
import std.json;
import std.range;
import std.stdio;
import std.string : strip;
import std.system;

alias Jsonbin = JsonbinT!double;

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
  
  ubyte[] toUbytes() const pure @trusted
    {
      auto app = appender!(ubyte[]);

      app.put( cast( ubyte[] )( j_str.dup ) );
      app.put( '\n' );
      app.put( cast( ubyte[] )( (T.stringof~':'~to!string(m.dim)).dup ) );
      while( !(0 == (app.data.length+1) % T.sizeof) )
        app.put( ' ' );
  
      app.put( '\n' );

      // We always save the data in littleEndian format
  
      auto m_data = m.data;

      version (LittleEndian)
      {
        app.put( cast( ubyte[] )( m_data.dup ));
      }
      else
        {
          version (BigEndian)
          {
            ubyte[] ubytes = new ubyte[ m_data.length * (T.sizeof) ];
            size_t index = 0;
            foreach (d; m_data)
              ubytes.write!(T, Endian.littleEndian)( d, &index );
            
            app.put( ubytes );
          }
          else
            {
              static assert( false, "Unsupported endianness" );
            }
        }
      
      auto ret = app.data;
      app.clear;
      return ret;
    }

  // --- API: Operators overloading

  bool opEquals( in JsonbinT!T other ) const pure nothrow @safe @nogc
  {
    

    return this.j_str == other.j_str
      &&  this.m == other.m;
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

  void toString
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

enum JsonbinCompress { yes, no, automatic };

JsonbinT!T jsonbin_of_filename_or_copy
( T = double
  , JsonbinCompress cprs = JsonbinCompress.automatic
  , string prefix = ".save-"
  )
( in string filename, ref string error_msg, bool verbose = true )
{
  JsonbinT!T ret = jsonbin_of_filename!(T,cprs)
    ( filename, error_msg );

  if (0 < error_msg.length)
    {
      if (verbose)
        {
          stderr.writeln( "jsonbin_of_filename_or_copy: failed on the main filename '"~filename~"' with error '"~error_msg~"' => about to try to find a fallback that work." );
        }
      
      auto fallback_arr = file_copy_fetch!prefix( filename ).sort;
      immutable is_cprs = _get_is_cprs_of_filename!cprs( filename);
      foreach_reverse (fallback; fallback_arr) // try latest first
        {
          if (is_cprs)
            {
              ret = jsonbin_of_filename!(T,JsonbinCompress.yes)
                ( fallback, error_msg );
            }
          else
            {
              ret = jsonbin_of_filename!(T,JsonbinCompress.no)
                ( fallback, error_msg );              
            }
          
          if (0 < error_msg.length)
            {
              if (verbose)
                {
                  stderr.writeln( "jsonbin_of_filename_or_copy: failed on a fallback as well: '"~fallback~"' with error '"~error_msg~"'");
                }
            }
          else
            {
              assert( 0 == error_msg.length );

              if (verbose)
                {
                  stderr.writeln("jsonbin_of_filename_or_copy: successfuly used the fallback: '"~fallback~"'");
                }
              
              break; // Worked!
            }
        }
    } 

  return ret;
}


JsonbinT!T jsonbin_of_filename( T = double, JsonbinCompress cprs = JsonbinCompress.automatic )( in string filename ) 
{
  

  string error_msg;
  auto ret = jsonbin_of_filename!(T,cprs)( filename, error_msg );

  if (0 < error_msg.length)
    {
      stderr.writeln( "jsonbin_of_filename: failed on filename '"
                      ~filename~"' with error '"~error_msg~"'");
    }

  return ret;
}

JsonbinT!T jsonbin_of_filename( T = double, JsonbinCompress cprs = JsonbinCompress.automatic )
( in string filename, ref string error_msg ) 
{
  bool is_cprs = _get_is_cprs_of_filename!cprs( filename );
  
  if (is_cprs)
    {
      auto uncompressed_data = gunzip( cast( ubyte[] )( std.file.read( filename ) ) );
      return jsonbin_of_ubytes!T( uncompressed_data, error_msg );
    }
  else
    {
      return jsonbin_of_chars!T( cast( char[] )( std.file.read( filename ) ), error_msg );
    }
}

JsonbinT!T jsonbin_of_ubytes( T = double )( in ubyte[] cdata ) pure
{
  
  return jsonbin_of_chars!T( cast( char[] )( cdata ) );
}

JsonbinT!T jsonbin_of_ubytes( T = double )
( in ubyte[] cdata, ref string error_msg ) pure
{
  
  return jsonbin_of_chars!T( cast( char[] )( cdata ), error_msg );
}


JsonbinT!T jsonbin_of_chars( T = double )( in char[] cdata ) pure
{
  string error_msg;

  auto ret = jsonbin_of_chars!T( cdata, error_msg );
  if (0 < error_msg.length)
    assert( false, error_msg );

  return ret;
}

JsonbinT!T jsonbin_of_chars( T = double )( in char[] cdata
                                           , ref string error_msg
                                           ) pure
// `0 < error_msg.length` if and only if failed.
{
  error_msg = "";
  
  immutable i     = cdata.countUntil( '\n' );
  immutable j_str = cdata[ 0..i ].idup;
  auto rest_0     = cdata[ i+1..$ ];

  immutable j_0   = rest_0.countUntil( '\n' );
  const     s_arr = rest_0[ 0..j_0 ].split( ':' );
  immutable s_T   = s_arr[ 0 ].idup;
  enforce( s_T == T.stringof );
  
  immutable s_dim = s_arr[ 1 ].idup;
  auto rest       = cast( ubyte[] )( rest_0[ j_0+1..$ ] );
  
  auto dim = to!(size_t[])( s_dim.strip );
  
  T[] data;

  // We always saved the data in littleEndian format

  if (0 != rest.length % T.sizeof)
    {
      error_msg = "corrupt or truncated data, cannot cast or peek, detail: endian == Endian.littleEndian: "~to!string( endian == Endian.littleEndian );
      return new JsonbinT!T();
    }
  
  if (endian == Endian.littleEndian)
    {
      data = cast( T[] )( rest );
    }
  else
    {
      immutable n = rest.length / T.sizeof;
      data = new T[ n ];
      size_t index;
      foreach (k; 0..n)
        data[ k ] = rest.peek!(T, Endian.littleEndian)( &index );
    }

  if (data.length != dim.reduce!`a*b`)
    {
      error_msg = "invalid data.length "~to!string(data.length)
        ~", does not match dim "~to!string(dim)
        ~", typically from a corrupt/truncated file";
      return new JsonbinT!T();
    }
  
  auto m = MatrixT!T( dim, data );
  
  return new JsonbinT!T( j_str, m );      
}
 
void jsonbin_write_to_filename( JsonbinCompress cprs = JsonbinCompress.automatic )( in Jsonbin jb, in string filename )
{
  ensure_file_writable_or_exit( filename, /*ensure_dir:*/true );
  
  bool is_cprs = _get_is_cprs_of_filename!cprs( filename );

  auto ubytes  = is_cprs
    ?  gzip( jb.toUbytes )
    :  jb.toUbytes;

  std.file.write( filename, ubytes );
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

  immutable string tmp_filename_gz = tmp_filename~".gz";

  if (verbose)
    {
      writeln(tmp_filename);
      writeln(tmp_filename_gz);
    }

  if (exists( tmp_filename ))    std.file.remove( tmp_filename );
  if (exists( tmp_filename_gz )) std.file.remove( tmp_filename_gz );
  
  {
    immutable string j_str = `{abcd:1234,efgh:{xyz:"qrst"}}`;
    auto m = Matrix( [ 0, 3 ]
                     , [ 1.234, 2.3456, 20.123,
                         17.123, -12.3, 0.0,
                         5.0, 6.0, 7.0,
                         8.0, 9.0, 11.0,
                         -12.34, +2.65, -123.456
                         ]
                     );
    const jb0 = new Jsonbin( j_str, m );

    const ubytes = jb0.toUbytes();

    auto jb1 = jsonbin_of_ubytes( ubytes );

    assert( jb0.j_str == jb1.j_str );
    assert( jb0.m == jb1.m );

    if (verbose)
      {
        writeln( jb0 );
      }

  }
  
  
  {
    immutable string j_str = `{abcd:1234,efgh:{xyz:"qrst"}}`;
    auto m = Matrix( [ 0, 3 ]
                     , [ 1.234, 2.3456, 20.123,
                         17.123, -12.3, 0.0,
                         5.0, 6.0, 7.0,
                         8.0, 9.0, 11.0,
                         -12.34, +2.65, -123.456
                         ]
                     );
    const jb0 = new Jsonbin( j_str, m );

    jsonbin_write_to_filename( jb0, tmp_filename );
    
    auto jb1 = jsonbin_of_filename( tmp_filename );

    assert( jb0.j_str == jb1.j_str );
    assert( jb0.m == jb1.m );

    if (verbose)
      {
        writeln( jb0 );
      }

  }

  {
    immutable string j_str = `{abcd:1234,efgh:{xyz:"qrst"}}`;
    auto m = Matrix( [ 0, 3 ]
                     , [ 1.234, 2.3456, 20.123,
                         17.123, -12.3, 0.0,
                         5.0, 6.0, 7.0,
                         8.0, 9.0, 11.0,
                         -12.34, +2.65, -123.456
                         ]
                     );
    const jb0 = new Jsonbin( j_str, m );

    jsonbin_write_to_filename( jb0, tmp_filename_gz );
    
    auto jb1 = jsonbin_of_filename( tmp_filename_gz );

    assert( jb0.j_str == jb1.j_str );
    assert( jb0.m == jb1.m );

    if (verbose)
      {
        writeln( jb0 );
      }
  }

  {
    assert( std.file.getSize( tmp_filename_gz ) < std.file.getSize( tmp_filename ) );
  }
  
  if (exists( tmp_filename ))    std.file.remove( tmp_filename );
  if (exists( tmp_filename_gz )) std.file.remove( tmp_filename_gz );
  
  writeln( "unittest passed: "~__FILE__ );
}

private:

bool _get_is_cprs_of_filename( JsonbinCompress cprs )( in string filename )
  pure nothrow @safe @nogc
{
  

  static if (cprs == JsonbinCompress.automatic)
    return filename.endsWith( ".gz" );
  else
    return cprs == JsonbinCompress.yes;
}
