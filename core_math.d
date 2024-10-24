module d_glat.core_math;

public import std.math;

import d_glat.core_array;
import d_glat.core_profile_acc;
import d_glat.flatmatrix.lib_stat : MatrixT, mean_cov_inplace_dim;
import std.algorithm : reduce, sort;
import std.exception : enforce;
import std.traits : hasMember, isArray, isCallable;

/*
  A few mathematical tool functions.

  By Guillaume Lathoud, 2019
  glat@glat.info

  The Boost license applies to this file, as described in ./LICENSE
 */

T[] cumsum( T )( in T[] arr ) pure nothrow @safe
{
  immutable n = arr.length;
  auto ret = new T[ n ];

  T v_cumsum = ret[ 0 ] = arr[ 0 ];
  foreach (i; 1..n)
    ret[ i ] = v_cumsum = v_cumsum + arr[ i ];

  return ret;
}



alias Buffer_e_w_logsum = Buffer_e_w_logsumT!double;

class Buffer_e_w_logsumT(T) : ProfileMemC
{
  T[] logsum_buffer;
  T[] work;
}

bool equal_nan(T)( in T a, in T b )   pure nothrow @safe @nogc
// Extended equal that also permits matching NaNs.  For an array
// version, `arr_equal_nan` in ./core_array.d
{
  static if (hasMember!(T, "nan")) // e.g. is(T==double)
    {
      if (isNaN( a )  &&  isNaN( b ))
        return true;
    }

  return a == b;
}

T e_w_logsum( T )( in T[] a_arr, in T[] logw_arr )
  @safe
// Wrapper that creates a temporary buffer
{ 
  scope auto buffer = new Buffer_e_w_logsumT!T;
  return e_w_logsum_dim( a_arr, logw_arr, buffer );
}



T e_w_logsum_dim( T )( in T[] a_arr, in T[] logw_arr
                       , ref Buffer_e_w_logsumT!T buffer
                       ) pure nothrow @safe
/* Input: 2 arrays containing `a_i` resp. `log(w_i)`.

   Output: `sum_i( a_i * w_i )` calculated as precisely as `logsum`
   permits.

   Implementation: two `logsum` calls, one for positive values
   (`a_i>0.0`), one for negative values (`a_i<0.0`);
*/
{
  immutable n = a_arr.length;
  
  debug assert( n == logw_arr.length );

  // Limit GC costs

  ensure_length( n, buffer.logsum_buffer );
  ensure_length( n, buffer.work );

  return e_w_logsum_nogc!T( a_arr, logw_arr, buffer );
}


T e_w_logsum_nogc( T )( in T[] a_arr, in T[] logw_arr
                        , ref Buffer_e_w_logsumT!T buffer
                        )   pure nothrow @safe @nogc
/* Input: 2 arrays containing `a_i` resp. `log(w_i)`.

   Output: `sum_i( a_i * w_i )` calculated as precisely as `logsum`
   permits.

   Implementation: two `logsum` calls, one for positive values
   (`a_i>0.0`), one for negative values (`a_i<0.0`);
*/
{
  immutable n = a_arr.length;
  
  debug assert( n == logw_arr.length );

  scope auto logsum_buffer = buffer.logsum_buffer;
  scope auto work          = buffer.work;

  assert( n == logsum_buffer.length );
  assert( n == work.length );

  size_t j_pos = 0; // positive values => work[0..j_pos]
  size_t j_neg = n; // negative values => work[j_neg..$]

  foreach (i,a_i; a_arr)
    {
      if (a_i > 0.0)
        work[ j_pos++ ] = log( a_i ) + logw_arr[ i ];
        
      else if (a_i < 0.0)
        work[ --j_neg ] = log( -a_i ) + logw_arr[ i ];
    }
  
  T ret = 0.0;

  if (0 < j_pos)
    {
      auto lsb_pos = logsum_buffer[ 0..j_pos ];
      ret += exp( logsum_nogc( work, 0, j_pos, lsb_pos ) );
    }

  if (j_neg < n)
    {
      auto lsb_neg = logsum_buffer[ j_neg..n ];
      ret -= exp( logsum_nogc( work, j_neg, n, lsb_neg ) );
    }

  return ret;
}


void linreg( in double[] x_arr, in double[] y_arr
             , out double alpha, out double beta )
{
  assert( x_arr.length == y_arr.length );
  
  double sum_x = 0.0, sum_y = 0.0, sum_xy = 0.0, sum_x2 = 0.0;

  foreach (k,x; x_arr)
    {
      immutable y = y_arr[ k ];
      sum_x += x;
      sum_y += y;
      sum_xy += x*y;
      sum_x2 += x*x;
    }
  
  // https://en.wikipedia.org/wiki/Simple_linear_regression

  immutable odN = 1.0 / cast(double)( x_arr.length );
  
  beta = (sum_xy - odN * sum_x * sum_y) / (sum_x2 - odN * sum_x * sum_x);

  alpha = odN * (sum_y - beta * sum_x);
}


