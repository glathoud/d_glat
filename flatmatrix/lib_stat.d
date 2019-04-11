module d_glat.flatmatrix.lib_stat;

/*
  A few statistics, like mean and variance.

  Used e.g. by ./lib_nmv.d

  By Guillaume Lathoud, 2019
  glat@glat.info

  The Boost License applies, as described in file ../LICENSE
 */

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


void mean_cov_inplace_dim( bool unbiased = true, T )
  ( in ref MatrixT!T m
    , ref MatrixT!T m_mean
    , ref MatrixT!T m_cov )
pure nothrow @safe
{
  pragma( inline, true );

  m_mean.setDim( [ 1UL ] ~ m.dim[ 1..$ ] );
  m_cov .setDim( [ m.restdim ] ~ m.dim[ 1..$ ] );
  mean_cov_inplace!( unbiased, T )( m, m_mean, m_cov );
}

void mean_cov_inplace( bool unbiased = true, T )
  ( in ref MatrixT!T m
    , ref MatrixT!T m_mean
    , ref MatrixT!T m_cov )
pure nothrow @safe @nogc
{
  pragma( inline, true );

  debug
    {
      assert( m_mean.dim[ 0 ] == 1 );
      assert( m_mean.dim[ 1..$ ] == m.dim[ 1..$ ] );

      assert( m_cov.dim[ 0 ] == m.restdim );
      assert( m_cov.dim[ 1..$ ] == m.dim[ 1..$ ] );
    }

  immutable n  = m.data.length;
  immutable nv = m.dim[ 0 ];
  immutable rd = m.restdim;

  debug assert( n > 1 );

  auto m_data    = m.data;
  auto mean_data = m_mean.data;
  auto cov_data  = m_cov.data;

  mean_data[] = cast( T )( 0.0 );
  cov_data[]  = cast( T )( 0.0 );

  for (size_t im = 0; im < n; )
    {
      immutable next_im = im + rd;

      size_t i_mean  = 0;
      size_t off_cov = 0;
      
      while (im < next_im)
        {
          immutable vi = m_data[ im ];
          
          mean_data[ i_mean ] += vi;

          {
            size_t jm = im;
            foreach (k; i_mean..rd)
              cov_data[ off_cov + k ] += vi * m_data[ jm++ ];

            debug assert( jm == next_im );
          }
          
          ++im;
          ++i_mean;
          off_cov += rd;
        }

      debug assert( im == next_im );
      debug assert( i_mean == rd );
      debug assert( off_cov == cov_data.length );
    }

  immutable double nv_dbl = cast( double )( nv );
  mean_data[] /= nv_dbl;
  
  immutable double r_cov = mixin((){
      if (unbiased)
        return `1.0 / (nv_dbl - 1.0)`;
      else
        return `1.0 / nv_dbl`;
    }());

  size_t offset = 0;
  foreach (i; 0..rd)
    {
      offset += i;
      
      foreach (j; i..rd)
        {
          debug assert( offset == i * rd + j );
          
          auto x
            = cov_data[ offset ]
            = r_cov *
            (cov_data[ offset ]
             - nv_dbl *  mean_data[ i ] * mean_data[ j ]);
          
          if (i < j)
            cov_data[ j * rd + i ] = x;
          
          ++offset;
        }
    }
  debug assert( offset == rd*rd );
}


void mean_var_inplace_dim
( bool unbiased = true, T )
  ( in ref MatrixT!T m
    , ref MatrixT!T m_mean
    , ref MatrixT!T m_var
    )
  pure nothrow @safe
{
  pragma( inline, true );

  auto mv_dim = [ 1UL ] ~ m.dim[ 1..$ ];
  m_mean.setDim( mv_dim );
  m_var .setDim( mv_dim );
  mean_var_inplace!( unbiased, T )( m, m_mean, m_var );
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

  import std.exception;
  import std.math;
  
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
    auto m = Matrix( [ 0, 4 ]
                     , [ 9.123,    543.543, 234.2,  34.213,
                         1.231,   -4.435, 5.4353, 7.56867,
                         -3.54,   3543.534, 21.2134, 9.123,
                         -10.432, -3.432, 25.543, 80.345,
                         +1.42,   +654.45, -32.432, -123.432,
                         +78.432, +12.123, -123.5435, -87.43
                         ] );

    Matrix m_mean, m_cov;

    mean_cov_inplace_dim( m, m_mean, m_cov );

    /*
      octave

m = [ 9.123,    543.543, 234.2,  34.213;
1.231,   -4.435, 5.4353, 7.56867;
-3.54,   3543.534, 21.2134, 9.123;
-10.432, -3.432, 25.543, 80.345;
+1.42,   +654.45, -32.432, -123.432;
+78.432, +12.123, -123.5435, -87.43
];

sprintf("%.12g ", mean(m))
# 12.7056666667 790.963833333 21.7360333333 -13.2687216667

sprintf("%.12g ",cov(m))
# 1078.21878907 -13194.6422333 -1918.22091097 -1314.01354014 -13194.6422333 1905362.54113 15295.8135786 6349.01473539 -1918.22091097 15295.8135786 13892.3471641 5366.92317258 -1314.01354014 6349.01473539 5366.92317258 5917.89439291
*/
    
    immutable double[] mean_truth =
      [ 12.705666666666666, 790.9638333333332, 21.736033333333335, -13.26872166666667 ];
    
    immutable double[] cov_truth = [1078.21878907, -13194.6422333, -1918.22091097, -1314.01354014, -13194.6422333, 1905362.54113, 15295.8135786, 6349.01473539, -1918.22091097, 15295.8135786, 13892.3471641, 5366.92317258, -1314.01354014, 6349.01473539, 5366.92317258, 5917.89439291 ];

    if (verbose)
      {
        writeln( "m_mean.data ", m_mean.data );
        writeln( "mean_truth: ", mean_truth );
      }
    
    assert( approxEqual( m_mean.data, mean_truth, 1e-10, 1e-10 ) );

    if (verbose)
      {
        writeln( "m_cov.data: ", m_cov.data );
        writeln( "cov_truth:  ", cov_truth);
      }
    
    assert( approxEqual( m_cov .data,  cov_truth, 1e-10, 1e-10 ) );
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
