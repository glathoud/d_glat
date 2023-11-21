module d_glat.flatmatrix.lib_corr;

/*
  Utility for correlation between 1 and N variables.
  
  For a full cross-correlation matrix, use ./lib_stat.d

  By Guillaume Lathoud, 2019.
  glat@glat.info

  The Boost License applies to the present file, as described in the
  file ../LICENSE
 */

public import d_glat.flatmatrix.core_matrix;

import d_glat.core_profile_acc;
import std.math;



T corr(T)( in T[] x, in T[] y ) @safe
// functional shortcut
{
  scope m_x = MatrixT!T( [0,1], x.dup );
  scope m_y = MatrixT!T( [0,1], y.dup );
  scope m_c = corr_one( m_x, m_y );
  return m_c.data[ 0 ];
}

// for a full cross-correlation matrix, use ./lib_stat.d



alias Buffer_corr_one_inplace = Buffer_corr_one_inplaceT!double;

class Buffer_corr_one_inplaceT(T) : ProfileMemC
{
  MatrixT!T m_many_mean, m_many_var;
}


MatrixT!T corr_one(T)( in MatrixT!T m_one
                       , in MatrixT!T m_many ) @safe
// Functional wrapper around `corr_one_inplace`
{
  MatrixT!T m_corr;
  scope auto buffer = new Buffer_corr_one_inplaceT!T;

  corr_one_inplace!T( m_one, m_many, m_corr, buffer );

  return m_corr;
}


void corr_one_inplace( T )
  ( in   ref MatrixT!T m_one
    , in ref MatrixT!T m_many
    ,    ref MatrixT!T m_corr
    ,    ref Buffer_corr_one_inplaceT!T buffer
    ) pure nothrow @safe
/*
  Corration of `m_one` (vector) with each dimension of `m_many`.
  In-place computations for speed.

  Input dimensions (n is the number of samples):

  `m_one`:  `[n,1]`
  `m_many`: `[n,d]`

  Output dimensions:

  `m_corr`: `[1,d]`

  Boost license, as described in file ../LICENSE

  By Guillaume Lathoud
  glat@glat.info
*/
{
  

  immutable d = m_many.dim[ 1 ];

  buffer.m_many_mean.setDim( [ 1, d ] );
  buffer.m_many_var .setDim( [ 1, d ] );

  m_corr.setDim( [1, d] );
  
  corr_one_inplace!T( m_one, m_many, m_corr
                      , buffer.m_many_mean, buffer.m_many_var 
                      );
}


void corr_one_inplace( T )
( /* inputs: */
 in   ref MatrixT!T m_one
 , in ref MatrixT!T m_many
 /* outputs: */
 ,    ref MatrixT!T m_corr
 ,    ref MatrixT!T m_many_mean
 ,    ref MatrixT!T m_many_var
  ) pure nothrow @safe @nogc
