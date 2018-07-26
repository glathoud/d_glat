module d_glat_common.flatmat.extract_matinv;

import std.algorithm;
import std.array;
import std.exception;
import std.math;
import std.range;
import std.stdio;
import std.typecons;

import d_glat_common.flatmat.mat_id;

// ---------- Runtime strategy

class FlatmatExtractMatinvWorkspace {

  ulong I, J;
  
  ulong IJ;

  mixin( flatmat_extract_matinv_decl_code() );
  
  void reinit( in ulong I, in ulong J )
  {
    if (this.I != I  ||  this.J != J)
      {
        debug writeln(" Flatmat_Extract_Matinv_Decl_Code reinit ", I
                      , " ", J
                      );
        this.I = I;
        this.J = J;
        
        IJ = I*J;
        
        mixin( flatmat_extract_matinv_init_code() );
      }
  }
  
}

bool flatmat_extract_matinv
// Returns `true` if the matrix inversion was a success,
// `false` otherwise.
//
// glat@glat.info
// 2017
  (
   // output
   ref double[] matinv  // `matinv.length == dim*dim`: square matrix
   // input
   , in ref double[] mat  // `mat.length == dim*dim`: square matrix
   , in ulong in_I
)
{
  // Default: square matrix
  return flatmat_extract_matinv( matinv, mat, in_I, in_I );
}

// Inner workspace cache for particular dimensions
private FlatmatExtractMatinvWorkspace[ulong][ulong] ws_of_IJ;
private Tuple!(const(ulong),const(ulong))[] last_IJ_arr;
private immutable LAST_IJ_ARR_LENGTH_MAX = 10;

bool flatmat_extract_matinv
// Returns `true` if the matrix inversion was a success,
// `false` otherwise.
//
// glat@glat.info
// 2017
  (
   // output
   ref double[] matinv  // `matinv.length == dim*dim`: square matrix
   // input
   , in ref double[] mat  // `mat.length == dim*dim`: square matrix
   , in ulong in_I
   , in ulong in_J
)
{
  // Automatic workspace allocation
  // Try to maximize re-use (cache)

  FlatmatExtractMatinvWorkspace ws;

  bool ws_found = false;
  if (auto pI = in_I in ws_of_IJ)
    {
      auto ws_of_J = *pI;
      if (auto pJ = in_J in ws_of_J)
        {
          ws = *pJ;
          ws_found = true;
        }
    }

  if (!ws_found)
    {
      // Forget the oldest workspace

      if (last_IJ_arr.length >= LAST_IJ_ARR_LENGTH_MAX)
        {
          foreach( tmp_IJ;
                   last_IJ_arr[ LAST_IJ_ARR_LENGTH_MAX-1..$ ]
                   )
            {
              auto tmp_I = tmp_IJ[ 0 ];
              auto tmp_J = tmp_IJ[ 1 ];
              ws_of_IJ[ tmp_I ].remove( tmp_J );
              
              if (ws_of_IJ[ tmp_I ].length < 1)
                ws_of_IJ.remove( tmp_I );
            }
          last_IJ_arr.length = LAST_IJ_ARR_LENGTH_MAX-1;
        }

      // Add the new workspace

      ws = new FlatmatExtractMatinvWorkspace;
      ws.reinit( in_I, in_J );
      
      ws_of_IJ[ in_I ][ in_J ] = ws;

      last_IJ_arr = [ tuple( in_I, in_J ) ] ~ last_IJ_arr;
    }
  
  return flatmat_extract_matinv( matinv, ws, mat, in_I, in_J );
}




bool flatmat_extract_matinv
// Returns `true` if the matrix inversion was a success,
// `false` otherwise.
//
// glat@glat.info
// 2017
  (
   // output
   ref double[] matinv  // `matinv.length == dim*dim`: square matrix
   // storage for temporary computation
   , ref FlatmatExtractMatinvWorkspace ws
   // input
   , in ref double[] mat  // `mat.length == dim*dim`: square matrix
   , in ulong in_I
)
{
  // Default: square matrix
  return flatmat_extract_matinv( matinv, ws, mat, in_I, in_I );
}

