module d_glat.core_array;

import d_glat.core_assert;
import std.algorithm : sort;
import std.array : appender, array;
import std.conv : to;
import std.format : format;
import std.math : abs, isNaN;

/*
  Tools for arrays. Boost License, see file ./LICENSE

  By Guillaume Lathoud, 2019
  glat@glat.info
*/

T[] ensure_length(T)( size_t desired_length, ref T[] arr )
pure nothrow @safe
/*
  Typical usages:
  

  ensure_length( n, arr );


  class Buffer { double[] arr; }
  auto buffer = new Buffer;
  // ...
  auto arr = ensure_length( n, buffer.arr );
*/
{
  pragma( inline, true );
  if (arr.length != desired_length)
    arr = new T[desired_length];

  return arr;
}


bool equal_nan( T = double )( in T[] a, in T[] b )
  pure nothrow @safe @nogc
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

  

size_t[] subset_ind_arr_of_sorted( bool exact = true, T )
  ( in T[] all_arr, in T[] subset_arr )
  pure nothrow @safe
/*
  Functional wrapper around `subset_ind_arr_of_sorted_inplace_nogc`

  Assume both `all_arr` and `subset_arr` are sorted by increasing
  value, and return the list of indices such that:

  subset_arr == ind_arr.map!( ind => all_arr[ ind ] ).array

  This is the default behaviour: `exact == true`.

  For a "closest" match instead, set `exact` to `false`.
*/
{
  pragma( inline, true );

  auto ret = new size_t[ subset_arr.length ];

  subset_ind_arr_of_sorted_inplace_nogc!(exact,T)
    ( all_arr, subset_arr, ret );

  return ret;
}

  
void subset_ind_arr_of_sorted_inplace_nogc( bool exact = true, T )
  ( in T[] all_arr, in T[] subset_arr
    , ref size_t[] out_ind_arr
    )
  pure nothrow @safe @nogc
