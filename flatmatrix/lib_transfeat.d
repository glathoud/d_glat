module d_glat.flatmatrix.lib_transfeat;

/*
  lib_transfeat: feature transformation based on an S-Expression
  configuration, with meta keywords `pipe` & `cat` (unix-like).

  Notes:

  Any matrix dimension is supported.  

  Each atom transformation must set the dimension of its output
  matrix.

  A few examples of `modif`:

  "()" identity (copy data where necessary)
  "nmv" normalize by mean and variance
  "(cat () nmv)" concatenate the original data with normalized data
  "(pipe f1 f2 f3)" apply three transformations successively
  "(cat () nmv (pipe f1 f2 f3) (pipe f1 f2 f3 nmv))" encapsulation

  Either you give a single transofrmation (first two examples),
  or you pass a meta-transformation (cat or pipe) with any level
  of encapsulation.

  By default a few standard transformations are supported:

  "()" identity (copy data where necessary)
  "nmv" normalize by mean and variance
  "sortindex" replace values of each feature dimension with sortidx
  "nmvpca" apply nmv then pca and replace the data with the result

  For more examples, see the unittests.
  
  By Guillaume Lathoud, 2019
  glat@glat.info

  The Boost License applies to this code, as described in the file
  ../LICENSE
*/

public import d_glat.flatmatrix.core_matrix;

import d_glat.core_sexpr;
import d_glat.flatmatrix.lib_nmv;
import d_glat.flatmatrix.lib_nmvpca;
import d_glat.flatmatrix.lib_pairs;
import d_glat.flatmatrix.lib_sortindex;
import std.algorithm : map;
import std.array : array;
import std.conv : to;
import std.exception : enforce;
import std.stdio;


immutable META_CAT  = "cat";
immutable META_PIPE = "pipe";


// shortcuts for a common use case: `double`
alias Transfeat        = TransfeatT!double;
alias OneTrans         = OneTransT!double;
alias OneTransOfString = OneTransOfStringT!double;

alias OneTransT( T ) = void delegate
  ( in ref MatrixT!T m_one_in
    , ref MatrixT!T m_one_out );

alias OneTransOfStringT( T ) = OneTransT!T[string];


// The transformations available by default.
// You can add your own through `one_trans_of_string`.
// Do not forget to call `b.setDim`
void set_default_transformations( T )
  ( ref OneTransOfStringT!T tmp ) pure nothrow @safe
{
  auto b_nmv = new Buffer_nmv_inplaceT!T;  
  tmp[ "nmv" ] = ( ref a, ref b ) pure nothrow @safe
    {
      nmv_inplace_dim!T( a, b, b_nmv );
    };

  static if (is(T == double))
    {
      auto b_nmvpca = new Buffer_nmvpca_inplace;
      tmp[ "nmvpca" ] = ( ref a, ref b ) pure nothrow @safe
        {
          nmvpca_inplace_dim( a, b, b_nmvpca );
        };
    }
  
  tmp[ "pairs:a-b" ] = ( ref c_in, ref d_out ) pure nothrow @safe
    {
      pairs_inplace_dim!"a-b"( c_in, d_out );
    };

  auto b_sortindex = new Buffer_sortindex_inplaceT!T;
  tmp[ "sortindex" ] = ( ref a, ref b ) pure nothrow @safe
    {
      sortindex_inplace_dim( a, b, b_sortindex );
    };
  
}



struct TransfeatT( T )
{
  immutable SExpr modif;
  immutable OneTransOfStringT!T one_trans_of_string;

  this( in string modif )
    {
      this( parse_sexpr( modif ) );
    }
 
  this( in SExpr modif )
    {
      OneTransOfStringT!T one_trans_of_string;
      this( modif, one_trans_of_string );
    }

  this( in string modif, in OneTransOfStringT!T one_trans_of_string ) 
    {
      this( parse_sexpr( modif ), one_trans_of_string );
    }


