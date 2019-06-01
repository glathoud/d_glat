module d_glat.lib_subset_ind_of_sorted_timeref;

import std.algorithm : filter, map, sort; 
import std.array : appender, array;
import std.math : abs;
import std.range : enumerate;

/*
  Advanced tools for arrays. Boost License, see file ./LICENSE

  By Guillaume Lathoud, 2019
  glat@glat.info
 */

void subset_ind_of_sorted_timeref
( TT/*TT means: TimeType (e.g. `long`)*/ )
  ( /*inputs:*/in TT[] timeref_arr, in TT[] time_arr
    , /*outputs:*/ref size_t[] ind_arr, ref TT[] deltatime_arr
    , /*option:*/TT max_deltatime = TT.max
    )
pure @safe
/*
  Task: 

  for each `timeref`, find the closest `time`, and output its index
  `ind` into `ind_arr`, and the corresponding signed value
  `deltatime`.

  In other words: to each `timref_arr[i]` correspond `ind_arr[i]` and
  `deltatime_arr[i]`.
  
  Details:

  - Input: two increasingly sorted arrays `timeref_arr` and
    `time_arr`.

  - Output: `ind_arr` an increasingly sorted array of indices in
  `time_arr`, and the corresponding `deltatime_arr` (signed values).
  
  - Option: restrict `max_deltatime` (by default: no restriction).
 */
in
{
  debug
    {
      TT a = -1;
      assert( a < 0, "TT must be a signed type" );
      assert( timeref_arr == timeref_arr.dup.sort.array );
      assert( time_arr    ==    time_arr.dup.sort.array );
    }  
}
out
{
  debug
    {
      assert( ind_arr.length       == timeref_arr.length );
      assert( deltatime_arr.length == timeref_arr.length );
      assert( ind_arr == ind_arr.dup.sort.array );
    }
}
body
{
  /* 
     0. easy case
  */

  if (timeref_arr.length < 1)
    {
      ind_arr = [];
      deltatime_arr = [];
      return;
    }
  
  /*
    1. loop: pick the best match in `time_arr` for `timeref_arr`
       update `data_max_deltatime`
  */

  // for optional restriction `max_deltatime`, implemented in 2.
  TT data_max_deltatime = -1;
  
  // output
  auto ind_app       = appender!(size_t[]);
  auto deltatime_app = appender!(TT[]);
  
  // indices in `time_arr`
  size_t    i      = 0;
  immutable t_len  = time_arr.length;
  
  foreach (tref; timeref_arr)
    {
      bool   found = false;
      size_t best_i;
      TT best_deltatime;
      TT best_abs_deltatime = TT.max;
      

      while (i < t_len)
        {
          immutable deltatime = time_arr[ i ] - tref;
          immutable abs_deltatime = abs( deltatime );
          if (abs_deltatime < best_abs_deltatime)
            {
              // decreased
              found  = true;
              best_i = i;
              best_deltatime     = deltatime;
              best_abs_deltatime = abs_deltatime;
              ++i;
            }
          else
            {
              // increased, since the arrays are sorted, we can stop
              break;
            }
        }

      debug assert( found );

      ind_app      .put( best_i );
      deltatime_app.put( best_deltatime );

      if (best_abs_deltatime > data_max_deltatime)
        data_max_deltatime = best_abs_deltatime;
      
      // Since the arrays are sorted, for the next `tref`, all the
      // previous ones (<best_i) will be worse, so we ignore them.
      i = best_i;
    }

  /*
    2. if necessary, filter out the ones having too much deltatime
   */

  debug assert( 0 <= data_max_deltatime );
  
  if (data_max_deltatime > max_deltatime)
    {
      auto deltatime_data = deltatime_app.data;
      auto ind_data       = ind_app      .data;

      auto tmp = deltatime_app
        .data
        .enumerate
        .filter!( a => a.value <= max_deltatime );
      
      ind_arr       = tmp.map!( a => ind_data[ a.index ] ).array;
      deltatime_arr = tmp.map!"a.value".array;
    }
  else
    {
        ind_arr       =       ind_app.data;
        deltatime_arr = deltatime_app.data;
    }
}

