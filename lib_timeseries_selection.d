module d_glat.lib_timeseries_selection;

/*
  Model to select part of timeseries along the time axis.
  
  By Guillaume Lathoud, 2022
  glat@glat.info
  
  Boost Software License version 1.0, see ./LICENSE
*/



import d_bourse_common.lib_time;
import std.algorithm : max, min;
import std.conv : to;

immutable TimeseriesSelection TS_SEL_FULL = {
 utc_ms_col_ind: -1 // not needed in that case
 , inf_begin:    INF_BEGIN_ALL_PAST
};

struct TimeseriesSelection
// To select part of a timeseries
{
  immutable long     utc_ms_col_ind; // Where to find the `utc_ms` value in each record
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