  this( in SExpr modif, in OneTransOfStringT!T one_trans_of_string ) 
    {
      this.modif = expand_sexpr_cat_pipe( modif );

      {
        OneTransOfStringT!T tmp;

        // Default transformations

        set_default_transformations!T( tmp );

        // Additional transformations given by the user
        
        foreach (k,v; one_trans_of_string)
          tmp[ k ] = v; 

        this.one_trans_of_string =
          cast(typeof(this.one_trans_of_string))( tmp );
      }

      check_and_setup_modif( this.modif, null, null );
    }

  void opCall( T )( ref MatrixT!T top_m_in
                    , ref MatrixT!T top_m_out )
  {
    set_dim_and_do( modif, &top_m_in, &top_m_out );
  }

 private:
  
  alias MaybeMatrix = MatrixT!T*;
  
  struct MinMout
  {
    // If is null => use _first_m_in resp. _last_m_out
    MaybeMatrix maybe_m_in = null, maybe_m_out = null;
  }
  MinMout[SExprId] mimo_of_sexpr_id;

  MaybeMatrix check_and_setup_modif( in SExpr one_modif
                                     , MaybeMatrix maybe_m_in
                                     , MaybeMatrix maybe_m_out
                                     ) pure @trusted  
  {
    immutable id = one_modif.id;

    debug
      {
        if (modif.id == one_modif.id)
          {
            // Top-level call, we do not have m_in & m_out yet
            assert( maybe_m_in == null );
            assert( maybe_m_out == null );
          }
      }

    if (one_modif.isEmpty  ||  one_modif.isAtom)
      {
        mimo_of_sexpr_id[ one_modif.id ] =
          MinMout( maybe_m_in, maybe_m_out );
      }
    else if (one_modif.isList)
      {
        auto slist = cast( SList )( one_modif );
        auto first = slist.first;
        enforce( first.isAtom );

        immutable is_cat  = first.toString == META_CAT;
        immutable is_pipe = first.toString == META_PIPE;

        immutable is_cat_or_pipe = is_cat  ||  is_pipe;
        enforce( is_cat_or_pipe, "lib_transfeat: !is_cat_or_pipe: "~one_modif.toString );

        immutable n = slist.rest.length;
        enforce( 0 < n );

        mimo_of_sexpr_id[ one_modif.id ] =
          MinMout( maybe_m_in, maybe_m_out );

        if (is_cat)
          {
            // Multicast, then concat
            
            foreach (i, sub; slist.rest)
              {
                // On the heap, to persist
                auto m_ptr = new Matrix();
                MaybeMatrix sub_m_out = m_ptr;
                
                auto tmp = check_and_setup_modif
                  ( sub, maybe_m_in, sub_m_out );
              }
            // The `sub_m_out`s will be interleaved into
            // `maybe_m_out`, see below in `set_dim_and_do`.
          }
        else if (is_pipe)
          {
            // Send `maybe_m_in` through the pipe.
            
            immutable nm1 = n - 1;
        
            MaybeMatrix current_m_in = maybe_m_in;
            foreach (i, sub; slist.rest)
              {
                MaybeMatrix current_m_out;
                if (i < nm1)
                  {
                    // On the heap, to persist
                    auto m_ptr = new Matrix();
                    current_m_out = m_ptr;
                  }
                else
                  {
                    current_m_out = maybe_m_out;
                  }
                
                auto tmp = check_and_setup_modif
                  ( sub, current_m_in, current_m_out );

                debug assert
                  ( (tmp == null) == (current_m_out == null) );
                
                current_m_in = current_m_out;
              }
            
            debug assert
              ( (current_m_in == null) == (maybe_m_out == null) );
          }
        else
          {
            assert( false, "bug" );
          }          
      }
    else
      {
        assert( false, "bug" );
      }

    return maybe_m_out;
  }

  private size_t[] b_sdad_interleave;
  
