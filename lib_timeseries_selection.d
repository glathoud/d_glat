module d_glat.lib_timeseries_selection;

/*
  Model to select part of timeseries along the time axis.
  
  By Guillaume Lathoud, 2022
  glat@glat.info
  
  Boost Software License version 1.0, see ./LICENSE
*/

import d_glat.core_assert;
import d_glat.lib_search_bisection;
import d_glat.lib_time;
import std.algorithm : max, min;
import std.conv : to;
import std.math : isNaN;
import std.stdio;

// ---------- Constants ----------

immutable BEGIN_UTC_MS_FROM_END = long.max;
immutable END_UTC_MS_ALL_FUTURE = long.max;

// ---------- API ----------

T[] apply(T, TArrLike=T[])( in TimeseriesSelection ts_sel, TArrLike arr )
{
  T[] ret;

  if (0 < arr.length)
    {
      if (ts_sel.inf_begin != INF_BEGIN_ALL_PAST)
        {
          mixin(alwaysAssertStderr!`0 < ts_sel.n_col`);
          mixin(alwaysAssertStderr!`0 == arr.length % ts_sel.n_col`);

          immutable ib_utc_ms = ts_sel.inf_begin.utc_ms;
          immutable ib_n_past = ts_sel.inf_begin.n_past;
          mixin(alwaysAssertStderr!`-long.max < ib_utc_ms`);
          mixin(alwaysAssertStderr!`0 <= ib_n_past`);

          size_t i_row_0;
          if (isInfBeginFromEnd( ts_sel.inf_begin ))
            {
              // `ts_sel.utc_ms_col_ind` not needed in this particular case
              i_row_0 = arr.length / ts_sel.n_col;
            }
          else
            {
              mixin(alwaysAssertStderr!`-1 < ts_sel.utc_ms_col_ind`);

              double begin_fun( in size_t ind )
              {
                immutable utc_ms = arr[ ind * ts_sel.n_col + ts_sel.utc_ms_col_ind ];
                return cast(double)( utc_ms );
              }

              // -0.5+... trick to be sure to get the very first occurence,
              // in case of duplicates.
              immutable v = -0.5 + cast(double)( ib_utc_ms );
              immutable size_t a0 = 0;
              immutable size_t b0 = (arr.length / cast(size_t)( ts_sel.n_col ))-1;

              size_t ind0 = size_t.max, ind1 = size_t.max;
              double prop = double.nan;

              search_bisection( &begin_fun, v, a0, b0 
                                , ind0, ind1, prop );

              mixin(alwaysAssertStderr!`ind0 < size_t.max`);
              mixin(alwaysAssertStderr!`ind1 < size_t.max`);
              mixin(alwaysAssertStderr!`!isNaN( prop )`);

              i_row_0 = 0.0 < prop  ?  ind1  :  ind0;
            }
          immutable size_t i_row   = i_row_0 > ib_n_past  ?  i_row_0 - ib_n_past  :  0;
          
          ret = arr[ (ts_sel.n_col * i_row)..$ ];
        }
      else
        {
          mixin(alwaysAssertStderr(`ts_sel.isFullPast`
                                   ,`"maybe implementation missing (todo)"`));

          ret = arr[ 0..$ ]; // [0..$] necessary to read from fake arrays (./flatmatrix/lib_jsonbin.d)
        }
    }

  
  if (0 < ret.length)
    {
      if (ts_sel.end_utc_ms != END_UTC_MS_ALL_FUTURE)
        {
          mixin(alwaysAssertStderr!`-1 < ts_sel.utc_ms_col_ind`);
          mixin(alwaysAssertStderr!`0 < ts_sel.n_col`);
          mixin(alwaysAssertStderr!`0 == ret.length % ts_sel.n_col`);

          immutable end_utc_ms = ts_sel.end_utc_ms;
          mixin(alwaysAssertStderr!`end_utc_ms < END_UTC_MS_ALL_FUTURE`);
          
          double end_fun( in size_t ind )
          {
            immutable utc_ms = ret[ ind * ts_sel.n_col + ts_sel.utc_ms_col_ind ];
            return cast(double)( utc_ms );
          }

          // `-0.5+...` trick, to be sure to be just before the first
          // occurence of the `end_utc_ms` value that we want to
          // *exclude*. See also `1+i_row`.
          immutable v = -0.5 + cast(double)( end_utc_ms );
          immutable size_t a0 = 0;
          immutable size_t b0 = (ret.length / cast(size_t)( ts_sel.n_col ))-1;

          size_t ind0 = size_t.max, ind1 = size_t.max;
          double prop = double.nan;

          search_bisection( &end_fun, v, a0, b0 
                            , ind0, ind1, prop );
          
          mixin(alwaysAssertStderr!`ind0 < size_t.max`);
          mixin(alwaysAssertStderr!`ind1 < size_t.max`);
          mixin(alwaysAssertStderr!`!isNaN( prop )`);
          
          immutable size_t i_row = 0.0 < prop  ?  ind1  :  ind0;
          
          ret = ret[ 0..(ts_sel.n_col * (1 + i_row)) ];
        }
      else
        {
          mixin(alwaysAssertStderr(`ts_sel.isFullFuture`
                                   ,`"maybe implementation missing (todo)"`));
        }
    }
  
  
  return ret;
}


