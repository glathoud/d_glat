module d_glat.flatmatrix.lib_jsonbin;

public import d_glat.flatmatrix.core_matrix;

import std.algorithm;
import std.bitmanip;
import std.conv;
import std.file;
import std.json;
import std.range;
import std.system;

alias JsonBin = JsonBinT!double;

struct JsonBinT( T )
{
  string    j_str;
  MatrixT!T m;

  bool isEmpty() const @safe pure nothrow
  {
    return 0 == m.data.length;
  }

  
  JSONValue j()
  {
  if (!_j_str_parsed)
    _j = parseJSON( j_str );
  
  return _j;
}
  
  ubyte[] toUbytes() const
    {
  auto app = appender!(ubyte[]);

  app.put( cast( ubyte[] )( j_str ) );
  app.put( '\n' );
  app.put( cast( ubyte[] )( to!string(m.dim) ) );
  while( !(0 == (app.data.length+1) % double.sizeof) )
    app.put( ' ' );
  
  app.put( '\n' );

  return app.data;
}

  
 private:
  bool      _j_str_parsed = false;
  JSONValue _j;
};

JsonBinT!T jsonbin_of_filename( T )( in string filename )
{
  pragma( inline, true );
  return jsonbin_of_filename!T( cast( char[] )( std.file.read( filename ) ) );
}

JsonBinT!T jsonbin_of_filename( T )( in char[] cdata )
{
  immutable i     = cdata.countUntil( '\n' );
  immutable j_str = cdata[ 0..i ].idup;
  auto rest_0     = cdata[ i+1..$ ];

  immutable j_0   = rest_0.countUntil( '\n' );
  immutable s_dim = rest_0[ 0..j_0 ].idup;
  auto rest       = cast( ubyte[] )( rest_0[ j_0+1..$ ] );
  
  auto dim = to!(size_t[])( s_dim );
  
  T[] data;
  
  if (endian == Endian.littleEndian)
    {
      data = cast( T[] )( rest );
    }
  else
    {
      immutable n = rest.length / double.sizeof;
      data = new T[ n ];
      size_t index;
      foreach (k; 0..n)
        data[ k ] = rest.peek!(double, Endian.littleEndian)( &index );
    }
  
  auto m = MatrixT!T( dim, data );
  
  return JsonBinT!T( j_str, m );      
}
 
 void jsonbin_write_to_filename( in JsonBin jb, in string filename )
 {
  std.file.write( filename, jb.toUbytes );
}