  MaybeMatrix set_dim_and_do( in SExpr one_modif
                              , MaybeMatrix top_m_in
                              , MaybeMatrix top_m_out
                             )
    // Applies `one_modif` and returns its `m_out`
    {
      debug
        {
          assert( top_m_in  != null );
          assert( top_m_out != null );
        }

      immutable is_top = modif.id == one_modif.id;

      MaybeMatrix maybe_m_in, maybe_m_out;

      if (is_top)
        {
          maybe_m_in  = top_m_in;
          maybe_m_out = top_m_out;
        }
      else
        {
          auto mimo   = mimo_of_sexpr_id[ one_modif.id ];
          maybe_m_in  = mimo.maybe_m_in;
          maybe_m_out = mimo.maybe_m_out;
        }

      MaybeMatrix m_in = maybe_m_in == null ? top_m_in
        : maybe_m_in;

      // `m_out` will be returned
      MaybeMatrix m_out = maybe_m_out == null ? top_m_out
        : maybe_m_out;
    
      if (one_modif.isEmpty)
        {
          // Copy if necessary

          debug assert( m_in  != null );
          debug assert( m_out != null );
          
          if (m_out != m_in)
            {
               auto m_in_data =(*m_in).data;
               (*m_out).setDim( (*m_in).dim );
               
               foreach (i,x; m_in_data)
                 (*m_out).data[ i ] = x;
            }
        }
      else if (one_modif.isAtom)
        {
          
          assert( one_modif.toString in one_trans_of_string
                  , "Undefined transformation \""
                  ~ one_modif.toString
                  ~ "\", available: "
                  ~ to!string( one_trans_of_string.keys ));
          
          // Remark: one_trans should do `m_out.setDim()`
          
          auto one_trans =
            one_trans_of_string[ one_modif.toString ];

          one_trans( *m_in, *m_out );
        }
      else
        {
          debug assert( one_modif.isList );

          auto slist = cast( SList )( one_modif );

          auto fs = slist.first.toString;
          
          if (fs == META_CAT)
            {
              // Do each
              MatrixT!T[] m_arr;
              m_arr.assumeSafeAppend();

              foreach (sub; slist.rest)
                {
                  m_arr ~= *set_dim_and_do
                    ( sub, top_m_in, top_m_out );
                }

              debug assert( m_arr.length == slist.rest.length );
              
              // Check the output dims and setDim on m_out
              // and concatenate row-by-row.
              
              interleave_inplace( m_arr, *m_out, b_sdad_interleave );
            }
          else if (fs == META_PIPE)
            {
              foreach (sub; slist.rest)
                set_dim_and_do( sub, top_m_in, top_m_out );
            }
          else
            {
              assert( false, "bug" );
            }
        }
      return m_out;
    }
  
};


// Details

immutable(SExpr) expand_sexpr_cat_pipe( in SExpr e )
{
  if (e.isList)
    {
      auto li  = cast(SList)( e );
      auto fis = li.first.toString;
      auto arr = li.rest.map!expand_sexpr_cat_pipe.array; // always recurse

      return fis == META_CAT  ||  fis == META_PIPE  ?  sList( [sAtom( fis )]~arr ) // no expansion needed
        
        : // Expand synctatic sugar e.g. (/ a b c) => (pipe (cat a b c) /)
        sList( [sAtom( META_PIPE )
                , sList( [sAtom( META_CAT )]~arr )
                , sAtom( fis )
                ] );
    }
  
  return e.idup;
}