bool flatmat_extract_matinv
// Returns `true` if the matrix inversion was a success,
// `false` otherwise.
//
// glat@glat.info
// 2017
  (
   // output
   ref double[] matinv  // `matinv.length == dim*dim`: square matrix
   // storage for temporary computation
   , ref FlatmatExtractMatinvWorkspace ws
   // input
   , in ref double[] mat  // `mat.length == dim*dim`: square matrix
   , in ulong in_I
   , in ulong in_J
)
{
  ws.reinit( in_I, in_J );
  with( ws )
  {
    mixin( flatmat_extract_matinv_do_code() );
  }
}

// ---------- Compile-time strategy: should be faster, but `I,J`
// must be known at compile time.

bool flatmat_extract_matinv( alias I, alias J = I )
// Returns `true` if the matrix inversion was a success,
// `false` otherwise.
//
// glat@glat.info
// 2017
  (
   // output
   ref double[] matinv  // `matinv.length == dim*dim`: square matrix
   // input
   , in ref double[] mat  // `mat.length == dim*dim`: square matrix
)
{
  static assert( 0 < I   &&  I < (1 << 16) );
  static assert( 0 < J   &&  J < (1 << 16) );

  static immutable ulong impl_key = (cast(ulong)(I)) << 16 + J;

  if (auto p = impl_key in matinvImpl_of_key)
    {
      return (*p)( matinv, mat );
    }
  else
    {
      auto f = matinvImpl_of_key[ impl_key ]
        = make_matinvImpl( I, J );

      return f( matinv, mat );        
    }
}

unittest
{
  double[] m = [
            1, 4, 2, 17
            , 54, 23, 12, 56
            , 7, 324, 23, 56
            , 542, 3, 23, 43
                ];

  double[] minv =
    [
     0.02666295701993568, -0.010690122413924162, 0.0004032528845117337, 0.0028556842862368756
     , 0.03806261011863206, -0.016499239220523557, 0.0037736340871618243, 0.001524872452360714
     , -0.9276078787064798, 0.31489411381119636, -0.010628270423968902, -0.029524495155222024
     , 0.1574295505834409, -0.03253536166625731, 0.00033875009498698656, 0.0029466950714567243
     ];

  double[] id = flatmat_mat_id( 4 );
  
  double[] tmp = new double[ 16 ];
  double epsilon = 1e-16;
}

private:

alias matinvImplT =
  bool delegate( ref double[], in ref double[] );

matinvImplT[ ulong ] matinvImpl_of_key;

matinvImplT make_matinvImpl( in ulong I, in ulong J )
{
  // Implementation translated from JavaScript:
  // https://github.com/glathoud/flatorize/blob/master/lib/flatmat.j

  immutable ulong IJ = I*J;

  mixin( flatmat_extract_matinv_decl_code() );
  mixin( flatmat_extract_matinv_init_code() );

  return delegate( ref double[] matinv, in ref double[] mat )
    {
      mixin( flatmat_extract_matinv_do_code() );
    };
  
}



// ---------- String mixin

string flatmat_extract_matinv_decl_code()
{
  return q{
    double[] A_flat, B_flat, B_flat_init;
    double[][] A, B, A_init, B_init;
  };
}

string flatmat_extract_matinv_init_code()
{
  return q{
  
    A_flat.length = IJ;

    // B will be initialized with the identity matrix

    B_flat.length = IJ;
    B_flat_init = flatmat_mat_id( I, J );

    // For matrix inversion it is faster to work in 2-D the whole
    // time, probably because of faster row swaps.

    A = iota( 0, I )
      .map!( i => A_flat[ i*J..(i+1)*J ] )
      .array;
    B = iota( 0, I )
      .map!( i => B_flat[ i*J..(i+1)*J ] )
      .array;

    // remember the initial order of rows

    A_init = A.dup;
    B_init = B.dup;
  };
}
  
