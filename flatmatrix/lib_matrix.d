module d_glat.flatmatrix.lib_matrix;

/*
  Advanced matrix utilities (on top of `core_matrix`),
  including matrix inversion.

  By Guillaume Lathoud, 2019.
  glat@glat.info

  The Boost License applies to this file, as described in the file
  ../LICENSE
  
*/

public import d_glat.flatmatrix.core_matrix;

import core.exception : RangeError;
import d_glat.core_array;
import std.algorithm : all;
import std.math : abs, isFinite;


alias Buffer_det = Buffer_detT!double;
class Buffer_detT(T) { T[] A, temp; }


T det(T)( in MatrixT!T m ) pure nothrow @safe
// Variant that allocates an internal buffer.
{
  scope auto buffer = new Buffer_detT!T;

  return det!T( m, buffer );
}



T det( T )( in ref MatrixT!T m
            , ref Buffer_detT!T buffer
            )
  pure nothrow @safe
{
  immutable n = m.nrow;
  
  debug
    {
      assert( m.dim.length == 2 );
      assert( n == m.ncol );
    }

  auto A    = ensure_length( n*n, buffer.A );
  auto temp = ensure_length( n,   buffer.temp );
  
  A[] = m.data[];
    
  // Implementation adapted from numeric.js

  T ret = cast( T )( 1.0 ), alpha;
  
  immutable nm1 = n-1;
  
  for(size_t j=0,j_offset = 0, jopn;
      j<nm1;
      ++j, j_offset = jopn)
    {
      jopn = j_offset + n;

      {
        size_t k=j;
        size_t k_offset = j_offset;
        for(size_t i=j+1, i_offset = i*n;
            i<n;
            ++i, i_offset += n)
          {
            if(abs(A[i_offset + j]) > abs(A[k_offset + j]))
              {
                k = i;
                k_offset = i_offset;
              }
          }
        if(k != j)
          {
            // Cost of flatmatrix: have to copy data However (1) not
            // that big a cost on not too big matrices, and (2) benefit
            // in the next loop (direct access).
            immutable kopn = k_offset + n;
            temp[] = A[k_offset..kopn][];
            A[k_offset..kopn][] = A[j_offset..jopn][];
            A[j_offset..jopn][] = temp[];
            ret *= cast( T )(-1.0);
          }
      }
      
      for(size_t i=j+1, i_offset = i*n; i<n; ++i, i_offset += n)
        {
          alpha = A[i_offset + j] / A[j_offset + j];
          size_t k;
          for(k=j+1;k<nm1;k+=2)
            {
              size_t k1 = k+1;
              A[i_offset + k]  -= A[j_offset + k]*alpha;
              A[i_offset + k1] -= A[j_offset + k1]*alpha;
            }
          if(k != n)
            A[i_offset + k] -= A[j_offset + k]*alpha;
        }
      if(A[j_offset + j] == 0)
        return cast( T )( 0.0 );

      ret *= A[j_offset + j];
    }
  return ret*A[$-1];
}



MatrixT!T inv( T )( in MatrixT!T m )
// Functional wrapper around `inv_inplace_dim`
pure nothrow @safe
{
  Matrix m_inv;
  scope auto buffer = new Buffer_inv_inplaceT!T;
  
  inv_inplace_dim!T( m, m_inv, buffer );
  return m_inv;
}

bool inv_inplace_dim( T )( in ref MatrixT!T m
                           , ref MatrixT!T m_inv
                           , ref Buffer_inv_inplaceT!T buffer
                           ) pure nothrow @safe
/*
  Returns `true` if the inversion was successful (result in `m_inv`),
  `false` otherwise.
*/
{
  m_inv.setDim( [m.nrow, m.nrow] );
  return inv_inplace!T( m, m_inv, buffer );
}

alias Buffer_inv_inplace = Buffer_inv_inplaceT!double;
class Buffer_inv_inplaceT(T)
{
  T[]    A_flat, B_flat, B_flat_init;
  T[][]  A, B, A_init, B_init;
}

