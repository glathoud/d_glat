module d_glat.flatcode.extract_mu_sigma;

import std.algorithm;
import std.array;
import std.conv;
import std.math;
import std.path;
import std.range;
import std.stdio;

// ---------- Runtime strategy

void flatcode_extract_mu_sigma
// glat@glat.info
// 2017
(
 // outputs
 double[] mu      // `mu.length == dim` (mean vector)
 , double[] sigma // `sigma.length == dim*dim` (covariance matrix)
 // inputs
 , in double[][] datavect_arr
 )
{
  flatcode_extract_mu_sigma( mu, sigma
                            , datavect_arr, datavect_arr.length
                            );
}

void flatcode_extract_mu_sigma
// glat@glat.info
// 2017
(
 // outputs
 double[] mu      // `mu.length == dim` (mean vector)
 , double[] sigma // `sigma.length == dim*dim` (covariance matrix)
 // inputs
 , in double[][] datavect_arr
 , in ulong      n_datavect  // To use only the beginning vectors
 )
{
  ulong I = mu.length;
  
  mu[] = 0;
  sigma[] = 0;
  for (ulong a = n_datavect; a--;)
    {
      auto v = datavect_arr[ a ];
      mu[] += v[];
      for (ulong i = I; i--; )
        {
          auto vi = v[ i ];
          auto offset = i*I;
          for (ulong j = i; j < I; ++j)
            {
              sigma[ offset + j ] += vi * v[ j ];
            }
        }
    }

  double n_dble = cast( double )( n_datavect );
  mu[] /= n_dble;
  
  for (ulong i = I; i--; )
    {
      auto offset = i*I;
      for (ulong j = i; j < I; ++j)
        {
          auto x = sigma[ offset + j ]
            = sigma[ offset + j ] / n_dble - mu[ i ] * mu[ j ];

          if (i < j)
            sigma[ j * I + i ] = x;
        }
    }
}


// ---------- Compile-time strategy: should be faster. Cost: `I`
// must be known at compile time.
 
void flatcode_extract_mu_sigma( alias I )
// glat@glat.info
// 2017
  (
   // outputs
   double[] mu      // `mu.length == dim` (mean vector)
   , double[] sigma // `sigma.length == dim*dim` (covariance matrix)
   // inputs
   , in double[][] datavect_arr
   )
{
  flatcode_extract_mu_sigma!( I )( mu, sigma, datavect_arr
                                  , datavect_arr.length
                                  );
}

void flatcode_extract_mu_sigma( alias I )
// glat@glat.info
// 2017
  (
   // outputs
   double[] mu      // `mu.length == dim` (mean vector)
   , double[] sigma // `sigma.length == dim*dim` (covariance matrix)
   // inputs
   , in double[][] datavect_arr
   , in ulong      n_datavect  // To use only the beginning vectors
   )
{
  static immutable ulong impl_key = I;

  if (auto p = impl_key in muSigmaImpl_of_key)
    (*p)( mu, sigma, datavect_arr, n_datavect );
  else
    {
      auto f = muSigmaImpl_of_key[ impl_key ]
        = makeImpl!( I )();

      f( mu, sigma, datavect_arr, n_datavect );
    }
}

private:

alias muSigmaImplT = void delegate( ref double[], ref double[]
                                    , in double[][], in ulong
                                    );

muSigmaImplT[ ulong ] muSigmaImpl_of_key;

muSigmaImplT makeImpl( alias I )()
{
  // Implementation translated from JavaScript:
  // https://github.com/glathoud/flatorize/blob/master/lib/flatcode.js
 
  return delegate( ref double[] mu, ref double[] sigma
                   , in double[][] datavect_arr
                   , in ulong n_datavect
                   )
    {
      assert( I == datavect_arr[ 0 ].length );
      assert( I == mu.length );
      assert( I*I == sigma.length );

      mixin( declLocalsCode( I ) );

      for (ulong k = n_datavect; k--;)
        {
          auto v = datavect_arr[ k ];
          mixin( update_vi_mu_sii_code( I ) );
          mixin( update_sij_code( I ) );
        }

      double n_dble = cast( double )( n_datavect );

      mixin( finish_mu_code   ( I ) );
      mixin( finish_sigma_code( I ) );
    };
}