string flatmat_extract_matinv_do_code()
{
  return q{

    assert( IJ == matinv.length );
    assert( IJ == mat.length );

      // The intermediary values
      A_flat[] = mat[];
      B_flat[] = B_flat_init[];

      // remember the initial order of rows
      A[] = A_init[];
      B[] = B_init[];

      double[] Ai, Aj, Bi, Bj;
      
      for(long j=0;j<J;++j) {
        long i0 = -1;
        double v0 = -1;
        for(long i=j;i!=I;++i) {
          double k = abs(A[i][j]); if(k>v0) { i0 = i; v0 = k; }
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
            matinv[] = double.nan;
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
      
      for (long i = 0, ind = 0;
           i<I;
           ++i,
             ind += J
           )
        matinv[ ind..ind+J ] = B[ i ][];
      
      return true;
  };
}








unittest  // ------------------------------
{
  writeln;
  writeln( "unittest starts: extract_matinv" );

  immutable double[] m = [
                          1, 4, 2, 17
                          , 54, 23, 12, 56
                          , 7, 324, 23, 56
                          , 542, 3, 23, 43
                          ];
  
  immutable double[] minv =
    [
     0.02666295701993568, -0.010690122413924162, 0.0004032528845117337, 0.0028556842862368756
     , 0.03806261011863206, -0.016499239220523557, 0.0037736340871618243, 0.001524872452360714
     , -0.9276078787064798, 0.31489411381119636, -0.010628270423968902, -0.029524495155222024
     , 0.1574295505834409, -0.03253536166625731, 0.00033875009498698656, 0.0029466950714567243
     ];

  immutable double[] mid = assumeUnique( flatmat_mat_id( 4 ) );

  double[] tmp = new double[ 16 ];
  double epsilon = 1e-10;

  debug writeln
    ( " // ---------- Make sure inversion failure leads to nan-fill" );

  tmp[] = 123;
  double[] zeros = new double[ tmp.length ];
  zeros[] = 0;

  assert( tmp[ 0 ] == 123 );
  flatmat_extract_matinv( tmp, zeros, 4 );
  assert( isNaN( tmp[ 0 ] ) );
  

  debug writeln
    ( " // ---------- Runtime stragegy with automatic workspace" );

  tmp[] = double.nan;

  // When running with -debug this time the message
  // "Flatmat_Extract_Matinv_Decl_Code reinit 4 4" should appear
  flatmat_extract_matinv( tmp, m, 4 );
  {
    double[] diff = new double[ 16 ];
    diff[] = tmp[] - minv[];
    // writeln( "extract_matinv: diff: ", diff );
    
    double maxdiff = diff.map!abs.reduce!max;
    assert( epsilon > maxdiff );    
  }


  tmp[] = double.nan;

  // When running with -debug this time the message
  // "Flatmat_Extract_Matinv_Decl_Code reinit 4 4" should NOT appear
  flatmat_extract_matinv( tmp, m, 4 );
  {
    double[] diff = new double[ 16 ];
    diff[] = tmp[] - minv[];
    // writeln( "extract_matinv: diff: ", diff );
    
    double maxdiff = diff.map!abs.reduce!max;
    assert( epsilon > maxdiff );    
  }

  
  debug writeln
    ( " // ---------- Runtime strategy with manual workspace" );
  
  auto ws = new FlatmatExtractMatinvWorkspace;

  tmp[] = double.nan;

  // When running with -debug this time the message
  // "Flatmat_Extract_Matinv_Decl_Code reinit 4 4" should appear
  flatmat_extract_matinv( tmp, ws, m, 4 );
  {
    double[] diff = new double[ 16 ];
    diff[] = tmp[] - minv[];
    // writeln( "extract_matinv: diff: ", diff );
    
    double maxdiff = diff.map!abs.reduce!max;
    assert( epsilon > maxdiff );    
  }

  tmp[] = double.nan;

  // When running with -debug this time the message
  // "Flatmat_Extract_Matinv_Decl_Code reinit 4 4" should NOT appear
  flatmat_extract_matinv( tmp, ws, m, 4 );
  {
    double[] diff = new double[ 16 ];
    diff[] = tmp[] - minv[];
    // writeln( "extract_matinv: diff: ", diff );
    
    double maxdiff = diff.map!abs.reduce!max;
    assert( epsilon > maxdiff );    
  }


  
  // ---------- Compile-time strategy
  
  tmp[] = double.nan;

  flatmat_extract_matinv!( 4 )( tmp, m );

  {
    double[] diff = new double[ 16 ];
    diff[] = tmp[] - minv[];
    // writeln( "extract_matinv: diff: ", diff );
    
    double maxdiff = diff.map!abs.reduce!max;
    assert( epsilon > maxdiff );
  }

  writeln( "unittest passed: extract_matinv" );
}
