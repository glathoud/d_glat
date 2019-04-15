module d_glat.flatmatrix.lib_gmm;

/*
  Gaussian Mixture Model (GMM).  

  Each "Gaussian" is a multivariate normal distribution.
  https://en.wikipedia.org/wiki/Multivariate_normal_distribution
  
  By Guillaume Lathoud, 2019.
  glat@glat.info

  The Boost License applies to the present file, as described in the
  file ../LICENSE
 */

import d_glat.flatmatrix.lib_matrix;
import d_glat.flatmatrix.lib_stat;
import std.array : array;
import std.math;
import std.range : iota;

alias Gmm = GmmT!double;

struct GmmT( T )
{
  size_t n;
  size_t dim;
  MatrixT!T[] m_mean_arr;
  MatrixT!T[] m_cov_arr;
  MatrixT!T[] m_invcov_arr;
  T[]         logfactor_arr; // log(1/sqrt((2*pi)^k * det(m_cov)))

  // private stuff for computation
  private immutable T LOG_TWO_PI =
    cast( T )( log( 2 ) + log( PI ) );

  private Matrix m_x, m_xmm, m_xmmT
    , m_invcov_t_xmm, m_xmm_t_invcov_xmm;

  
  void ll_inplace_dim( in ref Matrix m_feature
                       , /*output:*/ref Matrix m_ll )
  pure @safe
    /* Log-likelihoods of each Gaussian, at each point of `m_feature`.

       Input:  m_feature (npoints * <restdim>) where m_feature.restdim == gmm.dim
       Output: m_ll      (npoints * gmm.n)

       m_ll will be automatically redimensionned if necessary.
    */
  {
    debug assert( dim == m_feature.restdim );
    
    immutable npoints = m_feature.nrow;
    m_ll.setDim( [npoints, n] );

    ll_inplace( m_feature, m_ll );
  }

  
  void ll_inplace( in ref Matrix m_feature
                       , /*output:*/ref Matrix m_ll )
  pure @trusted @nogc
    /* Log-likelihoods of each Gaussian, at each point of `m_feature`.

       Input:  m_feature (npoints * <restdim>) where m_feature.restdim == gmm.dim
       Output: m_ll      (npoints * gmm.n)

       m_ll will NOT be automatically redimensionned, it must have the right dimension.
       (that is the price of @nogc)
    */
  {
    debug assert( dim == m_feature.restdim );

    immutable npoints = m_feature.nrow;

    /* Implementation note: we could consider moving to a Cholesky
       factorization-based implementation, see:
       https://octave.sourceforge.io/statistics/function/mvnpdf.html
       
       That said, the implementation does not look *that* simple at
       first sight:
       http://octave.org/doxygen/4.0/da/d25/chol_8cc_source.html

       ...and the current flatmatrix implementation has in at least 
       one numerical case a *better* precision than the octave chol-based
       implementation, see the `m12` use case further below (-Inf overflow
       in the case of octave, whereas flatmatrix does not overflow).

       => leave covinv as it is.
    */
    
    auto feature_data = m_feature.data;
    auto      ll_data = m_ll.data;
    
    size_t i_f   = 0;
    size_t i_out = 0;
    foreach (i_p; 0..npoints)
      {
        size_t next_i_f = i_f + dim;

        // Cast okay, we will not modify the data!
        m_x.data = cast( T[] )( feature_data[ i_f..next_i_f ] );

        foreach (j; 0..n)
          {
            direct_sub_inplace( m_x, m_mean_arr[ j ], m_xmm );
            
            auto invcov_j = m_invcov_arr[ j ];

            dot_inplace( invcov_j, m_xmmT, m_invcov_t_xmm );
            dot_inplace( m_xmm, m_invcov_t_xmm
                         , m_xmm_t_invcov_xmm );
            
            debug assert( m_xmm_t_invcov_xmm.data.length == 1 );
            
            ll_data[ i_out++ ] = logfactor_arr[ j ]
              - cast( T )( 0.5 ) * m_xmm_t_invcov_xmm.data[ 0 ];
          }
        
        i_f = next_i_f;
      }

    debug assert( i_f == feature_data.length );
    debug assert( i_out == ll_data.length );
  }