/*
  Corration of `m_one` (vector) with each dimension of `m_many`.
  In-place computations for speed.  

  We also output `m_many_mean`, and `m_many_var` (uncorrected
  variance).

  Input dimensions (n is the number of samples):

  `m_one`:  `[n,1]`
  `m_many`: `[n,d]`

  Output dimensions:

  `m_corr`:      `[1,d]`
  `m_many_mean`: `[1,d]`
  `m_many_var`:  `[1,d]`

  Boost license, as described in file ../LICENSE

  By Guillaume Lathoud
  glat@glat.info
*/
{
  immutable n = m_one.data.length;
  immutable d = m_many.dim[ 1 ];

  debug
    {
      assert( m_one.dim.length == 1  &&  m_one.dim[ 0 ] == n
              ||
              m_one.dim.length == 2
              &&  m_one.dim[ 0 ] == n  &&  m_one.dim[ 1 ] == 1
              );
      
      assert( m_many.dim.length == 2 );
      assert( m_many.dim[ 0 ] == n );
      assert( m_many.dim[ 1 ] == d );

      static foreach (name;
                      [`m_corr`, `m_many_mean`, `m_many_var`])
      {
        mixin
          ( `assert
            ( `~name~`.dim.length == 2
              &&  `~name~`.dim[ 0 ] == 1  &&  `~name~`.dim[ 1 ] ==d

              || `~name~`.dim.length == 1
              &&  `~name~`.dim[ 0 ] == d
              );`
            );
      }
    }

  // all are `double[]`
  scope auto one  = m_one .data;
  scope auto many = m_many.data;
  scope auto corr = m_corr.data;
  scope auto many_mean = m_many_mean.data;
  scope auto many_var  = m_many_var .data;

  immutable one_over_n_dbl = 1.0 / cast( double )( n );

  immutable many_len = many.length;

  debug
    {
      assert( corr.length == d );
      assert( many_len == n * d );
    }
  
  // one

  double acc = 0.0;
  foreach (x; one) acc += x;
  immutable one_mean = acc * one_over_n_dbl;

  acc = 0;
  foreach (x; one)
    {
      double tmp = x - one_mean;
      acc += tmp * tmp;
    }
  immutable one_var = acc * one_over_n_dbl;

  // many

  many_mean[] = 0.0;
  {
    size_t i = 0;
    foreach (x; many)
      {
        many_mean[ i++ ] += x;
        if (i == d)
          i = 0;
      }
  }
  many_mean[] *= one_over_n_dbl;

  /* one & many

     Progressively build `corr` using, for each dimension, the
     formula:

     r_xy = 
     (sum_i(x_i * y_i) / n - mean_x * mean_y) 
     / sqrt(var_x * var_y)
  */
  many_var[] = 0.0;
  corr[] = 0.0;

  double x_one = one[ 0 ];
  size_t i_one = 0;
  size_t i_mod_d = 0;

  immutable many_len_m_1 = many_len - 1;
  
  foreach (i,x; many)
    {
      double tmp = x - many_mean[ i_mod_d ];
      many_var[ i_mod_d ] += tmp * tmp;

      corr[ i_mod_d ] += x * x_one;

      // Prepare the next sample

      if ((++i_mod_d) == d  &&  i < many_len_m_1)
        {
          i_mod_d = 0;
          x_one = one[ ++i_one ];  
        }
    }
  debug
    {
      assert( i_one   == n-1 );
      assert( i_mod_d == d );
    }
  many_var[] *= one_over_n_dbl; // uncorrected variance
  
  // Implement the formula

  corr[] *= one_over_n_dbl;
  
  corr[] -= one_mean * many_mean[];
  
  foreach (i,v; many_var)
    corr[ i ] /= sqrt( one_var * v );
}

