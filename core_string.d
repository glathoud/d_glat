module d_glat.core_string;

public import std.conv : to;

/*
  String tools including _tli for (mixin) templating.

  Implementation note: regex-free functions for fast compilation

  By Guillaume Lathoud, 2019
  glat@glat.info

  The Boost license applies to this file, as described in ./LICENSE
 */

import std.algorithm.searching : countUntil;
import std.array : appender, join, replace, split;
import std.string : count;

string _tli( string s_0 )() pure @safe
/*
  Minimal template literal implementation, inspired from ECMAScript

  Example:

    int i = 34;
    double d = 56.78;
    auto s = mixin(_tli!"this \"thing\" is i+2: ${i+2} and that other \"thing\" is d: ${d}. Done!");
    assert( s == "this \"thing\" is i+2: 36 and that other \"thing\" is d: 56.78. Done!" );

  Also usable to mixin multiline templates in a readable way:

  int e=1,f=2,g=3;

  immutable template_parameter = "xyz";
  immutable v0 = "f";

  mixin(_tri!q{
    static if (abc)
    {
      app.put( "some_string_with_a_${template_parameter}_in_it");
    }
    else
    {
      app.put( "something else" );
    }
    writeln( "${v0}:", ${v0} ); // prints "f:2" ; ok, a bit contrived but you get the idea
  });
  
 */
{
  string rest = s_0;
  scope auto app = appender!(string[]);

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


string string_default( in string s, in string s_dflt ) pure @safe
{
  return 0 < s.length   ?  s  :  s_dflt;
}



bool string_is_float( in string s ) pure @safe
{
  

  if (s.length < 1)
    return false;

  // maybe sign
  auto s2 = s[0] == '+'  ||  s[0] == '-'
    ?  s[1..$]
    :  s;

  scope auto arr = s2.split( '.' );
  if (arr.length < 2)
    arr = "0" ~ arr;

  // maybe exponent
  scope auto tmp = arr[ 1 ].split( 'e' );
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


string string_shorten( in string s, in size_t nmax, in string shortener = "..." ) pure nothrow @safe
{
  debug assert( 5 <= nmax );
  
  immutable n = s.count;
  if (n <= nmax)
    return s;

  immutable slen = shortener.count;
  immutable slen_m1 = slen - 1;
  
  immutable n_left_0  = nmax / 2;
  immutable n_left    = slen_m1 < n_left_0  ?  n_left_0 - slen_m1  :  1;

  immutable n_right = nmax - slen - n_left;
  
  immutable ret = s[0..n_left] ~ shortener ~ s[$-n_right..$];
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
