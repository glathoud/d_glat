module d_glat.lib_array;

public import d_glat.core_array;

import d_glat.core_assert;
import d_glat.lib_search_bisection;
import std.array : array;
import std.algorithm : map, max, sort;
import std.math : isFinite;
import std.traits : isFloatingPoint;

T[] arr_interpolate(T)( in T[] sorted_x_arr, in T[] s_y_arr, in T[] x_arr )
{
  return x_arr.map!((x) => arr_interpolate!T( sorted_x_arr, s_y_arr, x )).array;
}

T arr_interpolate(T)( in T[] sorted_x_arr, in T[] s_y_arr, in T x) 
{
  debug assert( sorted_x_arr == sorted_x_arr.dup.sort.array );

  if (x < sorted_x_arr[ 0 ])   return s_y_arr[ 0 ];
  if (x > sorted_x_arr[ $-1 ]) return s_y_arr[ $-1 ];

  static if (isFloatingPoint!T)
    {
      if (!isFinite( x ))
        return x; // e.g. nan => nan
    }
  
  {
    size_t ind0, ind1; double prop;
    immutable found = search_bisection( (ind) => sorted_x_arr[ ind ], x, 0, sorted_x_arr.length-1
                                        , ind0, ind1, prop
                                        );
    mixin(alwaysAssertStderr!`/*not*/found`);
    return s_y_arr[ ind0 ] + prop * (s_y_arr[ ind1 ] - s_y_arr[ ind0 ]);
  }
}

unittest
{
  import std.path;
  import std.stdio;
  
  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  immutable verbose = false;
  
  {
    import std.algorithm : fold, map;
    import std.conv : to;
    import std.range : zip;

    immutable double[] sorted_x_arr = [ 1.0,    3.0,    5.0 ];
    immutable double[]      s_y_arr = [ 10.0, 100.0, 1000.0 ];

    immutable double[]  in_x_arr =
      [ -10.0,  0.0,  1.0,  1.5,   2.0,   3.0,   4.0,    5.0,    6.0,  +10.0 ];

    // expected for `in_x_arr`
    immutable double[] exp_y_arr =
      [  10.0, 10.0, 10.0, 32.5,  55.0, 100.0, 550.0, 1000.0, 1000.0, 1000.0 ];

    // obtained
    auto obt_y_arr = arr_interpolate( sorted_x_arr, s_y_arr, in_x_arr );

    if (verbose)
      {
        writeln( "sorted_x_arr: ", sorted_x_arr );
        writeln( "     s_y_arr: ",      s_y_arr );
        writeln;
        writeln( "    in_x_arr: ",     in_x_arr );
        writeln( "   exp_y_arr: ",    exp_y_arr );
        writeln( "   obt_y_arr: ",    obt_y_arr );
      }

    
    auto error_arr = zip( obt_y_arr, exp_y_arr ).map!"abs( a[0]-a[1] )".array;
    auto error_max = error_arr.fold!max;

    if (verbose)
      {
        writeln( "error_arr: ", error_arr );
        writeln( "error_max: ", error_max );
      }

    
    assert( 1e-7 > error_max, to!string( error_arr ) );
  }

  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
