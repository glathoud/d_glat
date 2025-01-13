module d_glat.core_array;

import d_glat.core_assoc_array : aa_set_of_array;
import d_glat.core_assert;
import d_glat.core_string : _tli;
import std.algorithm : sort;
import std.array : appender, array;
import std.exception : assumeUnique;
import std.conv : to;
import std.format : format;
import std.math : abs, isNaN;
import std.traits : hasMember;

/*
  Tools for arrays. Boost License, see file ./LICENSE

  By Guillaume Lathoud, 2019
  glat@glat.info
*/


T[] arr_change_order(T)( in size_t[] ind_arr, in T[] arr) pure @trusted
{
  auto ret = new T[ arr.length ];

  auto ret_ptr = ret.ptr;
  foreach (out_ind, in_ind; ind_arr)
    ret_ptr[ out_ind ] = arr[ in_ind ];
  
  return ret;
}

void arr_change_order_inplace(T)( in size_t[] ind_arr, ref T[] arr ) pure @safe
{
  scope auto buff = new T[ arr.length ];
  arr_change_order_inplace_nogc!T( ind_arr, buff, arr );
}

void arr_change_order_inplace_nogc(T)( in size_t[] ind_arr, ref T[] buff, ref T[] arr )
  pure @safe @nogc
{
  buff[] = arr[];
  foreach (out_ind, in_ind; ind_arr) // ind_arr[ out_ind ] == in_ind
    arr[ out_ind ] = buff[ in_ind ];
}


string arr_each_parallel_C
(string taskPool_c = "taskPool"
 , string a_c = "a", string a_step_c="a_step", string a_begin_c="a_begin", string a_end_c="a_end"
 , string arr_len_c="arr_len")
 ( in string arr_c, in string do_c ) pure nothrow @safe 
{
  return mixin(_tli!q{
      {
        immutable ${arr_len_c} = (${arr_c}).length;
        immutable ${a_step_c} = cast(size_t)( ceil( (cast(double)( ${arr_len_c} ))
                                                      / (cast(double)( 1 + (${taskPool_c}).size ))));

        foreach (${a_begin_c}; (${taskPool_c}).parallel( iota( 0, ${arr_len_c}, ${a_step_c} )
                                                         , /*workUnitSize:*/1 ))
          {
            immutable ${a_end_c} = min( ${arr_len_c}, ${a_begin_c} + ${a_step_c} );
            foreach (${a_c}; ${a_begin_c}..${a_end_c})
              {
                ${do_c}
              }
          }
      }
    });
}



alias arr_ensure_length = ensure_length;

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
  mixin(arr_ensure_length_C( `desired_length`, `arr` ));
  return arr;
}

string arr_ensure_length_C( in string desired_length_c, in string arr_c ) pure nothrow @safe
{
  return mixin(_tli!q{{
        if (${arr_c}.length != ${desired_length_c})
          ${arr_c}.length = ${desired_length_c};
      }});
}



bool arr_equal_nan(T)( in T[] a, in T[] b )
  pure nothrow @safe @nogc
// Extended equal that also permits matching NaNs.  For simple
// non-array types like float etc. see also `equal_nan` in
// ./core_math.d
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


void arr_filter_inplace(string test_c, T)( ref T[] arr ) pure nothrow @safe
// In practice, should probably be @nogc since `arr.length` can only diminish.
{
  mixin(arr_filter_inplace_C("arr",test_c));
}


string arr_filter_inplace_C(string a_c="a", string b_c="b",string old_length_c="old_length")
  ( in string arr_c, in string test_c ) pure nothrow @safe
// Code for single pass, (GC & CPU)-cost-effective inplace removal of
// several elements of an array.
//
// In practice, should probably be @nogc since `arr.length` can only diminish.
{
  return mixin(_tli!q{
      {
        immutable size_t ${old_length_c} = ${arr_c}.length;

        size_t ${a_c} = 0;
        size_t ${b_c} = 0;

        /* ${a_c} == ${b_c} */
        for (;
             (${test_c})  &&  ${a_c} < ${old_length_c};
             ++${a_c}, ++${b_c}
             )
          {/*keep the element, nothing to change*/}
        
        /*At this point, either finished, or ${b_c} < ${a_c}*/
        for (;
             ${a_c} < ${old_length_c};
             ++${a_c})
          {
            if (!(${test_c}))
              continue; /*skip*/

            /*keep*/
            ${arr_c}[ ${b_c}++ ] = ${arr_c}[ ${a_c} ];
          }

        ${arr_c}.length = ${b_c};
      }
    });
}


  
string arr_filter_inplace_remove_C(string a_c="a", string b_c="b",string old_length_c="old_length")
  ( in string arr_c, in string test_c ) pure nothrow @safe
// Code for remove-based, (GC & CPU)-cost-effective inplace removal of
// several elements of an array.
//
// This probably makes sense when there are few removals.  Else,
// consider the single-pass, remove-free `arr_filter_inplace_C`.
//
// In practice, should probably be @nogc since `arr.length` can only diminish.
{
  return mixin(_tli!q{
      {
        immutable size_t ${old_length_c} = ${arr_c}.length;

        size_t ${b_c} = ${old_length_c};

        for (size_t ${a_c} = ${old_length_c}; ${a_c}--;)
          {
            if (!(${test_c}))
              {
                ${arr_c}.remove( ${a_c} );
                --${b_c};
              }
          }
        
        ${arr_c}.length = ${b_c};
      }
    });
}


  
string arr_fold_C(string opt_acctype_c="double")
  ( in string opt_accinit_c, in string loopspec_c, in string iter_c ) pure nothrow @safe
{
  assert(!(0 == opt_acctype_c.length  &&  0 < opt_accinit_c.length));

  const maybe_init_c = 0 < opt_accinit_c.length ?  mixin(_tli!q{ ${opt_acctype_c} ${opt_accinit_c}; })
    :  "";
  
  return mixin(_tli!q{ ${maybe_init_c}
                      foreach( ${loopspec_c} )
                      {
                        ${iter_c}
                      }
    });
}