unittest
{
  import std.path;
  import std.stdio;
  
  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  enum verbose = false;
  
  import core.exception : AssertError;
  import std.exception : assertThrown;
  
  void check_assertThrown( alias ExceptionType, TT )
    ( in TT[] timeref_arr, in TT[] time_arr
      , in TT max_deltatime = TT.max
      )
  {
    size_t[] ind_arr;
    long[]   deltatime_arr;

    assertThrown!ExceptionType
      (
       subset_ind_of_sorted_timeref
       ( timeref_arr, time_arr,  ind_arr, deltatime_arr
         , max_deltatime
         )
       );
  }  

    
  void check( TT )
    ( in TT[] timeref_arr, in TT[] time_arr
      , in size_t[] expected_ind_arr
      , in TT[]     expected_deltatime_arr
      , in TT max_deltatime = TT.max
      )
  {
    size_t[] ind_arr;
    long[]   deltatime_arr;

    subset_ind_of_sorted_timeref
      ( timeref_arr, time_arr,  ind_arr, deltatime_arr );

    static if (verbose)
      {
        writeln;
        writeln( "in:    timeref_arr: ", timeref_arr );
        writeln( "in:       time_arr: ", time_arr );
        writeln( "out:       ind_arr: ", ind_arr );
        writeln( "          expected: ", expected_ind_arr );
        writeln( "out: deltatime_arr: ", deltatime_arr );
        writeln( "          expected: ", expected_deltatime_arr );
      }
    
    assert( ind_arr       == expected_ind_arr );
    assert( deltatime_arr == expected_deltatime_arr );
  }  

  immutable check_code =
    `check( timeref_arr, time_arr
            , expected_ind_arr, expected_deltatime_arr );`;
  
  // --- Error test cases
  
  {
    // Error thrown in debug mode: one of them is not sorted
    long[] timeref_arr = [ 1, 5, 3 ];
    long[] time_arr    = [ 1, 2, 4, 6, 8 ];

    check_assertThrown!AssertError( timeref_arr, time_arr );
  }

  {
    // Error thrown in debug mode: one of them is not sorted
    long[] timeref_arr = [ 1, 3, 5 ];
    long[] time_arr    = [ 1, 2, 6, 4, 8 ];

    size_t[] ind_arr;
    long[]   deltatime_arr;

    check_assertThrown!AssertError( timeref_arr, time_arr );
  }

  {
    // Error thrown in debug mode: at least one of them not sorted
    long[] timeref_arr = [ 1, 5, 3 ];
    long[] time_arr    = [ 1, 2, 6, 4, 8 ];

    size_t[] ind_arr;
    long[]   deltatime_arr;

    check_assertThrown!AssertError( timeref_arr, time_arr );
  }

  // --- Error-free test cases

  {
    long[] timeref_arr = [];
    long[] time_arr    = [ 1, 2, 4, 6, 8 ];

    immutable size_t[] expected_ind_arr =
      [];
    
    immutable long[]   expected_deltatime_arr =
      [];

    mixin(check_code);
  }
  
  {
    long[] timeref_arr = [ 1, 3, 5 ];
    long[] time_arr    = [ 1, 2, 6, 8 ];

    immutable size_t[] expected_ind_arr =
      [ 0, 1, 2 ];
    
    immutable long[]   expected_deltatime_arr =
      [ 0, -1, 1 ];

    mixin(check_code);
  }

  {
    long[] timeref_arr = [ 1, 3, 7 ];
    long[] time_arr    = [ 1, 2, 6, 8 ];

    immutable size_t[] expected_ind_arr =
      [ 0, 1, 2 ];
    
    immutable long[]   expected_deltatime_arr =
      [ 0, -1, -1 ];

    mixin(check_code);
  }

  {
    long[] timeref_arr = [ 1, 3,    7 ];
    long[] time_arr    = [ 1, 2, 4, 6, 8 ];

    immutable size_t[] expected_ind_arr =
      [ 0, 1, 3 ];
    
    immutable long[]   expected_deltatime_arr =
      [ 0, -1, -1 ];

    mixin(check_code);
  }
  
  {
    long[] timeref_arr =
      [ -2, -1,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10 ];

    long[] time_arr    = [ 1, 2, 4, 6, 8 ];

    immutable size_t[] expected_ind_arr =
      [  0,  0,  0,  1,  1,  2,  2,  3,  3,  4,  4,   4 ];
    
    immutable long[]   expected_deltatime_arr =
      [  3,  2,  0,  0, -1,  0, -1,  0, -1,  0, -1,  -2 ];

    mixin(check_code);
  }

  static if (verbose)
    writeln;
  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
