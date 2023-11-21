module d_glat.core_param_values_sorted;

import d_glat.core_assoc_array : aa_set_of_array;
import d_glat.core_parse_number : isParsableDouble;
import std.algorithm : all, filter, map, sort;
import std.array : array, assocArray;
import std.conv : to;
import std.range : iota;
import std.stdio : writeln;

/*
  Generate sorted values for parameter value strings:

  - if the strings are all numerical, just parse them.

  - else sort the strings, then use an increasing index as value.
  
  By Guillaume Lathoud, 2023
  glat@glat.info
  
  The Boost license applies to this file, as described in ./LICENSE
 */

T[string] param_values_sorted(T = double)( in bool[string] sv_set )
// Assign a numerical value to each "true" key k of sv_set[k], so that
// their numerical values are sorted.
{
  scope auto keys = sv_set.keys.filter!((k) => sv_set[ k ]).array;

  if (keys.all!isParsableDouble)
    return assocArray( keys, keys.map!(to!T).array );
  
  keys.sort;
  return assocArray( keys, iota( keys.length ).map!(to!T).array );
}

  
T[] param_values_sorted(T = double)( in string[] sv_arr )
{
  scope auto aa = aa_set_of_array( sv_arr );
  scope auto bb = param_values_sorted!T( aa );
  return sv_arr.map!((k) => bb[ k ]).array;
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
    immutable AV = ["0.123", "0.789", "0.8", "0.7", "0.555", "0.444", "0.5"];
    immutable AVD = [0.123, 0.789, 0.8, 0.7, 0.555, 0.444, 0.5];
    
    if (verbose)
      {
        writeln( "AV: ", AV, " => ", param_values_sorted( AV ) );
        writeln( "AVD: ", AVD );
      }

    assert( AVD == param_values_sorted( AV ) );
    assert( AVD == param_values_sorted!double( AV ) );
  }
  
  {
    immutable AV2 = ["123", "789", "8", "7", "555", "444", "5"];
    immutable AV2I = [123, 789, 8, 7, 555, 444, 5];
    
    if (verbose)
      {
        writeln( "AV2: ", AV2, " => ", param_values_sorted( AV2 ) );
        writeln( "AV2I: ", AV2I );
      }

    assert( AV2I == param_values_sorted!int( AV2 ) );
  }
  
  {
    immutable A = ["bcd","aaa","xxx","qqq","lll"];
    immutable int[]    BI = [1,0,4,3,2];
    immutable double[] BD = [1.0,0.0,4.0,3.0,2.0];
    
    if (verbose)
      {
        writeln( "A: ", A, " => ", param_values_sorted( A ) );
        writeln( "BD: ", BD );
      }
    
    assert(BI == param_values_sorted!int( A ));
    assert(BD == param_values_sorted( A ));

    immutable Q = ["qqq", "aaa", "lll", "bcd", "xxx"];
    
    if (verbose) writeln( Q, " => ", param_values_sorted( Q ) );
    
    auto A_set = assocArray( A.dup, A.map!"true".array );
    if (verbose) writeln( "A_set: ", A_set, " => ", param_values_sorted( A_set ) );   
    assert(["aaa":0.0,"bcd":1.0,"lll":2.0,"qqq":3.0,"xxx":4.0] == param_values_sorted( A_set ));
    assert(["aaa":0U,"bcd":1,"lll":2,"qqq":3,"xxx":4] == param_values_sorted!uint( A_set ));
    assert(["aaa":0,"bcd":1,"lll":2,"qqq":3,"xxx":4] == param_values_sorted!int( A_set ));

    immutable B_set = assocArray( A.dup, [true, false, true, false, true] );
    if (verbose) writeln( "B_set: ", B_set, " => ", param_values_sorted( B_set ) );
    assert(["bcd":0.0, "xxx":2.0, "lll":1.0] == param_values_sorted( B_set ));
    assert(["bcd":0U, "xxx":2, "lll":1] == param_values_sorted!uint( B_set ));
    assert(["bcd":0, "xxx":2, "lll":1] == param_values_sorted!int( B_set ));
  }
  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
