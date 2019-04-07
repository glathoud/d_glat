module d_glat.flatmatrix.lib_nmvpca;

/*
  PCA projection of the mean/variance-normalized data.
  
  By Guillaume Lathoud, 2019
  glat@glat.info
  
  Boost Software License version 1.0, see ../LICENSE
*/

public import d_glat.flatmatrix.core_matrix;

import d_glat.core_static;
import d_glat.flatmatrix.lib_nmv;
import d_glat.flatmatrix.lib_stat;
import d_glat.flatmatrix.lib_svd;
import std.algorithm : any;
import std.math : isNaN, sqrt;

Matrix nmvpca( in Matrix a ) @safe
// Functional wrapper around `nmvpca_inplace`.
// Returns a new matrix.
{
  pragma( inline, true );

  auto b = Matrix( a.dim );
  nmvpca_inplace( a, b );
  return b;
}

bool nmvpca_inplace_dim( in ref Matrix a, ref Matrix b )
  nothrow @safe
// Wrapper around `nmvpca_inplace`, calls `b.setDim(a.dim)`
// Returns `true` if PCA successful, `false` otherwise.
// In the latter case `b` will be filled with NaNs.
{
  pragma( inline, true );

  b.setDim( a.dim );
  return nmvpca_inplace( a, b );
}


bool nmvpca_inplace( in ref Matrix a
                     , ref Matrix b
                     ) nothrow @safe
/*
  Compute the PCA-projected data `b` out of `normalized(a)`
  (mean and variance normalization).
  
  Returns `true` if successful (esp. the SVD step), `false`
  otherwise. The the `false` case, `b.data` is filled with NaNs.
*/
{
  pragma( inline, true );

  immutable m = a.nrow;
  immutable n = a.ncol;
  immutable mtn = m * n;
  debug
    {
      assert( a.dim.length == 2 );
      assert( a.dim == [m, n] );
      assert( a.data.length == mtn );
      assert( b.dim == [m, n] );
      assert( b.data.length == mtn );
    }

  // Normalize mean and variance

  static Matrix a_nmv;
  nmv_inplace_dim( a, a_nmv );
  
  auto a_nmv_data = a_nmv.data;
  
  // Multiply the normalized data with itself:
  // 
  // Pseudocode: sigma := dot( transpose( a_nmv ), a_nmv )
  
  static Matrix sigma;
  sigma.setDim( [n, n] );

  auto sigma_data = sigma.data;
  
  immutable one_over_m_dbl = 1.0 / cast( double )( m );
  
  foreach (i; 0..n)
    {
      immutable itn = i * n;
      
      foreach (j; i..n)
        {
          double acc = 0.0;

          if (i == j)
            {
              auto i2 = i;
              while (i2 < mtn)
                {
                  auto tmp = a_nmv_data[ i2 ];
                  acc += tmp*tmp;
                  i2 += n;
                }
            }
          else
            {
              debug assert( i < j );
              auto i2 = i;
              auto j2 = j;
              while (i2 < mtn)
                {
                  acc += a_nmv_data[ i2 ] * a_nmv_data[ j2 ];
                  i2 += n;
                  j2 += n;
                }
            }
          
          acc *= one_over_m_dbl;
          
          sigma_data[ itn + j ] = acc;

          if (i < j)
            sigma_data[ j*n + i ] = acc;
        }
    }

  // Apply the SVD to get the new space

  static SvdResult svd_res;
  svd_res.setDim( n, n );

  auto converged = svd_inplace( sigma, svd_res );

  auto success = converged  &&  !(any!isNaN( svd_res.U.data ));
  
  // Project the data onto the new space

  if (success)
      dot_inplace( a_nmv, svd_res.U, b );

  else
      b.data[] = double.nan;

  return success;
}


unittest  // --------------------------------------------------
{
  import std.stdio;
  import std.algorithm;
  import std.math : approxEqual, isNaN;
  import std.random;
  
  writeln;
  writeln( "unittest starts: "~__FILE__ );

  immutable verbose = false;
  
  {
    auto a = Matrix( [ 100, 2 ] );
    auto rnd = MinstdRand0(42);

    double noise() { return rnd.uniform01 * 0.02 - 0.01; }
    
    foreach (i; 0..a.nrow)
      {
        double x = rnd.uniform01;
        double y = x * 2.0 - 1.0;
        a.data[ i*2   ] = x + noise();
        a.data[ i*2+1 ] = y + noise();
      }

    auto b = nmvpca( a );

    auto c = Matrix( a.dim );
    auto success = nmvpca_inplace( a, c );

    if (verbose)
      {
        writeln("a: ", a);
        writeln("b: ", b);
        writeln("c: ", c);
        writeln("success: ", success);
      }

    assert(success);
    assert(!(any!isNaN( b.data )));
    assert(b.data == c.data);
    
    if (verbose)
      {
        foreach (i; 0..a.nrow)
          {
            writefln( "i:%d a: %.6g %.6g  b: %.6g %.6g"
                      , i, a.data[ i*2], a.data[ i*2+1 ]
                      , b.data[ i*2], b.data[ i*2+1 ]
                      );
          }
      }
  }



  {
    // No noise, no PCA

    auto a = Matrix( [ 100, 2 ] );
    auto rnd = MinstdRand0(42);
    
    foreach (i; 0..a.nrow)
      {
        double x = rnd.uniform01;
        double y = x * 2.0 - 1.0;
        a.data[ i*2   ] = x;
        a.data[ i*2+1 ] = y;
      }

    auto b = nmvpca( a );

    auto c = Matrix( a.dim );
    auto success = nmvpca_inplace( a, c );

    assert(all!isNaN( b.data ));
    assert(all!isNaN( c.data ));
    
    if (verbose)
      writeln( "nonoise => success: ", success );
    
    assert( !success );
    
  }

  
  writeln( "unittest passed: "~__FILE__ );
}
