module d_glat.flatmatrix.lib_stat;

/*
  A few statistics, like mean, variance, and covariance matrix.

  Used e.g. by ./lib_nmv.d

  By Guillaume Lathoud, 2019
  glat@glat.info

  The Boost License applies, as described in file ../LICENSE
 */

public import d_glat.flatmatrix.core_matrix;

import std.math : sqrt;

void mean_inplace_nogc( T )( in ref MatrixT!T m
                             , ref MatrixT!T m_mean )
  pure nothrow @safe @nogc
{
  
  
  debug
    {
      assert( m_mean.dim[ 0 ] == 1 );
      assert( m_mean.dim[ 1..$ ] == m.dim[ 1..$ ] );
    }

  immutable i_step = m.restdim;
  
  scope auto data = m.data;
  scope auto mean = m_mean.data;

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





void mean_cov_crosscorr_inplace_dim( bool unbiased = true, bool diag_only = false, T )
  ( in ref MatrixT!T m
    , ref MatrixT!T m_mean
    , ref MatrixT!T m_cov
    , ref MatrixT!T m_crosscorr
    )
pure nothrow @safe
// https://en.wikipedia.org/wiki/Covariance_and_correlation
{
  m_mean.setDim( [ 1UL ] ~ m.dim[ 1..$ ] );
  m_cov .setDim( [ m.restdim ] ~ m.dim[ 1..$ ] );
  m_crosscorr.setDim( m_cov.dim );
  mean_cov_crosscorr_inplace_nogc!( unbiased, diag_only, T )( m, m_mean, m_cov, m_crosscorr );
}


void mean_cov_crosscorr_inplace_nogc( bool unbiased = true, bool diag_only = false, T )
  ( in ref MatrixT!T m
    , ref MatrixT!T m_mean
    , ref MatrixT!T m_cov
    , ref MatrixT!T m_crosscorr
    )
pure nothrow @safe @nogc
// https://en.wikipedia.org/wiki/Covariance_and_correlation
{
  debug
    {
      assert( m_mean.dim[ 0 ] == 1 );
      assert( m_mean.dim[ 1..$ ] == m.dim[ 1..$ ] );

      assert( m_cov.dim[ 0 ] == m.restdim );
      assert( m_cov.dim[ 1..$ ] == m.dim[ 1..$ ] );

      assert( m_crosscorr.dim[ 0 ] == m.restdim );
      assert( m_crosscorr.dim[ 1..$ ] == m.dim[ 1..$ ] );
    }

  mean_cov_inplace_nogc( m, m_mean, m_cov );

  m_crosscorr.data[] = m_cov.data[];
  
  immutable rd = m.restdim;
  
  auto cov_data = m_cov.data;
  auto cc_data  = m_crosscorr.data;
  
  foreach (i; 0..rd)
    {
      immutable diag_ind = i*(rd+1);
      immutable var_i = cov_data[ diag_ind ];
      cc_data[ diag_ind ] /= var_i;

      static if (!diag_only)
        {
          immutable std_i = sqrt( var_i );
          
          foreach (j; (i+1)..rd)
            cc_data[ j*rd + i ] = (cc_data[ i*rd + j ] /= (std_i * sqrt( cov_data[ j*(rd+1) ] ) ));
        }
    }
}


void mean_cov_inplace_dim( bool unbiased = true, bool diag_only = false, T )
  ( in ref MatrixT!T m
    , ref MatrixT!T m_mean
    , ref MatrixT!T m_cov
    )
pure nothrow @safe
{
  m_mean.setDim( [ 1UL ] ~ m.dim[ 1..$ ] );
  m_cov .setDim( [ m.restdim ] ~ m.dim[ 1..$ ] );
  mean_cov_inplace_nogc!( unbiased, diag_only, T )( m, m_mean, m_cov );
}

void mean_cov_inplace_nogc( bool unbiased = true, bool diag_only = false, T )
  ( in ref MatrixT!T m
    , ref MatrixT!T m_mean
    , ref MatrixT!T m_cov
    )
pure nothrow @safe @nogc
{
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

  scope auto m_data    = m.data;
  scope auto mean_data = m_mean.data;
  scope auto cov_data  = m_cov.data;

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

          static if (diag_only)
            {
              cov_data[ off_cov + i_mean ] += vi * m_data[ im ];
            }
          else
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
          
          static if (diag_only)
            {
              offset += rd-i;
              break;
            }
          else
            {
              if (i < j)
                cov_data[ j * rd + i ] = x;
              
              ++offset;
            }
        }
    }
  debug assert( offset == rd*rd );
}



