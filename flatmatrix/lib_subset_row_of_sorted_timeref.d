module d_glat.flatmatrix.lib_subset_row_of_sorted_timeref;

public import d_glat.flatmatrix.core_matrix;

import d_glat.lib_subset_ind_of_sorted_timeref;

MatrixT!T subset_row_of_sorted_timeref
( TT/*means TimeType, must be signed*/, T )
  ( in TT[] timeref_arr, in TT[] time_arr, in MatrixT!T m
    , ref TT[] deltatime_arr
    , TT max_deltatime = TT.max
    )
  pure @safe
{
  size_t[] rowind_arr;
  
  subset_ind_of_sorted_timeref
    ( timeref_arr, time_arr
      , rowind_arr, deltatime_arr
      , max_deltatime );
  
  return subset_row( m, rowind_arr );
}
