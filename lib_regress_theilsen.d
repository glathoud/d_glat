module d_glat.lib_regress_theilsen;

import d_glat.core_array;
import d_glat.core_math;
import std.array;

/*
  Theil-Sen linear regression (i.e. median-based i.e. robust to outliers).

  By Guillaume Lathoud, 2024
  glat@glat.info

  The Boost license applies to this file, as described in ./LICENSE
 */

void regress_theilsen(T)( in T[] y, in T[] x
                          , /*outputs:*/ref T m, ref T b )
/*
  TheilSen linear regression (i.e. median-based i.e. robust to outliers)

  Set output values for `m` and `b` so that `y` close to `x * m + b`.

  For a matrix wrapper, see ./flatmatrix/lib_regress.d
 */
{
  regress_theilsen!T( y, x, m );
  
  scope tmp = y.dup;
  tmp[] -= m * x[];
  b = median( tmp );
}


void regress_theilsen(T)( in T[] y, in T[] x
                          , /*output:*/ref T m )
/*
  TheilSen linear regression (i.e. median-based i.e. robust to outliers)

  Set output values for `m` and `b` so that `y` close to `x * m + b`.

  For a matrix wrapper, see ./flatmatrix/lib_regress.d
 */
{
  immutable n = y.length;
  debug assert( n == x.length );

  scope slopes = new T[ (n * (n-1)) >> 1 ];
  {
    size_t i_s = 0;
    foreach (i; 0..n)
      {
        immutable yi = y[ i ];
        immutable xi = x[ i ];
      
        foreach (j; i+1..n)
          slopes[ i_s++ ] = (y[ j ] - yi) / (x[ j ] - xi);
      }
    debug assert( i_s == slopes.length );
  }
  m = median( slopes );
}

T[] apply_theilsen_multi(T)( in T[] x, in T[] m_arr, in T[] b_arr ) pure nothrow @safe
// Robust in the application as well: use median to estimate y.
{
  immutable d = m_arr.length;
  immutable n = x.length / d;
  
  auto y_estim = new T[ n ];
  scope buff   = new T[ d ];
  apply_theilsen_multi_inplace!T( x, m_arr, b_arr, buff, y_estim );
  return y_estim;
}

void apply_theilsen_multi_inplace(T)( in T[] x, in T[] m_arr, in T[] b_arr
                                      , /*intermediary:*/ref T[] buff
                                      , /*output:*/ref T[] y_estim
                                      ) pure nothrow @safe
// Robust in the application as well: use median to estimate y.
{
  immutable d = m_arr.length;
  immutable n = x.length / d;

  arr_ensure_length( d, buff );
  arr_ensure_length( n, y_estim );

  apply_theilsen_multi_inplace_nogc!T( x, m_arr, b_arr, buff, y_estim );
}

void apply_theilsen_multi_inplace_nogc(T)( in T[] x, in T[] m_arr, in T[] b_arr
                                           , /*intermediary:*/ref T[] buff
                                           , /*output:*/ref T[] y_estim
                                           ) pure nothrow @safe @nogc
// Robust in the application as well: use median to estimate y.
{
  immutable d = m_arr.length;
  immutable n = x.length / d;

  debug
    {
      assert( n*d == x.length );
      assert( d == b_arr.length );
      assert( d == buff.length );
      assert( n == y_estim.length );
    }

  y_estim[] = 0.0;

  size_t ix = 0;
  foreach (i; 0..n)
    {
      immutable next_ix = ix + d;

      buff[] = m_arr[] * x[ix..next_ix][] + b_arr[];
      y_estim[ i ] = median_inplace( buff );

      ix = next_ix;
    }
}



void regress_theilsen_multi(T)( in T[] y, in T[] x
                                , /*outputs:*/ref T[] m_arr, ref T[] b_arr )
/*
  TheilSen linear regression (i.e. median-based i.e. robust to outliers)

  For each dimension `a` of `x` separately, set output values for `m_arr[a]`
  and `b_arr[a]` so that `y[]` close to `x[a,a+d,a+2d,...][] * m_arr[a] + b_arr[a]`.
  
  For a matrix wrapper, see ./flatmatrix/lib_regress.d
 */
{
  immutable n = y.length;
  immutable d = x.length / n;
  immutable nd = n*d;
  debug assert( nd == x.length );

  arr_ensure_length( d, m_arr );
  arr_ensure_length( d, b_arr );

  regress_theilsen_multi!T( y, x, m_arr );

  T[] tmp;
  foreach (a; 0..d)
    {
      immutable m = m_arr[ a ];
      tmp = y.dup;
      for (size_t i = 0, ix = a;
           i < n;
           ++i, ix += d)
        {
          tmp[ i ] -= m * x[ ix ];
        }
        
      b_arr[ a ] = median( tmp );
    }
}

void regress_theilsen_multi(T)( in T[] y, in T[] x
                                , /*outputs:*/ref T[] m_arr )
