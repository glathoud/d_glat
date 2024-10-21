module d_glat.flatmatrix.lib_regress;

import d_glat.core_array;
import d_glat.core_assert;
import d_glat.core_math;
import d_glat.core_string;
import d_glat.flatmatrix.core_matrix;
import d_glat.lib_regress_theilsen;
import d_glat.lib_tmpfilename;
import std.algorithm : fold, map;
import std.array : array, join;
import std.file : remove, tempDir;
import std.stdio;

public import d_glat.flatmatrix.lib_octave_exec; // public: isOctaveSupported()

/*
  Various linear regression methods.

  By Guillaume Lathoud, 2024
  glat@glat.info

  The Boost license applies to this file, as described in ./LICENSE
 */

// ---------- TheilSen linear regression (median-based, robust to outliers)

MatrixT!T mat_regress_theilsen(T)( in MatrixT!T Y, in MatrixT!T X )
/* Input: Y:dim:[n,1]  X:dim:[n,d]
   Output: MB:=[m0, m1, ... md; b0, b1 ... bd;]
   so that `Y` is close to `mat_apply_theilsen( X, MB )`

   Based on the median and should thus be robust to outliers.
   See also: ../lib_regress_theilsen.d
*/
{
  if (Y.dim == X.dim) // both 1-D
    {
      T m, b;
      regress_theilsen( Y.data, X.data, m, b );
      return MatrixT!T( [2,1], [m
                                , b]);
    }
  else // multidimensional
    {
      immutable n = Y.data.length;
      immutable d = X.data.length / n;

      debug assert( Y.nrow == n );
      debug assert( Y.nrow == X.nrow );
      debug assert( Y.nrow == Y.data.length ); // Y: 1-D
      debug assert( d * n == X.data.length ); // X: multidimensional
      
      auto ret = new T[ d<<1 ];
      scope m_arr = ret[0..d];
      scope b_arr = ret[d..$];
      regress_theilsen_multi!T( Y.data, X.data, m_arr, b_arr );

      return MatrixT!T( [2, 0], ret );
    }
}

MatrixT!T mat_apply_theilsen(T)( in MatrixT!T X, in MatrixT!T MB ) pure nothrow @safe
{
  scope T[] buff;
  MatrixT!T Y_estim;
  mat_apply_theilsen_inplace!T( X, MB, buff, Y_estim );
  return Y_estim;
}

void mat_apply_theilsen_inplace(T)( in MatrixT!T X, in MatrixT!T MB
                                    , /*intermediary*/ref T[] buff
                                    , /*output*/ref MatrixT!T Y_estim
                                    ) pure nothrow @safe
{
  immutable d = MB.data.length >> 1;
  arr_ensure_length( d, buff );
  Y_estim.setDim( [X.nrow, 1] );
  mat_apply_theilsen_inplace_nogc!T( X, MB
                                     , buff, Y_estim );
}

void mat_apply_theilsen_inplace_nogc(T)( in MatrixT!T X, in MatrixT!T MB
                                         , /*intermediary*/ref T[] buff
                                         , /*output*/ref MatrixT!T Y_estim
                                         ) pure nothrow @safe @nogc
{
  immutable d = MB.dim[ 1 ];

  apply_theilsen_multi_inplace_nogc( X.data, MB.data[ 0..d ], MB.data[ d..$ ], buff, Y_estim.data );
}



// ---------- Octave-based linear regression

const(MatrixT!T) get_X1_of_X(T)( in MatrixT!T X )
{
  return concatcol_parallel( [mat_ones( [X.nrow, 1] ), X] );
}


MatrixT!T linpred_apply(T)( in MatrixT!T beta, in MatrixT!T X )
{
  scope auto X1 = get_X1_of_X( X );
  return dot( X1, beta );
}



