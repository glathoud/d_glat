module d_glat.flatmatrix.lib_nmv;

/*
  Normalize each dimension by mean and variance.

  By Guillaume Lathoud, 2019.
  glat@glat.info
  
  The Boost License applies, as described in the file ../LICENSE
 */

public import d_glat.flatmatrix.core_matrix;

import d_glat.core_array;
import d_glat.flatmatrix.lib_stat;
import std.math;

alias Buffer_nmv_inplace = Buffer_nmv_inplaceT!double;
class Buffer_nmv_inplaceT(T)
{
  MatrixT!T m_mean, m_var;
  T[] std_arr;
}


MatrixT!T nmv(T)( in MatrixT!T a ) pure nothrow @safe
// Functional wrapper around `nmv_inplace_dim`
{
  pragma( inline, true );
  MatrixT!T b;
  auto buffer = new Buffer_nmv_inplaceT!T;

  nmv_inplace_dim!T( a, b, buffer );

  return b;
}


void nmv_inplace_dim( T )( in ref MatrixT!T a
                           , ref MatrixT!T b
                           , ref Buffer_nmv_inplaceT!T buffer
                           )
  pure nothrow @safe
{
  pragma( inline, true );

  b.setDim( a.dim );

  auto  m_mean  = buffer.m_mean;
  auto  m_var   = buffer.m_var;
  
  mean_var_inplace_dim( a, m_mean, m_var );

  auto mean_arr = m_mean.data;
  immutable restdim = mean_arr.length;

  auto std_arr = ensure_length( restdim, buffer.std_arr );
  
  foreach (i,x; m_var.data)
    std_arr[ i ] = sqrt( x );

  auto a_data = a.data;
  auto b_data = b.data;

  immutable i_end = a_data.length;

  debug assert( i_end == b_data.length );
  
  foreach (j; 0..restdim)
    {
      immutable mj = mean_arr[ j ];
      immutable sj =  std_arr[ j ];
      
      for (size_t i = j; i < i_end; i += restdim)
        b_data[ i ] = (a_data[ i ] - mj) / sj;
    }
}



unittest  // ------------------------------
{
  import std.stdio;

  import std.algorithm;

  writeln;
  writeln( "unittest starts: "~__FILE__ );

  immutable verbose = false;

  auto buffer_nmv_inplace = new Buffer_nmv_inplace;



  {
    // Functional variant (buffer internally allocated)
    
    auto A = Matrix( [ 5, 2 ], [ 1.0, 10.0,
                                 2.0, 15.0,
                                 3.0, 20.0,
                                 4.0, 25.0,
                                 5.0, 30.0,
                                 ]);

    auto B = nmv( A );

    if (verbose)
      {
        writeln( "A: ", A );
        writeln( "B: ", B );
      }

    Matrix m_mean, m_var;

    mean_var_inplace_dim( A, m_mean, m_var );

    if (verbose)
      {
        writeln( "m_mean: ", m_mean );
        writeln( "m_var: ", m_var);
      }

    assert( m_mean.data.all!"!approxEqual( a, 0.0, 1e-10, 1e-10 )" );
    assert( m_var .data.all!"!approxEqual( a, 1.0, 1e-10, 1e-10 )" );


    mean_var_inplace_dim( B, m_mean, m_var );

    if (verbose)
      {
        writeln( "m_mean: ", m_mean );
        writeln( "m_var: ", m_var);
      }

    assert( m_mean.data.all!"approxEqual( a, 0.0, 1e-10, 1e-10 )" );
    assert( m_var .data.all!"approxEqual( a, 1.0, 1e-10, 1e-10 )" );
  }  



  
  {
    // In-place variant
    
    auto A = Matrix( [ 5, 2 ], [ 1.0, 10.0,
                                 2.0, 15.0,
                                 3.0, 20.0,
                                 4.0, 25.0,
                                 5.0, 30.0,
                                 ]);

    auto B = Matrix();

    nmv_inplace_dim( A, B, buffer_nmv_inplace );

    if (verbose)
      {
        writeln( "A: ", A );
        writeln( "B: ", B );
      }

    Matrix m_mean, m_var;

    mean_var_inplace_dim( A, m_mean, m_var );

    if (verbose)
      {
        writeln( "m_mean: ", m_mean );
        writeln( "m_var: ", m_var);
      }

    assert( m_mean.data.all!"!approxEqual( a, 0.0, 1e-10, 1e-10 )" );
    assert( m_var .data.all!"!approxEqual( a, 1.0, 1e-10, 1e-10 )" );


    mean_var_inplace_dim( B, m_mean, m_var );

    if (verbose)
      {
        writeln( "m_mean: ", m_mean );
        writeln( "m_var: ", m_var);
      }

    assert( m_mean.data.all!"approxEqual( a, 0.0, 1e-10, 1e-10 )" );
    assert( m_var .data.all!"approxEqual( a, 1.0, 1e-10, 1e-10 )" );
  
  }
  
  writeln( "unittest passed: "~__FILE__ );
}
