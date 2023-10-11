module d_glat.core_param_gen;

import std.algorithm : map;
import std.array : array, split;
import std.conv : to;
import std.range : iota;

/*
  Tools to generate ranges of parameter values from specification
  strings.

  By Guillaume Lathoud, 2023
  glat@glat.info

  The Boost license applies to this file, as described in ./LICENSE
 */

T[] param_gen(T)( in string spec )
/* Generate an array T[] of parameter values from an input spec, which is:
   a number string e.g. "34" 
   | array string "[1,2,3,5,8,13]" 
   | range string "1..10" 
*/
{
  if (spec[ 0 ] == '[')
    {
      assert( spec[ $-1 ] == ']' );
      return spec[1..$-1].split( ',' ).map!(to!T).array;
    }

  scope auto tmp = spec.split( ".." );
  if (tmp.length == 1)
    return [tmp[ 0 ].to!T];

  assert( tmp.length == 2 );
  return iota( to!T( tmp[ 0 ] ), to!T( tmp[ 1 ] ) ).array;
}


unittest
{
  import std.stdio;
  import std.path;

  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  immutable verbose = false;
  
  import std.random;
  import std.algorithm;
  import std.range;

  {
    assert( param_gen!size_t( "23" ) == [cast(size_t)( 23 )] );
    assert( param_gen!int( "[1,2,3,5,78]" ) == cast(int[])[1,2,3,5,78] );
    assert( param_gen!long( "-12..37" ) == (iota!long(-12,37).array) );

    if (verbose) writeln( param_gen!long( "-12..37" ) );
    
  }


  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