// ---------- Model ----------

immutable TimeseriesSelection TS_SEL_FULL = {
 utc_ms_col_ind: -1 // not needed in that case
 , n_col: -1  // not needed in that case
 , inf_begin:    INF_BEGIN_ALL_PAST
 , end_utc_ms:   END_UTC_MS_ALL_FUTURE
};


// In such a "..FromEnd" case, `n_col` is needed ; `utc_ms_col_ind` is
// not needed.
bool isTimeseriesSelectionFromEnd( in TimeseriesSelection ts_sel ) pure @safe @nogc nothrow
{ return isInfBeginFromEnd( ts_sel.inf_begin ); }

bool isTimeseriesSelectionFromEndIncomplete( in TimeseriesSelection ts_sel ) pure @safe @nogc nothrow
{ return isTimeseriesSelectionFromEnd( ts_sel )  &&  0 > ts_sel.n_col; }


immutable TimeseriesSelection TS_SEL_LAST_INCOMPLETE = get_TS_SEL_FROM_END_INCOMPLETE( 1 );

TimeseriesSelection get_TS_SEL_FROM_END_INCOMPLETE( in size_t n_past ) pure @safe nothrow
{
  // See ./flatmatrix/lib_jsonbin.d for an example of client
  // implementation that replaces `n_col:-1` with an actual value
  // (e.g. after reading the dimension of the data, but before reading
  // the actual data).
  TimeseriesSelection ret = {
  utc_ms_col_ind: -1 // not needed in that case
  , n_col       : -1 // *missing* in that case - needs to be set later, before calling "apply()"
  , inf_begin   : getInfBeginFromEnd( n_past )
  , end_utc_ms  : END_UTC_MS_ALL_FUTURE
  };
  return ret;
}


struct TimeseriesSelection
// To select part of a timeseries
{
  long     utc_ms_col_ind; // Where to find the `utc_ms` value in each record
  long     n_col;          // Length of each record
  InfBegin inf_begin;      // Optional cut of the beginning
  long     end_utc_ms = END_UTC_MS_ALL_FUTURE;     // Optional cut at the end
  
  bool isFull() const pure @safe @nogc
  {
    return isFullPast()  &&  isFullFuture();
  }

  
  bool isFullFuture() const pure @safe @nogc
  {
    return end_utc_ms == END_UTC_MS_ALL_FUTURE;
  }
  
  bool isFullPast() const pure @safe @nogc
  {
    return inf_begin == INF_BEGIN_ALL_PAST;
  }
}



immutable InfBegin INF_BEGIN_ALL_PAST = {
 utc_ms : -long.max,
 n_past : 0
};

immutable InfBegin INF_BEGIN_LAST_ONE = getInfBeginFromEnd( 1 );

InfBegin getInfBeginFromEnd( in size_t n_past ) pure @safe nothrow
{
  InfBegin ret = {
  utc_ms : BEGIN_UTC_MS_FROM_END,
  n_past : n_past
  };
  return ret;
}

bool isInfBeginFromEnd( in InfBegin inf_begin ) pure @safe @nogc nothrow
{ return inf_begin.utc_ms == BEGIN_UTC_MS_FROM_END; }



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
