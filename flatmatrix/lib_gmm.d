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

import d_glat.flatmatrix.core_matrix;

alias Gmm = GmmT!double;

struct GmmT( T )
{
  size_t n;
  size_t dim;
  MatrixT!T[] m_mean;
  MatrixT!T[] m_cov;
  MatrixT!T[] m_cov_inv;
  T[]         log_factor; // log(1/sqrt((2*pi)^k * det(m_cov)))
  
  void ll_inplace( in ref Matrix m_feature
                   , /*output:*/ref Matrix m_ll )
    pure const @safe
  // Log-likelihoods of each Gaussian, at each point of `m_feature`.
  {
    immutable npoints = m_feature.nrow;
    m_ll.setDim( [npoints, n] );
    
    assert( false, "xxx ll_inplace not impl yet" );
  }

  void setOfGroupArr( in ref Matrix m_feature
                      , in ref size_t[][] group_arr
                      )
  {
    n   = group_arr.length;
    dim = m_feature.restdim;
    _resize();
    
    assert( false, "xxx setOfGroupArr not impl yet");
  }
  
 private:

  void _resize() pure nothrow @safe
  {
    if (m_mean.length != n)     m_mean     = new MatrixT!T[ n ];
    if (m_cov .length != n)     m_cov      = new MatrixT!T[ n ];
    if (m_cov_inv.length != n)  m_cov_inv  = new MatrixT!T[ n ];
    if (log_factor.length != n) log_factor = new T[ n ];
  }
}