string declLocalsCode( in ulong I )
{
  auto arr_dim = get_arr_dim( I );
  
  string declLocalsCodeOne( in ulong i )
  {
    auto si = to!string(i);

    return "v" ~ si
      ~ ", mu" ~ si ~ " = 0"
      ~ ", " ~
      (
       arr_dim[ i..$ ]
       .map!( j => "sigma" ~ si ~ "_" ~ to!string( j ) ~ " = 0" )
       .join( ", " )
       );
  }

  return "double "
    ~ arr_dim.map!( declLocalsCodeOne ).join( "," )
    ~ ";";
}

string update_vi_mu_sii_code( in ulong I )
{
  auto arr_dim = get_arr_dim( I );
  
  string update_vi_mu_sii_code_one( in ulong i )
  {
    auto si = to!string(i);

    return "mu" ~ si ~ " += (v" ~ si ~ " = v[" ~ si ~ "]); "
      ~ "sigma" ~ si ~ "_" ~ si ~ " += v" ~ si ~ " * v" ~ si;
  }

 return arr_dim.map!( update_vi_mu_sii_code_one ).join( "; " )
    ~ ";";
}


string update_sij_code( in ulong I )
{
  auto arr_dim = get_arr_dim( I );
  
  string update_sij_code_one( in ulong i )
  {
    auto si = to!string(i);

    return arr_dim[ i+1..$ ].map!
      (
       j => "sigma" ~ si ~ "_" ~ to!string(j)
       ~ "+= v" ~ si ~ " * v" ~ to!string(j)
       ~ "; "
       ).join( "" );
  }

  return arr_dim.map!( update_sij_code_one ).join( " " );
    
}

string finish_mu_code( in ulong I )
{
  auto arr_dim = get_arr_dim( I );
  
  return arr_dim.map!
    ( i => "mu[" ~ to!string(i) ~ "] = "
      ~ "(mu" ~ to!string(i) ~ " /= n_dble)")
    .join( "; " )
    ~ ";";
}

string finish_sigma_code( in ulong I )
{
  auto arr_dim = get_arr_dim( I );
  
  auto dim = arr_dim.length;
  
  return arr_dim.map!
    ( i =>
      arr_dim[ i..$ ].map!
      ( j =>
        (i < j
         ?  "sigma[" ~ to!string(j*dim+i) ~ "] = "
         :  ""
         )
        ~ "sigma[" ~ to!string(i*dim+j) ~ "] = "
        ~ "sigma" ~ to!string(i) ~ "_" ~ to!string(j) ~ "/n_dble"
        ~ "- mu" ~ to!string(i) ~ " * mu" ~ to!string(j)
        ).join( "; " )
      )
    .join( "; ")
    ~ ";";
}

ulong[] get_arr_dim( in ulong I )
{
  return iota( 0, I ).array;
}




