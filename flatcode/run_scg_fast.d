module d_glat.flatcode.run_scg_fast;

import d_glat.flatcode.lib_vector;
import std.algorithm;
import std.conv;
import std.math;
import std.stdio;

/*
  Implementation of the Scaled Conjugate Gradient (SCG) algorithm.
  See: NN 1993, vol. 6 article from M. Moller.

  Use at your own risk. Boost license, see ./LICENSE

  Simple performance tip: ldc2 -O
  
  By Guillaume Lathoud, 2005, 2016, 2018 
  glat@glat.info
*/

struct ScgWorkspace
{
  // ---------- Main input parameters (mandatory)

  double[] w_1;

  // ---------- Output values 

  // Main
  
  double[] w_k;
  double   E_w_k;

  // Secondary
  
  bool has_converged;
  uint k;

  // ---------- Secondary input parameters (optional)

  // Step "1." in the article

  double sigma    = 1e-5;
  double lambda_1 = 1e-7;

  // By default, no minimum nb of iter
  int min_iter = -1;
  
  // By default we never stop before convergence
  int max_iter           = int.max;
  int max_iter_nosuccess = int.max;

  // If verbose, then at each iteration the `ScgWorkspace` is
  // dumped, and a few messages may be displayed.
  bool verbose = false;

  // Convergence test: infinite norm of ws.r_k < ws.cv_thr and sqrt(cv_thr) on w_k variation
  double cv_thr = 1e-8;
};

//------------------------------------------------------------

