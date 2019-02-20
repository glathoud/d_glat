module d_glat.numeric.core;

import std.algorithm;
import std.stdio;
import std.string;

// See ./README
// Boost license.

immutable double numeric_epsilon = 2.220446049250313e-16;

/*
  Direct operations (ret = f(a,b), a,b,ret all of the same type)
  in octave/matlab: .+ .- .* ./

  Each line creates a pair of functions:
  
  `direct_add(a,b)`,`direct_add_inplace(a,b,ret)`
  `direct_sub(a,b)`,`direct_sub_inplace(a,b,ret)`
  etc.
*/
// ...on vectors
mixin(_direct_code(`direct_add`,`+`,`double[]`));
mixin(_direct_code(`direct_sub`,`-`,`double[]`));
mixin(_direct_code(`direct_mul`,`*`,`double[]`));
mixin(_direct_code(`direct_div`,`/`,`double[]`));
// ...on matrices
mixin(_direct_code(`direct_add`,`+`,`double[][]`));
mixin(_direct_code(`direct_sub`,`-`,`double[][]`));
mixin(_direct_code(`direct_mul`,`*`,`double[][]`));
mixin(_direct_code(`direct_div`,`/`,`double[][]`));


double[][] clone( in double[][] X )
{
  immutable m = X.length;
  immutable n = X[ 0 ].length; 
  auto ret = new double[][]( m, n );

  return clone_inplace( X, ret );
}

double[][] clone_inplace( in double[][] X
                                  , ref double[][] ret
                                  )
{
  debug
    {
      assert( ret.length      == X.length );
      assert( ret[ 0 ].length == X[ 0 ].length );
    }
  
  foreach (i,Xi; X)
    ret[ i ][] = Xi[];

  return ret;
}



double[][] diag( in double[] x )
{
  immutable n = x.length;
  double[][] ret = new double[][]( n, n );
  return diag_inplace( x, ret );
}

double[][] diag_inplace( in double[] x
                                     , ref double[][] ret
                                     )
{
  debug
    {
      assert( x.length == ret.length );
      assert( x.length == ret[ 0 ].length );
    }

  foreach (i,v; x)
    {
      ret[ i ][] = 0.0;
      ret[ i ][ i ] = v;
    }

  return ret;
}





double[][] div( T )( in double[][] X, T s )
// matrix ./ scalar
{
  size_t m = X.length;
  size_t n = X[ 0 ].length;
  double[][] ret = new double[][]( m, n );

  return div_inplace!T( X, s, ret );
}

double[][] div_inplace( T )( in double[][] X, T s
                                     , ref double[][] ret
                                     )
{
  debug
    {
      assert( ret.length      == X.length );
      assert( ret[ 0 ].length == X[ 0 ].length );
    }

  immutable double s_dbl = cast( double )( s );

  foreach (i,row; X)
    ret[ i ][] = row[] / s_dbl;

  return ret;
}





double[] dot( in double[][] X, in double[] y )
// matrix * vector
{
  immutable size_t p = X.length, q = y.length;
  debug assert( X[ 0 ].length == q );

  double[] ret = new double[]( p );

  return dot_inplace( X, y, ret );
}

double[] dot_inplace( in double[][] X, in double[] y
                              , ref double[] ret
                              )
{
  immutable size_t p = X.length, q = y.length;
  debug
    {
      assert( X[ 0 ].length == q );

      assert( ret.length    == p );
    }

  foreach (i; 0..p)
    {
      double acc = 0;
      
      foreach (j,Xij; X[ i ])
        acc += Xij * y[ j ];
      
      ret[ i ] = acc;
    }
  return ret;
}





double[][] dot( in double[][] X, in double[][] Y )
// matrix * matrix
{
  immutable size_t p = X.length, q = Y.length, r = Y[0].length;
  debug assert( X[ 0 ].length == q );

  double[][] ret = new double[][]( p, r );

  return dot_inplace( X, Y, ret );
}

double[][] dot_inplace( in double[][] X, in double[][] Y
                                , ref double[][] ret
                                )
{
  immutable size_t p = X.length, q = Y.length, r = Y[0].length;
  debug
    {
      assert( X[ 0 ].length == q );

      assert( ret.length      == p );
      assert( ret[ 0 ].length == r );
    }

  foreach (i; 0..p)
    {
      auto     Xi   = X[ i ];
      double[] reti = ret[ i ];
      
      foreach (j; 0..r)
        {
          double acc = 0;

          foreach (k; 0..q)
            acc += Xi[ k ] * Y[ k ][ j ];

          reti[ j ] = acc;
        }
    }
  return ret;
}


double[][] rep( in size_t m, in size_t n, in double v )
{
  auto ret = new double[][]( m, n );
  return rep_inplace( m, n, v, ret );
}

double[][] rep_inplace( in size_t m, in size_t n, in double v
                                , ref double[][] ret
                                )
{
  debug
    {
      assert( ret.length      == m );
      assert( ret[ 0 ].length == n );
    }
  
  foreach (reti; ret)
    reti[] = v;
  
  return ret;
}



double[][] transpose( in double[][] A )
{
  double[][] ret = new double[][]( A[ 0 ].length, A.length );
  return transpose_inplace( A, ret );
}

double[][] transpose_inplace( in double[][] A
                                      , ref double[][] ret 
                                      )
{
  debug
    {
      assert( A.length == ret[ 0 ].length );
      assert( A[ 0 ].length == ret.length );
    }

  foreach (i,Ai; A)
    foreach (j,Aij; Ai)
    ret[ j ][ i ] = Aij;
  
  return ret;
}






