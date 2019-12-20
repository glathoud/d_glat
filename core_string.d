module d_glat.core_string;

// regex-free functions for fast compilation

import std.array : split;

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


unittest // --------------------
{
  import std.stdio;

  writeln;
  writeln( "unittest starts: "~__FILE__ );

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
