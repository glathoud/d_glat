module d_glat.flatmatrix.lib_pairs;

public import d_glat.flatmatrix.core_matrix;

/*
  The Boost license applies, as described in ./LICENSE

  by Guillaume Lathoud, 2019
  glat@glat.info
*/

void pairs( alias opstr_or_fun, T )
  ( in Matrix!T m ) pure nothrow @safe
// Functional wrapper around `pairs_inplace`.
{
  pragma( inline, true );
  
  immutable n = m.dim[ 0 ];
  auto ret = Matrix( [ (n*(n-1)) >> 1 ] ~ m.dim[ 1..$ ] );
  pairs_inplace!( opstr_or_fun, T )( m, ret );
  return ret;
}

void pairs_inplace( alias opstr_or_fun, T )
  ( in ref MatrixT!T m, ref MatrixT!T m_pairdelta )
  pure nothrow @safe @nogc
/*
  Compute pair-wise "deltas" according to `opstr_or_fun` (e.g. "-")
  
  Input: `m` has dimensionality >= 2 and dim = [ n, p, ... ]

  Output: `m_pairs` must have dim = [ n*(n-1)/2, p, ... ] because
  n*(n-1)/2 is the number of pairs.

  Examples: see the unit tests further below.
*/
{
  pragma( inline, true );
  
  immutable n = m.dim[ 0 ];
  debug
    {
      immutable n_pair = (n * (n - 1)) >> 1;
      assert( m.dim.length >= 2 );
      assert( m_pairdelta.dim.length >= 2 );
      assert( m_pairdelta.dim[ 0 ] == n_pair );
      assert( m.dim[ 1..$ ] == m_pairdelta.dim[ 1..$ ] );
    }

  immutable restdim = m.restdim;

  auto data = m.data;
  auto pairdelta = m_pairdelta.data;

  static immutable bool is_opstr = typeof(opstr_or_fun).stringof == "string";
  // xxx add impl for special case restdim == 1 and op string

  size_t i = 0;
  immutable i_end = data.length;
    
  size_t ipd = 0;
  size_t ipd_next = restdim;

  debug immutable ipd_end = pairdelta.length;


  static if (is_opstr)
    {
      // `iopstr` case (e.g. "+", "-", "*", "/")

      if (1 == restdim)
        {
          // Scalar case: no vector operation needed

          while (i < i_end)
            {
              immutable i_next = i+1;
              auto x_i = data[ i ];
      
              size_t i2 = i_next;
              while (i2 < i_end)
                {
                  mixin
                    (
                     `pairdelta[ ipd ] = 
                     data[ i2 ] `
                     ~opstr_or_fun~
                     ` x_i;`
                     );
              
                  ipd       = ipd_next;
                  ipd_next++;
          
                  i2++;
                }

              debug assert( i2 == i_end );

              i = i_next;
            }
        }
      else
        {
          // Vector case

          while (i < i_end)
            {
              immutable i_next = i + restdim;
              
              auto v_i = data[ i..i_next ];
              
              size_t i2 = i_next;
              while (i2 < i_end)
                {
                  immutable i2_next = i2 + restdim;
                  
                  mixin
                    (
                     `pairdelta[ ipd..ipd_next ][] = 
                     data[ i2..i2_next ][] `
                     ~opstr_or_fun~
                     ` v_i[];`
                     );
              
                  ipd       = ipd_next;
                  ipd_next += restdim;
          
                  i2 = i2_next;
                }

              debug assert( i2 == i_end );

              i = i_next;
            }
        }
    }
  else
    {
      // `fun` case (void ( in double[], in double[], double[]))
      
      while (i < i_end)
        {
          immutable i_next = i + restdim;

          auto v_i = data[ i..i_next ];
      
          size_t i2 = i_next;
          while (i2 < i_end)
            {
              immutable i2_next = i2 + restdim;

              opstr_or_fun( data[ i2..i2_next ], v_i
                            , pairdelta[ ipd..ipd_next ]
                            );
              
              ipd       = ipd_next;
              ipd_next += restdim;
          
              i2 = i2_next;
            }

          debug assert( i2 == i_end );

          i = i_next;
        }
    }
  
  debug assert( i == i_end );
  
  debug assert( ipd == ipd_end );
}