private: // ------------------------------

string _direct_code( in string fname, in string op, in string type ) pure
// Returns code that declares two functions named `fname` and
// `fname~"_inplace"`.
{
  immutable is_mat = type.endsWith( `[][]` );
  if (is_mat)
    {
      return type~` `~fname~`( in `~type~` A, in `~type~` B )
        {
          `~type~` RET = new `~type~`(A.length, A[0].length);
          return `~fname~`_inplace( A, B, RET );
        }

      `~type~` `~fname~`_inplace( in `~type~` A, in `~type~` B
                                  , ref `~type~` RET
                                  )
        {
          debug
            {
              immutable m = A.length, n = A[ 0 ].length;
              assert( B.length == m );
              assert( B[ 0 ].length == n );
              assert( RET.length == m );
              assert( RET[ 0 ].length == n );
            }

          foreach (i,RETi; RET)
            RETi[] = A[ i ][] `~op~` B[ i ][];
          
          return RET;
        }
      `;      
    }
  else
    {
      return type~` `~fname~`( in `~type~` a, in `~type~` b )
        {
          `~type~` ret = new `~type~`(a.length);
          return `~fname~`_inplace( a, b, ret );
        }

      `~type~` `~fname~`_inplace( in `~type~` a, in `~type~` b
                                  , ref `~type~` ret
                                  )
        {
          debug
            {
              immutable dim = a.length;
              assert( b.length == dim );
              assert( ret.length == dim );
            }

          ret[] = a[] `~op~` b[];

          return ret;
        }
      `;
    }
}





unittest  // ------------------------------
{
  import std.stdio;

  writeln;
  writeln( "unittest starts: "~__FILE__ );

  assert( diag( [ 1.0, 2.0, 3.0, 4.0 ] )
          == [
              [ 1.0, 0.0, 0.0, 0.0 ],
              [ 0.0, 2.0, 0.0, 0.0 ],
              [ 0.0, 0.0, 3.0, 0.0 ],
              [ 0.0, 0.0, 0.0, 4.0 ]
              ]
          );

  
  assert( rep( 3, 4, 1.234 )
          == [
              [ 1.234, 1.234, 1.234, 1.234 ]
              , [ 1.234, 1.234, 1.234, 1.234 ]
              , [ 1.234, 1.234, 1.234, 1.234 ]
              ]
          );

  {
    auto m = [ [ 1.0, 2.0, 3.0 ],
               [ 4.0, 5.0, 6.0 ]
               ];

    auto v = [ 10.0, 100.0, 1000.0 ];
    
    assert( dot( m, v )
            == [ 3210.0, 6540.0 ] );
  }

  {
    auto ma = [ [ 1.0, 2.0, 3.0 ],
               [ 4.0, 5.0, 6.0 ]
               ];

    auto mb = [ [ 1e1, 1e2, 1e3, 1e4 ],
                [ 1e5, 1e6, 1e7, 1e8 ],
                [ 1e9, 1e10, 1e11, 1e12 ]
                ];

    assert( dot( ma, mb )
            == [
                [ 3000200010.0, 30002000100.0, 300020001000.0, 3000200010000.0 ],
                [ 6000500040.0, 60005000400.0, 600050004000.0, 6000500040000.0 ]
                ]
            );
  }

  {
    auto m = [ [ 10.0, 20.0, 30.0 ],
               [ 40.0, 50.0, 60.0 ]
               ];

    assert( div( m, 10.0 )
            == [ [ 1.0, 2.0, 3.0 ],
                 [ 4.0, 5.0, 6.0 ]
                 ]
            );
  }

  {
    auto va = [ 1.0, 2.0, 3.0, 4.0 ];
    auto vb = [ 10.0, 100.0, 1000.0, 10000.0 ];

    assert( direct_add( va, vb )
            == [ 11.0, 102.0, 1003.0, 10004.0 ]
            );

    assert( direct_sub( va, vb )
            == [ -9.0, -98.0, -997.0, -9996.0 ]
            );

    assert( direct_mul( va, vb )
            == [ 10.0, 200.0, 3000.0, 40000.0 ]
            );

    assert( direct_div( vb, va )
            == [ 10.0, 50.0, 1000.0/3.0, 2500.0 ]
            );
  }
  
  {
    auto A = [ [ 1.0, 2.0 ], [ 3.0, 4.0 ] ];
    auto B = [ [ 10.0, 100.0], [ 1000.0, 10000.0 ] ];

    assert( direct_add( A, B )
            == [ [ 11.0, 102.0], [ 1003.0, 10004.0 ] ]
            );

    assert( direct_sub( A, B )
            == [ [ -9.0, -98.0], [ -997.0, -9996.0 ] ]
            );

    assert( direct_mul( A, B )
            == [ [ 10.0, 200.0], [ 3000.0, 40000.0 ] ]
            );

    assert( direct_div( B, A )
            == [ [ 10.0, 50.0], [ 1000.0/3.0, 2500.0 ] ]
            );
  }


  {
    auto A = [ [ 1.0, 2.0, 3.0 ],
               [ 4.0, 5.0, 6.0 ] ];

    assert( transpose( A )
            == [ [ 1.0, 4.0 ],
                 [ 2.0, 5.0 ],
                 [ 3.0, 6.0 ] ] );
  } 

  
  writeln( "unittest passed: "~__FILE__ );
}
