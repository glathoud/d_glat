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
  MatrixT!T m_mu;
  MatrixT!T m_sigma;
  MatrixT!T m_sigma_inv;
  T         one_over_sigmadet;

  void ll_inplace( in ref Matrix m_feature
                   , /*output:*/ref Matrix m_ll )
    pure const @safe
  // Log-likelihoods of each Gaussian, at each point of `m_feature`.
  {
    immutable npoints = m_feature.nrow;
    m_ll.setDim( [npoints, n] );
    
    assert( false, "xxx ll_inplace not impl yet" );
  }

}
