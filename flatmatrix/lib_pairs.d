module d_glat.flatmatrix.lib_pairs;

/*
  Compute pairwise differences between point pairs, on each
  dimension of a matrix.
  
  The Boost license applies, as described in ../LICENSE

  by Guillaume Lathoud, 2019
  glat@glat.info
*/

public import d_glat.flatmatrix.core_matrix;

import std.math; // for expstr

alias PairsFunT( T ) = MatrixT!T function( in MatrixT!T );
alias PairsFun       = PairsFunT!double;

MatrixT!T pairs( alias expstr_or_fun, T )
  ( in MatrixT!T m ) pure nothrow @safe
// Functional wrapper around `pairs_inplace`.
{
  
  
  immutable n = m.dim[ 0 ];
  auto ret = MatrixT!T( [ (n*(n-1)) >> 1 ] ~ m.dim[ 1..$ ] );
  pairs_inplace!( expstr_or_fun, T )( m, ret );
  return ret;
}


void pairs_inplace_dim( alias expstr_or_fun, T )
( in ref MatrixT!T m, ref MatrixT!T m_pairdelta )
 pure nothrow @safe
{
  immutable n = m.dim[ 0 ];
  m_pairdelta.setDim( [ (n*(n-1)) >> 1 ] ~ m.dim[ 1..$ ] );
  pairs_inplace!( expstr_or_fun, T )( m, m_pairdelta );
}


alias PairsInplaceFunT( T ) =
  void function( in ref MatrixT!T, ref MatrixT!T );

alias PairsInplaceFun = PairsInplaceFunT!double;

void pairs_inplace( alias expstr_or_fun, T )
  ( in ref MatrixT!T m, ref MatrixT!T m_pairdelta )
  pure nothrow @safe @nogc
/*
  Compute pair-wise "deltas" according to `expstr_or_fun` (e.g. "-" or "(a-b)^^2")
  
  Input: `m` has dimensionality >= 2 and dim = [ n, p, ... ]

  Output: `m_pairs` must have dim = [ n*(n-1)/2, p, ... ] because
  n*(n-1)/2 is the number of pairs.

  Examples: see the unit tests further below.
*/
{
  immutable n = m.dim[ 0 ];
  debug
    {
      immutable n_pair = (n * (n - 1)) >> 1;
      assert( m.dim.length >= 2 );
      assert( m_pairdelta.dim.length >= 2 );
      assert( m_pairdelta.dim[ 0 ] == n_pair );
      assert( m.dim[ 1..$ ] == m_pairdelta.dim[ 1..$ ] );
      assert( m.data.length == m.nrow * m.restdim );
    }

  immutable restdim = m.restdim;

  auto data = m.data;
  auto pairdelta = m_pairdelta.data;

  static immutable bool is_expstr =
    is( typeof(expstr_or_fun) == string )
    || is( typeof(expstr_or_fun) == immutable(string) );


  size_t i = 0;
  immutable i_end = data.length;

  debug assert( i_end == m.nrow * m.restdim );
  
  size_t ipd = 0;
  size_t ipd_next = restdim;

  debug immutable ipd_end = pairdelta.length;

  static if (is_expstr)
    {
      // `iexpstr` case (e.g. shortcuts "+", "-", "*", "/" or expr
      // e.g. "(a-b)^^2")

      static immutable string expstr =
        1 == expstr_or_fun.length
        &&  expstr_or_fun[0] != 'a'
        &&  expstr_or_fun[0] != 'b'
        
        ?  "a"~expstr_or_fun~"b"

        :  expstr_or_fun
        ;
      
      if (1 == restdim)
        {
          // Scalar case: no vector operation needed

          while (i < i_end)
            {
              immutable i_next = i+1;
              auto b = data[ i ];
      
              size_t i2 = i_next;
              while (i2 < i_end)
                {
                  auto a = data[ i2 ];
                  
                  mixin( `pairdelta[ ipd ] = `~expstr~`;` );
                  
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
              
              size_t i2 = i_next;
              while (i2 < i_end)
                {
                  foreach (i_b; i..i_next)
                    {
                      auto a = data[ i2++ ];
                      auto b = data[ i_b ];
                      pairdelta[ ipd++ ] = mixin( expstr );
                    }
                }

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

              expstr_or_fun( data[ i2..i2_next ], v_i
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

  // expstr
  
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

  {
    // 3-D matrix and full expression `a-b`
    auto m = Matrix( [ 4, 2, 2 ], [ 1.0,   10.0,     100.0,  1000.0,
                                    3.0,   30.0,     300.0,  3000.0,
                                    7.0,   70.0,     700.0,  7000.0,
                                    13.0, 130.0,    1300.0, 13000.0,
                                    ] );
    auto m_pairdelta = Matrix( [ 4*3/2, 2, 2 ] );
    pairs_inplace!"a-b"( m, m_pairdelta );

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

  {
    // 3-D matrix and full expression `(a-b)^^2`
    auto m = Matrix( [ 4, 2, 2 ], [ 1.0,   10.0,     100.0,  1000.0,
                                    3.0,   30.0,     300.0,  3000.0,
                                    7.0,   70.0,     700.0,  7000.0,
                                    13.0, 130.0,    1300.0, 13000.0,
                                    ] );
    auto m_pairdelta = Matrix( [ 4*3/2, 2, 2 ] );
    pairs_inplace!"(a-b)^^2"( m, m_pairdelta );

    if (verbose)
      writeln( "m_pairdelta: ", m_pairdelta );
    
    assert( m_pairdelta ==
            Matrix( [ 4*3/2, 2, 2 ]
                    , [ (3.0  - 1.0)^^2,  ( 20.0)^^2,    ( 200.0)^^2,  ( 2000.0)^^2,
                        (7.0  - 1.0)^^2,  ( 60.0)^^2,    ( 600.0)^^2,  ( 6000.0)^^2,
                        (13.0 - 1.0)^^2,  (120.0)^^2,    (1200.0)^^2,  (12000.0)^^2,

                        (7.0  - 3.0)^^2,  ( 40.0)^^2,    ( 400.0)^^2,  ( 4000.0)^^2,
                        (13.0 - 3.0)^^2,  (100.0)^^2,    (1000.0)^^2,  (10000.0)^^2,

                        (13.0 - 7.0)^^2,  ( 60.0)^^2,    ( 600.0)^^2,  ( 6000.0)^^2,
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