void mean_cov_inplace_dim( bool unbiased = true, bool diag_only = false, T )
  ( in ref MatrixT!T m
    , in size_t[] subset
    , ref MatrixT!T m_mean
    , ref MatrixT!T m_cov )
pure nothrow @safe
{
  m_mean.setDim( [ 1UL ] ~ m.dim[ 1..$ ] );
  m_cov .setDim( [ m.restdim ] ~ m.dim[ 1..$ ] );
  mean_cov_inplace_nogc!( unbiased, diag_only, T )( m, subset, m_mean, m_cov );
}

void mean_cov_inplace_nogc( bool unbiased = true, bool diag_only = false, T )
  ( in ref MatrixT!T m
    , in size_t[] subset
    , ref MatrixT!T m_mean
    , ref MatrixT!T m_cov )
pure nothrow @safe @nogc
{
  debug
    {
      assert( m_mean.dim[ 0 ] == 1 );
      assert( m_mean.dim[ 1..$ ] == m.dim[ 1..$ ] );

      assert( m_cov.dim[ 0 ] == m.restdim );
      assert( m_cov.dim[ 1..$ ] == m.dim[ 1..$ ] );

      foreach (i; subset)
        assert( 0 <= i  &&  i < m.dim[ 0 ] );
    }

  immutable n  = m.data.length;
  immutable nv = subset.length;
  immutable rd = m.restdim;

  debug assert( n > 1 );

  scope auto m_data    = m.data;
  scope auto mean_data = m_mean.data;
  scope auto cov_data  = m_cov.data;

  mean_data[] = cast( T )( 0.0 );
  cov_data[]  = cast( T )( 0.0 );

  foreach (iss; subset)
    {
      size_t         im = iss * rd;
      immutable next_im = im + rd;

      size_t i_mean  = 0;
      size_t off_cov = 0;
      
      while (im < next_im)
        {
          immutable vi = m_data[ im ];
          
          mean_data[ i_mean ] += vi;

          static if (diag_only)
            {
              cov_data[ off_cov + i_mean ] += vi * m_data[ im ];
            }
          else
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
          
          static if (diag_only)
            {
              offset += rd-i;
              break;
            }
          else
            {
              if (i < j)
                cov_data[ j * rd + i ] = x;
              
              ++offset;
            }
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
  auto mv_dim = [ 1UL ] ~ m.dim[ 1..$ ];
  m_mean.setDim( mv_dim );
  m_var .setDim( mv_dim );
  mean_var_inplace_nogc!( unbiased, T )( m, m_mean, m_var );
}

void mean_var_inplace_nogc
( bool unbiased = true, T )
  ( in ref MatrixT!T m
    , ref MatrixT!T m_mean
    , ref MatrixT!T m_var
    )
  pure nothrow @safe @nogc
{
  debug
    {
      assert( m_mean.dim[ 0 ] == 1 );
      assert( m_mean.dim[ 1..$ ] == m.dim[ 1..$ ] );
      assert( m_var.dim[ 0 ] == 1 );
      assert( m_var.dim[ 1..$ ] == m.dim[ 1..$ ] );
    }

  mean_inplace_nogc( m, m_mean );
  
  scope auto data = m.data;
  scope auto mean = m_mean.data;
  scope auto var  = m_var .data;

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
    mean_inplace_nogc( m, m_mean );

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
    
    assert( isClose( m_mean.data, mean_truth, 1e-10, 1e-10 ) );

    if (verbose)
      {
        writeln( "m_cov.data: ", m_cov.data );
        writeln( "cov_truth:  ", cov_truth);
      }
    
    assert( isClose( m_cov .data,  cov_truth, 1e-10, 1e-10 ) );


    {
      // diag_only variant

    Matrix m_mean2, m_cov2;

    mean_cov_inplace_dim!(/*unbiased:*/true, /*diag_only:*/true)( m, m_mean2, m_cov2 );

    auto mean_truth2 = mean_truth;
    
    immutable double[] cov_truth2 = assumeUnique
      ( () {

        auto tmp = new double[ cov_truth.length ];
        tmp[] = 0.0;

        immutable rd = m.restdim;
        for (size_t i = 0; i < tmp.length; i += rd+1)
          tmp[ i ] = cov_truth[ i ];

        return tmp;
      } () );

    if (verbose)
      {
        writeln( "m_mean2.data ", m_mean2.data );
        writeln( "mean_truth2: ", mean_truth2 );
      }
    
    assert( isClose( m_mean2.data, mean_truth2, 1e-10, 1e-10 ) );

    if (verbose)
      {
        writeln( "m_cov2.data: ", m_cov2.data );
        writeln( "cov_truth2:  ", cov_truth2);
      }
    
    assert( isClose( m_cov2 .data,  cov_truth2, 1e-10, 1e-10 ) );
    
    }
  }

  
  
  {
    if (verbose)
      writeln("---------- Test mean_cov with subset");

    auto nan = double.nan;
    auto m = Matrix( [ 0, 4 ]
                     , [ nan, nan, nan, nan,
                         nan, nan, nan, nan,
                         9.123,    543.543, 234.2,  34.213,
                         nan, nan, nan, nan,
                         1.231,   -4.435, 5.4353, 7.56867,
                         nan, nan, nan, nan,
                         nan, nan, nan, nan,
                         -3.54,   3543.534, 21.2134, 9.123,
                         -10.432, -3.432, 25.543, 80.345,
                         nan, nan, nan, nan,
                         nan, nan, nan, nan,
                         +1.42,   +654.45, -32.432, -123.432,
                         nan, nan, nan, nan,
                         +78.432, +12.123, -123.5435, -87.43,
                         nan, nan, nan, nan,
                         nan, nan, nan, nan,
                         ] );
    immutable size_t[] subset = [ 2, 4, 7, 8, 11, 13 ];
    
    Matrix m_mean, m_cov;

    mean_cov_inplace_dim( m, subset, m_mean, m_cov );

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
    
    assert( isClose( m_mean.data, mean_truth, 1e-10, 1e-10 ) );

    if (verbose)
      {
        writeln( "m_cov.data: ", m_cov.data );
        writeln( "cov_truth:  ", cov_truth);
      }
    
    assert( isClose( m_cov .data,  cov_truth, 1e-10, 1e-10 ) );

    {
      // diag_only variant

    Matrix m_mean2, m_cov2;

    mean_cov_inplace_dim!(/*unbiased:*/true, /*diag_only:*/true)( m, subset, m_mean2, m_cov2 );

    auto mean_truth2 = mean_truth;
    
    immutable double[] cov_truth2 = assumeUnique
      ( () {

        auto tmp = new double[ cov_truth.length ];
        tmp[] = 0.0;

        immutable rd = m.restdim;
        for (size_t i = 0; i < tmp.length; i += rd+1)
          tmp[ i ] = cov_truth[ i ];

        return tmp;
      } () );

    if (verbose)
      {
        writeln( "m_mean2.data ", m_mean2.data );
        writeln( "mean_truth2: ", mean_truth2 );
      }
    
    assert( isClose( m_mean2.data, mean_truth2, 1e-10, 1e-10 ) );

    if (verbose)
      {
        writeln( "m_cov2.data: ", m_cov2.data );
        writeln( "cov_truth2:  ", cov_truth2);
      }
    
    assert( isClose( m_cov2 .data,  cov_truth2, 1e-10, 1e-10 ) );
    
    }
  }



  {
    double[] data =
      [
       +0,           +0.745698,             +0.2784,                  +1,
       +0.06,            +0.55504,            +0.08934,                  +1,
       +0.07,           +0.581278,            +0.03786,                  +1,
       +0.08,           +0.646216,            +0.09331,                  +1,
       +0.09,           +0.666258,            +0.08732,                  +1,
       +0.1,           +0.661642,             +0.1574,                  +1,
       +0.11,           +0.672052,            +0.17735,                  +1,
       +0.12,           +0.724512,            +0.18385,                  +1,
       +0.13,           +0.561142,            +0.35242,                  +1,
       +0,           +0.846568,            -0.04713,                  -1,
       +0.06,           +0.664134,            +0.03801,                  +1,
       +0.07,           +0.669486,             +0.0375,                  +1,
       +0.08,           +0.736414,            +0.04757,                  +1,
       +0.09,           +0.729618,             +0.0721,                  +1,
       +0.1,           +0.745226,            +0.02618,                  +1,
       +0.11,           +0.764142,            +0.03794,                  +1,
       +0.12,           +0.797046,            +0.02165,                  +1,
       +0.13,           +0.688214,            +0.10682,                  +1,
       +0,            +0.82194,            +0.01821,                  +1,
       +0.06,           +0.647054,            +0.06016,                  +1,
       +0.07,           +0.716422,            +0.06524,                  +1,
       +0.08,           +0.762928,            +0.07487,                  +1,
       +0.09,           +0.779934,            +0.09499,                  +1,
       +0.1,           +0.761882,            +0.02548,                  +1,
       +0.11,             +0.7678,            +0.02669,                  +1,
       +0.12,           +0.810286,            +0.07275,                  +1,
       +0.13,           +0.724058,            +0.12702,                  +1,
       +0,           +0.910448,            +0.56944,                  +1,
       +0.06,              +0.668,            +0.31771,                  +1,
       +0.07,           +0.704018,            +0.39307,                  +1,
       +0.08,           +0.749464,            +0.20706,                  +1,
       +0.09,           +0.803782,            +0.20043,                  +1,
       +0.1,            +0.80421,            +0.20998,                  +1,
       +0.11,            +0.77987,            +0.21036,                  +1,
       +0.12,           +0.816802,            +0.11718,                  +1,
       +0.13,           +0.813522,            +0.50393,                  +1,
       +0,           +0.734188,             +0.4402,                  +1,
       +0.06,            +0.60401,            +0.22178,                  +1,
       +0.07,           +0.628692,            +0.27936,                  +1,
       +0.08,           +0.629598,            +0.33652,                  +1,
       +0.09,           +0.640478,            +0.37464,                  +1,
       +0.1,             +0.6315,            +0.31173,                  +1,
       +0.11,           +0.648876,            +0.34442,                  +1,
       +0.12,            +0.66727,            +0.38682,                  +1,
       +0.13,           +0.744162,            +0.42148,                  +1,
       +0,           +0.961724,            -0.09651,                  -1,
       +0.06,           +0.725776,            +0.11736,                  +1,
       +0.07,           +0.745798,            +0.06034,                  +1,
       +0.08,            +0.76283,            -0.01588,                  -1,
       +0.09,           +0.805392,            -0.03948,                  -1,
       +0.1,           +0.839664,            -0.12597,                  -1,
       +0.11,            +0.91273,            +0.06446,                  +1,
       +0.12,           +0.904048,            +0.06166,                  +1,
       +0.13,           +0.940512,            -0.08926,                  -1,
       +0,           +0.902214,            +0.18959,                  +1,
       +0.06,           +0.695058,             +0.0775,                  +1,
       +0.07,           +0.662224,            +0.03247,                  +1,
       +0.08,           +0.680936,            +0.08766,                  +1,
       +0.09,           +0.737684,             +0.2043,                  +1,
       +0.1,            +0.78054,            +0.14636,                  +1,
       +0.11,           +0.828428,            +0.11643,                  +1,
       +0.12,            +0.82372,            +0.08056,                  +1,
       +0.13,            +0.88389,            +0.33935,                  +1,
       +0,           +0.919452,            -0.12644,                  -1,
       +0.06,           +0.697238,            +0.08756,                  +1,
       +0.07,           +0.701236,            -0.02108,                  -1,
       +0.08,           +0.745638,            -0.25264,                  -1,
       +0.09,           +0.797444,            -0.02103,                  -1,
       +0.1,           +0.803122,            -0.14358,                  -1,
       +0.11,           +0.822788,            -0.10582,                  -1,
       +0.12,           +0.839866,            -0.01969,                  -1,
       +0.13,           +0.921442,            -0.12372,                  -1,
       +0,            +0.88472,            +0.06828,                  +1,
       +0.06,           +0.764288,+0.00017999999999999,                  +1,
       +0.07,           +0.741446,            -0.07362,                  -1,
       +0.08,           +0.782008,            -0.14851,                  -1,
       +0.09,           +0.815368,            -0.14932,                  -1,
       +0.1,           +0.815978,            +0.03936,                  +1,
       +0.11,           +0.834858,            +0.05347,                  +1,
       +0.12,           +0.866186,            +0.15677,                  +1,
       +0.13,           +0.862766,             +0.2354,                  +1,
       +0,           +0.864498,            +0.01688,                  +1,
       +0.06,           +0.601014,            +0.03662,                  +1,
       +0.07,           +0.613766,            -0.12081,                  -1,
       +0.08,            +0.64405,            -0.16018,                  -1,
       +0.09,            +0.70264,            -0.11361,                  -1,
       +0.1,            +0.72696,            -0.13686,                  -1,
       +0.11,           +0.745166,            +0.01623,                  +1,
       +0.12,           +0.784602,            -0.16944,                  -1,
       +0.13,           +0.848102,             -0.1838,                  -1,
       ];
    
    auto m = Matrix( [0, 4], data );

    Matrix m_mean, m_cov, m_crosscorr;
    mean_cov_crosscorr_inplace_dim( m, m_mean, m_cov, m_crosscorr );

    // expected values computed using octave's mean cov and corr functions
    
    auto m_expected_mean = Matrix( [1,4], [ 0.08444444444444443, 0.7551743333333337, 0.08956611111111115, 0.4888888888888889] );

    auto m_expected_cov = Matrix
      ( [4,4]
        , [  0.001373283395755306,  -0.0001033241947565544,  -3.157802746566778e-05,   0.0002746566791510611,
             -0.0001033241947565544,    0.008572589869595505,   -0.003431627706779028,    -0.02241820973782771,
             -3.157802746566778e-05,   -0.003431627706779028,     0.02836485350268414,      0.1021213607990012,
             0.0002746566791510611,    -0.02241820973782771,      0.1021213607990012,      0.7695380774032456,
             ]
        );

    auto m_expected_crosscorr = Matrix
      ( [4,4]
        , [
           1,    -0.03011382494519723,   -0.005059582026811015,    0.008448799875609089,
           -0.03011382494519723,                       1,     -0.2200664662998454,     -0.2760131971258546,
           -0.005059582026811015,     -0.2200664662998454,                       1,       0.691211991431827,
           0.008448799875609089,     -0.2760131971258546,       0.691211991431827,                       1,
           ]
        );
    
    assert( m_mean.approxEqual( m_expected_mean, 1e-7 ) );
    assert( m_cov.approxEqual( m_expected_cov, 1e-7 ) );
    assert( m_crosscorr.approxEqual( m_expected_crosscorr, 1e-5 ) );
  }

  
  
  {
    auto m = Matrix( [0, 2, 2]
                     , [ 1.0, 10.0,  100.0,  1000.0,
                         2.0, 30.0,  400.0,  5000.0,
                         3.0, 60.0,  800.0, 10000.0,
                         ]);
    auto m_mean = Matrix( [1, 2, 2] );
    auto m_var  = Matrix( [1, 2, 2] );
    mean_var_inplace_nogc( m, m_mean, m_var );

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



    mean_var_inplace_nogc!( /*unbiased:*/false )( m, m_mean, m_var );
    
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