bool inv_inplace( T )( in ref MatrixT!T m, ref MatrixT!T m_inv
                       , ref Buffer_inv_inplaceT!T buffer
                       ) pure nothrow @trusted
{
  immutable I  = m.nrow;
  immutable J  = m.ncol;
  immutable IJ = I*J;
  immutable I2 = I*I;

  debug
    {
      assert( m    .dim == [I, J] );
      assert( m_inv.dim == [I, I] );
    }

  try
    {
      // Implementation note: for matrix inversion it is faster to work in
      // 2-D the whole time, probably because of faster row swaps.
  
      size_t sI, sJ;

      auto A_flat = buffer.A_flat;
      auto B_flat = buffer.B_flat;
      auto B_flat_init = buffer.B_flat_init;
      auto A = buffer.A;
      auto B = buffer.B;
      auto A_init = buffer.A_init;
      auto B_init = buffer.B_init;

      if (sI != I  ||  sJ != J)
        {
          sI = I; sJ = J;
          ensure_length( IJ, A_flat );
          ensure_length( I2, B_flat );
          ensure_length( I2, B_flat_init );

          scope Matrix id; id.setDim( [I, I]); diag_inplace_nogc( 1.0, id );
          B_flat_init[] = id.data[];

          ensure_length( I, A );
          ensure_length( I, B );
          ensure_length( I, A_init );
          ensure_length( I, B_init );
      
          foreach (i; 0..I)
            {
              A_init[ i ] = A_flat[ i*J..(i+1)*J ];
              B_init[ i ] = B_flat[ i*I..(i+1)*I ];
            }
        }

      // Init structure: initial row order

      A[] = A_init[];
      B[] = B_init[];

      // Init data

      A_flat[] = m.data[];
      B_flat[] = B_flat_init[];

      T[] Ai, Aj, Bi, Bj;

      // Implementation adapted from numeric.js
  
      for(long j=0;j<J;++j) {
        long i0 = -1;
        T v0 = -1;
        for(long i=j;i!=I;++i) {
          T k = abs(A[i][j]); if(k>v0) { i0 = i; v0 = k; }
        }
        
        if (i0 == j)
          {
            Aj = A[j];
            Bj = B[j];
          }
        else
          {
            Aj = A[i0]; A[i0] = A[j]; A[j] = Aj;
            Bj = B[i0]; B[i0] = B[j]; B[j] = Bj;
          }
        
        auto x = Aj[j];
        if (x == 0)
          {
            // Failed to inverse
            // 
            // Matrix not invertible at all and/or not invertible
            // within the Float64 numerical precision.
            m_inv.data[] = T.nan;
            return false;
          }
            
        for(long k=j;k!=J;++k)    Aj[k] /= x; 
        for(long k=J-1;k!=-1;--k) Bj[k] /= x;
        for(long i=I-1;i!=-1;--i) {
          if(i!=j) {
            Ai = A[i];
            Bi = B[i];
            x = Ai[j];
            long k;
            for(k=j+1;k!=J;++k)  Ai[k] -= Aj[k]*x;
            for(k=J-1;k>0;--k) { Bi[k] -= Bj[k]*x; --k; Bi[k] -= Bj[k]*x; }
            if(k==0) Bi[0] -= Bj[0]*x;
          }
        }
      }
      
      // Copy the resulting values: *not* from B_flat, but rather
      // row-by-row because B's rows have been swapped

      {
        auto inv = m_inv.data;
        
        for (size_t i = 0, ind = 0;
             i<I;
             ++i,
               ind += I
             )
          inv[ ind..ind+I ] = B[ i ][];
      }

    }
  catch( RangeError e )
    {
      debug assert( !(m.data.all!isFinite) ); // The implementation should never throw an error on finite data
      return false;
    }
  
  return true;
    
}






