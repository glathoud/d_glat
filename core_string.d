module d_glat.core_string;

// regex-free functions for fast compilation

bool string_is_num09( in string s ) pure nothrow @safe @nogc
{
  pragma( inline, true );

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

  assert( !string_is_num09( "" ) );

  assert( string_is_num09( "0" ) );
  assert( string_is_num09( "0123456789" ) );
  assert( string_is_num09( "1234567890" ) );

  assert( !string_is_num09( "+1234567890" ) );
  assert( !string_is_num09( "a1234567890" ) );
  assert( !string_is_num09( "a1234567890" ) );
  assert( !string_is_num09( "1234567890d39ww" ) );

  writeln( "unittest passed: "~__FILE__ );
}