/*
  TheilSen linear regression (i.e. median-based i.e. robust to outliers)

  For each dimension `a` of `x` separately, set output values for `m_arr[a]`
  and `b_arr[a]` so that `y[]` close to `x[a,a+d,a+2d,...][] * m_arr[a] + b_arr[a]`.
  
  For a matrix wrapper, see ./flatmatrix/lib_regress.d
 */
{
  immutable n = y.length;
  immutable d = x.length / n;
  immutable nd = n*d;
  debug assert( nd == x.length );

  arr_ensure_length( d, m_arr );

  scope slopes = new T[ (n * (n-1)) >> 1 ];
  foreach (a; 0..d)
    {
      {
        size_t i_s = 0;
        for (size_t i = 0, ix = a;
             i < n;
             ++i, ix += d)
          {
            immutable yi = y[ i ];
            immutable xi = x[ ix ];
          
            for (size_t j = i+1, jx = ix+d;
                 j < n;
                 ++j, jx += d)
              {
                slopes[ i_s++ ] = (y[ j ] - yi) / (x[ jx ] - xi);
              }
          }
        debug assert( i_s == slopes.length );
      }
      m_arr[ a ] = median( slopes );
    }
}



unittest
{
  import std.stdio;
  import std.path;

  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  immutable verbose = false;

  import std.random;
  import std.algorithm;
  import std.exception;
  import std.range;

  // ---------- 1-D

  {
    auto rnd = MinstdRand0(42);

    immutable true_m = 2.345;
    immutable true_b = 7.987;

    immutable x = [1.0,  9.0, 7.0, 3.0, -5.0, 6.0, 11.1, 7.77];
    immutable true_y = (){
      auto tmp = x.dup;
      tmp[] = x[] * true_m + true_b;
      return assumeUnique( tmp );
    }();

    {
      double m, b;
      regress_theilsen( true_y, x, m, b );

      if (verbose)
        writeln("[m, true_m, b, true_b]:",[m, true_m, b, true_b]);
      
      assert( isClose( m, true_m ) );
      assert( isClose( b, true_b ) );
    }

    immutable noisy_y = (){
      auto tmp = true_y.map!((x) => x + uniform( -0.1, +0.1, rnd )).array;
      return assumeUnique( tmp );
    }();

    {
      double m2, b2;
      
      regress_theilsen( noisy_y, x, m2, b2 );

      if (verbose)
        writeln("[m2, true_m, b2, true_b]:",[m2, true_m, b2, true_b]);
      
      assert( isClose( m2, true_m, 0.03 ) );
      assert( isClose( b2, true_b, 0.03 ) );
    }

    immutable noisy_y_outliers = (){
      auto tmp = noisy_y.dup;
      tmp[ 1 ] += 100.0;
      tmp[ 4 ] += 1000.0;
      return assumeUnique( tmp );
    }();

    {
      double m3, b3;
      
      regress_theilsen( noisy_y_outliers, x, m3, b3 );

      if (verbose)
        writeln("[m3, true_m, b3, true_b]:",[m3, true_m, b3, true_b]);
      
      assert( isClose( m3, true_m, 0.03 ) );
      assert( isClose( b3, true_b, 0.03 ) );
    }
  }


  // ---------- 1-D using the N-D API

  {
    auto rnd = MinstdRand0(42);

    immutable true_m = [2.345];
    immutable true_b = [7.987];

    immutable x = [1.0,  9.0, 7.0, 3.0, -5.0, 6.0, 11.1, 7.77];
    immutable true_y = (){
      auto tmp = x.dup;
      tmp[] = x[] * true_m[ 0 ] + true_b[ 0 ];
      return assumeUnique( tmp );
    }();

    {
      double[] m, b;
      regress_theilsen_multi( true_y, x, m, b );

      if (verbose)
        writeln("[m, true_m, b, true_b]:",[m, true_m, b, true_b]);
      
      assert( isClose( m, true_m ) );
      assert( isClose( b, true_b ) );
    }

    immutable noisy_y = (){
      auto tmp = true_y.map!((x) => x + uniform( -0.1, +0.1, rnd )).array;
      return assumeUnique( tmp );
    }();

    {
      double[] m2, b2;
      
      regress_theilsen_multi( noisy_y, x, m2, b2 );

      if (verbose)
        writeln("[m2, true_m, b2, true_b]:",[m2, true_m, b2, true_b]);
      
      assert( isClose( m2, true_m, 0.03 ) );
      assert( isClose( b2, true_b, 0.03 ) );
    }

    immutable noisy_y_outliers = (){
      auto tmp = noisy_y.dup;
      tmp[ 1 ] += 100.0;
      tmp[ 4 ] += 1000.0;
      return assumeUnique( tmp );
    }();

    {
      double[] m3, b3;
      
      regress_theilsen_multi( noisy_y_outliers, x, m3, b3 );

      if (verbose)
        writeln("[m3, true_m, b3, true_b]:",[m3, true_m, b3, true_b]);
      
      assert( isClose( m3, true_m, 0.03 ) );
      assert( isClose( b3, true_b, 0.03 ) );
    }
  }


  // ---------- N-D

  {
    auto rnd = MinstdRand0(42);

    immutable true_m = [2.345, -30.11, +231.0];
    immutable true_b = [7.987, +13.23,  +73.4];

    immutable v0 = [1.0,  9.0, 7.0, 3.0, -5.0, 6.0, 11.1, 7.77];
    immutable n  = v0.length;
    immutable true_y = (){
      auto tmp = v0.dup;
      tmp[] = v0[] * true_m[ 0 ] + true_b[ 0 ];
      return assumeUnique( tmp );
    }();

    immutable v1 = (){
      auto tmp = true_y.dup;
      tmp[] = (true_y[] - true_b[ 1 ]) / true_m[ 1 ];
      return assumeUnique( tmp );
    }();
  
    immutable v2 = (){
      auto tmp = true_y.dup;
      tmp[] = (true_y[] - true_b[ 2 ]) / true_m[ 2 ];
      return assumeUnique( tmp );
    }();

    immutable x = (){
      auto tmp = new double[ n*3 ];
      size_t j = 0;
      foreach (i; 0..n)
      {
        tmp[ j++ ] = v0[ i ];
        tmp[ j++ ] = v1[ i ];
        tmp[ j++ ] = v2[ i ];
      }
      return assumeUnique( tmp );
    }();

    if (verbose)
      writeln("N-D x: ", x);
    
    {
      double[] m, b;
      regress_theilsen_multi( true_y, x, m, b );

      if (verbose)
        writeln("N-D [m, true_m, b, true_b]:",[m, true_m, b, true_b]);
      
      assert( isClose( m, true_m ) );
      assert( isClose( b, true_b ) );
    }

    immutable noisy_x = (){
      auto tmp = x.map!((x) => x + uniform( -0.01, +0.01, rnd )).array;
      return assumeUnique( tmp );
    }();

    {
      double[] m2, b2;
      
      regress_theilsen_multi( true_y, noisy_x, m2, b2 );

      if (verbose)
        writeln("N-D [m2, true_m, b2, true_b]:",[m2, true_m, b2, true_b]);
      
      assert( isClose( m2, true_m, 0.03 ) );
      assert( isClose( b2, true_b, 0.03 ) );
    }

    immutable noisy_y = (){
      auto tmp = true_y.map!((x) => x + uniform( -0.1, +0.1, rnd )).array;
      return assumeUnique( tmp );
    }();

    {
      double[] m2, b2;
      
      regress_theilsen_multi( noisy_y, x, m2, b2 );

      if (verbose)
        writeln("N-D [m2, true_m, b2, true_b]:",[m2, true_m, b2, true_b]);
      
      assert( isClose( m2, true_m, 0.03 ) );
      assert( isClose( b2, true_b, 0.03 ) );
    }

    {
      double[] m2, b2;
      
      regress_theilsen_multi( noisy_y, noisy_x, m2, b2 );

      if (verbose)
        writeln("N-D [m2, true_m, b2, true_b]:",[m2, true_m, b2, true_b]);
      
      assert( isClose( m2, true_m, 0.03 ) );
      assert( isClose( b2, true_b, 0.03 ) );
    }

    immutable noisy_y_outliers = (){
      auto tmp = noisy_y.dup;
      tmp[ 1 ] += 100.0;
      tmp[ 4 ] += 1000.0;
      return assumeUnique( tmp );
    }();

    {
      double[] m3, b3;
      
      regress_theilsen_multi( noisy_y_outliers, x, m3, b3 );

      if (verbose)
        writeln("N-D [m3, true_m, b3, true_b]:",[m3, true_m, b3, true_b]);
      
      assert( isClose( m3, true_m, 0.03 ) );
      assert( isClose( b3, true_b, 0.03 ) );
    }

    {
      double[] m3, b3;
      
      regress_theilsen_multi( noisy_y_outliers, noisy_x, m3, b3 );

      if (verbose)
        writeln("N-D [m3, true_m, b3, true_b]:",[m3, true_m, b3, true_b]);
      
      assert( isClose( m3, true_m, 0.03 ) );
      assert( isClose( b3, true_b, 0.03 ) );
    }

    auto noisy_x_outliers = (){
      auto tmp = noisy_x.dup;
      tmp[ 1 ] += 100.0;
      tmp[ 13 ] -= 233.0;
      tmp[ 17 ] += 342.123;
      tmp[ 21 ] -= 700.0;
      return tmp;
    }();

    {
      double[] m4, b4;
      
      regress_theilsen_multi( noisy_y, noisy_x_outliers, m4, b4 );

      if (verbose)
        writeln("N-D [m4, true_m, b4, true_b]:",[m4, true_m, b4, true_b]);
      
      assert( isClose( m4, true_m, 0.1 ) );
      assert( isClose( b4, true_b, 0.1 ) );

      auto y_estim = apply_theilsen_multi( noisy_x_outliers, m4, b4 );

      if (verbose)
        {
          writeln( "N-D 4 x:                ", x );
          writeln( "N-D 4 noisy_x_outliers: ", noisy_x_outliers );
          writeln( "N-D 4 y_estim:          ", y_estim );
          writeln( "N-D 4 true_y:           ", true_y );
        }
    }
    
  }
    
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}