  void setSingle( in ref Matrix m_feature )
    nothrow @safe
  {
    // Single group
    auto group_arr = [ iota( 0, m_feature.nrow ).array ];
    setOfGroupArr( m_feature, group_arr );
  }

  
  void setOfGroupArr( in ref Matrix m_feature
                      , in ref size_t[][] group_arr
                      )
    nothrow @safe
  {
    n   = group_arr.length;
    dim = m_feature.restdim;
    immutable dim_T = cast( T )( dim );

    _resize();

    foreach (i_g, group; group_arr)
      {
        mean_cov_inplace
          ( /*Inputs:*/  m_feature, /*subset:*/group
            /*Outputs:*/ , m_mean_arr[ i_g ], m_cov_arr[ i_g ] );
        
        inv_inplace( m_cov_arr[ i_g ], m_invcov_arr[ i_g ] );

        logfactor_arr[ i_g ] = -0.5 *
          (/*k:*/dim_T * LOG_TWO_PI
           + log( det( m_cov_arr[ i_g ] ) )
           );
      }
  }
  
 private:

  void _resize() pure nothrow @safe
  {
    if (m_mean_arr.length != n)
      {
        m_mean_arr = new MatrixT!T[ n ];
        foreach (i; 0..n) m_mean_arr[ i ].setDim([1, dim]);
      }
    
    if (m_cov_arr .length != n)
      {
        m_cov_arr = new MatrixT!T[ n ];
        foreach (i; 0..n) m_cov_arr[ i ].setDim([dim, dim]);
      }
    
    if (m_invcov_arr.length != n)
      {
        m_invcov_arr   = new MatrixT!T[ n ];
        foreach (i; 0..n) m_invcov_arr[ i ].setDim([dim, dim]);
      }
    
    if (logfactor_arr.length != n)
      logfactor_arr = new T[ n ];

    // Setup buffers for computations
    m_x  .setDim( [1, dim] );
    
    m_xmm .setDim( [1, dim] );
    m_xmmT.setDim( [dim, 1] );
    m_xmmT.data = m_xmm.data;
    
    m_invcov_t_xmm.setDim( [dim, 1] );
    m_xmm_t_invcov_xmm.setDim( [1, 1] );
  }
}