unittest  // ------------------------------
{
  import std.stdio;

  writeln;
  writeln( "unittest starts: "~__FILE__ );

  immutable verbose = false;


  import std.algorithm;
  import std.math;

  const m = Matrix
    ( [ 4, 4 ]
      , [ 1, 4, 2, 17
          , 54, 23, 12, 56
          , 7, 324, 23, 56
          , 542, 3, 23, 43
          ]
      );
  
  const m_inv_truth = Matrix
    ( [4, 4]
      , [ 0.02666295701993568, -0.010690122413924162, 0.0004032528845117337, 0.0028556842862368756
          , 0.03806261011863206, -0.016499239220523557, 0.0037736340871618243, 0.001524872452360714
          , -0.9276078787064798, 0.31489411381119636, -0.010628270423968902, -0.029524495155222024
          , 0.1574295505834409, -0.03253536166625731, 0.00033875009498698656, 0.0029466950714567243
          ]
      );


  /*
    octave

    m2 = [0.946068,   0.186274,   0.241528,   0.129626,   0.507351,   0.096300,   0.160248;
    0.657460,   0.873230,   0.127067,   0.362916,   0.189469,   0.234131,   0.576750;
    0.410037,   0.533891,   0.600077,   0.754741,   0.837460,   0.920658,   0.331678;
    0.131647,   0.053679,   0.045693,   0.897648,   0.203202,   0.862052,   0.016565;
    0.197822,   0.980076,   0.111997,   0.996879,   0.346470,   0.397345,   0.604819;
    0.926194,   0.070189,   0.598575,   0.044587,   0.519265,   0.474527,   0.536617;
    0.715006,   0.433708,   0.796754,   0.737583,   0.041156,   0.667159,   0.811830 ];
    m2_inv = inv(m2); sprintf( "%.12g, ", m2_inv.' )
    # 1.07047132091, 0.62669277972, -0.40527138515, 0.471158676194, -0.645044606512, -0.394003317874, 0.24043583308, -0.0212938497762, 1.81470522082, 1.25024923739, -0.521338354684, -1.22401527701, -1.65446624883, 0.220316168281, 0.723243232078,-0.550242846652, 1.47523733053, -1.29190626206, -0.9647403913, -1.86447933354, 1.62294515541, 1.21849496334, -1.54732786909, -0.562534298632, 0.212295418105, 1.21690396273, -0.662529003411, 0.615573745119, 0.0946850733968, -1.2099940721, 0.168657149906, -0.355295999316, 1.38863733597, 1.30381360059, -1.11708878497, -1.46179434145, 1.73496392685, 0.483628752339, 1.04989712194, -1.40996324221, 0.584692698826, -0.49908832157, -1.55179510586, -0.94003502125, -1.65373989769, 0.0937974371765,2.15154401831, 3.1160818548, -0.782977409577,

    sprintf("%.12f",det(m2))
    #0.062664340664
  */
  const m2 = Matrix
    ( [ 7, 7 ]
      , [  0.946068,   0.186274,   0.241528,   0.129626,   0.507351,   0.096300,   0.160248,
           0.657460,   0.873230,   0.127067,   0.362916,   0.189469,   0.234131,   0.576750,
           0.410037,   0.533891,   0.600077,   0.754741,   0.837460,   0.920658,   0.331678,
           0.131647,   0.053679,   0.045693,   0.897648,   0.203202,   0.862052,   0.016565,
           0.197822,   0.980076,   0.111997,   0.996879,   0.346470,   0.397345,   0.604819,
           0.926194,   0.070189,   0.598575,   0.044587,   0.519265,   0.474527,   0.536617,
           0.715006,   0.433708,   0.796754,   0.737583,   0.041156,   0.667159,   0.811830,
           ]
      );
  const m2_inv_truth = Matrix
    ( [7, 7]
      , [ 1.07047132091, 0.62669277972, -0.40527138515, 0.471158676194, -0.645044606512, -0.394003317874, 0.24043583308, -0.0212938497762, 1.81470522082, 1.25024923739, -0.521338354684, -1.22401527701, -1.65446624883, 0.220316168281, 0.723243232078,-0.550242846652, 1.47523733053, -1.29190626206, -0.9647403913, -1.86447933354, 1.62294515541, 1.21849496334, -1.54732786909, -0.562534298632, 0.212295418105, 1.21690396273, -0.662529003411, 0.615573745119, 0.0946850733968, -1.2099940721, 0.168657149906, -0.355295999316, 1.38863733597, 1.30381360059, -1.11708878497, -1.46179434145, 1.73496392685, 0.483628752339, 1.04989712194, -1.40996324221, 0.584692698826, -0.49908832157, -1.55179510586, -0.94003502125, -1.65373989769, 0.0937974371765,2.15154401831, 3.1160818548, -0.782977409577, ] );
  immutable m2_det_truth = 0.062664340664;
  
  /*
    octave

    m3 = [  
    0.634177,   0.773415,   0.967997,   0.819219,   0.626578,   0.197867;
    0.932414,   0.883805,   0.187540,   0.119388,   0.076340,   0.789061;
    0.163102,   0.906632,   0.672437,   0.449716,   0.635745,   0.875804;
    0.782329,   0.088954,   0.548773,   0.121327,   0.685141,   0.953328;
    0.804302,   0.649907,   0.168236,   0.983482,   0.190573,   0.532328;
    0.284247,   0.543901,   0.988484,   0.111830,   0.846268,   0.267094;];

    m3_inv = inv(m3); sprintf( "%.12g, ", m3_inv.' )
    # -0.268769457224, 0.54990342013, -1.2461483692, 0.177661640135, 0.613666691691, 0.803511914233, -1.39627802534, 0.600368561678, 0.0189455364223, -1.30596472448, 1.03924546357, 1.7886984715, 4.76124504743, 0.43115330184, 1.0113608562, 1.27429115596, -4.13492692713, -4.42441039661, 0.688652451123, -0.756875780723, 0.383001646342, 0.146456550437, 0.44977007184, -0.949183213116, -5.02184309165, -0.990874570291, -1.22691500269, -1.05309921408, 4.33628511425, 5.78701714979, 1.13155848719, 0.0529748345784, 1.27169927481, 1.02969457212, -1.39399452088, -2.31765641514,

    sprintf("%.12f",det(m3))
    #0.117622046234
  */
  const m3 = Matrix
    ( [ 6, 6 ]
      , [ 0.634177,   0.773415,   0.967997,   0.819219,   0.626578,   0.197867,
          0.932414,   0.883805,   0.187540,   0.119388,   0.076340,   0.789061,
          0.163102,   0.906632,   0.672437,   0.449716,   0.635745,   0.875804,
          0.782329,   0.088954,   0.548773,   0.121327,   0.685141,   0.953328,
          0.804302,   0.649907,   0.168236,   0.983482,   0.190573,   0.532328,
          0.284247,   0.543901,   0.988484,   0.111830,   0.846268,   0.267094]
      );
  const m3_inv = Matrix
    ( [ 6, 6 ]
      , [ -0.268769457224, 0.54990342013, -1.2461483692, 0.177661640135, 0.613666691691, 0.803511914233, -1.39627802534, 0.600368561678, 0.0189455364223, -1.30596472448, 1.03924546357, 1.7886984715, 4.76124504743, 0.43115330184, 1.0113608562, 1.27429115596, -4.13492692713, -4.42441039661, 0.688652451123, -0.756875780723, 0.383001646342, 0.146456550437, 0.44977007184, -0.949183213116, -5.02184309165, -0.990874570291, -1.22691500269, -1.05309921408, 4.33628511425, 5.78701714979, 1.13155848719, 0.0529748345784, 1.27169927481, 1.02969457212, -1.39399452088, -2.31765641514, ] );
  immutable m3_det_truth = 0.117622046234;

  auto buffer_det = new Buffer_det;
  auto buffer_inv_inplace = new Buffer_inv_inplace;


  {
    // Variant with internal buffer allocation

    if (verbose)
      writeln( "// ---------- Test determinant" );

    /* octave

       sprintf("%.12g",det([ 1, 4, 2, 17;
       54, 23, 12, 56;
       7, 324, 23, 56;
       542, 3, 23, 43 ]))

       // 9053872
       */

    auto d = det( m );
    assert( isClose( 9053872.0, d, 1e-10, 1e-10 ) );

    auto d2 = det( m2 );
    assert( isClose( 0.062664340664, d2, 1e-10, 1e-10 ) );

    auto d3 = det( m3 );
    assert( isClose( 0.117622046234, d3, 1e-10, 1e-10 ) );

    if (verbose)
      writefln( "d:%.12g d2:%.12g d3:%.12g", d, d2, d3 );
  }

  
  {
    // Variant with external buffer

    if (verbose)
      writeln( "// ---------- Test determinant" );

    /* octave

       sprintf("%.12g",det([ 1, 4, 2, 17;
       54, 23, 12, 56;
       7, 324, 23, 56;
       542, 3, 23, 43 ]))

       // 9053872
       */

    auto d = det( m, buffer_det );
    assert( isClose( 9053872.0, d, 1e-10, 1e-10 ) );

    auto d2 = det( m2, buffer_det );
    assert( isClose( 0.062664340664, d2, 1e-10, 1e-10 ) );

    auto d3 = det( m3, buffer_det );
    assert( isClose( 0.117622046234, d3, 1e-10, 1e-10 ) );

    if (verbose)
      writefln( "d:%.12g d2:%.12g d3:%.12g", d, d2, d3 );
  }
  

  {
    if (verbose)
      writeln( " // ---------- Make sure inversion failure leads to nan-fill" );

    auto a = Matrix( [4, 4], 123.0 );
    Matrix b;

    bool success = inv_inplace_dim( a, b, buffer_inv_inplace );

    assert( !success );
    assert( b.dim == [4, 4] );
    assert( b.data.all!isNaN );    
  }

  {
    if (verbose)
      writeln( " // ---------- Make sure inversion works" );

    Matrix m_inv;
    
    bool success = inv_inplace_dim( m, m_inv, buffer_inv_inplace );

    assert( success );
    assert( m_inv.dim == [4, 4] );
    assert( isClose( m_inv.data, m_inv_truth.data
                         , 1e-10, 1e-10 ) );
  }


  // Redo matrix inversion stuff with the same dimension, to make
  // sure that having already used buffers does not mess up the
  // computation.

  
  {
    if (verbose)
      writeln( " // ---------- Make sure inversion failure leads to nan-fill" );

    auto a = Matrix( [4, 4], 123.0 );
    Matrix b;

    bool success = inv_inplace_dim( a, b, buffer_inv_inplace );

    assert( !success );
    assert( b.dim == [4, 4] );
    assert( b.data.all!isNaN );    
  }

  {
    if (verbose)
      writeln( " // ---------- Make sure inversion works" );

    Matrix m_inv;

    bool success = inv_inplace_dim( m, m_inv, buffer_inv_inplace );

    assert( success );
    assert( m_inv.dim == [4, 4] );
    assert( isClose( m_inv.data, m_inv_truth.data
                         , 1e-10, 1e-10 ) );
  }

  

  {
    if (verbose)
      writeln( " // ---------- Matrix inversion: more examples" );
    
    Matrix m2_inv = inv( m2 );

    assert( !m2_inv.data.any!isNaN ); // not a failure
    assert( m2_inv.approxEqual( m2_inv_truth, 1e-10, 1e-10 ) );
  }


  
  {
    if (verbose)
      writeln( " // ---------- Test the functional wrapper" );

    
    Matrix m_inv = inv( m );

    assert( m_inv.dim == [4, 4] );
    assert( isClose( m_inv.data, m_inv_truth.data
                         , 1e-10, 1e-10 ) );

  }

  {
    if (verbose)
      writeln( " // ---------- Test the functional wrapper" );

    auto a = Matrix( [4, 4], 123.0 );
    
    Matrix a_inv = inv( a );

    assert( a_inv.dim == [4, 4] );
    assert( a_inv.data.all!isNaN );
  }
  
  writeln( "unittest passed: "~__FILE__ );
}