unittest
{
  import std.stdio;

  import std.algorithm;
  import std.array;
  import std.range;
  import std.stdio;

  immutable verbose = false;
  
  writeln;
  writeln( "unittest starts: "~__FILE__ );

  // opstr
  
  {
    auto m = Matrix( [ 4, 1 ], [ 1.0,
                                 3.0,
                                 7.0,
                                 13.0
                                 ] );
    auto m_pairdelta = Matrix( [ 4*3/2, 1 ] );
    pairs_inplace!"-"( m, m_pairdelta );

    if (verbose)
      writeln( "m_pairdelta: ", m_pairdelta );
    
    assert( m_pairdelta ==
            Matrix( [ 4*3/2, 1 ], [ 3.0  - 1.0,
                                    7.0  - 1.0,
                                    13.0 - 1.0,
                                    
                                    7.0  - 3.0,
                                    13.0 - 3.0,
                                    
                                    13.0 - 7.0 ] ) );
  }

  {
    auto m = Matrix( [ 4, 3 ], [ 1.0,   10.0,  100.0,
                                 3.0,   30.0,  300.0,
                                 7.0,   70.0,  700.0,
                                 13.0, 130.0, 1300.0,
                                 ] );
    auto m_pairdelta = Matrix( [ 4*3/2, 3 ] );
    pairs_inplace!"-"( m, m_pairdelta );

    if (verbose)
      writeln( "m_pairdelta: ", m_pairdelta );
    
    assert( m_pairdelta ==
            Matrix( [ 4*3/2, 3 ]
                    , [ 3.0  - 1.0,   20.0,  200.0,
                        7.0  - 1.0,   60.0,  600.0,
                        13.0 - 1.0,  120.0, 1200.0,
                        
                        7.0  - 3.0,   40.0,  400.0,
                        13.0 - 3.0,  100.0, 1000.0,
                        
                        13.0 - 7.0,   60.0,  600.0, ] ) );
  }

  {
    // 3-D matrix
    auto m = Matrix( [ 4, 2, 2 ], [ 1.0,   10.0,     100.0,  1000.0,
                                    3.0,   30.0,     300.0,  3000.0,
                                    7.0,   70.0,     700.0,  7000.0,
                                    13.0, 130.0,    1300.0, 13000.0,
                                    ] );
    auto m_pairdelta = Matrix( [ 4*3/2, 2, 2 ] );
    pairs_inplace!"-"( m, m_pairdelta );

    if (verbose)
      writeln( "m_pairdelta: ", m_pairdelta );
    
    assert( m_pairdelta ==
            Matrix( [ 4*3/2, 2, 2 ]
                    , [ 3.0  - 1.0,   20.0,     200.0,   2000.0,
                        7.0  - 1.0,   60.0,     600.0,   6000.0,
                        13.0 - 1.0,  120.0,    1200.0,  12000.0,
                                                              
                        7.0  - 3.0,   40.0,     400.0,   4000.0,
                        13.0 - 3.0,  100.0,    1000.0,  10000.0,
                                                              
                        13.0 - 7.0,   60.0,     600.0,   6000.0,
                        ] ) );
  }


  
  // fun
  
  void v_sub( in double[] a, in double[] b, double[] c )
  {
    c[] = a[] - b[];
  }
  
  {
    auto m = Matrix( [ 4, 1 ], [ 1.0,
                                 3.0,
                                 7.0,
                                 13.0
                                 ] );
    auto m_pairdelta = Matrix( [ 4*3/2, 1 ] );

    void fun( in double[] a, in double[] b, double[] c )
    {
      c[] = a[] - b[];
    }

    pairs_inplace!v_sub( m, m_pairdelta );

    if (verbose)
      writeln( "m_pairdelta: ", m_pairdelta );
    
    assert( m_pairdelta ==
            Matrix( [ 4*3/2, 1 ], [ 3.0  - 1.0,
                                    7.0  - 1.0,
                                    13.0 - 1.0,
                                    
                                    7.0  - 3.0,
                                    13.0 - 3.0,
                                    
                                    13.0 - 7.0 ] ) );
  }

  {
    auto m = Matrix( [ 4, 3 ], [ 1.0,   10.0,  100.0,
                                 3.0,   30.0,  300.0,
                                 7.0,   70.0,  700.0,
                                 13.0, 130.0, 1300.0,
                                 ] );
    auto m_pairdelta = Matrix( [ 4*3/2, 3 ] );

    pairs_inplace!v_sub( m, m_pairdelta );

    if (verbose)
      writeln( "m_pairdelta: ", m_pairdelta );
    
    assert( m_pairdelta ==
            Matrix( [ 4*3/2, 3 ]
                    , [ 3.0  - 1.0,   20.0,  200.0,
                        7.0  - 1.0,   60.0,  600.0,
                        13.0 - 1.0,  120.0, 1200.0,
                        
                        7.0  - 3.0,   40.0,  400.0,
                        13.0 - 3.0,  100.0, 1000.0,
                        
                        13.0 - 7.0,   60.0,  600.0, ] ) );
  }

  {
    // 3-D matrix
    auto m = Matrix( [ 4, 2, 2 ], [ 1.0,   10.0,     100.0,  1000.0,
                                    3.0,   30.0,     300.0,  3000.0,
                                    7.0,   70.0,     700.0,  7000.0,
                                    13.0, 130.0,    1300.0, 13000.0,
                                    ] );
    auto m_pairdelta = Matrix( [ 4*3/2, 2, 2 ] );
    pairs_inplace!v_sub( m, m_pairdelta );

    if (verbose)
      writeln( "m_pairdelta: ", m_pairdelta );
    
    assert( m_pairdelta ==
            Matrix( [ 4*3/2, 2, 2 ]
                    , [ 3.0  - 1.0,   20.0,     200.0,   2000.0,
                        7.0  - 1.0,   60.0,     600.0,   6000.0,
                        13.0 - 1.0,  120.0,    1200.0,  12000.0,
                                                              
                        7.0  - 3.0,   40.0,     400.0,   4000.0,
                        13.0 - 3.0,  100.0,    1000.0,  10000.0,
                                                              
                        13.0 - 7.0,   60.0,     600.0,   6000.0,
                        ] ) );
  }

  
  writeln( "unittest passed: "~__FILE__ );
}