unittest  // ------------------------------
{
  import std.stdio;

  writeln;
  writeln( "unittest starts: "~__FILE__ );

  immutable verbose = false;

  import std.algorithm;
  import std.math;
  import std.range;

  /* # First define some mean and covariance from some data,
     
     # octave
     
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

     # Now extract log-likelihood at those data points
     # sudo apt install liboctave-dev
     # pkg install -forge io
     # pkg install -forge statistics
     pkg load statistics
     ll = log(mvnpdf(m, mean(m), cov(m)));

     sprintf("%.12g ",ll)
     # -25.1267722553 -23.4663477129 -25.1237698848 -24.4644651969 -24.9829380998 -25.1180285045
  */

  const Matrix m_data = Matrix
    ( [ 0, 4 ], [ 9.123,    543.543, 234.2,  34.213,
                  1.231,   -4.435, 5.4353, 7.56867,
                  -3.54,   3543.534, 21.2134, 9.123,
                  -10.432, -3.432, 25.543, 80.345,
                  +1.42,   +654.45, -32.432, -123.432,
                  +78.432, +12.123, -123.5435, -87.43
                  ] );
  
  const Matrix m_mean_truth = Matrix( [ 1, 4 ], [ 12.705666666666666, 790.9638333333332, 21.736033333333335, -13.26872166666667 ] );

  const Matrix m_cov_truth  = Matrix( [ 4, 4 ],  [1078.21878907, -13194.6422333, -1918.22091097, -1314.01354014, -13194.6422333, 1905362.54113, 15295.8135786, 6349.01473539, -1918.22091097, 15295.8135786, 13892.3471641, 5366.92317258, -1314.01354014, 6349.01473539, 5366.92317258, 5917.89439291 ] );

  const Matrix m_ll_truth = Matrix( [ 0, 1 ], [ -25.1267722553, -23.4663477129, -25.1237698848, -24.4644651969, -24.9829380998, -25.1180285045 ] );
  
  {
    Gmm gmm;

    // "read" some data
    
    gmm.setSingle( m_data );
    assert( gmm.n == 1 );
    assert( gmm.dim == m_data.restdim );
    assert( gmm.m_mean_arr.length == 1 );
    assert( gmm.m_cov_arr .length == 1 );
    assert( gmm.m_mean_arr[ 0 ].approxEqual
            ( m_mean_truth, 1e-10, 1e-10 ) );
    assert( gmm.m_cov_arr[ 0 ].approxEqual
            ( m_cov_truth, 1e-10, 1e-10 ) );

    // "write" some log-likelihood

    Matrix m_ll;

    gmm.ll_inplace_dim( m_data, m_ll );

    assert( m_ll.approxEqual( m_ll_truth, 1e-10, 1e-10 ) );
  }

  /* octave

    m2 = [0.092707,   0.131768,   0.135686,   0.368515;
                  0.631762,   0.775828,   0.390226,   0.554016;
                  0.948819,   0.232960,   0.757014,   0.659997;
                  0.114874,   0.547982,   0.287796,   0.166472;
                  0.198228,   0.251269,   0.321560,   0.048973;
                  0.701833,   0.213674,   0.367240,   0.466107;
                  0.048493,   0.346971,   0.089153,   0.431382;
                  0.364042,   0.775604,   0.244870,   0.473673;
                  0.315460,   0.276054,   0.200118,   0.920906;
                  0.625797,   0.737658,   0.027077,   0.721632
     ];
     
     sprintf("%.12g ", mean(m2))
     # 0.4042015 0.4289768 0.282074 0.4811673
     
     sprintf("%.12g ",cov(m2))
     # 0.0939179736225 0.0111186481421 0.0405905269436 0.0396580939211 0.0111186481421 0.0649670933471-0.0111114870292 0.00830639425051 0.0405905269436 -0.0111114870292 0.0419869271207 0.000186729429111 0.0396580939211 0.00830639425051 0.000186729429111 0.065528614408

     # Now extract log-likelihood at those data points
     # sudo apt install liboctave-dev
     # pkg install -forge io
     # pkg install -forge statistics
     pkg load statistics
     ll2 = log(mvnpdf(m2, mean(m2), cov(m2)));

     sprintf("%.12g ",ll2)
     # 1.28775487271 1.20252019608 -0.504696226109 1.09676571148 0.900182619597 0.639816493184 1.68860859648 1.37382989168 -0.351434304434 -0.424339488551
  */

  const Matrix m_data2 = Matrix
    ( [ 0, 4 ], [ 0.092707,   0.131768,   0.135686,   0.368515,
                  0.631762,   0.775828,   0.390226,   0.554016,
                  0.948819,   0.232960,   0.757014,   0.659997,
                  0.114874,   0.547982,   0.287796,   0.166472,
                  0.198228,   0.251269,   0.321560,   0.048973,
                  0.701833,   0.213674,   0.367240,   0.466107,
                  0.048493,   0.346971,   0.089153,   0.431382,
                  0.364042,   0.775604,   0.244870,   0.473673,
                  0.315460,   0.276054,   0.200118,   0.920906,
                  0.625797,   0.737658,   0.027077,   0.721632,]
      );

  const Matrix m_mean2_truth = Matrix
    ( [ 1, 4 ], [ 0.4042015, 0.4289768, 0.282074, 0.4811673 ]);

  const Matrix m_cov2_truth = Matrix
    ( [ 4, 4 ], [ 0.0939179736225, 0.0111186481421, 0.0405905269436, 0.0396580939211, 0.0111186481421, 0.0649670933471,-0.0111114870292, 0.00830639425051, 0.0405905269436, -0.0111114870292, 0.0419869271207, 0.000186729429111, 0.0396580939211, 0.00830639425051, 0.000186729429111, 0.065528614408 ] );

  const Matrix m_ll2_truth = Matrix
    ( [ 0, 1 ], [ 1.28775487271, 1.20252019608, -0.504696226109, 1.09676571148, 0.900182619597, 0.639816493184, 1.68860859648, 1.37382989168, -0.351434304434, -0.424339488551 ] );

  {
    Gmm gmm;

    // "read" some data
    
    gmm.setSingle( m_data2 );
    assert( gmm.n == 1 );
    assert( gmm.dim == m_data2.restdim );
    assert( gmm.m_mean_arr.length == 1 );
    assert( gmm.m_cov_arr .length == 1 );
    assert( gmm.m_mean_arr[ 0 ].approxEqual
            ( m_mean2_truth, 1e-10, 1e-10 ) );
    assert( gmm.m_cov_arr[ 0 ].approxEqual
            ( m_cov2_truth, 1e-10, 1e-10 ) );

    // "write" some log-likelihood

    Matrix m_ll2;

    gmm.ll_inplace_dim( m_data2, m_ll2 );

    assert( m_ll2.approxEqual( m_ll2_truth, 1e-10, 1e-10 ) );
  }

  if (verbose)
    writeln( "// ---------- Test: mix 2 gmms");

  const Matrix m_data12 = Matrix
    ( [ 0, 4 ], [ 9.123,    543.543, 234.2,  34.213,

                  0.092707,   0.131768,   0.135686,   0.368515,
                  0.631762,   0.775828,   0.390226,   0.554016,
                  
                  1.231,   -4.435, 5.4353, 7.56867,

                  0.948819,   0.232960,   0.757014,   0.659997,
                  
                  -3.54,   3543.534, 21.2134, 9.123,

                  0.114874,   0.547982,   0.287796,   0.166472,
                  0.198228,   0.251269,   0.321560,   0.048973,
                  0.701833,   0.213674,   0.367240,   0.466107,
                                    
                  -10.432, -3.432, 25.543, 80.345,

                  0.048493,   0.346971,   0.089153,   0.431382,
                  0.364042,   0.775604,   0.244870,   0.473673,
                  
                  +1.42,   +654.45, -32.432, -123.432,

                  0.315460,   0.276054,   0.200118,   0.920906,
                  0.625797,   0.737658,   0.027077,   0.721632,

                  +78.432, +12.123, -123.5435, -87.43,
                  ] );

  const size_t[][] group_arr =
    [
     [ 0, 3, 5, 9, 12, 15 ],
     [ 1,2, 4, 6,7,8, 10,11, 13,14 ],
     ];

    /* # First define some mean and covariance from some data,
     
     # octave
     
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

     # Now extract log-likelihood at those data points
     # sudo apt install liboctave-dev
     # pkg install -forge io
     # pkg install -forge statistics
     pkg load statistics
     ll = log(mvnpdf(m, mean(m), cov(m)));

     sprintf("%.12g ",ll)
     # -25.1267722553 -23.4663477129 -25.1237698848 -24.4644651969 -24.9829380998 -25.1180285045

   m2 = [0.092707,   0.131768,   0.135686,   0.368515;
                  0.631762,   0.775828,   0.390226,   0.554016;
                  0.948819,   0.232960,   0.757014,   0.659997;
                  0.114874,   0.547982,   0.287796,   0.166472;
                  0.198228,   0.251269,   0.321560,   0.048973;
                  0.701833,   0.213674,   0.367240,   0.466107;
                  0.048493,   0.346971,   0.089153,   0.431382;
                  0.364042,   0.775604,   0.244870,   0.473673;
                  0.315460,   0.276054,   0.200118,   0.920906;
                  0.625797,   0.737658,   0.027077,   0.721632
     ];
     
     sprintf("%.12g ", mean(m2))
     # 0.4042015 0.4289768 0.282074 0.4811673
     
     sprintf("%.12g ",cov(m2))
     # 0.0939179736225 0.0111186481421 0.0405905269436 0.0396580939211 0.0111186481421 0.0649670933471-0.0111114870292 0.00830639425051 0.0405905269436 -0.0111114870292 0.0419869271207 0.000186729429111 0.0396580939211 0.00830639425051 0.000186729429111 0.065528614408

     # Now extract log-likelihood at those data points
     # sudo apt install liboctave-dev
     # pkg install -forge io
     # pkg install -forge statistics
     pkg load statistics
     ll2 = log(mvnpdf(m2, mean(m2), cov(m2)));

     sprintf("%.12g ",ll2)
     # 1.28775487271 1.20252019608 -0.504696226109 1.09676571148 0.900182619597 0.639816493184 1.68860859648 1.37382989168 -0.351434304434 -0.424339488551

     m12 = [ 9.123,    543.543, 234.2,  34.213;

                  0.092707,   0.131768,   0.135686,   0.368515;
                  0.631762,   0.775828,   0.390226,   0.554016;
                  
                  1.231,   -4.435, 5.4353, 7.56867;

                  0.948819,   0.232960,   0.757014,   0.659997;
                  
                  -3.54,   3543.534, 21.2134, 9.123;

                  0.114874,   0.547982,   0.287796,   0.166472;
                  0.198228,   0.251269,   0.321560,   0.048973;
                  0.701833,   0.213674,   0.367240,   0.466107;
                                    
                  -10.432, -3.432, 25.543, 80.345;

                  0.048493,   0.346971,   0.089153,   0.431382;
                  0.364042,   0.775604,   0.244870,   0.473673;
                  
                  +1.42,   +654.45, -32.432, -123.432;

                  0.315460,   0.276054,   0.200118,   0.920906;
                  0.625797,   0.737658,   0.027077,   0.721632;

                  +78.432, +12.123, -123.5435, -87.43;
                  ];

   ll12_1 = log(mvnpdf(m12, mean(m), cov(m)));
   ll12_2 = log(mvnpdf(m12, mean(m2), cov(m2)));

   sprintf("%.12g, ", [ll12_1, ll12_2]')
   # -25.1267722553, -Inf, -23.4963465024, 1.28775487271, -23.4816461208, 1.20252019608, -23.4663477129, -Inf, -23.4726410142, -0.504696226109, -25.1237698848, -Inf, -23.494364888, 1.09676571148, -23.4920220921, 0.900182619597, -23.4801739256,0.639816493184, -24.4644651969, -Inf, -23.4977176386, 1.68860859648, -23.4888268924, 1.37382989168, -24.9829380998, -Inf, -23.491506205, -0.351434304434, -23.484059015, -0.424339488551, -25.1180285045, -Inf,
  */

  enum Inf = double.infinity;
  
  const m_ll12_truth = Matrix
    ( [0, 2]
      , [ -25.1267722553, -Inf, -23.4963465024, 1.28775487271, -23.4816461208, 1.20252019608, -23.4663477129, -Inf, -23.4726410142, -0.504696226109, -25.1237698848, -Inf, -23.494364888, 1.09676571148, -23.4920220921, 0.900182619597, -23.4801739256,0.639816493184, -24.4644651969, -Inf, -23.4977176386, 1.68860859648, -23.4888268924, 1.37382989168, -24.9829380998, -Inf, -23.491506205, -0.351434304434, -23.484059015, -0.424339488551, -25.1180285045, -Inf, ] );
  
  {
    Gmm gmm;

    // "read" some data
    
    gmm.setOfGroupArr( m_data12, group_arr );
    assert( gmm.n == 2 );
    assert( gmm.dim == m_data2.restdim );
    assert( gmm.m_mean_arr.length == 2 );
    assert( gmm.m_cov_arr .length == 2 );
    assert( gmm.m_mean_arr[ 0 ].approxEqual
            ( m_mean_truth, 1e-10, 1e-10 ) );
    assert( gmm.m_cov_arr[ 0 ].approxEqual
            ( m_cov_truth, 1e-10, 1e-10 ) );
    assert( gmm.m_mean_arr[ 1 ].approxEqual
            ( m_mean2_truth, 1e-10, 1e-10 ) );
    assert( gmm.m_cov_arr[ 1 ].approxEqual
            ( m_cov2_truth, 1e-10, 1e-10 ) );
    

    // "write" some log-likelihood

    Matrix m_ll12;

    gmm.ll_inplace_dim( m_data12, m_ll12 );

    if (verbose)
      writeln("m_ll12: ", m_ll12 );

    // In this case we seem to have better precision than octave
    // finite numbers where octave outputs -Inf. Deal with this.
    
    assert( m_ll12.dim == [m_data12.nrow, gmm.n]);
    assert( m_ll12.dim == m_ll12_truth.dim );


    if (verbose)
      {
        writeln( "m_ll12_truth: ", m_ll12_truth);
        foreach (vt; zip(m_ll12.data, m_ll12_truth.data))
          {
            writeln( vt
                     , " ", approxEqual(vt[0],vt[1],1e-10,1e-10)
                     , " ", vt[1] == -double.infinity
                     , " ", vt[0] < -1000.0
                     , " => "
                     ,
                     approxEqual(vt[0],vt[1],1e-10,1e-10)
                     || vt[1] == -double.infinity
                     && vt[0] < -1000.0 
                     );
          }
      }

    assert( zip(m_ll12.data, m_ll12_truth.data)
            .all!( vt => approxEqual(vt[0],vt[1],1e-10,1e-10)
                   || vt[1] == -double.infinity && vt[0] < -1000.0 )
            );
    
  }
  
  writeln( "unittest passed: "~__FILE__ );
}
