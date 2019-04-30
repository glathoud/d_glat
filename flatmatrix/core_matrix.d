module d_glat.flatmatrix.core_matrix;

/*
  Flat matrix computations. Purpose: lightweight
  implementation, @nogc as often as possible.
  
  By Guillaume Lathoud, 2019
  glat@glat.info
  
  Boost Software License version 1.0, see ../LICENSE
*/

import d_glat.core_static;
import std.algorithm : max;
import std.conv : to;
import std.format : format;
import std.math;

immutable double numeric_epsilon = 2.220446049250313e-16;

struct MatrixT( T )
{
  size_t[] dim;

  /*
    `data`: length should be == the product of dim values
    
    Example: 2D matrix: [ <row1> <row2> <row3> ... ]
  */ 
  T[] data;

  // --- API: Constructors

  this( size_t[] dim, T[] data ) pure nothrow @safe
    {
      this.dim = dim;
      this.data = data;

      // One of the `dim[i]` numbers may be `0` => will be
      // automatically computed
      complete_dim();
    }
  
  this( in size_t[] dim, in T init_val ) pure nothrow @safe
    {
      this.dim = dim.dup;

      size_t total = dim[ 0 ];
      for (size_t i = 1, i_end = dim.length; i < i_end; ++i)
        total *= dim[ i ];

      this.data = new T[ total ];
      this.data[] = init_val;

      // One of the `dim[i]` numbers may be `0` => will be
      // automatically computed
      complete_dim();
    }

  this( in size_t[] dim ) pure nothrow @safe
    // Typically a `double.nan` initialization.
    {
      this.setDim( dim );
    }

  void complete_dim() pure nothrow @safe
  // Find at most one `0` value in the `dim` array, and compute that
  // dimension out of `data.length` and the other `dim[i]` values.
  {
    pragma( inline, true );

    size_t sub_total   = dim.length < 1  ?  0  :  1;
    bool   has_missing = false;
    size_t i_missing;
    foreach (i,d; dim)
      {
        if (d == 0)
          {
            debug
              {
                if (has_missing)
                  {
                    // At most one `0` value is allowed in `dim`.
                    dim = [];
                    data = [];
                    auto x = dim[ 0 ];
                  }
              }
            has_missing = true;
            i_missing   = i;
          }
        else
          {
            sub_total *= d;
          }
      }

    if (has_missing)
      {
        const total = data.length;
        debug
          {
            if (0 != total % sub_total)
              {
                // Cannot divide total `total` by `sub_total`.
                dim = [];
                data = [];
                auto x = dim[ 0 ];
              }
          }
        dim[ i_missing ] = total / sub_total;
      }
    else
      {
        assert( sub_total == data.length, "Fails to verify: sub_total == data.length" );
      }
  }

  // --- API: reinitialization

  void setDim( in size_t[] dim ) pure nothrow @safe
  {
    pragma( inline, true );

    size_t total = dim[ 0 ];
    for (size_t i = 1, i_end = dim.length; i < i_end; ++i)
      total *= dim[ i ];

    // Here we cannot support `0` since there is no data.
    debug if (!(0 < total ))
      {
        this.dim = [];
        this.data = [];
        auto x = this.dim[ 0 ];
      }

    if (this.dim != dim)
      {
        this.dim = dim.dup;
        this.data = new T[ total ];
      }
  }
  
  // --- API: Comparison

  bool approxEqual( in ref Matrix other, in double maxRelDiff, in double maxAbsDiff = 1e-5 ) const pure nothrow @safe @nogc
  {
    pragma( inline, true );
    
    return this.dim == other.dim
      &&  std.math.approxEqual( this.data, other.data, maxRelDiff, maxAbsDiff );
  }
  
  // --- API: Operators overloading

  bool opEquals( in Matrix other ) const pure nothrow @safe @nogc
  {
    pragma( inline, true );

    return this.dim == other.dim
      &&  this.data == other.data;
  }

  void toString(scope void delegate(const(char)[]) sink) const
  {
    sink( format( "Matrix(%s):[\n", dim ) );

    immutable tab = "  ";
    
    _spit_d!T( sink, tab, dim, data );
    
    sink( "]\n" );
  }
  
  // --- Convenience shortcuts
  
  size_t ndim() const @property pure nothrow @safe @nogc
  {
    pragma( inline, true );
    
    return dim.length;
  }