unittest  // ------------------------------
{
  import std.stdio;

  import std.algorithm;
  import std.math : approxEqual, isNaN;
  import std.random;

  writeln;
  writeln( "unittest starts: "~__FILE__ );

  immutable bool verbose = false;
  
  {
    auto A = Matrix( [ 3, 2 ], [ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 ] );

    immutable A_data_0 = A.data.idup;
    
    Matrix B;
    auto transfeat = Transfeat( "()" );
    transfeat( A, B );

    assert( A.data == A_data_0 );
    
    if (verbose)
      {
        writeln("A: ", A);
        writeln("B: ", B);
      }
    
    assert( A == B );
    assert( A.data.ptr != B.data.ptr );
    
    A.data[] = 0.0;
    assert( A != B );
  }
  
  {
    if (verbose)
      {
        writeln("------------- test 2");stdout.flush;
      }
    
    auto A = Matrix( [ 3, 2 ], [ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 ] );
    Matrix B;

    immutable A_data_0 = A.data.idup;
    
    if (verbose)
      {
        writeln("A: ", A);
        writeln("B: ", B);stdout.flush;
      }

    auto transfeat2 = Transfeat( "(pipe () () ())" );
    transfeat2( A, B );

    assert( A.data == A_data_0 );
    
    if (verbose)
      {
        writeln("A: ", A);
        writeln("B: ", B);stdout.flush;
      }

    
    assert( A == B );
    assert( A.data.ptr != B.data.ptr );
    
    A.data[] = 0.0;
    assert( A != B );
  }
  
  {
    if (verbose)
      {
        writeln("------------- test 3");stdout.flush;
      }
    
    auto A = Matrix( [ 3, 2 ], [ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 ] );
    Matrix B;
    
    immutable A_data_0 = A.data.idup;

    if (verbose)
      {
        writeln("A: ", A);
        writeln("B: ", B);stdout.flush;
      }

    auto transfeat2 = Transfeat( "(cat () () ())" );
    transfeat2( A, B );

    assert( A.data == A_data_0 );
    
    if (verbose)
      {
        writeln("A: ", A);
        writeln("B: ", B);stdout.flush;
      }

    
    assert( B == Matrix( [ 3, 6 ]
                          , [ 1.0, 2.0, 1.0, 2.0, 1.0, 2.0,
                              3.0, 4.0, 3.0, 4.0, 3.0, 4.0,
                              5.0, 6.0, 5.0, 6.0, 5.0, 6.0, ]) );
    
    A.data[] = 0.0;
    assert( A != B );
  }

  
  {
    if (verbose)
      {
        writeln("------------- test 4");stdout.flush;
      }
    
    auto A = Matrix( [ 3, 2 ], [ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 ] );
    Matrix B;

    immutable A_data_0 = A.data.idup;

    if (verbose)
      {
        writeln("A: ", A);
        writeln("B: ", B);stdout.flush;
      }

    OneTransOfString one_trans_of_string =
      [ "inc1" : ((ref a, ref b) {
            b.setDim(a.dim);
            b.data[] = a.data[] + 1.0;
          })
        , "sub3" : ((ref a, ref b) {
            b.setDim(a.dim);
            b.data[] = a.data[] - 3.0;
          })
        ];
    
    auto transfeat2 = Transfeat( "(cat () inc1 sub3)"
                                 , one_trans_of_string
                                 );
    transfeat2( A, B );

    assert( A.data == A_data_0 );
    
    if (verbose)
      {
        writeln("A: ", A);
        writeln("B: ", B);stdout.flush;
      }

    assert( B == Matrix( [ 3, 6 ]
                          , [ 1.0, 2.0, 2.0, 3.0,-2.0,-1.0,
                              3.0, 4.0, 4.0, 5.0, 0.0, 1.0,
                              5.0, 6.0, 6.0, 7.0, 2.0, 3.0, ]) );
    
    A.data[] = 0.0;
    assert( A != B );
  }

  
  {
    if (verbose)
      {
        writeln("------------- test 5 encapsulation");stdout.flush;
      }
    
    auto A = Matrix( [ 3, 2 ], [ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 ] );
    Matrix B;

    immutable A_data_0 = A.data.idup;
    
    if (verbose)
      {
        writeln("A: ", A);
        writeln("B: ", B);stdout.flush;
      }

    OneTransOfString one_trans_of_string =
      [ "inc1" : ((ref a, ref b) {
            b.setDim(a.dim);
            b.data[] = a.data[] + 1.0;
          })
        , "sub3" : ((ref a, ref b) {
            b.setDim(a.dim);
            b.data[] = a.data[] - 3.0;
          })
        ];
    
    auto transfeat2 = Transfeat( "(cat () inc1 (pipe inc1 sub3) sub3)"
                                 , one_trans_of_string
                                 );
    transfeat2( A, B );

    assert( A.data == A_data_0 );
    
    if (verbose)
      {
        writeln("A: ", A);
        writeln("B: ", B);stdout.flush;
      }

    assert
      ( B == Matrix
        ( [ 3, 8 ]
          , [ 1.0, 2.0, 2.0, 3.0, -1.0, 0.0, -2.0,-1.0,
              3.0, 4.0, 4.0, 5.0, 1.0, 2.0,  0.0, 1.0,
              5.0, 6.0, 6.0, 7.0, 3.0, 4.0,  2.0, 3.0, ]) );
    
    A.data[] = 0.0;
    assert( A != B );
  }

  

  {
    if (verbose)
      {
        writeln("------------- test 6 encapsulation");stdout.flush;
      }
    
    auto A = Matrix( [ 3, 2 ], [ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 ] );
    Matrix B;

    immutable A_data_0 = A.data.idup;

    if (verbose)
      {
        writeln("A: ", A);
        writeln("B: ", B);stdout.flush;
      }

    OneTransOfString one_trans_of_string =
      [ "inc1" : ((ref a, ref b) {
            b.setDim(a.dim);
            b.data[] = a.data[] + 1.0;
          })
        , "sub3" : ((ref a, ref b) {
            b.setDim(a.dim);
            b.data[] = a.data[] - 3.0;
          })
        ];
    
    auto transfeat2 = Transfeat( "(pipe (cat () inc1 sub3) inc1 sub3)"
                                 , one_trans_of_string
                                 );
    transfeat2( A, B );

    assert( A.data == A_data_0 );
    
    if (verbose)
      {
        writeln("A: ", A);
        writeln("B: ", B);stdout.flush;
      }

    auto cat_out = [ 1.0, 2.0, 2.0, 3.0,-2.0,-1.0,
                     3.0, 4.0, 4.0, 5.0, 0.0, 1.0,
                     5.0, 6.0, 6.0, 7.0, 2.0, 3.0, ];

    auto pipe_out = cat_out.dup;
    pipe_out[] += 1.0 - 3.0;
      
    assert( B == Matrix( [ 3, 6 ], pipe_out ) );
        
    A.data[] = 0.0;
    assert( A != B );
  }

  {
    auto a = Matrix( [ 100, 2 ] );
    auto rnd = MinstdRand0(42);
    
    double noise() { return rnd.uniform01 * 0.02 - 0.01; }
    
    foreach (i; 0..a.nrow)
      {
        double x = rnd.uniform01;
        double y = x * 2.0 - 1.0;
        a.data[ i*2   ] = x + noise();
        a.data[ i*2+1 ] = y + noise();
      }

    immutable a_data_0 = a.data.idup;
    
    auto transfeat = Transfeat( "nmvpca" );

    Matrix b;
    transfeat( a, b );

    assert( a.data == a_data_0 );
    
    if (verbose)
      {
        writeln;
        writeln(transfeat.modif);
        writeln( "a: ", a );
        writeln( "b: ", b );
      }

    assert( b.dim == a.dim );

    Matrix b_expected = nmvpca( a );

    assert( b == b_expected );
  }

    {
    auto a = Matrix( [ 100, 2 ] );
    auto rnd = MinstdRand0(42);
    
    double noise2() { return rnd.uniform01 * 0.02 - 0.01; }
    
    foreach (i; 0..a.nrow)
      {
        double x = rnd.uniform01;
        double y = x * 2.0 - 1.0;
        a.data[ i*2   ] = x + noise2();
        a.data[ i*2+1 ] = y + noise2();
      }

    immutable a_data_0 = a.data.idup;
    
    auto transfeat = Transfeat( "(pipe (cat () nmv nmvpca sortindex) pairs:a-b)");

    Matrix b;
    transfeat( a, b );

    assert( a.data == a_data_0 );
    
    if (verbose)
      {
        writeln;
        writeln(transfeat.modif);
        writeln( "a: ", a );
        writeln( "b: ", b );
      }

    assert( b.dim == [ a.nrow * (a.nrow - 1) >> 1 // pairs:a-b
                       , a.ncol * 4  // (cat ...)
                       ] );
  }

  
  writeln( "unittest passed: "~__FILE__ );
}
