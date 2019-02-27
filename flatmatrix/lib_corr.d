module d_glat.flatmatrix.lib_corr;

import d_glat.flatmatrix.core_matrix;
import std.math;

void corr_one_inplace
( bool unbiased = false )
  ( in   ref Matrix m_one
    , in ref Matrix m_many
    ,    ref Matrix m_corr)
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

      assert( m_corr.dim.length == 1  &&  m_corr.dim[ 0 ] == d
              ||  m_corr.dim.length == 2
              &&  m_corr.dim[ 0 ] == 1  &&  m_corr.dim[ 1 ] ==d
              );
    }

  // all are `double[]`
  auto one  = m_one .data;
  auto many = m_many.data;
  auto corr = m_corr.data;
  
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

  string setup_acc_code( in string name ) pure
  {
    return `static double[] `~name~`;
    if (`~name~`.length != d)
      `~name~` = new double[ d ];
    `;
  }


  mixin( setup_acc_code( `many_mean` ) );
  
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
  mixin( setup_acc_code( `many_var` ) );
  
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
  many_var[] *= one_over_n_dbl;
  
  // Implement the formula

  static if (!unbiased)
    {
      // Exactly like the formula above

      corr[] *= one_over_n_dbl;
      
      corr[] -= one_mean * many_mean[];

      // At this point `many_var` looses its meaning, modified in-place
      // for speed.
      foreach (i,x; many_var)
        many_var[ i ] = sqrt( one_var * x );
  
      corr[] /= many_var[];
    }
  else
    {
      // Slight variation

      corr[] -= (cast( double )( n )) * one_mean * many_mean[];

      corr[] /= (cast( double )( n-1 ));
      
      // At this point `many_var` looses its meaning, modified in-place
      // for speed.
      foreach (i,x; many_var)
        many_var[ i ] = sqrt( ((cast( double )( n )) / (cast( double )( n-1 )))
                              * ((cast( double )( n )) / (cast( double )( n-1 )))
                              * one_var * x );
  
      corr[] /= many_var[];

      
    }
}

unittest
{
  import std.algorithm;
  import std.array;
  import std.range;
  import std.stdio;

  immutable verbose = true;
  
  writeln;
  writeln( "unittest starts: "~__FILE__ );

  // ---------- Biased
  {
    immutable biased = false;
    
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
      corr_one_inplace!biased( m_one, m_many, m_corr );

      if (verbose) writeln("corr: ", m_corr );

      assert( approxEqual( +1.0, m_corr.data[ 0 ] ) );
      assert( approxEqual( -1.0, m_corr.data[ 1 ] ) );
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
      corr_one_inplace!biased( m_one, m_many, m_corr );

      if (verbose) writeln("corr: ", m_corr );

      assert( approxEqual
              ( 0.9970257946, m_corr.data[ 0 ], 1e-8, 1e-8 ) );
    
      assert( approxEqual
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
      corr_one_inplace!biased( m_one, m_many, m_corr );

      if (verbose) writeln("corr: ", m_corr );

      assert( approxEqual
              ( 0.9448199076, m_corr.data[ 0 ], 1e-8, 1e-8 ) );
    
      assert( approxEqual
              ( -0.9487419465, m_corr.data[ 1 ], 1e-8, 1e-8 ) );
    
      assert( isNaN( m_corr.data[ 2 ] ) );
    }
  }
  




  // ---------- Unbiased

  {
    immutable biased = true;
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
      corr_one_inplace!biased( m_one, m_many, m_corr );

      if (verbose) writeln("corr: ", m_corr );

      assert( approxEqual( +1.0, m_corr.data[ 0 ] ) );
      assert( approxEqual( -1.0, m_corr.data[ 1 ] ) );
      assert( isNaN( m_corr.data[ 2 ] ) );
    }
  }



    
  writeln( "unittest passed: "~__FILE__ );
}