  size_t restdim() const @property pure nothrow @safe @nogc
  {
    pragma( inline, true );

    if (dim.length < 2)
      return 1;
    
    size_t rd = dim[ 1 ];
    foreach (d; dim[ 2..$ ])
      rd *= d;

    return rd;
  }
  
  // --- Convenience shortcuts for 2D matrices

  size_t nrow() const @property pure nothrow @safe @nogc
  {
    pragma( inline, true );
    return dim[ 0 ];
  }
  
  size_t ncol() const @property pure nothrow @safe @nogc
  {
    pragma( inline, true );
    return dim.length < 2  ?  1  :  dim[ 1 ];
  }

  // --- Convenience check when doing unsafe, performance-optimized
  // modifications.

  void check_dim() const pure @safe @nogc
  {
    assert( data.length == dim[ 0 ] * restdim );
  }
};

alias Matrix = MatrixT!double;


/*
  Direct operations (ret = f(a,b), a,b,ret all of the same type)
  in octave/matlab: .+ .- .* ./

  Each line creates a pair of functions:
  
  `direct_add(a,b)`,`direct_add_inplace(a,b,ret)`
  `direct_sub(a,b)`,`direct_sub_inplace(a,b,ret)`
  etc.
*/
mixin(_direct_code(`direct_add`,`+`));
mixin(_direct_code(`direct_sub`,`-`));
mixin(_direct_code(`direct_mul`,`*`));
mixin(_direct_code(`direct_div`,`/`));


MatrixT!T clone( T )( in MatrixT!T X ) pure nothrow @safe
{
  pragma( inline, true );
  return MatrixT!T( X.dim.dup, X.data.dup );
}

/*
Implementation note about *_inplace functions: I opted for a `void`
return type to lean towards best performance while retaining the
simplicity of a `struct` (no `new` keyword and above all simplistic
memory management).

The alternative would be `return ret;` but then for best performance
we'd need a class `class Matrix` (instead of a struct), which might
increase the use of the Garbage Collector.

(Feel free to correct me if I am wrong).
*/

  void clone_inplace( T )
  ( in ref MatrixT!T X
    , ref MatrixT!T ret ) pure nothrow @safe @nogc
{
  pragma( inline, true );
  ret.dim[]  = X.dim[];
  ret.data[] = X.data[];
}


MatrixT!T diag( T )( in T[] x ) pure nothrow @safe
{
  MatrixT!T ret = MatrixT!T( [ x.length, x.length ], 0 );
  diag_inplace!T( x, ret );
  return ret;
}

void diag_inplace( T )( in T[] x
                        , ref MatrixT!T ret ) pure nothrow @safe @nogc
{
  pragma( inline, true );

  debug assert( ret.dim == [ x.length, x.length ] );

  ret.data[] = 0;
  
  {
    size_t i = 0
      ,  np1 = ret.ncol + 1
      ;
    foreach (v; x)
      {
        ret.data[ i ] = v;
        i += np1;
      }
  }
}

void diag_inplace( T )( in T v
                        , ref MatrixT!T ret ) pure nothrow @safe @nogc
{
  pragma( inline, true );

  ret.data[] = cast( T )( 0.0 );
  
  {
    size_t np1 = ret.ncol + 1;
    for (size_t i = 0, i_end = ret.data.length;
         i < i_end;
         i += np1 )
      {
        ret.data[ i ] = v;
      }
  }
}



T[] dot( T )( in MatrixT!T X, in T[] y ) pure nothrow @safe
// matrix * vector
{
  T[] ret = new T[]( X.nrow );
  dot_inplace( X, y, ret );
  return ret;
}

void dot_inplace( T )( in ref MatrixT!T X, in T[] y
                       , ref T[] ret
                       ) pure nothrow @safe @nogc
{
  pragma( inline, true );
  debug
    {
      assert( X.ndim == 2 );
      assert( X.nrow == ret.length );
      assert( X.ncol ==   y.length );
    }

  immutable q = X.ncol;

  size_t ij_offset = 0;
  
  foreach (i; 0..X.nrow)
    {
      T acc = 0;
      
      foreach (yj; y)
        acc += X.data[ ij_offset++ ] * yj;
      
      ret[ i ] = acc;
    }
}


MatrixT!T dot( T )( in MatrixT!T X, in MatrixT!T Y ) pure nothrow @safe
// matrix * matrix
{
  auto ret = MatrixT!T( [ X.nrow, Y.ncol ] );
  dot_inplace( X, Y, ret );
  return ret;
}

