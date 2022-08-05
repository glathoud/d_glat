module d_glat.core_array;

import d_glat.core_assoc_array : aa_set_of_array;
import d_glat.core_assert;
import std.algorithm : sort;
import std.array : appender, array;
import std.conv : to;
import std.format : format;
import std.math : abs, isNaN;
import std.traits : hasMember;

/*
  Tools for arrays. Boost License, see file ./LICENSE

  By Guillaume Lathoud, 2019
  glat@glat.info
*/


T[] arr_change_order(T)( in size_t[] ind_arr, in T[] arr) pure @safe
{
  auto ret = new T[ arr.length ];
  
  foreach (out_ind, in_ind; ind_arr)
    ret[ out_ind ] = arr[ in_ind ];
  
  return ret;
}

void arr_change_order_inplace(T)( in size_t[] ind_arr, ref T[] arr ) pure @safe
{
  auto buff = new T[ arr.length ];
  arr_change_order_inplace_nogc!T( ind_arr, buff, arr );
}

void arr_change_order_inplace_nogc(T)( in size_t[] ind_arr, ref T[] buff, ref T[] arr )
  pure @safe @nogc
{
  buff[] = arr[];
  foreach (out_ind, in_ind; ind_arr) // ind_arr[ out_ind ] == in_ind
    arr[ out_ind ] = buff[ in_ind ];
}



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
  
  if (arr.length != desired_length)
    arr = new T[desired_length];

  return arr;
}


bool equal_nan(T)( in T[] a, in T[] b )
  pure nothrow @safe @nogc
// Extended equal that also permits matching NaNs.
{
  static if (hasMember!(T, "nan"))
    {
      // e.g. T == double

      if (a.length != b.length)
        return false;

      foreach (i,x; a)
        {
          immutable y = b[ i ];
          immutable one_equal = x == y
            ||  isNaN( x )  &&  isNaN( y );

          if (!one_equal)
            return false;
        }

      return true;
    }
  else
    {
      // e.g. T == int

      return a == b;
    }
}



size_t[T] get_indmap_of_arr( bool unique = true, T)( in T[] arr )
// see also: core_assoc_array.aa_ind_of_array
{
  size_t[T] indmap;

  foreach (ind,v; arr)
    {
      static if (unique)
        {
          if (v in indmap)
            assert( false, "bug: "~to!string( v )~" not unique." );
        }

      indmap[ v ] = ind;
    }

  return indmap;
}


alias get_set_of_arr = aa_set_of_array;

  

size_t[] subset_ind_arr_of_sorted( bool exact = true, T )
  ( in T[] all_arr, in T[] subset_arr )
  pure nothrow @safe
/*
  Functional wrapper around `subset_ind_arr_of_sorted_inplace_nogc`

  Assume both `all_arr` and `subset_arr` are sorted by increasing
  value, and return the list of indices `ind_arr` such that:

  subset_arr == ind_arr.map!( ind => all_arr[ ind ] ).array

  This is the default behaviour: `exact == true`.

  For a "closest" match instead, set `exact` to `false`.
*/
{
  

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
  value, and return the list of indices `ind_arr` such that:

  subset_arr == ind_arr.map!( ind => all_arr[ ind ] ).array


  This is the default behaviour: `exact == true`.

  For a "closest" match instead, set `exact` to `false`.
*/
{
  

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
    immutable long[] a = [0,10,20,30,40,50,60];
    auto b = arr_change_order( [4,2,3,1,0,6,5], a );
    assert( a == [0,10,20,30,40,50,60] );
    assert( b == [40,20,30,10,0,60,50] );
  }

  {
    long[] a = [0,10,20,30,40,50,60];
    arr_change_order_inplace( [4,2,3,1,0,6,5], a );
    assert( a == [40,20,30,10,0,60,50] );
  }

  {
    long[] a = [0,10,20,30,40,50,60];
    auto buff = new long[ a.length ];
    arr_change_order_inplace_nogc( [4,2,3,1,0,6,5], buff, a );
    assert( a == [40,20,30,10,0,60,50] );
  }


  
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
