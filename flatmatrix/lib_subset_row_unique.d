module d_glat.flatmatrix.lib_subset_row_unique;

import d_glat.flatmatrix.core_matrix;
import std.array : appender;

/*
  Return a new matrix where duplicate rows have been eliminated:
  only the first resp. last row of a series of duplicates is kept.
  
  Guillaume Lathoud, 2019
  glat@glat.info

  The Boost License apply to this file, as described in file
  ../LICENSE
*/

alias     IgnoreIndex = bool[size_t];
immutable IgnoreIndex ignore_index_dflt;// empty:compare all values

MatrixT!T subset_row_unique
( bool keep_first = true, T )
( in MatrixT!T m
  , in IgnoreIndex ignore_index = ignore_index_dflt ) @safe
/*
  Returns a new matrix where duplicate rows have been eliminated.
  
  If there are duplicate rows, keep only the last one.
  
  Option: The row comparison can be restricted using `ignore_index`
*/
{
  auto      m_data  = m.data;
  immutable restdim = m.restdim;

  if (m_data.length < 1)
    return m.clone;
  
  size_t[] compare_index_arr;
  foreach(i; 0..restdim)
    {
      if (!(i in ignore_index))
        compare_index_arr ~= i;
    }

  import std.stdio;
  
  auto rowind_app = appender!(size_t[]);

  static if (keep_first)
    rowind_app.put( 0 );
  
  size_t rowind = 0
    , j = 0, next_j = restdim, j_end = m_data.length - restdim;

  auto x = m_data[ 0..next_j ];

  immutable last_rowind = m.nrow - 1;
  
  while (j < j_end)
    {
      size_t next_j2 = next_j + restdim;
      auto   next_x  = m_data[ next_j..next_j2 ];

      bool equal = true;
      foreach (i; compare_index_arr)
        {
          if (x[ i ] != next_x[ i ])
            {
              equal = false;
              break;
            }
        }

      static if (keep_first)
        {
          if (!equal)
            rowind_app.put( rowind + 1 );
        }
      else
        {
          if (!equal)
            rowind_app.put( rowind );
        }
      
      ++rowind;
      j      = next_j;
      next_j = next_j2;
      x      = next_x;
    }

  static if (!keep_first)
    rowind_app.put( last_rowind );
  
  auto ret = subset_row( m, rowind_app.data );
  rowind_app.clear;
  
  return ret;
}
 