void run_scg_fast( alias dE_E_fun, alias verbose = false )
  ( ref ScgWorkspace ws )
  in
{
  with (ws)
  {
    assert( 0 < w_1.length );
    assert( w_1.all!isFinite );
    assert( [ sigma, lambda_1, cv_thr ].all!isFinite );
    assert( 0 < max_iter );
    assert( 0 < max_iter_nosuccess );
  }
}
/*
  run_scg_fast!dE_E_fun( ws )

  Implementation of the Scaled Conjugate Gradient (SCG)
  algorithm.
      
  Mandatory parameters: ws.w_1 (initialization array of numbers)
  and dE_E_fun (function, see below).

  `ws` is a `ScgWorkspace`, and will, mostly for performance
  reasons, contain both your inputs:
  
  * `ws.w_1`: double[], the first "initialization" value

  *  the optional parameters

  and the outputs:

  * `ws.has_converged`: bool
      
  * `ws.w_k`: double[], the last value (where `ws.w_1` was the
  first "initialization" value).

  * other, usually less important, outputs.

  The `ws` structure is used for storing all input, transient
  and output variables.  The stopping criterion is: 

  `max_k( | ws.r_k | ) < ws.cv_thr`
      
      

  `dE_e_fun` must have the following form:
      
  double dE_E_fun(    // Optional `double` output if `deliver_E`
  in ref double[] w
  , in   bool     deliver_E
  , ref  double[] out_dE   // where to store the `out_dE` output
  )
      
  ...and the following behaviour:

  * if `deliver_E == false`, only `out_dE` is set, and the
  returned value is meaningless (e.g. double.nan).

  e.g.

  dE_E_fun( w, false, out_dE );

  * if `deliver_E == true`, then `out_dE` is set AND a
  meaningful `E` double value is returned.
      
  e.g.

  E = dE_E_fun( w, true, out_dE );

      
      
  You may want to optimize the CPU cost of `dE_E_fun`, e.g. when
  only `dE` is required (`deliver_E == false`).


  For other variables, refer to the article: notations are
  consistent with those of the NN 1993, vol. 6 article from
  M. Moller.


  By Guillaume Lathoud, 2005, 2016, 2018
  glat@glat.info
*/
body {
  auto w_1 = ws.w_1
    ,    N = w_1.length
    ;
  immutable double sigma    = ws.sigma;
  immutable double lambda_1 = ws.lambda_1;

  immutable int min_iter = ws.min_iter
    ,           max_iter = ws.max_iter
    , max_iter_nosuccess = ws.max_iter_nosuccess
    ;

  immutable double cv_thr  = ws.cv_thr;
  immutable double sqrt_cv_thr = sqrt( cv_thr );

  static if (verbose)
    {
      writeln( "Starting value of ws: ", ws );
      writeln( "Starting value of ws.w_1: ", w_1 );
    }

  // -- Prepare local scratch space

  // Cached to reduce memory management costs
  auto scratch = _get_scratch_of_N( N );
  
  auto w_k   = scratch.w_k;
  auto w_kp1 = scratch.w_kp1;
  auto dE_w_k   = scratch.dE_w_k;
  auto dE_w_kp1 = scratch.dE_w_kp1; 
  auto r_k    = scratch.r_k;
  auto r_kp1  = scratch.r_kp1;
  auto p_k    = scratch.p_k;
  auto p_kp1  = scratch.p_kp1;
  auto s_k    = scratch.s_k;
  auto tmpv = scratch.tmpv;
  auto dE_sigma = scratch.dE_sigma;
  auto tmp_w_k_delta = scratch.tmp_w_k_delta;
  auto tmp_w_kp1     = scratch.tmp_w_kp1;
  auto  dE_alpha = scratch.dE_alpha;

  double E_alpha;
  double E_w_kp1;
  double tmp;  
  double delta_k;

  double norm_p_k_square;

  // --- Init
  
  int k = 1;
  w_k[] = w_1[];
  double lambda_k     = lambda_1;
  double lambda_bar_k = 0;

  double E_w_k = dE_E_fun( w_k, true, dE_w_k );

  static if (verbose)
    {
      writeln( "init: dE_w_k: ", dE_w_k );
      writeln( "init:  E_w_k: ",  E_w_k );
    }
  
  vecneg( dE_w_k, r_k );
  p_k[] = r_k[];

  assert
    (
     ([k, lambda_k, lambda_bar_k ] ~ w_k ~ p_k ~ r_k)
     .all!isFinite
     );
  
  // -- Do the SCG descent
  
  double success = true;
  int iter_success   = 0;
  int iter_nosuccess = 0;
  int iter_scale_increase = 0;

  while (true)
    {
      // -- Step "2." in the article
      if (success)
        {    
          vecsumsq( p_k, norm_p_k_square );

          double norm_p_k         = sqrt( norm_p_k_square )
            ,    sigma_k          = sigma / norm_p_k
            ,    one_div_sigma_k  = 1 / sigma_k
            ;
          static if (verbose)
            {
              writeln( "  norm_p_k: ", norm_p_k );
              writeln( "  sigma: ", sigma );
              writeln( "  sigma_k: ", sigma_k );
              writeln( "  one_div_sigma_k: ", one_div_sigma_k );
              writeln( "  p_k: ", p_k );
            }


          if (!isFinite( sigma_k ))
            {
              throw new Error( "run_scg_fast: bug or overflow."
                               ~" "~to!string( norm_p_k )
                               ~" "~to!string( sigma )
                               );
            }

          vecscaladd( p_k, sigma_k
                      , w_k
                      , tmpv );
          
          dE_E_fun( tmpv, false, dE_sigma );

          static if (verbose)
            {
              writeln( "  dE_sigma: ", dE_sigma );
            }
          
          vecsubscal( dE_sigma, dE_w_k
                      , one_div_sigma_k
                      , s_k );
          
          vecdotprod( p_k, s_k
                      , delta_k
                      );

          static if (verbose)
            {
              writeln( "  delta_k from vecdotprod: ", delta_k );
            }

        }

      // -- Step "3." in the article
      
      delta_k += (lambda_k - lambda_bar_k) * norm_p_k_square;

      static if (verbose)
        {
          writeln( "  new delta_k:", delta_k );
        }

      
      // -- Step "4." in the article
      if (delta_k <= 0)
        {
          lambda_bar_k = 2 * (lambda_k - delta_k / norm_p_k_square);
          delta_k      = -delta_k + lambda_k * norm_p_k_square;
          lambda_k     = lambda_bar_k;
        }
      
      // -- Step "5." in the article
      double mu_k;
      vecdotprod( p_k, r_k, mu_k );

      double alpha_k = mu_k / delta_k;

      // -- Step "6." in the article
      //
      // Tentative w_kp1 (will be kept as `w_kp1` only if success in
      // step 7.)

      vecscal( p_k, alpha_k
               , tmp_w_k_delta  // we'll need this one later
               );

      vecadd( w_k, tmp_w_k_delta
              , tmp_w_kp1 );

      static if (verbose)
        {
          writeln( "tmp_w_kp1: ", tmp_w_kp1 );
        }

      
      E_alpha = dE_E_fun( tmp_w_kp1, true, dE_alpha );

      static if (verbose)
        {
          writeln( "delta_k: ", delta_k );
          writeln( "E_w_k: ", E_w_k );
          writeln( "E_alpha: ", E_alpha );
          writeln( "mu_k: ", mu_k );
        }
      
      double DELTA_k =
        2 * delta_k * (E_w_k - E_alpha) / (mu_k * mu_k);


      static if (verbose)
        writeln( "DELTA_k: ", DELTA_k );
      
      // -- Step "7." in the article
      if (DELTA_k >= 0)
        {
          static if (verbose)
            {
              writeln( "run_scg_fast: success" );
              writeln( "run_scg_fast: k: ", k+1, " E:", E_alpha );
            }
          vecswap( w_kp1, tmp_w_kp1 );
          E_w_kp1 = E_alpha;
          vecswap( dE_w_kp1, dE_alpha );

          r_kp1[] = -dE_w_kp1[];
          
          lambda_bar_k = 0;
          
          success = true;
          iter_success++;
          iter_nosuccess = 0;
          
          // Restart or continue

          if (k % N == 0)
            {	
              static if (verbose)
                writeln( "run_scg_fast: restarting the algorithm.");

              p_kp1[] = r_kp1[];

              static if (verbose)
                writeln( "p_kp1[] = r_pk1[] = ", p_kp1, r_kp1 );
            }
          else
            {
              vecsubdotprod( r_kp1, r_k
                             , r_kp1
                             , tmp );
              
              auto beta_k = tmp / mu_k;
              
              vecscaladd( p_k, beta_k
                          , r_kp1
                          , p_kp1 ) ;
            }
          
          // Reduce the scale parameter if necessary
          
          if (DELTA_k >= 0.75)
            {
              static if (verbose)
                {
                  writeln
                    ( "run_scg_fast: reducing the scale parameter");
                }

              lambda_k /= 4;
            }
          
        }
      else      
        {
          // Failure
          
          static if (verbose)
            writeln( "run_scg_fast: Failure" );

          
          lambda_bar_k = lambda_k;
          
          success       = false;
          iter_success  = 0;
          iter_nosuccess++;
          
        }
      
      // Step "8." in the algorithm
      // Increase the scale parameter if necessary
      
      if (DELTA_k < 0.25)
        {
          static if (verbose)
            {
              writeln
                ( "run_scg_fast: Increasing the scale parameter" );
            }

          lambda_k += delta_k * (1 - DELTA_k) / norm_p_k_square;
                
          iter_scale_increase++;
        }
      else
        {
          iter_scale_increase = 0;
        }
      
      assert( isFinite( alpha_k ) );
      
      bool has_converged = false;
      
      if (success)
        {
          static if (verbose) writeln( "  has_converged: success");

          // Test: gradient close to zero?
          vecinfnorm( r_k, tmp );
          if (cv_thr > alpha_k * tmp)
            {
              static if (verbose)
                {
                  writeln( "  has_converged: v_thr > alpha_k * tmp "
                           , cv_thr, " > ", alpha_k, " * ", tmp
                           );
                }

              // ...and almost no motion in `w_k` space?

              tmp = 0;
              foreach( i, v; w_k )
                {
                  tmp = max
                    ( tmp
                      , abs( tmp_w_k_delta[ i ] )
                      / max( abs( v ), abs( w_kp1[ i ] ), 1e-10 )
                      );
                }

              has_converged = sqrt_cv_thr > tmp;

              static if (verbose)
                {
                  writeln( "  has_converged: ", has_converged
                           , " sqrt_cv_thr > tmp "
                           , " ", sqrt_cv_thr, " > ", tmp );
                }
            }
        }

      ws.has_converged = has_converged;
        
      bool do_continue = k < min_iter  ||
        (
         !has_converged  &&
         k < max_iter  &&
         iter_nosuccess < max_iter_nosuccess
         );

      static if (verbose)
        {
          writeln( "run_scg_fast: after step 8. :" );
          writeln( "k+1: ", k+1 );
          writeln( "w_kp1: ", w_kp1 );
          writeln( "ws: ", ws );
          writeln( "  k < min_iter: ", k < min_iter );
          writeln( "  ||" );
          writeln( "  !has_converged: ", !has_converged );
          writeln( "  k < max_iter: ", k < max_iter );
          writeln( "  iter_nosuccess < max_iter_nosuccess: "
                   , iter_nosuccess < max_iter_nosuccess );
          writeln( "do_continue: ", do_continue );
        }

      // Update
      
      k++;
      
      if (success)
        {
          vecswap( w_k, w_kp1 );
          E_w_k = E_w_kp1;
          vecswap( dE_w_k, dE_w_kp1 );
          vecswap( r_k,    r_kp1 );
          vecswap( p_k,    p_kp1 );
          
          static if (verbose)
            {
              writeln( "run_scg_fast: success: k: ", k
                       , ", E_w_k: ", E_w_k
                       );
            }
        }
      
      if (!do_continue)
        {
          // Finished
              
          // Return the result anyway, even if not converged
          // yet, because of e.g. `max_iter` optional settings.
                
          assert( w_k.length == N );
                
          ws.k     = k;

          ws.w_k   = w_k.dup;
          ws.E_w_k = E_w_k;
                
          static if (verbose)
            {
              if (ws.has_converged)
                writeln( "run_scg_fast: finished converging." );
              else
                writeln
                  (
                   "stopped before reaching convergence "
                   ~ "(max iter reached)."
                   );
            }
              
          break;
        }
      
    } // while (true)
  
}

