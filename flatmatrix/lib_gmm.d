module d_glat.flatmatrix.lib_gmm;

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
}
