module d_glat.flatmatrix.lib_regress;

import d_glat.flatmatrix.core_matrix;

public import d_glat.flatmatrix.lib_octave_exec; // public: isOctaveSupported()

const(MatrixT!T) get_X1_of_X(T)( in MatrixT!T X )
{
  return concatcol( [mat_ones( [X.nrow, 1] ), X] );
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
  return octaveExec ([
                      mClearAll
                      , mExec( `pkg('load','statistics');`)
                      , mSetT!T( "Y", Y )
                      , mSetT!T( "X1", X1 )
                      , mExec( "b = regress( Y, X1 );" )
                      , mPrintMatrixT!T( "b" )
                      ]
                     , verbose );
}


private:
enum _HERE_C=`baseName(__FILE__)~':'~to!string(__LINE__)`;
enum _HERE_WR_C=`{writeln(`~_HERE_C~`);stdout.flush;}`;

unittest  // --------------------------------------------------
{
  import std.math : approxEqual;
  import std.conv : to;
  import std.datetime : Clock;
  import std.stdio;
  import std.path : baseName;
  import std.string : strip;
  
  enum verbose = false;
  
  writeln;
  writeln( "unittest starts: "~__FILE__~", isOctaveSupported():", isOctaveSupported() );

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