/*
  `regress` function similar to that of Octave: Multiple Linear
     Regression using Least Squares Fit of Y on X with the model 'y =
     X * beta + e' (where the first column of X contains ones).

  For now running on top of an Octave engine.
  Compatible at least with Octave (6.4.0).
  You need to install the statistics package on it.

  sudo apt install liboctave-dev
  #
  # download the io and statistics packages
  # check their signature and install them.
  # in octave:
  # pkg install io-<some-numbers>.tar.gz
  # pkg install statistics-<some-numbers>.tar.gz
  #
  # alternatively, without signature check (full trust),
  # in octave:
  # pkg install -forge io
  # pkg install -forge statistics


   With the Lubeck library you could achieve a similar result
   (at least on the unittest) along those lines:
 
   auto mir_y  = y.data.sliced( y.nrow, y.restdim );
   auto mir_X1 = X1.data.sliced( X1.nrow, X1.restdim );
   auto mir_b  = mldivide( mir_X1, mir_y );


  Usage note: before using this, consider checking that Octave is
  excluded from apport, e.g. this way:

  checkApportBlacklistOctaveOrExit();
  
  
  By Guillaume Lathoud, 2023
  glat@glat.info

  The Boost License applies, as described in file ../LICENSE
*/

MatrixT!T regress(T)( in MatrixT!T Y, in MatrixT!T X1, in bool verbose = OCTAVE_VERBOSE_DEFAULT )
// `regress` function similar to that of Octave (6.4.0) but only
// returns `beta` for the model `y = X1*beta + error`
//
// Typically the first column of X1 contains only ones.
{
  scope char[][] oarr_warning;
  return regress!T( Y, X1, oarr_warning, verbose );
}


enum REGRESS_N_RETRY = 3; // in case octave crashes (rare but might happen). Regress idempotent so we can use retry.

MatrixT!T regress(T)( in MatrixT!T Y, in MatrixT!T X1, ref char[][] oarr_warning
                      , in bool verbose = OCTAVE_VERBOSE_DEFAULT )
/* `regress` function similar to that of Octave (6.4.0) but only
   returns `beta` for the model `y = X1*beta + error`
   
   Typically the first column of X1 contains only ones.

   For performance, for bigger data sizes you may want to prefer
   passing data through temporary files: regress_tmpf 

   might throw OctaveException (e.g. if octave crashes, even after
   REGRESS_N_RETRY - typically when X1 is too big and has too many
   columns).
*/
{
  return octaveExecT!T([
                        mClearAll
                        , mExec( `pkg('load','statistics');`)
                        , mSetT!T( "Y", Y )
                        , mSetT!T( "X1", X1 )
                        , mExec( "b = regress( Y, X1 );" )
                        , mPrintMatrixT!T( "b" )
                        ]
                       , oarr_warning
                       , verbose
                       , REGRESS_N_RETRY );
}


MatrixT!T regress_tmpf(T, alias do_remove_tmpf=true)
( in MatrixT!T Y, in MatrixT!T X1, ref char[][] oarr_warning
  , in bool verbose = OCTAVE_VERBOSE_DEFAULT
  , in string tmpdir = tempDir() // good alternative: ramfs
  )

/* `regress` function similar to that of Octave (6.4.0) but only
   returns `beta` for the model `y = X1*beta + error`
   
   Typically the first column of X1 contains only ones.

   Implementation: passing data through temporary files, for
   much better performance than regress!T on large data.
   
   (you *might* want to try tmpfs/ramfs)

   might throw OctaveException (e.g. if octave crashes, even after
   REGRESS_N_RETRY - typically when X1 is too big and has too many
   columns).
*/
{
  immutable in_y_fn  = get_tmpfilename( ".y.data",  tmpdir );
  immutable in_x1_fn = get_tmpfilename( ".x1.data", tmpdir );
  immutable out_b_fn = get_tmpfilename( ".b.data",  tmpdir );

  immutable nr = Y.nrow;
  immutable nc1 = X1.restdim;

  mixin(alwaysAssertStderr!`nr == X1.nrow`);

  {
    scope auto f_y = File( in_y_fn, "w" );
    f_y.rawWrite( Y.data );
  }

  {
    scope auto f_x1 = File( in_x1_fn, "w" );
    // Octave has columns first
    foreach (c; 0..nc1)
      {
        size_t i = c;
        foreach (r; 0..nr)
          {
            f_x1.rawWrite( X1.data[ i..(1+i) ] ); // xxx performance? Can't we just write a double?
            i += nc1;
          }
      }
  }
  
  scope auto octCode_arr =
    [
     mClearAll
     , mExec( `pkg('load','statistics');`) // xxx stg like 0.06 sec the first time, consider keeping a hot octave instance
     , mExec( mixin(_tli!`nr = ${nr};`) )
     , mExec( mixin(_tli!`nc1 = ${nc1};`) )
     , mExec( mixin(_tli!`in_y_fn = "${in_y_fn}";`) )
     , mExec( mixin(_tli!`in_x1_fn = "${in_x1_fn}";`) )
     , mExec( mixin(_tli!`out_b_fn = "${out_b_fn}";`) )
     ]
    ~mExecArr_freadT!T( `in_y_fn`, `y`, `[nr, 1]` )
    ~mExecArr_freadT!T( `in_x1_fn`, `x1`, `[nr, nc1]` )
    ~[mExec( `b = regress( y, x1 );` )]
    ~mExecArr_fwriteT!T( `out_b_fn`, `b` )
    ;

  static if (false) // xxx only to debug
    {
      if (verbose)
        {
          writeln("lib_regress: octCode_arr:" );
          writeln(octCode_arr.map!((a) => a.getCode).array.join('\n'));
          stdout.flush;
        }
    }
  
  octaveExecNoOutputT!T(octCode_arr, oarr_warning, verbose, REGRESS_N_RETRY);

  auto b_data = (){
    scope auto f_b = File( out_b_fn, "r" );
    return f_b.rawRead( new T[ nc1 ] );
  }();

  static if (do_remove_tmpf)
    {
      remove( in_y_fn );
      remove( in_x1_fn );
      remove( out_b_fn );
    }
  
  return MatrixT!T( [nc1, 1], b_data );
}