unittest
{
  import std.algorithm;
  import std.array;
  import std.range;
  import std.stdio;

  immutable verbose = false;
  
  writeln;
  writeln( "unittest starts: "~__FILE__ );

  auto buffer = new Buffer_corr_one_inplace;


  // Functional variant

  {
    // Noiseless data
    
    auto m_one = Matrix( [ 4, 1 ], [ 1.0, 2.0, 3.0, 4.0 ] );
    auto m_many = Matrix
      ( [ 4, 0 ]
        , zip(
              m_one.data.map!"-1.0+3.0*a"
              , m_one.data.map!"+12.0-5.0*a"
              , m_one.data.map!"0.0"
              )
        .map!"a.array"
        .reduce!"a~b"
        .array
        );

    if (verbose) writeln("one: ", m_one);
    if (verbose) writeln("many: ", m_many);

    auto m_corr = corr_one( m_one, m_many );

    if (verbose) writeln("corr: ", m_corr );

    assert( isClose( +1.0, m_corr.data[ 0 ] ) );
    assert( isClose( -1.0, m_corr.data[ 1 ] ) );
    assert( isNaN( m_corr.data[ 2 ] ) );
  }


  {
    // Some noise

    /*
      Octave used to generate this slightly noisy data, and its
      correlation values:

      orig = [1.0;2.0;3.0;4.0];

      m_one=round(1e5*(orig + 0.1 * stdnormal_rnd([4,1])))/1e5;

      a =round(1e5*(-1.0+3.0*orig+ 0.1 * stdnormal_rnd([4,1])))/1e5;

      b =round(1e5*(+12.0-5.0*orig+ 0.1 * stdnormal_rnd([4,1])))/1e5; 

      c=0.0*orig;
      m_many=[a b c];
      m_corr = cov(m_one,m_many,1) ./ (std(m_one,1)*std(m_many,1));

      disp(m_one)

      disp(m_many)
      
      disp(sprintf( "%.10g, ", m_corr))
    */
    
    auto m_one = Matrix( [ 4, 1 ]
                         , [ 0.87717,
                             2.08774,
                             2.86322,
                             4.02435
                             ]);
    
    auto m_many = Matrix
      ( [ 4, 0 ]
        , [
           2.12938, 7.11666, 0.00000
           , 5.01599, 1.81814, 0.00000
           , 7.89512, -2.84041, 0.00000
           , 11.08435, -8.14922, 0.00000
           ]
        );

    if (verbose) writeln("one: ", m_one);
    if (verbose) writeln("many: ", m_many);

    auto m_corr = corr_one( m_one, m_many );

    if (verbose) writeln("corr: ", m_corr );

    assert( isClose
            ( 0.9970257946, m_corr.data[ 0 ], 1e-8, 1e-8 ) );
    
    assert( isClose
            ( -0.9984470896, m_corr.data[ 1 ], 1e-8, 1e-8 ) );
    
    assert( isNaN( m_corr.data[ 2 ] ) );
  }

  
  {
    // More noise

    /*
      Octave used to generate this more noisy data, and its
      correlation values:

      orig = [1.0;2.0;3.0;4.0];

      m_one=round(1e5*(orig + 1.0 * stdnormal_rnd([4,1])))/1e5;

      a =round(1e5*(-1.0+3.0*orig+ 0.1 * stdnormal_rnd([4,1])))/1e5;

      b =round(1e5*(+12.0-5.0*orig+ 0.1 * stdnormal_rnd([4,1])))/1e5; 

      c=0.0*orig;
      m_many=[a b c];
      m_corr = cov(m_one,m_many,1) ./ (std(m_one,1)*std(m_many,1));

      disp(m_one)

      disp(m_many)
      
      disp(sprintf( "%.10g, ", m_corr))
    */
    
    auto m_one = Matrix( [ 4, 1 ]
                         , [ 0.84571,
                             2.33270, 
                             3.12509, 
                             3.36448 ]);
    
    auto m_many = Matrix
      ( [ 4, 0 ]
        , [
           2.01754, 6.88942, 0.00000
           , 4.95877, 1.88913, 0.00000
           , 7.94578, -3.07764, 0.00000
           , 11.03451, -8.04965, 0.00000
           ]
        );

    if (verbose) writeln("one: ", m_one);
    if (verbose) writeln("many: ", m_many);

    auto m_corr = corr_one( m_one, m_many );

    if (verbose) writeln("corr: ", m_corr );

    assert( isClose
            ( 0.9448199076, m_corr.data[ 0 ], 1e-8, 1e-8 ) );
    
    assert( isClose
            ( -0.9487419465, m_corr.data[ 1 ], 1e-8, 1e-8 ) );
    
    assert( isNaN( m_corr.data[ 2 ] ) );
  }
    



  // In-place variant

  
  {
    // Noiseless data
    
    auto m_one = Matrix( [ 4, 1 ], [ 1.0, 2.0, 3.0, 4.0 ] );
    auto m_many = Matrix
      ( [ 4, 0 ]
        , zip(
              m_one.data.map!"-1.0+3.0*a"
              , m_one.data.map!"+12.0-5.0*a"
              , m_one.data.map!"0.0"
              )
        .map!"a.array"
        .reduce!"a~b"
        .array
        );

    if (verbose) writeln("one: ", m_one);
    if (verbose) writeln("many: ", m_many);

    auto m_corr = Matrix( [ 1, 3 ] );
    corr_one_inplace( m_one, m_many, m_corr, buffer );

    if (verbose) writeln("corr: ", m_corr );

    assert( isClose( +1.0, m_corr.data[ 0 ] ) );
    assert( isClose( -1.0, m_corr.data[ 1 ] ) );
    assert( isNaN( m_corr.data[ 2 ] ) );
  }


  {
    // Some noise

    /*
      Octave used to generate this slightly noisy data, and its
      correlation values:

      orig = [1.0;2.0;3.0;4.0];

      m_one=round(1e5*(orig + 0.1 * stdnormal_rnd([4,1])))/1e5;

      a =round(1e5*(-1.0+3.0*orig+ 0.1 * stdnormal_rnd([4,1])))/1e5;

      b =round(1e5*(+12.0-5.0*orig+ 0.1 * stdnormal_rnd([4,1])))/1e5; 

      c=0.0*orig;
      m_many=[a b c];
      m_corr = cov(m_one,m_many,1) ./ (std(m_one,1)*std(m_many,1));

      disp(m_one)

      disp(m_many)
      
      disp(sprintf( "%.10g, ", m_corr))
    */
    
    auto m_one = Matrix( [ 4, 1 ]
                         , [ 0.87717,
                             2.08774,
                             2.86322,
                             4.02435
                             ]);
    
    auto m_many = Matrix
      ( [ 4, 0 ]
        , [
           2.12938, 7.11666, 0.00000
           , 5.01599, 1.81814, 0.00000
           , 7.89512, -2.84041, 0.00000
           , 11.08435, -8.14922, 0.00000
           ]
        );

    if (verbose) writeln("one: ", m_one);
    if (verbose) writeln("many: ", m_many);

    auto m_corr = Matrix( [ 1, 3 ] );
    corr_one_inplace( m_one, m_many, m_corr, buffer );

    if (verbose) writeln("corr: ", m_corr );

    assert( isClose
            ( 0.9970257946, m_corr.data[ 0 ], 1e-8, 1e-8 ) );
    
    assert( isClose
            ( -0.9984470896, m_corr.data[ 1 ], 1e-8, 1e-8 ) );
    
    assert( isNaN( m_corr.data[ 2 ] ) );
  }

  


  {
    // More noise

    /*
      Octave used to generate this more noisy data, and its
      correlation values:

      orig = [1.0;2.0;3.0;4.0];

      m_one=round(1e5*(orig + 1.0 * stdnormal_rnd([4,1])))/1e5;

      a =round(1e5*(-1.0+3.0*orig+ 0.1 * stdnormal_rnd([4,1])))/1e5;

      b =round(1e5*(+12.0-5.0*orig+ 0.1 * stdnormal_rnd([4,1])))/1e5; 

      c=0.0*orig;
      m_many=[a b c];
      m_corr = cov(m_one,m_many,1) ./ (std(m_one,1)*std(m_many,1));

      disp(m_one)

      disp(m_many)
      
      disp(sprintf( "%.10g, ", m_corr))
    */
    
    auto m_one = Matrix( [ 4, 1 ]
                         , [ 0.84571,
                             2.33270, 
                             3.12509, 
                             3.36448 ]);
    
    auto m_many = Matrix
      ( [ 4, 0 ]
        , [
           2.01754, 6.88942, 0.00000
           , 4.95877, 1.88913, 0.00000
           , 7.94578, -3.07764, 0.00000
           , 11.03451, -8.04965, 0.00000
           ]
        );

    if (verbose) writeln("one: ", m_one);
    if (verbose) writeln("many: ", m_many);

    auto m_corr = Matrix( [ 1, 3 ] );
    corr_one_inplace( m_one, m_many, m_corr, buffer );

    if (verbose) writeln("corr: ", m_corr );

    assert( isClose
            ( 0.9448199076, m_corr.data[ 0 ], 1e-8, 1e-8 ) );
    
    assert( isClose
            ( -0.9487419465, m_corr.data[ 1 ], 1e-8, 1e-8 ) );
    
    assert( isNaN( m_corr.data[ 2 ] ) );
  }
    
  writeln( "unittest passed: "~__FILE__ );
}
