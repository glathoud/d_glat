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

import std.math : abs;

MatrixT!T matinv( T )( in ref MatrixT!T m )
// Functional wrapper around `matinv_inplace_dim`
nothrow @safe
{
  Matrix m_inv;
  matinv_inplace_dim!T( m, m_inv );
  return m_inv;
}


bool matinv_inplace_dim( T )( in ref MatrixT!T m
                              , ref MatrixT!T m_inv )
/*
  Returns `true` if the inversion was successful (result in `m_inv`),
 `false` otherwise.
*/
  nothrow @safe
{
  pragma( inline, true );
  m_inv.setDim( [m.nrow, m.nrow] );
  return matinv_inplace!T( m, m_inv );
}

bool matinv_inplace( T )( in ref MatrixT!T m, ref MatrixT!T m_inv )
  nothrow @safe
{
  pragma( inline, true );

  immutable I  = m.nrow;
  immutable J  = m.ncol;
  immutable IJ = I*J;
  immutable I2 = I*I;

  debug
    {
      assert( m    .dim == [I, J] );
      assert( m_inv.dim == [I, I] );
    }
  
  // Implementation note: for matrix inversion it is faster to work in
  // 2-D the whole time, probably because of faster row swaps.
  
  static size_t sI, sJ;
  static T[]    A_flat, B_flat, B_flat_init;
  static T[][]  A, B, A_init, B_init;

  if (sI != I  ||  sJ != J)
    {
      sI = I; sJ = J;
      A_flat      = new T[ IJ ];
      B_flat      = new T[ I2 ];
      B_flat_init = new T[ I2 ];

      Matrix id; id.setDim( [I, I]); diag_inplace( 1.0, id );
      B_flat_init[] = id.data[];

      A = new T[][ I ];
      B = new T[][ I ];
      A_init = new T[][ I ];
      B_init = new T[][ I ];
      
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
    auto matinv = m_inv.data;
        
    for (size_t i = 0, ind = 0;
         i<I;
         ++i,
           ind += I
         )
      matinv[ ind..ind+I ] = B[ i ][];
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


  {
    if (verbose)
      writeln( " // ---------- Make sure inversion failure leads to nan-fill" );

    auto a = Matrix( [4, 4], 123.0 );
    Matrix b;

    bool success = matinv_inplace_dim( a, b );

    assert( !success );
    assert( b.dim == [4, 4] );
    assert( b.data.all!isNaN );    
  }

  {
    if (verbose)
      writeln( " // ---------- Make sure inversion works" );

    Matrix m_inv;
    
    bool success = matinv_inplace_dim( m, m_inv );

    assert( success );
    assert( m_inv.dim == [4, 4] );
    assert( approxEqual( m_inv.data, m_inv_truth.data
                         , 1e-10, 1e-10 ) );
  }

  // Redo matrix inversion stuff with the same dimension, to make sure
  // the static caches are not messed up

  
  {
    if (verbose)
      writeln( " // ---------- Make sure inversion failure leads to nan-fill" );

    auto a = Matrix( [4, 4], 123.0 );
    Matrix b;

    bool success = matinv_inplace_dim( a, b );

    assert( !success );
    assert( b.dim == [4, 4] );
    assert( b.data.all!isNaN );    
  }

  {
    if (verbose)
      writeln( " // ---------- Make sure inversion works" );

    Matrix m_inv;
    
    bool success = matinv_inplace_dim( m, m_inv );

    assert( success );
    assert( m_inv.dim == [4, 4] );
    assert( approxEqual( m_inv.data, m_inv_truth.data
                         , 1e-10, 1e-10 ) );
  }

  {
    if (verbose)
      writeln( " // ---------- Test the functional wrapper" );

    
    Matrix m_inv = matinv( m );

    assert( m_inv.dim == [4, 4] );
    assert( approxEqual( m_inv.data, m_inv_truth.data
                         , 1e-10, 1e-10 ) );

  }

  {
    if (verbose)
      writeln( " // ---------- Test the functional wrapper" );

    auto a = Matrix( [4, 4], 123.0 );
    
    Matrix a_inv = matinv( a );

    assert( a_inv.dim == [4, 4] );
    assert( a_inv.data.all!isNaN );
  }

  writeln( "unittest passed: "~__FILE__ );
}