// ------------------------------------------------------------

unittest  // reset ; rdmd -unittest unittest.d 
{
  writeln;
  writeln( "unittest starts: " ~ __FILE__ );
  
  bool are_close(T)( in T[] a, in T[] b, T epsilon = 1e-10 )
  {
    foreach (k,v; a)
      if (!are_close_one( v, b[k], epsilon ))
        return false;
    
    return true;
  }

  bool are_close_one(T)( in T a, in T b, T epsilon = 1e-10 )
  { return isFinite( a )  &&  isFinite( b )  &&
      epsilon > abs( a - b ) / max( abs(a), abs(b), epsilon );
  }

  {
    double t0_dE_E_fun( in ref double[] w, in bool deliver_E
                        , ref double[] out_dE
                        )
    // y = (w0 - 2)^2 + (w1 - 3)^2
    {
      auto w0 = w[ 0 ]
        ,   w1 = w[ 1 ]
      
        ,   w0_m_2 = (w0 - 2)
        ,   w1_m_3 = (w1 - 3)
        ;
      out_dE[ 0 ] = 2 * w0_m_2;
      out_dE[ 1 ] = 2 * w1_m_3;
    
      if (deliver_E)
        return w0_m_2 * w0_m_2 + w1_m_3 * w1_m_3;
    
      return double.nan;
    }

    ScgWorkspace t0_ws = {
    w_1 : [ 0.0, 0.0 ]
    };
    double[] t0_wk_expected = [ 2.0, 3.0 ];

    run_scg_fast!(t0_dE_E_fun,/*verbose:*/false)( t0_ws );

    assert( t0_ws.has_converged );
    assert( are_close( t0_ws.w_k, t0_wk_expected ) );
  }
  
  
  
  {
    double t1_dE_E_fun( in ref double[] w, in bool deliver_E
                        , ref double[] out_dE
                        )
    // y = (w0 - 2)^2 + (w1 - 3)^2
    {
      auto w0 = w[ 0 ]
        ,   w1 = w[ 1 ]

        ,   w0_m_2 = (w0 - 2)
        ,   w1_m_3 = (w1 - 3)
        ;
      out_dE[ 0 ] = 2 * w0_m_2;
      out_dE[ 1 ] = 2 * w1_m_3;

      if (deliver_E)
        return w0_m_2 * w0_m_2 + w1_m_3 * w1_m_3;
      
      return double.nan;
    }

    ScgWorkspace t1_ws = {
    w_1 : [ 7.0, -2.0 ]  // different init from t0_ws
    };
    double[] t1_wk_expected = [ 2.0, 3.0 ];

    run_scg_fast!(t1_dE_E_fun,/*verbose:*/false)( t1_ws );

    assert( t1_ws.has_converged );
    assert( are_close( t1_ws.w_k, t1_wk_expected ) );

  }

  
  {
    double t2_dE_E_fun( in ref double[] w, in bool deliver_E
                        , ref double[] out_dE
                        )
    // y = (w0 - 2)^4 + (w1 - 3)^4
    {
      auto w0 = w[ 0 ]
        ,   w1 = w[ 1 ]
        
        ,   w0_m_2 = (w0 - 2)
        ,   w1_m_3 = (w1 - 3)
        
        ,   w0_m_2_p3 = w0_m_2 * w0_m_2 * w0_m_2
        ,   w1_m_3_p3 = w1_m_3 * w1_m_3 * w1_m_3
        ;
      out_dE[ 0 ] = 4 * w0_m_2_p3;
      out_dE[ 1 ] = 4 * w1_m_3_p3;

      if (deliver_E)
        return w0_m_2 * w0_m_2_p3 + w1_m_3 * w1_m_3_p3;

      return double.nan;
      
    }

    ScgWorkspace t2_ws = {
    w_1 : [ 0.0, 0.0 ]
    };
    double[] t2_wk_expected = [ 2.0, 3.0 ];

    run_scg_fast!(t2_dE_E_fun,/*verbose:*/false)( t2_ws );
    
    assert( t2_ws.has_converged );
    assert( are_close( t2_ws.w_k, t2_wk_expected, 1e-5 )
            , "w_k: " ~ to!string( t2_ws.w_k)
            ~", wk_expected: " ~ to!string( t2_wk_expected )
            );
  }


  {
    double t3_dE_E_fun( in ref double[] w, in bool deliver_E
                        , ref double[] out_dE
                        )
    // y = (w0 - 2)^2 + (w1 - 3)^2 + (w2 - 4)^2
    {
      auto w0 = w[ 0 ]
        ,   w1 = w[ 1 ]
        ,   w2 = w[ 2 ]
        
        ,   w0_m_2 = (w0 - 2)
        ,   w1_m_3 = (w1 - 3)
        ,   w2_m_4 = (w2 - 4)
        ;
      out_dE[ 0 ] = 2 * w0_m_2;
      out_dE[ 1 ] = 2 * w1_m_3;
      out_dE[ 2 ] = 2 * w2_m_4;

      if (deliver_E)
        return w0_m_2 * w0_m_2 + w1_m_3 * w1_m_3 + w2_m_4 * w2_m_4;

      return double.nan;      
    }

 
    ScgWorkspace t3_ws = {
    w_1 : [ 0.0, 0.0, 0.0 ]
    };
    double[] t3_wk_expected = [ 2.0, 3.0, 4.0 ];

    run_scg_fast!(t3_dE_E_fun,/*verbose:*/false)( t3_ws );
    
    assert( t3_ws.has_converged );
    assert( are_close( t3_ws.w_k, t3_wk_expected )
            , "w_k: " ~ to!string( t3_ws.w_k)
            ~", wk_expected: " ~ to!string( t3_wk_expected )
            );


  }


  writeln( "unittest passed: " ~ __FILE__ );

} // end of unittest block

// ____________________________________________________________

private:

class Scratch
{
  this( in size_t N )
    {
      this.N = N;
      static foreach( k; __traits( derivedMembers, Scratch ) )
        static if (k != "N" && !k.startsWith("__"))
        mixin( `this.`~k~` = new double[ N ];` );
    }

  immutable size_t N;
  
  double[] w_k
    ,         w_kp1
    ,         dE_w_k
    ,         dE_w_kp1
    
    ,         r_k
    ,         r_kp1

    ,         p_k
    ,         p_kp1

    ,         s_k
    
    ,         tmpv
  
    ,         dE_sigma
    
    ,         tmp_w_k_delta
    ,         tmp_w_kp1
    
    ,         dE_alpha
    ,         E_alpha
    ;
};

Scratch[size_t] _scratch_of_N;

Scratch _get_scratch_of_N( in size_t N )
{
  // 2.080 does not have .require yet
  auto p = N in _scratch_of_N;
  if (p)
    return *p;

  return (_scratch_of_N[ N ] = new Scratch( N ));
  
}