T logsum( T )( in T[] arr )
pure nothrow @safe
/* Input log(data), output: log(sum(data))
 
 Addition done in a smart way to minimize precision loss.

 Practical node: if the logsum is greater than say 1e10, you might
 want to post-process (e.g. rescale) to compensate for the overflow.
*/
{
  immutable n = arr.length;
  scope auto buffer = new T[n];
  
  return logsum_nogc!T( arr, 0, n, buffer );
}

T logsum_nogc( T )( in T[] arr, in size_t i_begin, in size_t i_end
                    , T[] buffer
                    )
pure nothrow @safe @nogc
/*
 Input log(data) := arr[i_begin..i_end]

 Output: log(sum(data))
 
 Addition done in a smart sorted way to minimize precision loss.

 Some explanation can be found e.g. here 
http://www.glat.info/ma/2006-CHN-USS-TIME-DOMAIN/my_logsum_fast.pdf

 Practical node: if the logsum is greater than say 1e10, you might
 want to post-process (e.g. rescale) to compensate for the overflow.
*/
{
  immutable n = buffer.length;

  debug assert( i_begin < i_end );
  debug assert( i_end - i_begin == n );

  buffer[] = arr[ i_begin..i_end ][];
  buffer.sort;

  immutable one = cast( T )( 1.0 );
  
  size_t step = 1;
  size_t step_pow = 0;
  
  while (step < n)
    {
      immutable next_step = step << 1;

      immutable j_end = ((n-1) >>> step_pow) << step_pow;
      
      debug assert( j_end > 0 );
      
      for (size_t j = 0; j < j_end;)
        {
          immutable j0 = j;
          
          T a = buffer[ j ];  j += step;
          T b = buffer[ j ];  j += step;
          
          buffer[ j0 ] = b + log( one + exp( a - b ) );
        }
      
      step = next_step;
      ++step_pow;
    }

  return buffer[ 0 ];
}


T mean_of_arr(T)( in T[] arr )
{
  return arr.reduce!"a+b" / cast(T)( arr.length );
}

double stddev_of_arr(bool unbiased = true,T)( in T[] arr )
{
  double v_mean, v_stddev;
  mean_stddev_inplace!(unbiased, T)( arr, v_mean, v_stddev );
  return v_stddev;
}


void mean_stddev_inplace(bool unbiased = true, T)( in T[] arr, ref T v_mean, ref T v_stddev )
{
  immutable N = arr.length;
  scope auto m      = MatrixT!T( [N, 1], cast(T[])( arr ) );
  scope auto m_mean = MatrixT!T( [1, 1] );
  scope auto m_cov  = MatrixT!T( [1, 1] );

  if (1 == arr.length)
    {
      v_mean   = arr[ 0 ];
      v_stddev = cast(T)( 0 );
    }
  else
    {
      mean_cov_inplace_dim!(unbiased, /*diag_only:*/true, T)( m, m_mean, m_cov );
      v_mean   = m_mean.data[ 0 ];
      v_stddev = sqrt( m_cov .data[ 0 ] );
    }
}


T median( T )( in T[] arr )
pure nothrow @safe
{
  return median_inplace( arr.dup );
}

T ratio_finite(T, alias final_modif = false)( in T num, in T denom ) pure nothrow @safe @nogc
{
  immutable r0 = 0.0 == denom
    ?  (0.0   < num  ?  +T.max
        : 0.0 > num  ?  -T.max
        : 0.0)
    :  num / denom
    ;

  static if (isCallable!final_modif)
    return final_modif( r0 );
  else
    return r0;
}

T ratio_finite_symlog7(T)( in T num, in T denom ) pure nothrow @safe @nogc
{
  return ratio_finite!(T, symlog7!T)( num, denom );
}



T symlog7(T)( in T x ) pure nothrow @safe @nogc { return symlog( x, 1e7 ); }
T symlog(T)( in T x, in T one_div_eps ) pure nothrow @safe @nogc
// Symmetric logarithm. Visually:
// http://glat.info/plot/#x%3Dt%2F100%2Cone_div_eps%3D1e7%2C(x%20%3C%200.0%20%3F%20%20-1.0%20%20%3A%20%20%2B1.0)%20*log(%201.0%20%2Babs(%20x%20)%20*one_div_eps)
{
  immutable y0 = 1.0 + abs( x ) * one_div_eps;
  static if (__traits( isFloating, T ))
    {
      immutable y =
        y0 == T.infinity  ?  T.max
        :  y0 == -T.infinity  ?  -T.max
        :  y0;
    }
  else
    {
      alias y = y0;
    }
  
  return (x < 0.0 ?  -1.0  :  +1.0) * log( y );
}

T undefined(T)()
{
  static if (__traits( isFloating, T ))
    {
      return T.nan;
    }
  else
    {
      static if (__traits( isUnsigned, T ))
        return T.max;
      else
        return -T.max;
    }
}