unittest  // ------------------------------
{
  import std.stdio;

  writeln;
  writeln( "unittest starts: "~__FILE__ );

  immutable verbose = false;

  import std.algorithm;
  import std.conv;
  import std.datetime;
  import std.file;
  import std.math;

  {
    auto A = Matrix( [ 0, 4 ]
                     , [ 1.0,  3.0, 2.0, 4.0,
                         1.0, -7.0, 2.0, 4.0,
                         2.0,  1.5, 1.0, 0.5,
                         3.0,  4.0, 5.0, 6.0,
                         3.0,  4.0, 5.0, 6.0,
                         ]);

    enum keep_first = true;
    auto B = subset_row_unique// !keep_first  (keep_first: true is the default)
      ( A , [ 1 : true ] );

    if (verbose)
      {
        writeln( "A: ", A );
        writeln( "B: ", B );
      }
    
    assert( B == Matrix( [ 0, 4 ]
                         , [ 1.0,  3.0, 2.0, 4.0,
                             // 1.0, -7.0, 2.0, 4.0,
                            2.0,  1.5, 1.0, 0.5,
                            3.0,  4.0, 5.0, 6.0,
                             // 3.0,  4.0, 5.0, 6.0,
                             ])
            );
  }

  {
    auto A = Matrix( [ 0, 4 ]
                     , [ 1.0,  3.0, 2.0, 4.0,
                         1.0, -7.0, 2.0, 4.0,
                         2.0,  1.5, 1.0, 0.5,
                         3.0,  4.0, 5.0, 6.0,
                         3.0,  4.0, 5.0, 6.0,
                         ]);

    enum keep_first = true;
    auto B = subset_row_unique!keep_first
      ( A , [ 1 : true ] );

    if (verbose)
      {
        writeln( "A: ", A );
        writeln( "B: ", B );
      }
    
    assert( B == Matrix( [ 0, 4 ]
                         , [ 1.0,  3.0, 2.0, 4.0,
                             // 1.0, -7.0, 2.0, 4.0,
                            2.0,  1.5, 1.0, 0.5,
                            3.0,  4.0, 5.0, 6.0,
                             // 3.0,  4.0, 5.0, 6.0,
                             ])
            );
  }

  {
    auto A = Matrix( [ 0, 4 ]
                     , [ 1.0,  3.0, 2.0, 4.0,
                         1.0, -7.0, 2.0, 4.0,
                         2.0,  1.5, 1.0, 0.5,
                         3.0,  4.0, 5.0, 6.0,
                         3.0,  4.0, 5.0, 6.0,
                         ]);

    enum keep_first = false;
    auto B = subset_row_unique!keep_first
      ( A , [ 1 : true ] );

    if (verbose)
      {
        writeln( "A: ", A );
        writeln( "B: ", B );
      }
    
    assert( B == Matrix( [ 0, 4 ]
                         , [ //1.0,  3.0, 2.0, 4.0,
                            1.0, -7.0, 2.0, 4.0,
                            2.0,  1.5, 1.0, 0.5,
                            // 3.0,  4.0, 5.0, 6.0,
                            3.0,  4.0, 5.0, 6.0,
                             ])
            );
  }

  {
    IgnoreIndex ignore_index;
    ignore_index[ 2 ] = true;
    
    auto A = Matrix( [ 0, 8 ]
                     , [
                        1567088100000, 1567088399999, 1567144783000, 4049.5, 4051, 4046.5, 4049, 61064
                        , 1567088100000, 1567088399999, 1567145713000, 4049.5, 4051, 4046.5, 4049, 61064
                        , 1567088100000, 1567088399999, 1567146950000, 4049.5, 4051, 4047, 4049, 61064
                        , 1567088100000, 1567088399999, 1567148130000, 4049.5, 4051, 4047, 4049, 61064
                        , 1567088100000, 1567088399999, 1567156723000, 4049.5, 4051, 4047, 4049, 61064
                        ]);

    enum keep_first = true;
    auto B = subset_row_unique!keep_first( A, ignore_index );

    if (verbose)
      {
        writeln;
        writeln("A: ", A );
        writeln;
        writeln("B: ", B);
      }

    assert( B == Matrix( [ 0, 8 ]
                         , [
                            1567088100000, 1567088399999, 1567144783000, 4049.5, 4051, 4046.5, 4049, 61064
                            , 1567088100000, 1567088399999, 1567146950000, 4049.5, 4051, 4047, 4049, 61064
                            ]
                         ));
  }

  
  {
    IgnoreIndex ignore_index;
    ignore_index[ 2 ] = true;
    
    auto A = Matrix( [ 0, 8 ]
                     , [
                        1567088100000, 1567088399999, 1567144783000, 4049.5, 4051, 4046.5, 4049, 61064
                        , 1567088100000, 1567088399999, 1567145713000, 4049.5, 4051, 4046.5, 4049, 61064
                        , 1567088100000, 1567088399999, 1567146950000, 4049.5, 4051, 4047, 4049, 61064
                        , 1567088100000, 1567088399999, 1567148130000, 4049.5, 4051, 4047, 4049, 61064
                        , 1567088100000, 1567088399999, 1567156723000, 4049.5, 4051, 4047, 4049, 61064
                        ]);

    enum keep_first = false;
    auto B = subset_row_unique!keep_first( A, ignore_index );

    if (verbose)
      {
        writeln;
        writeln("A: ", A );
        writeln;
        writeln("B: ", B);
      }

    assert( B == Matrix( [ 0, 8 ]
                         , [
                            1567088100000, 1567088399999, 1567145713000, 4049.5, 4051, 4046.5, 4049, 61064
                            , 1567088100000, 1567088399999, 1567156723000, 4049.5, 4051, 4047, 4049, 61064
                            ]
                         ));
  }



  {
    IgnoreIndex ignore_index;
    ignore_index[ 2 ] = true;
    
    auto A = Matrix( [ 0, 8 ]
                     , [
                        0, 0, 0, 0, 0, 0, 0, 0
                        , 0, 0, 0, 0, 0, 0, 0, 0
                        , 1567088100000, 1567088399999, 1567144783000, 4049.5, 4051, 4046.5, 4049, 61064
                        , 1567088100000, 1567088399999, 1567145713000, 4049.5, 4051, 4046.5, 4049, 61064
                        , 1567088100000, 1567088399999, 1567146950000, 4049.5, 4051, 4047, 4049, 61064
                        , 1567088100000, 1567088399999, 1567148130000, 4049.5, 4051, 4047, 4049, 61064
                        , 1567088100000, 1567088399999, 1567156723000, 4049.5, 4051, 4047, 4049, 61064
                        , 0, 0, 0, 0, 0, 0, 0, 0
                        ]);

    enum keep_first = true;
    auto B = subset_row_unique!keep_first( A, ignore_index );

    if (verbose)
      {
        writeln;
        writeln("A: ", A );
        writeln;
        writeln("B: ", B);
      }

    assert( B == Matrix( [ 0, 8 ]
                         , [
                            0, 0, 0, 0, 0, 0, 0, 0
                            , 1567088100000, 1567088399999, 1567144783000, 4049.5, 4051, 4046.5, 4049, 61064
                            , 1567088100000, 1567088399999, 1567146950000, 4049.5, 4051, 4047, 4049, 61064
                            , 0, 0, 0, 0, 0, 0, 0, 0
                            ]
                         ));
  }

  
  {
    IgnoreIndex ignore_index;
    ignore_index[ 2 ] = true;
    
    auto A = Matrix( [ 0, 8 ]
                     , [
                        0, 0, 0, 0, 0, 0, 0, 0
                        , 0, 0, 0, 0, 0, 0, 0, 0
                        , 1567088100000, 1567088399999, 1567144783000, 4049.5, 4051, 4046.5, 4049, 61064
                        , 1567088100000, 1567088399999, 1567145713000, 4049.5, 4051, 4046.5, 4049, 61064
                        , 1567088100000, 1567088399999, 1567146950000, 4049.5, 4051, 4047, 4049, 61064
                        , 1567088100000, 1567088399999, 1567148130000, 4049.5, 4051, 4047, 4049, 61064
                        , 1567088100000, 1567088399999, 1567156723000, 4049.5, 4051, 4047, 4049, 61064
                        , 0, 0, 0, 0, 0, 0, 0, 0
                        ]);

    enum keep_first = false;
    auto B = subset_row_unique!keep_first( A, ignore_index );

    if (verbose)
      {
        writeln;
        writeln("A: ", A );
        writeln;
        writeln("B: ", B);
      }

    assert( B == Matrix( [ 0, 8 ]
                         , [
                            0, 0, 0, 0, 0, 0, 0, 0
                            , 1567088100000, 1567088399999, 1567145713000, 4049.5, 4051, 4046.5, 4049, 61064
                            , 1567088100000, 1567088399999, 1567156723000, 4049.5, 4051, 4047, 4049, 61064
                            , 0, 0, 0, 0, 0, 0, 0, 0
                            ]
                         ));
  }

  
  
  writeln( "unittest passed: "~__FILE__ );
}

