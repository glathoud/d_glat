module d_glat.flatmatrix.lib_jsonbin;

public import d_glat.flatmatrix.core_matrix;

import std.algorithm;
import std.bitmanip;
import std.conv;
import std.exception : enforce;
import std.file;
import std.json;
import std.range;
import std.string : strip;
import std.system;

alias JsonBin = JsonBinT!double;

struct JsonBinT( T )
{
  string    j_str;
  MatrixT!T m;

  // --- API: methods
  
  bool isEmpty() const @safe pure nothrow
  {
    return 0 == m.data.length;
  }

  
  JSONValue j() @safe pure 
  {
    if (!_j_str_parsed)
      _j = parseJSON( j_str );
  
    return _j;
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

      if (endian == Endian.littleEndian)
        {
          app.put( cast( ubyte[] )( m_data.dup ));
        }
      else
        {
          ubyte[] ubytes = new ubyte[ m_data.length * (T.sizeof) ];
          size_t index = 0;
          foreach (d; m_data)
            ubytes.write!(T, Endian.littleEndian)( d, &index );

          app.put( ubytes );
        }
  
      return app.data;
    }

  // --- API: Operators overloading

  bool opEquals( in JsonBinT!T other ) const pure nothrow @safe @nogc
  {
    pragma( inline, true );

    return this.j_str == other.j_str
      &&  this.m == other.m;
  }

  
 private:
  bool      _j_str_parsed = false;
  JSONValue _j;
};

JsonBinT!T jsonbin_of_filename( T = double )( in string filename )
{
  pragma( inline, true );
  return jsonbin_of_chars!T( cast( char[] )( std.file.read( filename ) ) );
}

JsonBinT!T jsonbin_of_ubytes( T = double )( in ubyte[] cdata ) pure
{
  pragma( inline, true );
  return jsonbin_of_chars!T( cast( char[] )( cdata ) );
}


JsonBinT!T jsonbin_of_chars( T = double )( in char[] cdata ) pure
{
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
  
  auto m = MatrixT!T( dim, data );
  
  return JsonBinT!T( j_str, m );      
}
 
void jsonbin_write_to_filename( in JsonBin jb, in string filename )
{
  std.file.write( filename, jb.toUbytes );
}



unittest  // ------------------------------
{
  import std.stdio;

  writeln;
  writeln( "unittest starts: "~__FILE__ );

  immutable verbose = false;

  import std.algorithm;
  import std.file;
  import std.math;
  import std.path;

  immutable string tmp_filename = __FILE__~".tmpfile4unittest.jsonbin";

  if (exists( tmp_filename ))
    std.file.remove( tmp_filename );
  
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
    const jb0 = JsonBin( j_str, m );

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
    const jb0 = JsonBin( j_str, m );

    jsonbin_write_to_filename( jb0, tmp_filename );
    
    auto jb1 = jsonbin_of_filename( tmp_filename );

    assert( jb0.j_str == jb1.j_str );
    assert( jb0.m == jb1.m );

    if (verbose)
      {
        writeln( jb0 );
      }

  }

  if (exists( tmp_filename ))
    std.file.remove( tmp_filename );
  
  
  writeln( "unittest passed: "~__FILE__ );
}