void dot_inplace( T )( in ref MatrixT!T X, in ref MatrixT!T Y
                       , ref MatrixT!T ret
                       ) pure nothrow @safe @nogc
{
  pragma( inline, true );

  immutable size_t p = X.nrow, q = X.ncol, r = Y.ncol;
  debug
    {
      assert( 2 == X.ndim );
      assert( 2 == Y.ndim );
      assert( 2 == ret.ndim );
      
      assert( q == Y.nrow );

      assert( p == ret.nrow );
      assert( r == ret.ncol );
    }

  size_t i_j_ret = 0;
  size_t rowi_X  = 0;

  auto ret_data = ret.data;
  
  foreach (i; 0..p)
    {
      foreach (j; 0..r)
        {
          T acc = 0;

          size_t ik_X = rowi_X;
          size_t kj_Y = j;
          foreach (k; 0..q)
            {
              acc += X.data[ ik_X++ ] * Y.data[ kj_Y ];
              kj_Y += r;
            }
          
          ret_data[ i_j_ret++ ] = acc;
        }

      rowi_X += q;
    }
}



void dot_inplace_YT( T )( in ref MatrixT!T X, in ref MatrixT!T YT
                          , ref MatrixT!T ret
                          ) pure nothrow @safe @nogc
// YT means "Y transposed"
{
  pragma( inline, true );

  immutable size_t p = X.nrow, q = X.ncol, r = YT.nrow;
  debug
    {
      assert( 2 == X.ndim );
      assert( 2 == YT.ndim );
      assert( 2 == ret.ndim );
      
      assert( q == YT.ncol );

      assert( p == ret.nrow );
      assert( r == ret.ncol );
    }

  size_t i_j_ret = 0;
  size_t rowi_X  = 0;

  auto ret_data = ret.data;
  
  foreach (i; 0..p)
    {
      size_t pYT = 0;
      foreach (j; 0..r)
        {
          T acc = 0;

          size_t ik_X = rowi_X;
          foreach (k; 0..q)
            {
              acc += X.data[ ik_X++ ] * YT.data[ pYT++ ];
            }
          
          ret_data[ i_j_ret++ ] = acc;
        }

      rowi_X += q;
    }
}




void interleave_inplace( T )( in MatrixT!T[] m_arr
                              , ref MatrixT!T m_out )
@safe
// Calls m_out.setDim() and fills it with m_arr's concatenated rows
{
  auto first_dim = m_arr[ 0 ].dim;
  
  size_t[] restdim_arr;
  size_t   restdim_total = 0;

  foreach (i,m; m_arr)
    {
      // Read
                  
      auto restdim = m.restdim;
      auto dim = m.dim;

      // Write
                  
      restdim_arr ~= restdim;
      restdim_total += restdim;

      // Check
                  
      debug if (0 < i)
        _check_dim_match( i, first_dim, dim );
    }

  m_out.setDim( first_dim[ 0..max(1,$-1) ] ~ [ restdim_total] );
              
  // Fill `m_out` with interleaved data

  auto   m_out_data = m_out.data;
  size_t i_out = 0;
  size_t i_end = m_out_data.length;

  mixin(static_array_code(`i_in_arr`, `size_t`, `m_arr.length`));
  i_in_arr[] = 0;
  
  while (i_out < i_end)
    {
      foreach (i_m,m; m_arr)
        {
          auto rd = restdim_arr[ i_m ];

          auto next_i_out = i_out + rd;

          auto i_in = i_in_arr[ i_m ];
          auto next_i_in = i_in + rd;
                      
          m_out_data[ i_out..next_i_out ][] =
            m.data[ i_in..next_i_in ][];

          i_in_arr[ i_m ] = next_i_in;
          i_out = next_i_out;
        }
    }
}

private void _check_dim_match( in size_t i
                               , in size_t[] da, in size_t[] db )
@safe
{
  
  // Special case: [4, 1] matches [4]
        
  size_t[] da2 = da.dup;
  size_t[] db2 = db.dup;
  if (da2.length < 2)  da2 ~= 1;
  if (db2.length < 2)  db2 ~= 1;

  assert
    ( da2.length == db2.length
      , "dim length mismatch: "
      ~"i: "~to!string(i)
      ~", first_dim:"~to!string( da2 )
      ~", dim:"~to!string( db2 )
      );
        
  assert
    ( da2[ 0..$-1 ] == db2[ 0..$-1 ]
      , "dimension 0..$-1 mismatch: "
      ~"i: "~to!string(i)
      ~", first_dim:"~to!string( da2 )
      ~", dim:"~to!string( db2 )
      );
}