unittest
{
  writeln;
  writeln( "unittest starts: extract_mu_sigma" );

  /*
    http://glat.info/flatorize/lib/flatcode_speedtest.html

    JavaScript to generate the "truth":
    
    f = fm_mu_sigma_of_dim( 4 );
    data = [
    [ 9.123, 543.543, 234.2,  34.213 ],
    [ 1.231, -4.435, 5.4353, 7.56867 ],
    [ -3.54, 3543.534, 21.2134, 9.123],
    [ -10.432, -3.432, 25.543, 80.345 ],
    [ +1.42, +654.45, -32.432, -123.432 ],
    [ +78.432, +12.123, -123.5435, -87.43 ]
    ];
    f( data )
    
    // mu: 12.705666666666666, 790.9638333333332, 21.736033333333335, -13.26872166666667
    // sigma: [898.5156575555558, -10995.535194388887, -1598.5174258055556, -1095.0112834488891, -10995.535194388887, 1587802.1176058059, 12746.51131547222, 5290.845612824723, -1598.5174258055556, 12746.51131547222, 11576.955970082221, 4472.435977145889, -1095.0112834488891, 5290.845612824723, 4472.435977145889, 4931.578660760681]
   */

  immutable double[][] data =
    [
     [ 9.123, 543.543, 234.2,  34.213 ],
     [ 1.231, -4.435, 5.4353, 7.56867 ],
     [ -3.54, 3543.534, 21.2134, 9.123],
     [ -10.432, -3.432, 25.543, 80.345 ],
     [ +1.42, +654.45, -32.432, -123.432 ],
     [ +78.432, +12.123, -123.5435, -87.43 ]
     ];

  immutable ulong n_datavect = data.length;
  immutable double[][] data2 = cast( immutable( double[][] ))
    (
     data ~
     [
      [ -2.3543, 5.3452, 21.3432, 6.7546 ],
      [ +12.31, -5.4353, +32.3432, -2.4324 ]
      ]
     );
  
  immutable double epsilon = 1e-10;

  double[] mu    = new double[ 4 ];
  double[] sigma = new double[ 16 ];

  immutable double[] mu_truth = [ 12.705666666666666, 790.9638333333332, 21.736033333333335, -13.26872166666667 ];
  immutable double[] sigma_truth = [ 898.5156575555558, -10995.535194388887, -1598.5174258055556, -1095.0112834488891, -10995.535194388887, 1587802.1176058059, 12746.51131547222, 5290.845612824723, -1598.5174258055556, 12746.51131547222, 11576.955970082221, 4472.435977145889, -1095.0112834488891, 5290.845612824723, 4472.435977145889, 4931.578660760681 ];

  // runtime strategy

  mu[]    = double.nan;
  sigma[] = double.nan;
  
  flatcode_extract_mu_sigma( mu, sigma, data );

  {
    double[] tmp_v = new double[ 4 ];
    double[] tmp_m = new double[ 16 ];
    
    tmp_v[] =    mu[] - mu_truth[];
    tmp_m[] = sigma[] - sigma_truth[];
    
    assert( epsilon > tmp_v.map!abs.reduce!max );
    assert( epsilon > tmp_m.map!abs.reduce!max );
  }

  // runtime strategy with n_datavect

  mu[]    = double.nan;
  sigma[] = double.nan;
  
  flatcode_extract_mu_sigma( mu, sigma, data2, n_datavect );

  {
    double[] tmp_v = new double[ 4 ];
    double[] tmp_m = new double[ 16 ];
    
    tmp_v[] =    mu[] - mu_truth[];
    tmp_m[] = sigma[] - sigma_truth[];
    
    assert( epsilon > tmp_v.map!abs.reduce!max );
    assert( epsilon > tmp_m.map!abs.reduce!max );
  }

  // compile-time strategy

  mu[]    = double.nan;
  sigma[] = double.nan;
  
  flatcode_extract_mu_sigma!( 4 )( mu, sigma, data );

  {
    double[] tmp_v = new double[ 4 ];
    double[] tmp_m = new double[ 16 ];
    
    tmp_v[] =    mu[] - mu_truth[];
    tmp_m[] = sigma[] - sigma_truth[];
    
    assert( epsilon > tmp_v.map!abs.reduce!max );
    assert( epsilon > tmp_m.map!abs.reduce!max );
  }

  // compile-time strategy with n_datavect

  mu[]    = double.nan;
  sigma[] = double.nan;
  
  flatcode_extract_mu_sigma!( 4 )( mu, sigma, data2, n_datavect );

  {
    double[] tmp_v = new double[ 4 ];
    double[] tmp_m = new double[ 16 ];
    
    tmp_v[] =    mu[] - mu_truth[];
    tmp_m[] = sigma[] - sigma_truth[];
    
    assert( epsilon > tmp_v.map!abs.reduce!max );
    assert( epsilon > tmp_m.map!abs.reduce!max );
  }

  writeln( "unittest passed: extract_mu_sigma" );
}
