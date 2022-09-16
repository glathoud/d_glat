module d_glat.core_string;

public import std.conv : to;

// Note: regex-free functions for fast compilation

import std.algorithm.searching : countUntil;
import std.array : appender, join, replace, split;

string _tli( string s_0 )() pure @safe
/*
  Minimal template literal implementation, inspired from ECMAScript

  Example:

    int i = 34;
    double d = 56.78;
    auto s = mixin(_tli!"this \"thing\" is i: ${i} and that other \"thing\" is d: ${d}. Done!");
    assert( s == "this \"thing\" is i: 34 and that other \"thing\" is d: 56.78. Done!" );
 */
{
  string rest = s_0;
  auto app = appender!(string[]);

  void put_string( in string a )
  {
    app.put( '"'~(a.replace( "\"", "\\\"" ))~'"' );
  }

  
  while (true)
    {
      bool found_one = false;

      auto index = rest.countUntil( "${" );
      if (-1 < index)
        {
          put_string( rest[ 0..index ] );
          rest = rest[ index..$ ];
          
          auto index2 = rest.countUntil( "}" );
          if (2 < index2)
            {
              found_one = true;
              app.put( "~to!string("~rest[ 2..index2 ]~")~");
              rest = rest[ index2+1..$ ];
            }
          else
            {
              put_string( rest[ 0..2 ] );
              rest = rest[ 2..$ ];
            }
        }
      
      if (!found_one)
        break;
    }
  put_string( rest );

  return app.data.join( "" );
}


bool string_is_float( in string s ) pure @safe
{
  

  if (s.length < 1)
    return false;

  // maybe sign
  auto s2 = s[0] == '+'  ||  s[0] == '-'
    ?  s[1..$]
    :  s;

  auto arr = s2.split( '.' );
  if (arr.length < 2)
    arr = "0" ~ arr;

  // maybe exponent
  auto tmp = arr[ 1 ].split( 'e' );
  if (tmp.length > 2)
    return false;
  
  if (tmp.length > 1)
    {
      // maybe signed exponent
      auto e = tmp[ 1 ];
      if (e[0] == '+'  ||  e[0] == '-')
        tmp[ 1 ] = e[1..$];
      
      arr = arr[ 0 ] ~ tmp;
    }

  foreach (x; arr)
    if (!string_is_num09( x ))
      return false;

  return true;
}


bool string_is_num09( in string s ) pure nothrow @safe @nogc
{
  

  if (s.length < 1)
    return false;
  
  immutable char c0 = cast( char )( '0' );
  immutable char c9 = cast( char )( '9' );
  foreach (c; s)
    if (c < c0  ||  c > c9)
      return false;

  return true;
}


string string_shorten( in string s, in size_t nmax ) pure nothrow @safe
{
  debug assert( 5 <= nmax );
  
  immutable n = s.length;
  if (n <= nmax)
    return s;

  immutable n_left_0  = nmax / 3;
  immutable n_left    = 2 < n_left_0  ?  n_left_0 - 2  :  1;

  immutable n_right = nmax - 3 - n_left;
  
  immutable ret = s[0..n_left]~"..."~s[$-n_right..$];
  debug assert( ret.length == nmax );

  return ret;
}


unittest // --------------------
{
  import std.stdio;

  writeln;
  writeln( "unittest starts: "~__FILE__ );

  {
    int i = 34;
    double d = 56.78;
    auto s = mixin(_tli!"this \"thing\" is i: ${i} and that other \"thing\" is d: ${d}. Done!");
    assert( s == "this \"thing\" is i: 34 and that other \"thing\" is d: 56.78. Done!" );
  }

  
  {
    assert( !string_is_float( "" ));
    assert( string_is_float( "1" ));
    assert( string_is_float( "+1" ));
    assert( string_is_float( "1.234" ));
    assert( string_is_float( "-1.234" ));
    assert( string_is_float( "-1.234e12" ));
    assert( string_is_float( "-1.234e-12" ));
    assert( string_is_float( "-1.234e+12" ));
    assert( string_is_float( "1e12" ));
    assert( string_is_float( "1e+12" ));
    assert( string_is_float( "1e-12" ));
    assert( !string_is_float( "a1e-12" ));
    assert( !string_is_float( "1e-12." ));
  }

  
  {
    assert( !string_is_num09( "" ) );

    assert( string_is_num09( "0" ) );
    assert( string_is_num09( "0123456789" ) );
    assert( string_is_num09( "1234567890" ) );

    assert( !string_is_num09( "+1234567890" ) );
    assert( !string_is_num09( "a1234567890" ) );
    assert( !string_is_num09( "a1234567890" ) );
    assert( !string_is_num09( "1234567890d39ww" ) );
  }

  writeln( "unittest passed: "~__FILE__ );
}
