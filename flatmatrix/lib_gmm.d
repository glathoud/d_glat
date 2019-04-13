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
import std.math;

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

  private Matrix m_x, m_xmm, m_invcov_t_xmm, m_xmm_t_invcov_xmm;

  
  void ll_inplace( in ref Matrix m_feature
                   , /*output:*/ref Matrix m_ll )
    pure @trusted
  // Log-likelihoods of each Gaussian, at each point of `m_feature`.
  {
    debug
      {
        assert( dim == m_feature.restdim );
      }

    immutable npoints = m_feature.nrow;
    m_ll.setDim( [npoints, n] );

    auto feature_data = m_feature.data;
    auto      ll_data = m_ll.data;
    
    size_t i_f   = 0;
    size_t i_out = 0;
    foreach (i_p; 0..npoints)
      {
        size_t next_i_f = i_f + dim;

        // Cast okay, we will not modify it!
        m_x.data = cast( T[] )( feature_data[ i_f..next_i_f ] );

        foreach (j; 0..n)
          {
            direct_sub_inplace( m_x, m_mean_arr[ j ], m_xmm );
            
            auto invcov_j = m_invcov_arr[ j ];

            dot_inplace( invcov_j, m_xmm, m_invcov_t_xmm );

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
      m_mean_arr     = new MatrixT!T[ n ];
    
    if (m_cov_arr .length != n)
      m_cov_arr      = new MatrixT!T[ n ];
    
    if (m_invcov_arr.length != n)
      m_invcov_arr   = new MatrixT!T[ n ];
    
    if (logfactor_arr.length != n)
      logfactor_arr = new T[ n ];

    // Setup buffers for computations
    m_x  .setDim( [1, dim] );
    m_xmm.setDim( [1, dim] );
    m_invcov_t_xmm.setDim( [dim, dim] );
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

  writeln( "xxx no test yet" );
  writeln( "unittest passed: "~__FILE__ );
}