T median_inplace( T )( T[] arr )
  pure nothrow @safe @nogc
{
  immutable n = arr.length;

  if (1 > n)
      return undefined!T;

  if (2 > n)
    return arr[ 0 ];
  
  arr.sort;
  immutable half = cast( T )( 0.5 );

  return 1 == n % 2
    ?  arr[ $>>1 ]
    :  (arr[ $>>1 ] + arr[ ($-1)>>1 ]) * half;
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
  import std.range;

  auto buffer_e_w_logsum = new Buffer_e_w_logsum;
  
  {
    
    auto rnd = MinstdRand0(42);
    
    foreach (n; 1..301)
      {
        double[] data    = iota(0,n).map!(_ => uniform( cast( double )( 1.0 ), cast( double )( 100.0 ), rnd )).array;
        double[] logdata = data.map!"cast( double )( log(a) )".array;
        double   logsum  = logsum( logdata );
        immutable double logsum_expected = log( data.reduce!"a+b" );
        
        if (verbose)
          {
            writeln;
            writeln("n: ", n);
            writeln("data: ", data);
            writeln("logsum, expected: ", [logsum, logsum_expected], " delta:", logsum - logsum_expected);
          }

        assert( isClose( logsum, logsum_expected, 1e-8, 1e-8 ) );
      }

  }


  {
    
    auto rnd = MinstdRand0(42);
    
    foreach (n; 1..301)
      {
        double[] data     = iota(0,n).map!(_ => uniform( cast( double )( -100.0 ), cast( double )( 100.0 ), rnd )).array;
        if (n > 36) data[ 36 ] = 0.0;
        if (n > 77) data[ 77 ] = 0.0;
        
        double[] wdata    = iota(0,n).map!(_ => uniform( cast( double )( 1.0 ), cast( double )( 100.0 ), rnd )).array;
        double[] logwdata = wdata.map!"cast( double )( log(a) )".array;
        
        immutable double weighted_sum          = e_w_logsum_dim( data, logwdata, buffer_e_w_logsum );
        immutable double weighted_sum_expected = zip( data, wdata ).map!"a[0]*a[1]".reduce!"a+b";
        
        if (verbose)
          {
            writeln;
            writeln("n: ", n);
            writeln("data: ", data);
            writeln("weighted_sum, expected: ", [weighted_sum, weighted_sum_expected], " delta:", weighted_sum - weighted_sum_expected);
          }

        assert( isClose( weighted_sum, weighted_sum_expected, 1e-8, 1e-8 ) );
      }

  }


  
  {
    // Same without external buffer
    
    auto rnd = MinstdRand0(42);
    
    foreach (n; 1..301)
      {
        double[] data     = iota(0,n).map!(_ => uniform( cast( double )( -100.0 ), cast( double )( 100.0 ), rnd )).array;
        if (n > 36) data[ 36 ] = 0.0;
        if (n > 77) data[ 77 ] = 0.0;
        
        double[] wdata    = iota(0,n).map!(_ => uniform( cast( double )( 1.0 ), cast( double )( 100.0 ), rnd )).array;
        double[] logwdata = wdata.map!"cast( double )( log(a) )".array;
        
        immutable double weighted_sum          = e_w_logsum( data, logwdata );
        immutable double weighted_sum_expected = zip( data, wdata ).map!"a[0]*a[1]".reduce!"a+b";
        
        if (verbose)
          {
            writeln;
            writeln("n: ", n);
            writeln("data: ", data);
            writeln("weighted_sum, expected: ", [weighted_sum, weighted_sum_expected], " delta:", weighted_sum - weighted_sum_expected);
          }

        assert( isClose( weighted_sum, weighted_sum_expected, 1e-8, 1e-8 ) );
      }

  }


  {
    immutable double alpha_0 = 3.0;
    immutable double beta_0  = 10.0;
    
    double[] x = [2.0, 4.0, 7.0, 13.0, 19.0];
    auto y = x.map!((a) => alpha_0 + beta_0 * a).array;

    double alpha, beta;
    linreg( x, y, alpha, beta );

    assert( isClose( alpha, alpha_0, 1e-8, 1e-8 ) );
    assert( isClose( beta, beta_0, 1e-8, 1e-8 ) );
    
    if (verbose)
      {
        writefln( "alpha_0: %g  beta_0: %g", alpha_0, beta_0 );
        writefln( "x: %s", x );
        writefln( "y: %s", y );
        writefln( "alpha: %g  beta: %g", alpha, beta );
      }
  }
  
  
  {
    assert( median( [ 1.0,2.0,3.0,4.0,5.0 ] ) == 3.0 );
    assert( median( [ 1.0,2.0,3.0,4.0,5.0,6.0 ] ) == (3.0+4.0)*0.5 );

    {
      immutable double[] arr = [ 1.0, 4.0, 5.0, 2.0, 3.0 ];
      assert( 3.0 == median( arr ) );
    }

    {
      double[] arr = [ 1.0, 4.0, 5.0, 2.0, 3.0 ];
      auto arr0 = arr.idup;
      assert( arr == arr0 );
      assert( 3.0 == median_inplace( arr ) );
      assert( arr != arr0 );
    }
  }
  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
