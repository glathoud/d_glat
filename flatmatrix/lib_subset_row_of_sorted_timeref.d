module d_glat.flatmatrix.lib_subset_row_of_sorted_timeref;

public import d_glat.flatmatrix.core_matrix;

import d_glat.lib_subset_ind_of_sorted_timeref;

// `auto_max_deltatime_midseg == true` means "automatically in the middle of timref segments"

MatrixT!T subset_row_of_sorted_timeref
( bool auto_max_deltatime_midseg = false, TT/*means TimeType, must be signed*/, T )
( in TT[] timeref_arr, in TT[] time_arr, in MatrixT!T m
  , ref TT[] deltatime_arr

  , TT max_deltatime = TT.max  
  )
pure
{
  scope size_t[] rowind_arr;
  
  subset_ind_of_sorted_timeref!auto_max_deltatime_midseg
    ( timeref_arr, time_arr
      , rowind_arr, deltatime_arr
      , max_deltatime );
  
  return subset_row( m, rowind_arr );
}



MatrixT!T subset_row_of_sorted_timeref
( bool auto_max_deltatime_midseg = false, TT/*means TimeType, must be signed*/, T )
( in TT[] timeref_arr, in TT[] time_arr, in MatrixT!T m
  , ref size_t[] rowind_arr
  , ref TT[] deltatime_arr

  // `max_deltatime`: <0 value (e.g. -1) means "automatically in the middle of timref segments"
  , TT max_deltatime = TT.max  
  )
pure
{
  subset_ind_of_sorted_timeref!auto_max_deltatime_midseg
    ( timeref_arr, time_arr
      , rowind_arr, deltatime_arr
      , max_deltatime );
  
  return subset_row( m, rowind_arr );
}