MatrixT!T rep( T )
( in size_t nrow, in size_t ncol, in T v ) pure nothrow @safe
{
  return rep!T( [nrow, ncol], v );
}
  
MatrixT!T rep( T )( in size_t[] dim, in T v ) pure nothrow @safe
{
  return MatrixT!T( dim, v );
}



MatrixT!T subset( T )( in MatrixT!T A, in size_t[] row_arr ) pure nothrow @safe
{
  immutable new_nrow = row_arr.length;
  
  auto B = MatrixT!T( [ new_nrow ] ~ A.dim[ 1..$ ] );
  
  subset_inplace!T( A, row_arr, B );

  return B;
}

void subset_inplace( T )( in ref MatrixT!T A, in size_t[] row_arr
                          , ref MatrixT!T B ) pure nothrow @safe @nogc 
{
  debug
    {
      assert( A.restdim == B.restdim );
      assert( B.nrow == row_arr.length );
      assert( A.dim[ 1..$ ] == B.dim[ 1..$ ] );
    }

  immutable rd = A.restdim;
  
  auto A_data = A.data;
  auto B_data = B.data;
  
  size_t iB = 0;
  foreach (row; row_arr)
    {
      immutable next_iB = iB + rd;

      immutable      iA = row * rd;
      B_data[ iB..next_iB ][] = A_data[ iA..(iA+rd) ][];

      iB = next_iB;
    }
}



MatrixT!T transpose( T )
( in MatrixT!T A ) pure nothrow @safe
{
  auto ret = MatrixT!T( [A.ncol, A.nrow] );
  transpose_inplace( A, ret );
  return ret;
}

void transpose_inplace( T )( in ref MatrixT!T A
                             , ref MatrixT!T ret ) pure nothrow @safe @nogc
{
  pragma( inline, true );
  debug
    {
      assert( A.ndim == 2 );
      assert( ret.ndim == 2 );
      assert( ret.dim == [A.ncol, A.nrow] );
    }

  size_t ij_ret = 0;

  auto ret_data = ret.data;
  immutable ret_delta = ret.ncol;
  immutable rc = ret.data.length;
  
  foreach (va; A.data)
    {
      ret_data[ ij_ret ] = va;

      ij_ret += ret_delta;

      if (ij_ret >= rc)
        ij_ret = 1 + (ij_ret - rc);
    }
}




private: // ------------------------------

void _spit_d( T )( scope void delegate(const(char)[]) sink
                   , in string tab
                   , in ref size_t[] dim
                   , in ref T[] data
                   )
{
  size_t i_data;
  _spit_d!T( sink, tab, dim, data, 0, i_data );
}
  
void _spit_d( T )( scope void delegate(const(char)[]) sink
                   , in string tab
                   , in ref size_t[] dim
                   , in ref T[] data
                   , in size_t i_dim

                   , ref size_t i_data
                   )
{
  immutable  dim_length = dim.length;
  immutable data_length = data.length;
  
  if (i_data >= data_length)
    return;

  if (i_dim + 1 == dim_length)
    {
      sink( tab );
      auto new_i_data = i_data + dim[ $-1 ];
      sink( format( "%( %+18.12g%)\n", data[ i_data..new_i_data ] ) );
      i_data = new_i_data;
      return;
    }

  if (i_dim + 2 == dim_length)
      sink( "\n" );

  immutable d = dim[ i_dim ];
  foreach (_; 0..d)
    _spit_d!T( sink, tab, dim, data, i_dim + 1, i_data );
}


string _direct_code( in string fname, in string op ) pure
// Returns code that declares two functions named `fname` and
// `fname~"_inplace"`.
{
  return `Matrix `~fname~`( in Matrix A, in Matrix B ) pure nothrow @safe
    {
      Matrix RET = Matrix( A.dim );
      `~fname~`_inplace( A, B, RET );
      return RET;
    }
  
  void `~fname~`_inplace( in ref Matrix A, in ref Matrix B
                          , ref Matrix RET
                          ) pure nothrow @safe @nogc
  {
      pragma( inline, true );
      
      debug
        {
          assert( A.dim == B.dim );
          assert( A.dim == RET.dim );
        }
      
      RET.data[] = A.data[] `~op~` B.data[];
    }
  `;
}





