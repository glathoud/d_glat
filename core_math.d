module d_glat.core_math;

public import std.math;

import d_glat.core_static;
import std.algorithm : sort;

/*
  A few mathematical tool functions.

  By Guillaume Lathoud, 2019
  glat@glat.info

  The Boost license applies to this file, as described in ./LICENSE
 */

T e_w_logsum( T )( in T[] a_arr, in T[] logw_arr )
/* Input: 2 arrays containing `a_i` resp. `log(w_i)`.

   Output: `sum_i( a_i * w_i )` calculated as precisely as `logsum`
   permits.

   Implementation: two `logsum` calls, one for positive values
   (`a_i>0.0`), one for negative values (`a_i<0.0`);
*/
  nothrow @safe
{
  pragma( inline, true );

  immutable n = a_arr.length;
  
  debug assert( n == logw_arr.length );

  // Limit GC costs
  mixin(static_array_code(`logsum_buffer`,`T`,`n`));
  mixin(static_array_code(`work`         ,`T`,`n`));
  
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


T logsum( T )( in T[] arr )
nothrow @safe
/* Input log(data), output: log(sum(data))
 
 Addition done in a smart way to minimize precision loss.
*/
{
  pragma( inline, true );
  
  immutable n = arr.length;
  mixin(static_array_code(`buffer`, `T`, `n`));
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
*/
{
  pragma( inline, true );

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


T median( T )( in T[] arr )
pure nothrow @safe
{
  pragma( inline, true );
  
  return median_inplace( arr.dup );
}

T median_inplace( T )( T[] arr )
  pure nothrow @safe @nogc
{
  pragma( inline, true );
  
  arr.sort;
  immutable n = arr.length;
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

        assert( approxEqual( logsum, logsum_expected, 1e-8, 1e-8 ) );
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
        
        immutable double weighted_sum          = e_w_logsum( data, logwdata );
        immutable double weighted_sum_expected = zip( data, wdata ).map!"a[0]*a[1]".reduce!"a+b";
        
        if (verbose)
          {
            writeln;
            writeln("n: ", n);
            writeln("data: ", data);
            writeln("weighted_sum, expected: ", [weighted_sum, weighted_sum_expected], " delta:", weighted_sum - weighted_sum_expected);
          }

        assert( approxEqual( weighted_sum, weighted_sum_expected, 1e-8, 1e-8 ) );
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
