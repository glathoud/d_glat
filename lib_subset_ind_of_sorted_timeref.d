module d_glat.lib_subset_ind_of_sorted_timeref;

import std.algorithm : filter, map, sort; 
import std.array : appender, array;
import std.math : abs;
import std.range : enumerate;

void subset_ind_of_sorted_timeref
( alias max_deltatime = TT.max, TT )
  ( in TT[] timeref_arr, in TT[] time_arr
    , ref size_t[] ind_arr, ref TT[] deltatime_arr )
pure @safe
{
  debug
    {
      assert( timeref_arr == timeref_arr.dup.sort.array );
      assert( time_arr    ==    time_arr.dup.sort.array );
    }
  
  /*
    1. loop: pick the best match in `time_arr` for `timeref_arr`
       update `data_max_deltatime`
  */

  TT data_max_deltatime = -1;
  
  /*
    sketch
    
    i, iprev   (time)
    ir  (timeref) loop
   */

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
      auto   best_deltatime = TT.max;

      while (i < t_len)
        {
          auto deltatime = time_arr[ i ] - tref;
          if (abs( deltatime ) < best_deltatime)
            {
              // decreased
              found  = true;
              best_i = i;
              best_deltatime = deltatime;
              ++i;
            }
          else
            {
              // increased, since the arrays are sorted we can stop
              break;
            }
        }

      debug assert( found );

      ind_app.put( best_i );
      deltatime_app.put( best_deltatime );

      // Since the arrays are sorted, for the next `tr` all the
      // previous ones (<i) will be worse than the one at `i`.
      i = best_i;
    }

  ind_arr       = ind_app.data;
  deltatime_arr = deltatime_app.data;
  
  /*
    2. if necessary, filter out the ones having too much deltatime
   */

  debug assert( 0 <= data_max_deltatime );
  
  if (data_max_deltatime > max_deltatime)
    {
      auto tmp = deltatime_arr
        .enumerate
        .filter!( a => a.value <= max_deltatime );

      ind_arr       = tmp.map!( a => ind_arr[ a.index ] ).array;
      deltatime_arr = tmp.map!"a.value".array;
    }


  assert( false, "xxx subset_ind_of_sorted_timeref not tested yet" );
}