unittest  // ------------------------------
{
  import std.stdio;

  writeln;
  writeln( "unittest starts: "~__FILE__ );

  {
    // Automatic dimension (at most one `0` value).
    assert( Matrix( [ 2, 0 ]
                    , [ 1.0, 2.0, 3.0, 4.0,
                        5.0, 6.0, 7.0, 8.0 ]
                    )
            == Matrix( [ 2, 4 ]
                       , [ 1.0, 2.0, 3.0, 4.0,
                           5.0, 6.0, 7.0, 8.0 ]
                       )
            );
  }

  {
    // Automatic dimension (at most one `0` value).
    assert( Matrix( [ 0, 4 ]
                    , [ 1.0, 2.0, 3.0, 4.0,
                        5.0, 6.0, 7.0, 8.0 ]
                    )
            == Matrix( [ 2, 4 ]
                       , [ 1.0, 2.0, 3.0, 4.0,
                           5.0, 6.0, 7.0, 8.0 ]
                       )
            );
  }


  {
    assert( diag( [ 1.0, 2.0, 3.0, 4.0 ] )
            == Matrix( [4, 4]
                       , [
                          1.0, 0.0, 0.0, 0.0,
                          0.0, 2.0, 0.0, 0.0,
                          0.0, 0.0, 3.0, 0.0,
                          0.0, 0.0, 0.0, 4.0
                          ]
                       )
            );
  }


  {
    assert( rep( 3, 4, 1.234 )
            == Matrix( [3, 4]
                       , [ 1.234, 1.234, 1.234, 1.234,
                           1.234, 1.234, 1.234, 1.234,
                           1.234, 1.234, 1.234, 1.234
                           ]
                       )
            );
  }

  
  {
    auto A = Matrix( [4, 4], 0.0 );
    diag_inplace( [1.0, 2.0, 3.0, 4.0], A );

    assert( A == Matrix( [4, 4]
                         , [
                            1.0, 0.0, 0.0, 0.0,
                            0.0, 2.0, 0.0, 0.0,
                            0.0, 0.0, 3.0, 0.0,
                            0.0, 0.0, 0.0, 4.0
                            ]
                         )
            );
  }

  

  {
    auto A = Matrix( [4, 4], 0.0 );
    diag_inplace( 1.5, A );

    assert( A == Matrix( [4, 4]
                         , [
                            1.5, 0.0, 0.0, 0.0,
                            0.0, 1.5, 0.0, 0.0,
                            0.0, 0.0, 1.5, 0.0,
                            0.0, 0.0, 0.0, 1.5
                            ]
                         )
            );
  }

  

  {
    auto m = Matrix( [2, 3], [ 1.0, 2.0, 3.0,
                               4.0, 5.0, 6.0
                               ]
                     );

    auto v = [ 10.0, 100.0, 1000.0 ];
    
    assert( dot( m, v )
            == [ 3210.0, 6540.0 ] );
  }

  {
    auto ma = Matrix( [2, 3], [ 1.0, 2.0, 3.0,
                                4.0, 5.0, 6.0 ] );

    auto mb = Matrix( [3, 4], [ 1e1, 1e2, 1e3, 1e4,
                                1e5, 1e6, 1e7, 1e8,
                                1e9, 1e10, 1e11, 1e12 ] );

    assert( dot( ma, mb )
            == Matrix
            ( [2, 4],
              [ 3000200010.0, 30002000100.0, 300020001000.0, 3000200010000.0,
                6000500040.0, 60005000400.0, 600050004000.0, 6000500040000.0 ]
              )
            );
  }


  
  {
    auto ma = Matrix( [2, 3], [ 1.0, 2.0, 3.0,
                                4.0, 5.0, 6.0 ] );

    auto mbT = transpose( Matrix( [3, 4]
                                  , [ 1e1, 1e2, 1e3, 1e4,
                                      1e5, 1e6, 1e7, 1e8,
                                      1e9, 1e10, 1e11, 1e12 ] ) );

    auto mc = Matrix( [2, 4] );

    dot_inplace_YT( ma, mbT, mc );
    
    assert( mc
            == Matrix
            ( [2, 4],
              [ 3000200010.0, 30002000100.0, 300020001000.0, 3000200010000.0,
                6000500040.0, 60005000400.0, 600050004000.0, 6000500040000.0 ]
              )
            );
  }


  
  {
    auto A = Matrix( [2, 2], [ 1.0, 2.0,   3.0, 4.0 ] );
    auto B = Matrix( [2, 2], [ 10.0, 100.0,   1000.0, 10000.0 ] );

    assert( direct_add( A, B )
            == Matrix( [2, 2], [ 11.0, 102.0,   1003.0, 10004.0 ])
            );
            
    assert( direct_sub( A, B )
            == Matrix( [2, 2], [-9.0, -98.0,   -997.0, -9996.0])
            );

    assert( direct_mul( A, B )
            == Matrix( [2, 2], [10.0, 200.0,   3000.0, 40000.0])
            );

    assert( direct_div( B, A )
            == Matrix( [2, 2], [10.0, 50.0,   1000.0/3.0, 2500.0])
            );
  }


  {
    auto A = Matrix( [ 4, 1 ], [ 0.1,
                                 0.3,
                                 0.5,
                                 0.7 ] );
    
    auto B = Matrix( [ 4, 3 ], [ 1, 2, 3,
                                 4, 5, 6,
                                 7, 8, 9,
                                 10, 11, 12 ] );
    Matrix C;

    interleave_inplace( [ A, B, A ], C );

    assert( C == Matrix
            ([4, 5]
             ,[ +0.1, +1, +2, +3, +0.1,
                +0.3, +4, +5, +6, +0.3,
                +0.5, +7, +8, +9, +0.5,
                +0.7, +10, +11, +12, +0.7,
                ]));

  }

  {
    auto A = Matrix( [ 4 ], [ 0.1,
                              0.3,
                              0.5,
                              0.7 ] );
    
    auto B = Matrix( [ 4, 3 ], [ 1, 2, 3,
                                 4, 5, 6,
                                 7, 8, 9,
                                 10, 11, 12 ] );
    Matrix C;

    interleave_inplace( [ A, B, A ], C );

    assert( C == Matrix
            ([4, 5]
             ,[ +0.1, +1, +2, +3, +0.1,
                +0.3, +4, +5, +6, +0.3,
                +0.5, +7, +8, +9, +0.5,
                +0.7, +10, +11, +12, +0.7,
                ]));

  }

  {
    auto A = Matrix( [ 4, 2 ], [ 0.1, 0.2,
                                 0.3, 0.4,
                                 0.5, 0.6,
                                 0.7, 0.8 ] );
    
    auto B = Matrix( [ 4, 3 ], [ 1, 2, 3,
                                 4, 5, 6,
                                 7, 8, 9,
                                 10, 11, 12 ] );
    Matrix C;

    interleave_inplace( [ A, B, A ], C );

    assert( C == Matrix
            ([4, 7]
             ,[ +0.1, +0.2, +1, +2, +3, +0.1, +0.2,
                +0.3, +0.4, +4, +5, +6, +0.3, +0.4,
                +0.5, +0.6, +7, +8, +9, +0.5, +0.6,
                +0.7, +0.8, +10, +11, +12, +0.7, +0.8,
                ]));

  }


  {
    auto A = Matrix( [0, 3]
                     , [ 1.0, 2.0, 3.0,
                         4.0, 5.0, 6.0,
                         7.0, 8.0, 9.0,
                         10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0 ] );

    assert( subset( A, [0,3,4])
            == Matrix( [ 0, 3 ]
                       , [ 1.0, 2.0, 3.0,
                           10.0, 11.0, 12.0,
                           13.0, 14.0, 15.0 ]
                       ));
  }

  

    {
      auto A = Matrix( [2, 3], [ 1.0, 2.0, 3.0,
                                 4.0, 5.0, 6.0 ]
                       );

    assert( transpose( A )
            == Matrix( [3, 2], [ 1.0, 4.0,
                                 2.0, 5.0,
                                 3.0, 6.0 ] )
            );
  } 

    {
      auto A = Matrix( [2, 3], [ 1.0, 2.0, 3.0,
                                 4.0, 5.0, 6.0 ]
                       );

      Matrix f( ref Matrix a )
      {
        Matrix q = a;
        return q;
      }

      auto B = f(A);
      A.data[] = 0.0;

      assert( A == B );
      assert( A.data == B.data );
    }
  
  writeln( "unittest passed: "~__FILE__ );
}