private:
enum _HERE_C=`baseName(__FILE__)~':'~to!string(__LINE__)`;
enum _HERE_WR_C=`{writeln(`~_HERE_C~`);stdout.flush;}`;

unittest  // --------------------------------------------------
{
  import std.algorithm : map, max;
  import std.array;
  import std.math : abs, approxEqual, isClose;
  import std.conv : to;
  import std.datetime : Clock;
  import std.exception;
  import std.stdio;
  import std.path : baseName;
  import std.random;
  import std.string : strip;
  
  enum verbose = false;
  
  writeln;
  writeln( "unittest starts: "~__FILE__~", isOctaveSupported():", isOctaveSupported() );

  // ---------- Theil-Sen linear regression

  { // 1-D
    
    auto rnd = MinstdRand0(42);

    immutable true_m = 2.345;
    immutable true_b = 7.987;

    immutable x = [1.0,  9.0, 7.0, 3.0, -5.0, 6.0, 11.1, 7.77];
    immutable n = x.length;
    immutable true_y = (){
      auto tmp = x.dup;
      tmp[] = x[] * true_m + true_b;
      return assumeUnique( tmp );
    }();

    if (verbose)
      writeln("1-D x: ", x);

    auto noisy_x = x.map!((x) => x + uniform( -0.01, +0.01, rnd )).array;
    auto noisy_y = true_y.map!((x) => x + uniform( -0.1, +0.1, rnd )).array;
    
    auto Y = Matrix( [n,0], noisy_y );
    auto X = Matrix( [n,0], noisy_x );

    auto MB = mat_regress_theilsen( Y, X );

    if (verbose)
      {
        writeln("1-D: MB:", MB );
        writeln("1-D true_m true_b: ", true_m, ", ",true_b);
      }

    assert( MB.data.isClose( [true_m, true_b], 0.03 ) );
    
    auto Y_estim = mat_apply_theilsen( X, MB );

    auto delta = Y_estim.direct_sub( Y );
    
    if (verbose)
      {
        writeln( "[Y_estim, Y]: ", concatcol( [Y_estim, Y ] ) );
        writeln( "delta: ", delta );
      }

    assert( 1.0 > delta.data.map!abs.fold!max( -double.infinity ) );
  }
  

  { // N-D
    
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

    auto noisy_x = x.map!((x) => x + uniform( -0.01, +0.01, rnd )).array;
    auto noisy_y = true_y.map!((x) => x + uniform( -0.1, +0.1, rnd )).array;

    {
      auto Y = Matrix( [n,0], noisy_y );
      auto X = Matrix( [n,0], noisy_x );

      auto MB = mat_regress_theilsen( Y, X );

      auto expected_MB = true_m~true_b;

      if (verbose)
        {
          writeln( "N-D MB: ", MB );
          writeln( "expected_MB: ", expected_MB );
          writeln( "true_m: ", true_m );
          writeln( "true_b: ", true_b );
          stdout.flush;
        }

      assert( MB.data.isClose( expected_MB, 0.03 ) );

      auto Y_estim = mat_apply_theilsen( X, MB );

      auto delta = Y_estim.direct_sub( Y );
    
      if (verbose)
        {
          writeln( "[Y_estim, Y]: ", concatcol( [Y_estim, Y ] ) );
          writeln( "delta: ", delta );
        }

      assert( 1.0 > delta.data.map!abs.fold!max( -double.infinity ) );

      if (verbose)
        {
          // Let use compare with a more usual linear regression.
          if (isOctaveSupported())
            {
              auto X1 = get_X1_of_X( X );
              auto o_B = regress( Y, X1 );
              auto o_Y_estim = X1.dot( o_B );
              auto o_delta = o_Y_estim.direct_sub( Y );

              writeln( "[o_Y_estim, Y]: ", concatcol( [o_Y_estim, Y ] ) );
              writeln( "o_delta: ", o_delta );

              writeln( "o_B.data: ", o_B.data);
              writeln( "expected_MB: ", expected_MB);

            }
        }
    }
    
    // However, what about when y is noisy AND has outliers
    
    auto noisy_y_outliers = (){
      auto tmp = noisy_y.dup;
      tmp[ 1 ] += 100.0;
      tmp[ 4 ] += 1000.0;
      return tmp;
    }();

    {
      auto Y = Matrix( [n,0], noisy_y_outliers );
      auto X = Matrix( [n,0], noisy_x );

      auto MB = mat_regress_theilsen( Y, X );

      auto expected_MB = true_m~true_b;
      
      if (verbose)
        {
          writeln( "nyo N-D MB: ", MB );
          writeln( "nyo expected_MB: ", expected_MB );
          writeln( "nyo true_m: ", true_m );
          writeln( "nyo true_b: ", true_b );

          stdout.flush;
        }

      // Fundamental structure well estimated
      assert( MB.data.isClose( expected_MB, 0.03 ) );
      
      auto Y_estim = mat_apply_theilsen( X, MB );

      auto delta = Y_estim.direct_sub( Y );
    
      if (verbose)
        {
          writeln( "nyo [Y_estim, Y]: ", concatcol( [Y_estim, Y ] ) );
          writeln( "nyo delta: ", delta );
        }

      // outliers anyway!
      assert( 10.0 < delta.data.map!abs.fold!max( -double.infinity ) );
      
      
      if (verbose)
        {
          // Let use compare with a more usual linear regression.
          if (isOctaveSupported())
            {
              auto X1 = get_X1_of_X( X );
              auto o_B = regress( Y, X1 );
              auto o_Y_estim = X1.dot( o_B );
              auto o_delta = o_Y_estim.direct_sub( Y );

              writeln( "nyo [o_Y_estim, Y]: ", concatcol( [o_Y_estim, Y ] ) );
              writeln( "nyo o_delta: ", o_delta );
              
              writeln( "nyo o_B.data: ", o_B.data);
              writeln( "nyo expected_MB: ", expected_MB);
            }
        }
    }



    // And now, what about when x is noisy AND has outliers
    
    auto noisy_x_outliers = (){
      auto tmp = noisy_x.dup;
      tmp[ 1 ] += 100.0;
      tmp[ 13 ] -= 233.0;
      tmp[ 17 ] += 342.123;
      tmp[ 21 ] -= 700.0;
      return tmp;
    }();

    {
      auto Y = Matrix( [n,0], noisy_y );
      auto X = Matrix( [n,0], noisy_x_outliers );

      auto MB = mat_regress_theilsen( Y, X );

      auto expected_MB = true_m~true_b;
      
      if (verbose)
        {
          writeln( "nxo N-D MB: ", MB );
          writeln( "nxo expected_MB: ", expected_MB );
          writeln( "nxo true_m: ", true_m );
          writeln( "nxo true_b: ", true_b );

          stdout.flush;
        }

      // Fundamental structure still well estimated
      assert( MB.data.isClose( expected_MB, 0.1 ) );
      
      auto Y_estim = mat_apply_theilsen( X, MB );

      auto delta = Y_estim.direct_sub( Y );
    
      if (verbose)
        {
          writeln( "nxo [Y_estim, Y]: ", concatcol( [Y_estim, Y ] ) );
          writeln( "nxo delta: ", delta );
        }

      // outliers anyway...but the median in the application compensates quite a bit
      assert( 3.0 > delta.data.map!abs.fold!max( -double.infinity ) );
      
      
      if (verbose)
        {
          // Let use compare with a more usual linear regression.
          if (isOctaveSupported())
            {
              auto X1 = get_X1_of_X( X );
              auto o_B = regress( Y, X1 );
              auto o_Y_estim = X1.dot( o_B );
              auto o_delta = o_Y_estim.direct_sub( Y );

              writeln( "nxo [o_Y_estim, Y]: ", concatcol( [o_Y_estim, Y ] ) );
              writeln( "nxo o_delta: ", o_delta );

              writeln( "nxo o_B.data: ", o_B.data);
              writeln( "nxo expected_MB: ", expected_MB);
              // much worse on all accounts
            }
        }
    }

  }
  
  // ---------- Octave-based linear regression
  
  if (isOctaveSupported())
    {
      {
        if (verbose) mixin(_HERE_WR_C);

        // from the Longley data from the NIST Statistical Reference Dataset
        auto X = Matrix([0, 6], [   83.0,   234289,   2356,     1590,    107608,  1947,
                                    88.5,   259426,   2325,     1456,    108632,  1948,
                                    88.2,   258054,   3682,     1616,    109773,  1949,
                                    89.5,   284599,   3351,     1650,    110929,  1950,
                                    96.2,   328975,   2099,     3099,    112075,  1951,
                                    98.1,   346999,   1932,     3594,    113270,  1952,
                                    99.0,   365385,   1870,     3547,    115094,  1953,
                                   100.0,   363112,   3578,     3350,    116219,  1954,
                                   101.2,   397469,   2904,     3048,    117388,  1955,
                                   104.6,   419180,   2822,     2857,    118734,  1956,
                                   108.4,   442769,   2936,     2798,    120445,  1957,
                                   110.8,   444546,   4681,     2637,    121950,  1958,
                                   112.6,   482704,   3813,     2552,    123366,  1959,
                                   114.2,   502601,   3931,     2514,    125368,  1960,
                                   115.7,   518173,   4806,     2572,    127852,  1961,
                                   116.9,   554894,   4007,     2827,    130081,  1962, ]);

        auto X1 = concatcol( [mat_ones( [X.nrow, 1 ]), X] );
        
        auto y = Matrix([X1.nrow,1], [  60323,
                                        61122,
                                        60171,
                                        61187,
                                        63221,
                                        63639,
                                        64989,
                                        63761,
                                        66019,
                                        67857,
                                        68169,
                                        66513,
                                        68655,
                                        69564,
                                        69331,
                                        70551,]);


        foreach (_; 0..5)
          {
            auto start_time = Clock.currTime;
            auto b = regress( y, X1 );
            if (verbose) writeln(mixin(_HERE_C), ": #",_,": duration: ", Clock.currTime - start_time);

            if (verbose) writeln( mixin(_HERE_C), ": b: ", b );
    
            const b_expected = // Results certified by NIST using 500 digit arithmetic
              Matrix( [X1.restdim, 1], [-3482258.63459582        
                                        , 15.0618722713733        
                                        , -0.358191792925910E-01   
                                        , -2.02022980381683        
                                        , -1.03322686717359        
                                        , -0.511041056535807E-01   
                                        , 1829.15146461355
                                        ]);
    
            if (verbose) writeln( mixin(_HERE_C), ": b_expected: ", b_expected );
    
            assert( b.approxEqual( b_expected, 1e-7 ) );

            scope auto ypred = linpred_apply( b, X );
            scope auto ydelta = direct_sub( ypred, y );
            
            if (verbose)
              {
                writeln( mixin(_HERE_C), "y: "      , y );
                writeln( mixin(_HERE_C), "ypred: "  , ypred );
                writeln( mixin(_HERE_C), "ydelta: " , ydelta );
              }

            assert( ypred.approxEqual( y, 0.01 ) );
          }
      }
  }

  writeln( "unittest passed: "~__FILE__ );
}
