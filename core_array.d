module d_glat.core_array;

import std.algorithm : sort;
import std.array : appender, array;
import std.format : format;
import std.math : isNaN;

/*
  Tools for arrays. Boost License, see file ./LICENSE

  By Guillaume Lathoud, 2019
  glat@glat.info
 */

bool equal_nan( T = double )( in T[] a, in T[] b )
pure @safe @nogc
// Extended equal that also permits matching NaNs.
{
  pragma( inline, true );

  if (a.length != b.length)
    return false;
  
  foreach (i,ai; a)
    {
      auto bi = b[ i ];
      if (!(isNaN( ai )  &&  isNaN( bi )
            ||  ai == bi))
        return false;
    }

  return true;
}

  

size_t[] subset_ind_arr_of_sorted( T )
  ( in T[] all_arr, in T[] subset_arr )
pure @safe
/*
 Assume both `all_arr` and `subset_arr` are sorted by increasing
 value, and return the list of indices such that:

 subset_arr == ind_arr.map!( ind => all_arr[ ind ] ).array
*/
{
  pragma( inline, true );

  debug
    {
      assert( all_arr    ==    all_arr.dup.sort.array );
      assert( subset_arr == subset_arr.dup.sort.array );
    }
  
  if (subset_arr.length < 1)
    return [];
  
  auto app = appender!(size_t[]);
  
  size_t i_all = 0;
  T      x_all = all_arr[ i_all ];
  
  foreach (i_subset, x; subset_arr)
    {
      while (x_all < x)
        x_all = all_arr[ ++i_all ];

      debug
        {
          assert
            ( x_all == x
              , "Each value of `subset_arr` must be in `all_arr`"
              ~format
              ( "i_all: %d, x_all: %s, i_subset: %d, x: %s"
                , i_all, x_all, i_subset, x )
              );
        }

      app.put( i_all );
    }
  
  return app.data;
}

unittest
{
  import std.path;
  import std.stdio;
  
  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  {
    assert( equal_nan!double( [], [] ) );
    assert( equal_nan( [], [] ) );

    assert( equal_nan( [   1.0, 2.0, 3.0 ]
                       , [ 1.0, 2.0, 3.0 ] ) );

    assert( equal_nan( [   1.0, double.nan, 3.0 ]
                       , [ 1.0, double.nan, 3.0 ] ) );


    assert( !equal_nan( [   1.0, 2.0, 3.0 ]
                        , [ 1.0, 2.0, 3.0, 4.0 ] ) );
    
    assert( !equal_nan( [   1.0, 2.0, 3.0, 4.0 ]
                        , [ 1.0, 2.0, 3.0 ] ) );
    
    assert( !equal_nan( [   1.0, 2.0, 3.0 ]
                        , [ 1.1, 2.0, 3.0 ] ) );

    assert( !equal_nan( [   1.0, double.nan, 3.0 ]
                        , [ 1.0, double.nan, 3.1 ] ) );

    assert( !equal_nan( [   1.0, double.nan, 3.0 ]
                        , [ 1.0, 2.0,        double.nan ] ) );

  }

  
  {
    assert( subset_ind_arr_of_sorted
            ( [ 0, 1, 3, 5, 6, 7, 8, 11, 13 ]
              , [] )
            == []
            );   
  
    assert( subset_ind_arr_of_sorted
            ( [   0, 1, 3, 5, 6, 7, 8, 11, 13 ]
              , [    1,    5, 6,    8,     13 ] )
            == [     1,    3, 4,    6,     8  ]
            );   
  
    assert( subset_ind_arr_of_sorted
            ( [   0, 1, 3, 5, 6, 7, 8, 11, 13 ]
              , [ 0, 1,    5, 6,    8,        ] )
            == [  0, 1,    3, 4,    6,        ]
            );   
  
    assert( subset_ind_arr_of_sorted
            ( [   0, 1, 3, 5, 6, 7, 8, 11, 13 ]
              , [ 0, 1, 3, 5, 6, 7, 8, 11, 13 ] )
            == [  0, 1, 2, 3, 4, 5, 6,  7,  8 ]
            );   
  }
  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
