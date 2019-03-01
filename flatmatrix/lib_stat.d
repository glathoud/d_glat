module d_glat.flatmatrix.lib_stat;

public import d_glat.flatmatrix.core_matrix;

import d_glat.core_static;

void mean_inplace( T )( in ref MatrixT!T m
                        , ref MatrixT!T m_mean )
pure nothrow @safe @nogc
{
  pragma( inline, true );
  
  debug
    {
      assert( m_mean.dim[ 0 ] == 1 );
      assert( m_mean.dim[ 1..$ ] == m.dim[ 1..$ ] );
    }

  immutable i_step = m.restdim;
  
  auto data = m.data;
  auto mean = m_mean.data;

  size_t i = i_step;
  mean[] = data[ 0..i ][];

  immutable i_end = data.length;
  while (i < i_end)
    {
      size_t i_next = i + i_step;
      mean[] += data[ i..i_next ];
      i = i_next;
    }

  debug assert( i == i_end );
  debug assert( 0 == i_end % i_step );

  mean[] /= cast( T )( i_end / i_step );
}

void mean_var_inplace
( bool unbiased = true, T )
  ( in ref MatrixT!T m
    , ref MatrixT!T m_mean
    , ref MatrixT!T m_var
    )
  pure nothrow @safe @nogc
{
  pragma( inline, true );

  debug
    {
      assert( m_mean.dim[ 0 ] == 1 );
      assert( m_mean.dim[ 1..$ ] == m.dim[ 1..$ ] );
      assert( m_var.dim[ 0 ] == 1 );
      assert( m_var.dim[ 1..$ ] == m.dim[ 1..$ ] );
    }

  mean_inplace( m, m_mean );
  
  auto data = m.data;
  auto mean = m_mean.data;
  auto var  = m_var .data;

  var[] = 0;

  size_t i = 0;
  immutable i_end = data.length;
  immutable i_step = mean.length;

  while (i < i_end)
    {
      size_t i_next = i + i_step;

      size_t j = 0;
      while (i < i_next)
        {
          double tmp = data[ i++ ] - mean[ j ];
          var[ j++ ] += tmp*tmp;
        }
    }
  
  static if (unbiased)
    var[] /= cast( double )( m.dim[ 0 ] - 1 );
  else
    var[] /= cast( double )( m.dim[ 0 ] );
}


void var_inplace( T )( in ref MatrixT!T m,  ref MatrixT!T m_var )
  /*!pure*/ nothrow @safe /*!@nogc*/
{
  static MatrixT!T m_mean;
  m_mean.setDim( m_var.dim );

  mean_var_inplace!T( m, m_mean, m_var );
}





unittest // ------------------------------
{
  import std.stdio;

  immutable verbose = false;
  
  writeln;
  writeln( "unittest starts: "~__FILE__ );

  {
    auto m = Matrix( [0, 2, 2]
                     , [ 1.0, 10.0,  100.0,  1000.0,
                         2.0, 30.0,  400.0,  5000.0,
                         3.0, 60.0,  800.0, 10000.0,
                         ]);
    auto m_mean = Matrix( [1, 2, 2] );
    mean_inplace( m, m_mean );

    if (verbose)  writeln( "m: ", m );
    if (verbose)  writeln( "m_mean: ", m_mean );

    auto expected = Matrix
      ( [1, 2, 2]
        , [ 6.0/3.0,  100.0/3.0,
            1300.0/3.0, 16000.0/3.0 ]
        );

    assert( m_mean.approxEqual( expected, 1e-5 ) );
  }

  
  {
    auto m = Matrix( [0, 2, 2]
                     , [ 1.0, 10.0,  100.0,  1000.0,
                         2.0, 30.0,  400.0,  5000.0,
                         3.0, 60.0,  800.0, 10000.0,
                         ]);
    auto m_mean = Matrix( [1, 2, 2] );
    auto m_var  = Matrix( [1, 2, 2] );
    mean_var_inplace( m, m_mean, m_var );

    if (verbose)  writeln( "m: ", m );
    if (verbose)  writeln( "m_mean: ", m_mean );

    auto expected_mean = Matrix
      ( [1, 2, 2]
        , [ 6.0/3.0,  100.0/3.0,
            1300.0/3.0, 16000.0/3.0 ]
        );

    assert( m_mean.approxEqual( expected_mean, 1e-5 ) );

    import std.algorithm;
    
    double var_u( in double[] arr, in double mean )
    {
      double acc = 0;
      foreach (x; arr)
        {
          double tmp = x - mean;
          acc += tmp * tmp;
        }
      return acc / (cast( double )( arr.length - 1 ));
    }
    
    auto expected_var = Matrix
      ( [1, 2, 2]
        , [ var_u( [ 1.0, 2.0, 3.0 ], 6.0/3.0 ),
            var_u( [ 10.0, 30.0, 60.0 ], 100.0/3.0 ),
            var_u( [ 100.0, 400.0, 800.0 ],  1300.0/3.0),
            var_u( [ 1000.0, 5000.0, 10000.0 ], 16000.0/3.0 )
            ]
        );

    if (verbose)
      {
        writeln( "m_var: ", m_var );
        writeln( "expected_var: ", expected_var );
      }



    mean_var_inplace!( /*unbiased:*/false )( m, m_mean, m_var );
    
    double var_2( in double[] arr, in double mean )
    {
      double acc = 0;
      foreach (x; arr)
        {
          double tmp = x - mean;
          acc += tmp * tmp;
        }
      return acc / (cast( double )( arr.length));
    }
    
    auto expected_var2 = Matrix
      ( [1, 2, 2]
        , [ var_2( [ 1.0, 2.0, 3.0 ], 6.0/3.0 ),
            var_2( [ 10.0, 30.0, 60.0 ], 100.0/3.0 ),
            var_2( [ 100.0, 400.0, 800.0 ],  1300.0/3.0),
            var_2( [ 1000.0, 5000.0, 10000.0 ], 16000.0/3.0 )
            ]
        );

    if (verbose)
      {
        writeln( "m_var: ", m_var );
        writeln( "expected_var2: ", expected_var2 );
      }

    assert( m_var.approxEqual( expected_var2, 1e-5 ) );

  }

  
  writeln( "unittest passed: "~__FILE__ );
}
