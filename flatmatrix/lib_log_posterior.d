module d_glat.flatmatrix.lib_log_posterior;

import d_glat.core_math;
import d_glat.flatmatrix.core_matrix;

MatrixT!T log_posterior_of_ll(T)( in MatrixT!T m_ll ) pure nothrow @safe
// assume equal priors
{
  auto m_lpp = MatrixT!T( m_ll.dim );

  auto buffer = new T[ m_ll.restdim ];
  
  log_posterior_of_ll_inplace_nogc( m_ll, buffer, m_lpp );
  
  return m_lpp;
}


void log_posterior_of_ll_inplace_nogc(T)( in ref MatrixT!T m_ll
                                          , ref T[] buffer
                                          , ref MatrixT!T m_lpp ) pure nothrow @safe @nogc
// assume equal priors
{
  immutable ncol = m_ll.restdim;

  auto ll_data = m_ll.data;
  immutable n  = ll_data.length;

  auto lpp_data = m_lpp.data;
  
  debug
  {
    assert( n == lpp_data.length );
    assert( m_ll.dim == m_lpp.dim );
    assert( buffer.length == ncol );
  }

  {
    size_t i = 0;
    for (i = 0; i < n;)
      {
        immutable i_next = i + ncol;
        auto llsum = logsum_nogc( ll_data, i, i_next, buffer );
        while (i < i_next)
          {
            lpp_data[ i ] = ll_data[ i ] - llsum;
            ++i;
          }
      }
    debug assert( i == n );
  }
}

