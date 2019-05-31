module d_glat.flatmatrix.lib_subset_row_of_sorted_timeref;

public import d_glat.flatmatrix.core_matrix;

import d_glat.lib_subset_ind_of_sorted_timeref;

MatrixT!T subset_row_of_sorted_timeref
( alias max_deltatime = TT.max, TT, T )
  ( in TT[] timeref_arr, in TT[] time_arr, in MatrixT!T m
    , ref TT[] deltatime_arr
    )
  pure @safe
{
  size_t[] rowind_arr;
  
  subset_ind_of_sorted_timeref!max_deltatime
    ( timeref_arr, time_arr
      , rowind_arr, deltatime_arr );
  
  return subset_row( m, rowind_arr );
}
