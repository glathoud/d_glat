module d_glat.lib_timeseries_selection;

/*
  Model to select part of timeseries along the time axis.
  
  By Guillaume Lathoud, 2022
  glat@glat.info
  
  Boost Software License version 1.0, see ./LICENSE
*/

import d_bourse_common.lib_time;
import d_glat.core_assert;
import d_glat.lib_search_bisection;
import std.algorithm : max, min;
import std.conv : to;

// ---------- API ----------

T[] apply(T)( in TimeseriesSelection ts_sel, T[] arr )
{
  T[] ret;

  if (0 < arr.length)
    {
      if (ts_sel.inf_begin != INF_BEGIN_ALL_PAST)
        {
          mixin(alwaysAssertStderr!`-1 < ts_sel.utc_ms_col_ind`);
          mixin(alwaysAssertStderr!`0 < ts_sel.n_col`);
          mixin(alwaysAssertStderr!`0 == arr.length % ts_sel.n_col`);
      
          double begin_fun( in size_t ind )
          {
            immutable utc_ms = arr[ ind * ts_sel.n_col + ts_sel.utc_ms_col_ind ];
            return cast(double)( utc_ms );
          }

          // -0.5+... trick to be sure to get the very first occurence,
          // in case of duplicates.
          immutable v = -0.5 + cast(double)( ts_sel.inf_begin.utc_ms );
          immutable size_t a0 = 0;
          immutable size_t b0 = (arr.length / cast(size_t)( ts_sel.n_col ))-1;

          size_t ind0 = size_t.max, ind1 = size_t.max;
          double prop = double.nan;

          search_bisection( &begin_fun, v, a0, b0 
                                              , ind0, ind1, prop );

          mixin(alwaysAssertStderr!`ind0 < size_t.max`);
          mixin(alwaysAssertStderr!`ind1 < size_t.max`);
          mixin(alwaysAssertStderr!`!isNaN( prop )`);
      
          ret = arr[ (ts_sel.n_col * (0.0 < prop  ?  ind1  :  ind0))..$ ];
        }
      else
        {
          mixin(alwaysAssertStderr(`ts_sel.isFull`
                                   ,`"maybe implementation missing (todo)"`));

          ret = arr;
        }
    }
  
  return ret;
}


// ---------- Model ----------

immutable TimeseriesSelection TS_SEL_FULL = {
 utc_ms_col_ind: -1 // not needed in that case
 , n_col: -1  // not needed in that case
 , inf_begin:    INF_BEGIN_ALL_PAST
};

struct TimeseriesSelection
// To select part of a timeseries
{
  immutable long     utc_ms_col_ind; // Where to find the `utc_ms` value in each record
  immutable long     n_col;          // Length of each record
  immutable InfBegin inf_begin;      // Optional cut of the beginning
  // could extend later with e.g. SupEnd etc.

  bool isFull() const pure @safe @nogc
  {
    return inf_begin == INF_BEGIN_ALL_PAST;
  }
}



immutable InfBegin INF_BEGIN_ALL_PAST = {
 utc_ms : -long.max,
 n_past : 0
};


struct InfBegin
{
  /*
    Represents data knowledge about what we need : `n_past` samples
    before `utc_ms` (if available, else as many samples as we can
    get, up to `n_past`).

    Typically used to describe the target knowledge of an output
    infbegin_of_uname
  */
  long   utc_ms;
  size_t n_past;

  InfBegin copy() const pure @safe
  {
    InfBegin ret = {utc_ms:utc_ms, n_past:n_past};
    return ret;
  }

  bool is_all_past() const pure @safe @nogc nothrow
  {
    return utc_ms == -typeof( utc_ms ).max
      ||   n_past == +typeof( n_past ).max;
  }

  InfBegin get_inf( in InfBegin other ) const pure @safe @nogc nothrow
  {
    
    
    InfBegin ret = {
    utc_ms   : min( utc_ms, other.utc_ms )
    , n_past : max( n_past, other.n_past )
    };
    
    return ret;
  }

  string toString() const
  {
    return "InfBegin(utc_ms:"~to!string(utc_ms)~"("~get_utc_str_of_timems( utc_ms )~"),n_past:"~to!string(n_past)~")";
  }
}