/*
  Assume both `all_arr` and `subset_arr` are sorted by increasing
  value, and return the list of indices such that:

  subset_arr == ind_arr.map!( ind => all_arr[ ind ] ).array


  This is the default behaviour: `exact == true`.

  For a "closest" match instead, set `exact` to `false`.
*/
{
  pragma( inline, true );

  debug
    {
      assert( all_arr    ==    all_arr.dup.sort.array );
      assert( subset_arr == subset_arr.dup.sort.array );
      assert( out_ind_arr.length == subset_arr.length );
    }
  
  if (subset_arr.length < 1)
    return;
  
  size_t i_all = 0;
  T      x_all = all_arr[ i_all ];

  immutable all_length_m1 = all_arr.length - 1;
  
  foreach (i_subset, x; subset_arr)
    {
      static if (exact)
        {
          while (x_all < x  &&  i_all < all_length_m1)
            x_all = all_arr[ ++i_all ];
          
          if (x_all != x)
            {
              assert
                ( false
                  , "Each value of `subset_arr` must be"
                  ~" appear in `all_arr` as well."
                  );
            }
        }
      else
        {
          // Not so exact: pick the closest one
          while (i_all < all_length_m1)
            {
              immutable next_i_all = 1 + i_all;
              immutable next_x_all = all_arr[ next_i_all ];

              if (next_x_all > x)
                {
                  if (next_x_all - x > abs( x_all - x ))
                    break; // no improvement possible anymore
                }

              i_all = next_i_all;
              x_all = next_x_all;
            }
        }

      out_ind_arr[ i_subset ] = i_all;
    }
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


  {
    // exact:true should be the default => same results as above

    immutable exact = true;
    
    assert( subset_ind_arr_of_sorted!exact
            ( [ 0, 1, 3, 5, 6, 7, 8, 11, 13 ]
              , [] )
            == []
            );   
  
    assert( subset_ind_arr_of_sorted!exact
            ( [   0, 1, 3, 5, 6, 7, 8, 11, 13 ]
              , [    1,    5, 6,    8,     13 ] )
            == [     1,    3, 4,    6,     8  ]
            );   
  
    assert( subset_ind_arr_of_sorted!exact
            ( [   0, 1, 3, 5, 6, 7, 8, 11, 13 ]
              , [ 0, 1,    5, 6,    8,        ] )
            == [  0, 1,    3, 4,    6,        ]
            );   
  
    assert( subset_ind_arr_of_sorted!exact
            ( [   0, 1, 3, 5, 6, 7, 8, 11, 13 ]
              , [ 0, 1, 3, 5, 6, 7, 8, 11, 13 ] )
            == [  0, 1, 2, 3, 4, 5, 6,  7,  8 ]
            );   
  }
  



  {
    // Even with exact:false, if the data only has exact matches,
    // we'll use them => same results as above

    immutable exact = false;
    
    assert( subset_ind_arr_of_sorted!exact
            ( [ 0, 1, 3, 5, 6, 7, 8, 11, 13 ]
              , [] )
            == []
            );   
  
    assert( subset_ind_arr_of_sorted!exact
            ( [   0, 1, 3, 5, 6, 7, 8, 11, 13 ]
              , [    1,    5, 6,    8,     13 ] )
            == [     1,    3, 4,    6,     8  ]
            );   
  
    assert( subset_ind_arr_of_sorted!exact
            ( [   0, 1, 3, 5, 6, 7, 8, 11, 13 ]
              , [ 0, 1,    5, 6,    8,        ] )
            == [  0, 1,    3, 4,    6,        ]
            );   
  
    assert( subset_ind_arr_of_sorted!exact
            ( [   0, 1, 3, 5, 6, 7, 8, 11, 13 ]
              , [ 0, 1, 3, 5, 6, 7, 8, 11, 13 ] )
            == [  0, 1, 2, 3, 4, 5, 6,  7,  8 ]
            );   
  }


  {
    // Now we test exact:false on "approximate data", that is
    // actual use cases with approximate matches.

    immutable exact = false;
    
    assert( subset_ind_arr_of_sorted!exact
            ( [ 0.0, 1.0, 3.0, 5.0, 6.0, 7.0, 8.0, 11.0, 13.0, ]
              , [] )
            == []
            );   
  
    assert( subset_ind_arr_of_sorted!exact
            ( [   0.0, 1.3, 3.0, 4.6, 6.2, 7.1, 7.7, 11.3, 12.7, ]
              , [      1.0,      5.0, 6.0,      8.0,       13.0, ] )
            == [       1,        3,   4,        6,          8,   ]
            );   
  
    assert( subset_ind_arr_of_sorted!exact
            ( [   0.0, 1.3, 3.0, 4.6, 6.2, 7.1, 7.7, 11.3, 12.7, ]
              , [ 0.0, 1.0,    5.0, 6.0,    8.0,        ] )
            == [  0,   1,      3,   4,      6,          ]
            );   
  
    assert( subset_ind_arr_of_sorted!exact
            ( [   0.2, 1.3, 3.0, 4.6, 6.2, 7.1, 7.7, 11.3, 12.7, ]
              , [ 0.0, 1.0, 3.0, 5.0, 6.0, 7.0, 8.0, 11.0, 13.0, ] )
            == [  0,   1,   2,   3,   4,   5,   6,    7,    8,   ]
            );   

    // Some more

    assert( subset_ind_arr_of_sorted!exact
            ( [   0.0, 1.0, 3.0, 5.0, 6.0, 7.0, 8.0, 11.0, 13.0, ]
              , [      1.3,      4.6, 6.2,      7.7,       12.7, ] )
            == [       1,        3,   4,        6,          8,   ]
            );   
  
    assert( subset_ind_arr_of_sorted!exact
            ( [   0.0, 1.0, 3.0, 5.0, 6.0, 7.0, 8.0, 11.0, 13.0, ]
              , [ 0.4, 1.3,      4.6, 6.2,      7.7,             ] )
            == [  0,   1,        3,   4,        6,               ]
            );   
  
    assert( subset_ind_arr_of_sorted!exact
            ( [   0.0, 1.0, 3.0, 5.0, 6.0, 7.0, 8.0, 11.0, 13.0, ]
              , [ 0.2, 1.3, 3.0, 4.6, 6.2, 7.1, 7.7, 11.3, 12.7, ] )
            == [  0,   1,   2,   3,   4,   5,   6,    7,    8,   ]
            );   
  }

  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
