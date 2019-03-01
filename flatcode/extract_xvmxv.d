module d_glat.flatcode.extract_xvmxv;

import std.algorithm;
import std.math;
import std.range;
import std.stdio;

// ---------- Runtime strategy

class FlatcodeExtractXvmxvWorkspace {

  double[] x_minus_v;

  void reinit( ulong dim )
  {
    assert( 0 < dim );
    
    if (dim != x_minus_v.length)
      {
        debug writeln( " FlatcodeExtractXvmxvWorkspace reinit "
                       , dim );

        x_minus_v.length = dim;
      }
  }

}

// Inner workspace cache for particular dimensions
private FlatcodeExtractXvmxvWorkspace[ulong] ws_of_dim;
private ulong[] last_dim_arr;
private immutable LAST_DIM_ARR_LENGTH_MAX = 10;

void flatcode_extract_xvmxv
( // Output
 double[] out_xvmxv_arr
 // Inputs
 , in ref double[] in_v  // `dim*1` vector
 , in ref double[] in_m  // `dim*dim` matrix
 , in ref double[][] datavect_arr  // Each vector has dimentionality `dim`
  )
{
  ulong dim = datavect_arr[ 0 ].length;
  ulong n_datavect = datavect_arr.length;
  
  // Automatic workspace allocation
  // Try to maximize re-use (cache)

  FlatcodeExtractXvmxvWorkspace ws;

  bool ws_found = false;
  if (auto p = dim in ws_of_dim)
    {
      ws = *p;
      ws_found = true;
    }

  if (!ws_found)
    {
      // Forget the oldest workspace

      if (last_dim_arr.length >= LAST_DIM_ARR_LENGTH_MAX)
        {
          foreach( tmp_dim;
                   last_dim_arr[ LAST_DIM_ARR_LENGTH_MAX-1..$ ]
                   )
            {
              ws_of_dim.remove( dim );
            }
          last_dim_arr.length = LAST_DIM_ARR_LENGTH_MAX-1;
        }

      // Add the new workspace

      ws = new FlatcodeExtractXvmxvWorkspace;
      ws.reinit( dim );
      
      ws_of_dim[ dim ] = ws;

      last_dim_arr = [ dim ] ~ last_dim_arr;
    }
  
  flatcode_extract_xvmxv( out_xvmxv_arr
                         , ws
                         , in_v, in_m, datavect_arr
                         );
}


void flatcode_extract_xvmxv
( // Output
 double[] out_xvmxv_arr
 // Temporary workspace (to spare the GC)
 , ref FlatcodeExtractXvmxvWorkspace ws
 // Inputs
 , in ref double[] in_v  // `dim*1` vector
 , in ref double[] in_m  // `dim*dim` matrix
 , in ref double[][] datavect_arr  // Each vector has dimentionality `dim`
  )
{
  ulong dim = datavect_arr[ 0 ].length;
  assert( dim == in_v.length );
  assert( dim * dim == in_m.length );

  auto n_datavect = datavect_arr.length;
  assert( n_datavect <= out_xvmxv_arr.length );
  
  ws.reinit( dim );

  double[] x_minus_v = ws.x_minus_v;

  foreach( k, x; datavect_arr)
    {
      double y = 0;

      for( ulong i = dim; i--; )
        x_minus_v[ i ] = x[ i ] - in_v[ i ];
      
      for (ulong j = 0; j < dim; ++j)
        {
          double tmp_j = 0;
          for (ulong i = 0, m_offset = j;
               i < dim;
               ++i, m_offset += dim)
            {
              tmp_j += x_minus_v[ i ] * in_m[ m_offset ];
            }
          
          y += tmp_j * x_minus_v[ j ];
        }
      
      out_xvmxv_arr[ k ] = y;
    }

}





unittest  // ------------------------------
{
  writeln;
  writeln( "unittest starts: extract_xvmxv" );
  
  /*
    Existing, proofed JavaScript implementation to generate the test
    data:

    http://glat.info/flatorize/lib/flatcode_speedtest.html#speedtest-xvmxv
    
    hand_xvmxv = hand_xvmxv_of_dim(4);
    
    var x_1 = [ 1.234, 34.543, -17.234, -2.3214 ];
    var v = [ -1, -2, -3, -7 ];
    var m = [ -12.4325, 6.23, +6, -2.34,
              +123.432, 7.53, -3.4, +3.45,
              -7.88, +4.55, -2.342, +1.11,
              -2.3, +4.23, 3342.3, 2.123 ];
              
    var out_1 = hand_xvmxv( x, v, m );  // -201778.23740491495

    var x_2 = [ 5.345, 67.765, 2.342, -11 ];
    var out_2 = hand_xvmxv( x_2, v, m );  // 20409.796742899485

    var x_3 = [ 345.534, 675.45, -23.4324, 0.1123 ];
    var out_3 = hand_xvmxv( x_3, v, m );  // 31938442.85301983
    
   */

  double[] v = [ -1, -2, -3, -7 ];
  double[] m = [ -12.4325, 6.23, +6, -2.34,
                 +123.432, 7.53, -3.4, +3.45,
                 -7.88, +4.55, -2.342, +1.11,
                 -2.3, +4.23, 3342.3, 2.123 ];

  double[][] datavect_arr =
    [
     [ 1.234, 34.543, -17.234, -2.3214 ],
     [ 5.345, 67.765, 2.342, -11 ],
     [ 345.534, 675.45, -23.4324, 0.1123 ]
     ];

  double[] obtained = new double[ datavect_arr.length ];

  // When running with -debug this time the message
  // "FlatcodeExtractXvmxvWorkspace reinit 4" should appear
  flatcode_extract_xvmxv( obtained, v, m, datavect_arr );

  immutable double[] expected =
    [
     -201778.23740491495,
     20409.796742899485,
     31938442.85301983
     ];

  {
    double max_diff = zip( obtained, expected )
      .map!( t => abs( t[ 0 ] - t[ 1 ] ) )
      .reduce!max;
    
    debug writeln( " max_diff: ", max_diff );
    
    assert( max_diff < 1e-10 );
  }

  // Again

  obtained[] = double.nan;

  // When running with -debug this time the message
  // "FlatcodeExtractXvmxvWorkspace reinit 4" should NOT appear
  flatcode_extract_xvmxv( obtained, v, m, datavect_arr );

  {
    double max_diff = zip( obtained, expected )
      .map!( t => abs( t[ 0 ] - t[ 1 ] ) )
      .reduce!max;
    
    debug writeln( " max_diff: ", max_diff );
    
    assert( max_diff < 1e-10 );
  }
  
  
  writeln( "unittest passed: extract_xvmxv" );
}