string arr_loop_C( in string loopspec_c, in string iter_c ) pure nothrow @safe
{ return arr_fold_C( "", loopspec_c, iter_c ); }



T[] arr_set_iota(T)( in size_t desired_length, ref T[] arr ) pure nothrow @trusted
{
  mixin(arr_set_iota_C(`desired_length`, `arr`));
  return arr;
}

string arr_set_iota_C( in string desired_length_c, in string arr_c, in string E="i" )
  pure nothrow @safe
{
  return arr_ensure_length_C( desired_length_c, arr_c )
    ~mixin(_tli!q{{
        auto __tmp_arr_ptr__ = ${arr_c}.ptr;
        foreach (i; 0..${desired_length_c})
          __tmp_arr_ptr__[ i ] = ${E};
        }});
}


T[] arr_sign(T)( in T[] arr ) pure nothrow @safe
{
  T[] ret;
  arr_sign_inplace_dim!T( arr, ret );
  return ret;
}

void arr_sign_inplace_dim(T)( in T[] arr, ref T[] ret ) pure nothrow @safe
{
  ensure_length( arr.length, ret );
  arr_sign_inplace_nogc!T( arr, ret );
}


void arr_sign_inplace_nogc(T)( in T[] arr, ref T[] ret ) pure nothrow @safe @nogc
{
  debug assert( ret.length == arr.length );
  foreach (i,ref x; arr)
    ret[ i ] = x > 0  ?  +1  :  x < 0  ?  -1  :  0;
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
  
  size_t  i_all = 0;
  scope T x_all = all_arr[ i_all ];

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




T[] uniq_of_sorted_arr(T)( in T[] arr ) pure
{
  scope auto app = appender!(T[]);
  {
    scope T prev;
    foreach (i,v; arr)
      {
        debug
          {
            if (0 < i)
              assert( prev <= v );
          }

        if (i == 0  ||  prev < v)
          app.put( v );

        prev = v;
      }
  }

  return app.data;
}




unittest
{
  import std.algorithm;
  import std.path;
  import std.range;
  import std.stdio;

  enum verbose = true;
  
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
    assert( arr_equal_nan!double( [], [] ) );
    assert( arr_equal_nan( [], [] ) );

    assert( arr_equal_nan( [   1.0, 2.0, 3.0 ]
                       , [ 1.0, 2.0, 3.0 ] ) );

    assert( arr_equal_nan( [   1.0, double.nan, 3.0 ]
                       , [ 1.0, double.nan, 3.0 ] ) );


    assert( !arr_equal_nan( [   1.0, 2.0, 3.0 ]
                        , [ 1.0, 2.0, 3.0, 4.0 ] ) );
    
    assert( !arr_equal_nan( [   1.0, 2.0, 3.0, 4.0 ]
                        , [ 1.0, 2.0, 3.0 ] ) );
    
    assert( !arr_equal_nan( [   1.0, 2.0, 3.0 ]
                        , [ 1.1, 2.0, 3.0 ] ) );

    assert( !arr_equal_nan( [   1.0, double.nan, 3.0 ]
                        , [ 1.0, double.nan, 3.1 ] ) );

    assert( !arr_equal_nan( [   1.0, double.nan, 3.0 ]
                        , [ 1.0, 2.0,        double.nan ] ) );

  }

  {
    enum test_c = "0 == (a % 3)";
    auto arr_0 = assumeUnique( iota( 100 ).array );
    auto arr_1 = assumeUnique( arr_0.filter!test_c.array );

    auto arr_2 = arr_0.dup;
    arr_filter_inplace!test_c( arr_2 );

    if (verbose)
      {
        writeln( "arr_0: ", arr_0 );
        writeln( "arr_1: ", arr_1 );
        writeln( "arr_2: ", arr_2 );
      }

    assert( arr_2 == arr_1 );
  }

  
  {
    enum test_c = "0 == (a % 3)";
    auto arr_0 = assumeUnique( iota( 100 ).array );
    auto arr_1 = assumeUnique( arr_0.filter!test_c.array );

    auto arr_2 = arr_0.dup;
    mixin(arr_filter_inplace_remove_C("arr_2",test_c));

    if (verbose)
      {
        writeln( "(remove impl.) arr_0: ", arr_0 );
        writeln( "(remove impl.) arr_1: ", arr_1 );
        writeln( "(remove impl.) arr_2: ", arr_2 );
      }

    assert( arr_2 == arr_1 );
  }

  
  {
    size_t[] arr;
    arr_set_iota( 7, arr );
    assert( arr == [0 ,1 ,2 ,3 ,4 ,5 ,6] );
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


  {
    assert( uniq_of_sorted_arr([ 1, 2, 3, 3, 3, 4, 5, 5, 6])
            == [1,2,3,4,5,6]);
  }

  {
    assert( uniq_of_sorted_arr([ 1,1,1, 2, 3, 3, 3, 4, 5, 5, 6,6])
            == [1,2,3,4,5,6]);
  }

  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
