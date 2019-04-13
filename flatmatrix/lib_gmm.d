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

       Input:  m_feature (npoints * <restdim>>) where m_feature.restdim == gmm.dim
       Output: m_ll      (npoints * gmm.n)

       m_ll will be automatically redimensionned if necessary.
    */
  {
    debug assert( dim == m_feature.restdim );
    
    /* Implementation note: we could consider moving to a Cholesky
       factorization-based implementation, see:
       https://octave.sourceforge.io/statistics/function/mvnpdf.html

       That said, the implementation does not look *that* simple at
       first sight:
       http://octave.org/doxygen/4.0/da/d25/chol_8cc_source.html
    */
    
    immutable npoints = m_feature.nrow;
    m_ll.setDim( [npoints, n] );

    ll_inplace( m_feature, m_ll );
  }

  
  void ll_inplace( in ref Matrix m_feature
                       , /*output:*/ref Matrix m_ll )
  pure @trusted @nogc
    /* Log-likelihoods of each Gaussian, at each point of `m_feature`.

       Input:  m_feature (npoints * <restdim>>) where m_feature.restdim == gmm.dim
       Output: m_ll      (npoints * gmm.n)

       m_ll will NOT be automatically redimensionned, it must have the right dimension.
       (that is the price of @nogc)
    */
  {
    immutable npoints = m_feature.nrow;

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

  writeln( "xxx no GMM test yet for n > 1" );
  writeln( "unittest passed: "~__FILE__ );
}
