module d_glat.flatmatrix.core_matrix;

/*
  Flat matrix computations. Purpose: lightweight
  implementation, @nogc as often as possible.
  
  By Guillaume Lathoud, 2019
  glat@glat.info
  
  Boost Software License version 1.0, see ../LICENSE
*/

import core.memory;
import d_glat.core_array;
import d_glat.core_assert;
import d_glat.core_memory;
import d_glat.core_runtime;
import std.algorithm : map, max, min, sort;
import std.array : appender, array;
import std.conv : to;
import std.exception : enforce;
import std.format : format;
import std.math;
import std.range : enumerate;
import std.string : split;
import std.typecons : Nullable;

immutable double numeric_epsilon = 2.220446049250313e-16;

alias MatrixStringTransformfunT( T ) =
  string delegate( in size_t, in size_t , in size_t, in T );

alias MaybeMSTT( T ) = Nullable!(MatrixStringTransformfunT!T);

// ---------- Main type

alias Matrix = MatrixT!double;

struct MatrixT( T )
{
  size_t[] dim;
  
  /*
    `data`: length should be == the product of dim values
    
    Example: 2D matrix: [ <row1> <row2> <row3> ... ]
  */ 
  T[] data;

  // --- API: Constructors

  this( size_t[] dim, T[] data ) pure nothrow @safe @nogc
    { set( dim, data ); }

  this( in size_t[] dim, in T init_val ) pure nothrow @safe
    { set( dim, init_val ); }
  
  this( in size_t[] dim ) pure nothrow @safe
    // Typically a `double.nan` initialization.
    { setDim( dim ); }
  
  // --- API: reinitialization (top-level setters)

  void set( size_t[] dim, T[] data ) pure nothrow @safe
  {
      this.dim = dim;
      this.data = data;

      // One of the `dim[i]` numbers may be `0` => will be
      // automatically computed
      complete_dim();
  }

  
  void set( in size_t[] dim, in T init_val ) pure nothrow @safe
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

  void setDim( in size_t[] dim ) pure nothrow @safe
  {
    if (this.dim != dim)
      {
        size_t total = dim[ 0 ];
        for (size_t i = 1, i_end = dim.length; i < i_end; ++i)
          total *= dim[ i ];
        
        if (!(0 < total))
          {
            assert( false, "Here we cannot support `0` (for automatic nrow) since there is no data. Note: if you need to create an empty matrix, pass some empty data array, as in `Matrix([0,8], []) and NOT `Matrix([0,8])`." );
          }
        
        this.dim  = dim.dup;
        this.data = new T[ total ];
      }
  }

  // --- API: reinitialization (lower level)

  void complete_dim() pure nothrow @safe @nogc
  // Find at most one `0` value in the `dim` array, and compute that
  // dimension out of `data.length` and the other `dim[i]` values.
  {  
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

  // --- API: append etc.

  void append_data( in T[] newdata ) pure nothrow @safe
  {
    immutable rd = restdim;

    if (0 != newdata.length % rd)
      assert( false, "Fails to verify: 0 == newdata.length % restdim   (resp. "~to!string(newdata.length)~" and "~to!string(restdim)~")");

    auto apdr = appender(&data);
    apdr.put( newdata );
    
    dim[ 0 ] = data.length / rd;
  }

  void append_data( in T[][] newdata ) pure nothrow @safe
  {
    immutable rd = restdim;
    
    auto apdr = appender(&data);
    
    foreach (v; newdata)
      apdr.put( v );
       
    if (0 != data.length % rd)
      assert( false, "Fails to verify: 0 == data.length % restdim   (resp. "~to!string(data.length)~" and "~to!string(restdim)~")");
    
    dim[ 0 ] = data.length / rd;
  }

  void appendfill_new_columns( in T fill_value, in size_t n_new_columns )
  {
    immutable dlen_old = data.length;
    immutable nr       = nrow();
    immutable rd_old   = restdim();
    
    dim[ $-1 ] += n_new_columns;
    immutable rd_new = restdim();

    auto new_data = new T[ nr * rd_new ];

    for (size_t i = 0, j = 0; i < dlen_old; )
      {
        immutable i_next = i + rd_old;

        while (i < i_next)
          new_data[ j++ ] = data[ i++ ];
          
        j += n_new_columns;
      }

    data = new_data;
  }
  
  void slice( in long begin, in long end = +long.max )
    /* Input: Accepts negative values for `begin` and `end`,
       e.g. `-10` means `nrow-10`. Both designate rows.

       Behaviour: Modifies `data` in-place, keeping only rows
       `begin..end`. Updates `dim` accordingly.
    */
  {
    immutable nr = nrow();

    if (begin == 0  &&  end >= nr)
      return; // Nothing to do

    immutable rd = restdim();
    
    immutable size_t row_begin =
      begin < 0
      ?  (-begin < nr  ?  nr + begin  :  0)
      :  ( begin < nr  ?       begin  :  nr);
    
    immutable size_t row_end   = max
      ( row_begin
        , end < 0
        ?  (-end < nr  ?  nr + end  :  0)
        :  ( end < nr  ?       end  :  nr)
        );
    
    immutable size_t data_begin = rd * row_begin;
    immutable size_t data_end   = rd * row_end;

    data = data[ data_begin..data_end ];

    immutable new_nrow = row_end - row_begin;

    debug assert( data.length == rd * new_nrow );
    
    dim[ 0 ] = new_nrow;
  }
    
  T[] splice( in long begin, in long n = +long.max, in T[] to_insert = [] )
    /* Input: Accepts negative values for `begin`, e.g. `-10` means
       `nrow-10`. `begin` and `n` designate a row resp. a number of
       rows.

       Behaviour: Modifies `data` in-place, replacing rows
       `begin..begin+n` with the optional `to_insert` data. Updates
       `dim` accordingly.

       Returns: the removed data (original rows `begin..begin+n`).
    */
  {
    immutable nr = nrow();
    immutable rd = restdim();
    
    immutable size_t row_begin =
      begin < 0
      ?  (-begin < nr  ?  nr + begin  :  0)
      :  ( begin < nr  ?       begin  :  nr);
    
    immutable size_t row_end   =
      min( nr, n < 1 ?  row_begin  :  row_begin + n );
    
    immutable size_t data_begin = rd * row_begin;
    immutable size_t data_end   = rd * row_end;

    auto ret = data[ data_begin..data_end ];

    data = data[ 0..data_begin ] ~ to_insert ~ data[ data_end..$ ];

    if (0 != data.length % rd)
      assert( false, "Fails to verify: 0 == data.length % restdim   (resp. "~to!string(data.length)~" and "~to!string(restdim)~")");
      
    dim[ 0 ] = data.length / rd;

    return ret;
  }
  
  // --- API: Comparison

  bool approxEqual( in ref Matrix other, in double maxRelDiff, in double maxAbsDiff = 1e-5 ) const pure nothrow @safe @nogc
  {
    return this.dim == other.dim
      &&  std.math.isClose( this.data, other.data, maxRelDiff, maxAbsDiff );
  }
  
  // --- API: Operators overloading

  bool opEquals( in MatrixT!T other ) const pure nothrow @safe @nogc
  {
    return this.dim == other.dim
      &&  equal_nan( this.data, other.data );
  }
  
  string toString() const
  {
    MaybeMSTT!T mstt_null;
    return toString( mstt_null );
  }

  string toString( MaybeMSTT!T maybe_mstt ) const
  {
    auto app = appender!(char[]);
    this.toString( (carr) { foreach (c; carr) app.put( c ); }
                  , maybe_mstt
                  );
    auto ret = app.data.idup;
    app.clear;
    return ret;
  }

  
  void toString
    (scope void delegate(const(char)[]) sink) const
  {
    MaybeMSTT!T mstt_null;
    toString( sink, mstt_null );
  }

  void toString
    (scope void delegate(const(char)[]) sink
     , MaybeMSTT!T maybe_mstt
     ) const
  {
    toString( sink, "", maybe_mstt );
  }

  void toString
    (scope void delegate(const(char)[]) sink
     , in string tab
     , MaybeMSTT!T maybe_mstt
     ) const
  {  
    sink( format( "Matrix(%s):[\n", dim ) );

    immutable tab2 = tab~"  ";
    
    _spit_d!T( maybe_mstt, sink, tab2, dim, data );
    
    sink( tab~"]\n" );
  }
  
  // --- Convenience shortcuts
  
  size_t ndim() const @property pure nothrow @safe @nogc
  {    
    return dim.length;
  }

  size_t restdim() const @property pure nothrow @safe @nogc
  {
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
    return dim[ 0 ];
  }
  
  size_t ncol() const @property pure nothrow @safe @nogc
  {
    
    return dim.length < 2  ?  1  :  dim[ 1 ];
  }

  // --- Convenience check when doing unsafe, performance-optimized
  // modifications.

  void check_dim() const pure @safe @nogc
  {
    assert( data.length == dim[ 0 ] * restdim );
  }
};




/*
  Direct operations (ret = f(a,b), a,b,ret all of the same type)
  in octave/matlab: .+ .- .* ./

  Each line creates a triplet of functions:
  
  `direct_add(a,b)`,`direct_add_inplace(a,b,ret)`,`direct_add_inplace_nogc(a,b,ret)`
  `direct_sub(a,b)`,`direct_sub_inplace(a,b,ret)`,`direct_sub_inplace_nogc(a,b,ret)`
  etc.
*/
mixin(_direct_code(`direct_add`,`+`));
mixin(_direct_code(`direct_sub`,`-`));
mixin(_direct_code(`direct_mul`,`*`));
mixin(_direct_code(`direct_div`,`/`));


/*
  Reduce-columns operations (ret = f(a), a,ret all of the same type, but ret has only one column)
  examples in LISP: (+ 1 2 3) (- 10 3 4 5) etc.

  Each line creates 3 functions:
  
  `redcol_add(a,b)`,`redcol_add_inplace(a,b,ret)`,`redcol_add_inplace_nogc(a,b,ret)`
  `redcol_sub(a,b)`,`redcol_sub_inplace(a,b,ret)`,`redcol_sub_inplace_nogc(a,b,ret)`
  etc.
*/
mixin(_redcol_code(`redcol_add`,`+`));
mixin(_redcol_code(`redcol_sub`,`-`));
mixin(_redcol_code(`redcol_mul`,`*`));
mixin(_redcol_code(`redcol_div`,`/`));


MatrixT!T clone( T )( in MatrixT!T X ) pure nothrow @safe
{
  
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

  (Feel free to correct me if this analysis is wrong).
*/

void clone_inplace_nogc( T )
  ( in ref MatrixT!T X
    , ref MatrixT!T ret ) pure nothrow @safe @nogc
{
  
  ret.dim[]  = X.dim[];
  ret.data[] = X.data[];
}


MatrixT!T diag( T )( in T[] x ) pure nothrow @safe
{
  auto ret = MatrixT!T( [ x.length, x.length ], 0 );
  diag_inplace_nogc!T( x, ret );
  return ret;
}

void diag_inplace_nogc( T )
  ( in T[] x
    , ref MatrixT!T ret ) pure nothrow @safe @nogc
{
  

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

void diag_inplace_nogc( T )
  ( in T v
    , ref MatrixT!T ret ) pure nothrow @safe @nogc
{
  

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
  dot_inplace_nogc( X, y, ret );
  return ret;
}

void dot_inplace_nogc( T )( in ref MatrixT!T X, in T[] y
                            , ref T[] ret
                            ) pure nothrow @safe @nogc
{
  
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
  dot_inplace_nogc( X, Y, ret );
  return ret;
}

void dot_inplace_nogc( T )( in ref MatrixT!T X, in ref MatrixT!T Y
                            , ref MatrixT!T ret
                            ) pure nothrow @safe @nogc
{
  

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



void dot_inplace_YT_nogc( T )
  ( in ref MatrixT!T X, in ref MatrixT!T YT
    , ref MatrixT!T ret
    ) pure nothrow @safe @nogc
// YT means "Y transposed"
{
  

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




T[] extract_ind( T )( in MatrixT!T X, in size_t ind ) pure nothrow @safe
// Returns "flat column" `ind`.
{
  
  T[] ret = new T[ X.nrow ];
  extract_ind_inplace_nogc!T( X, ind, ret );
  return ret;
}

auto extract_ind_m_inplace( T )( in MatrixT!T X, in size_t ind
                                 , ref MatrixT!T Y
                                 ) pure nothrow @safe
{
  Y.setDim( [X.nrow, 1] );
  extract_ind_inplace_nogc!T( X, ind, Y.data );
}


void extract_ind_inplace_nogc( T )
  ( in MatrixT!T X, in size_t ind
    , ref T[] ret ) pure nothrow @safe @nogc
/* Extract "flat column" `ind` and put it into `ret`, which is assumed
   to be already allocated as `X.nrow`-long.

   See also `set_ind_inplace_nogc`.
*/
{
  immutable rd = X.restdim;
  debug
    {
      assert( 0 <= ind );
      assert( ind < rd );
      assert( ret.length == X.nrow );
    }

  auto data = X.data;
  immutable i_end = data.length;
  
  for (size_t i = ind, j = 0;
       i < i_end;
       i+=rd, ++j)
    {
      ret[ j ] = data[ i ];
    }
}


T[] fold_rows(alias /*T[] */fun/*( T[], in T[] row )*/, T)
  ( in MatrixT!T m )
// Fold rows, using the first row as implicit seed (duplicated).
{
  auto m_rest = MatrixT!T( [ m.nrow - 1 ] ~ m.dim[ 1..$ ]
                           , cast( T[] )( m.data[ m.restdim..$ ] ) // we trust .dup and fold_rows(m,seed)
                           );
  return fold_rows!fun( m_rest, m.data[ 0..m.restdim ].dup );
}

T_OUT fold_rows(alias /*T_OUT */fun/*( T_OUT, in T[] row )*/, T, T_OUT)
  ( in MatrixT!T m, T_OUT seed )
// Fold rows with an explicit seed (NOT duplicated: can be modified).
{
  auto data = m.data;
  auto rd   = m.restdim;

  auto ret = seed;
  
  for (size_t i = 0, i_end = data.length; i < i_end; )
    {
      immutable i_next = i + rd;
      ret = fun( ret, data[ i..i_next ] );
      i = i_next;      
    }

  return ret;
}

MatrixT!T interleave( T )( in MatrixT!T[] m_arr )
pure nothrow @safe
// Functional wrapper around `interleave_inplace`
{
  
  MatrixT!T m_out;
  size_t[]  buffer;

  interleave_inplace!T( m_arr, m_out, buffer );

  return m_out;
}


void interleave_inplace( T )( in MatrixT!T[] m_arr
                              , ref MatrixT!T m_out
                              , ref size_t[] buffer )
pure nothrow @safe
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

  ensure_length( m_arr.length, buffer );
  
  buffer[] = 0;
  
  while (i_out < i_end)
    {
      foreach (i_m,m; m_arr)
        {
          auto rd = restdim_arr[ i_m ];

          auto next_i_out = i_out + rd;

          auto i_in = buffer[ i_m ];
          auto next_i_in = i_in + rd;
                      
          m_out_data[ i_out..next_i_out ][] =
            m.data[ i_in..next_i_in ][];

          buffer[ i_m ] = next_i_in;
          i_out = next_i_out;
        }
    }
}



void set_ind_inplace_nogc( T )
  ( ref MatrixT!T X, in size_t ind, in T[] v ) pure nothrow @safe @nogc
/*
  Write the vector `v` into the column `ind` of `X` (0 <= ind < X.restdim).

  See also: extract_ind_inplace_nogc.
 */
{
  immutable rd = X.restdim;
  debug
    {
      assert( 0 <= ind );
      assert( ind <= rd );
      assert( v.length == X.nrow );
    }

  auto data = X.data;
  immutable i_end = data.length;
  
  for (size_t i = ind, j = 0;
       i < i_end;
       i+=rd, ++j)
    {
      data[ i ] = v[ j ];
    }
}


void sort_inplace( T )( ref MatrixT!T m )
{

  auto      data     = m.data;
  immutable data_len = data.length;

  if (data_len < 1)
    return;
  
  immutable       rd = m.restdim;
  immutable       n0 = data_len / rd;

  void sort_inplace_impl(U)()
  {
    immutable n = cast(U)( n0 );
        
    // Impl. note: used mostly C pointers to make sure the memory will
    // be correctly allocated and deallocated. Also sparing memory in
    // some places (lessThan).

    // Init
    
    mixin(localloc(`desired_arr,U,n`)); // Used now, to sort
    mixin(localloc(`what_is_arr,U,n`)); // Used later, while swapping data
    mixin(localloc(`where_is_arr,U,n`)); // Used later, while swapping data

    foreach (U i; 0..n)
      desired_arr[ i ] = what_is_arr[ i ] = where_is_arr[ i ] = i;


    // Sort using indices only, to spare memory
    
    auto ptr = data.ptr;


    bool lessThan( scope size_t a, scope size_t b ) @nogc
    {
      T* a_ptr = (cast(T*)( ptr )) + a * rd;
      T* b_ptr = (cast(T*)( ptr )) + b * rd;

      const a_ptr_end = a_ptr + rd;
      
      while (a_ptr < a_ptr_end)
        {
          auto va = *a_ptr;
          auto vb = *b_ptr;

          if (va < vb)
            return true;

          if (va > vb)
            return false;

          ++a_ptr;
          ++b_ptr;
        }

      return false;
    }
    
    desired_arr.sort!lessThan;
                      
    // Now swap data as needed, according to the sorted indices
    
    mixin(localloc(`swap_buffer,T,rd`));
  
    for (size_t i = 0, where_to = 0; i < n; ++i)
      {
        immutable where_to_end = where_to + rd;

        immutable where_is_i   = where_is_arr[ desired_arr[ i ] ];
          
        if (where_is_i != i)
          {
            // Swap some data

            debug assert( i < where_is_i );
              
            immutable where_from     = where_is_i * rd;
            immutable where_from_end = where_from + rd;

            debug assert( where_to_end <= where_from );
              
            swap_buffer[]                        = data[ where_to..where_to_end ][];
            data[ where_to..where_to_end ][]     = data[ where_from..where_from_end ][];
            data[ where_from..where_from_end ][] = swap_buffer[];

            // Now remember what we wrote at `where_from`
              
            immutable other_i = what_is_arr[ where_is_i ] = what_is_arr[ i ];
            where_is_arr[ other_i ] = where_is_i;
          }

        where_to = where_to_end;
      }
  }

  // Extra savings on memory by using a small type (usually `uint`).
  
  if (n0 <= ushort.max)
    sort_inplace_impl!ushort;
      
  else if (n0 <= uint.max)
    sort_inplace_impl!uint;

  else
    sort_inplace_impl!size_t;
}


private void _check_dim_match( in size_t i
                               , in size_t[] da, in size_t[] db )
  pure nothrow @safe 
{
  
  // Special case: [4, 1] matches [4]
        
  size_t[] da2 = da.dup;
  size_t[] db2 = db.dup;
  if (da2.length < 2)  da2 ~= 1;
  if (db2.length < 2)  db2 ~= 1;

  assertWrap
    ( da2.length == db2.length
      , () => "dim length mismatch: "
      ~"i: "~to!string(i)
      ~", first_dim:"~to!string( da2 )
      ~", dim:"~to!string( db2 )
      );
  
  assertWrap
    ( da2[ 0..$-1 ] == db2[ 0..$-1 ]
      , () => "dimension 0..$-1 mismatch: "
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


MatrixT!T subset_col(T)( in MatrixT!T A, in size_t[] col_arr ) pure nothrow @safe
{
  immutable nrow     = A.nrow;
  immutable new_ncol = col_arr.length;

  auto B = MatrixT!T( [nrow, new_ncol] );

  subset_col_inplace_nogc!T( A, col_arr, B );

  return B;
}

void subset_col_inplace_nogc(T)( in ref MatrixT!T A, in size_t[] col_arr
                                 , ref MatrixT!T B
                                 ) pure nothrow @safe @nogc
{
  immutable nrow     = A.nrow;
  immutable new_ncol = B.restdim;
  
  debug
    {
      assert( nrow     == B.nrow );
      assert( new_ncol == col_arr.length );
      foreach (i, col; col_arr)
        assert( col < A.restdim );

      assert( A.data.length == nrow * A.restdim );
      assert( B.data.length == nrow * new_ncol );
    }

  if (0 < new_ncol)
  {
    auto A_data = A.data;
    auto B_data = B.data;

    immutable A_ncol = A.restdim;
    immutable jA_end = A_data.length;

    size_t jA = 0, jB = 0;
    for (; jA < jA_end; jA += A_ncol)
      {
        foreach (col; col_arr)
          B_data[ jB++ ] = A_data[ jA + col ];
      }

    debug
      {
        assert( jA == jA_end );

        immutable jB_end = B_data.length;
        assert( jB == jB_end );
      }
  }
}


MatrixT!T subset_row( T )( in MatrixT!T A, in size_t[] row_arr ) pure nothrow @safe
{
  immutable new_nrow = row_arr.length;
  
  auto B = MatrixT!T( [ new_nrow ] ~ A.dim[ 1..$ ] );
  
  subset_row_inplace_nogc!T( A, row_arr, B );

  return B;
}

void subset_row_inplace_nogc
( T )( in ref MatrixT!T A, in size_t[] row_arr
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


MatrixT!T subset_row_filter
( alias filter_fun, T )( in MatrixT!T A )
// Functional variant of `subset_row_filter_inplace
{
  bool mapfilter_inplace_fun( in size_t row_ind
                              , in T[] in_row
                              , ref T[] out_row
                              )
  {
    immutable ret = filter_fun( row_ind, in_row );

    if (ret)
      out_row[] = in_row[];

    return ret;
  }
  
  return subset_row_mapfilter!mapfilter_inplace_fun( A );
}

void subset_row_filter_inplace
(alias filter_fun, T)( ref MatrixT!T A )
/* in-place variant of `subset_row_filter`
   Might be interesting to spare memory.
 */
{
  immutable rd = A.restdim;

  auto      A_data        = A.data;
  immutable A_data_length = A_data.length;

  size_t j = 0;
  {
    T[] row;
    for (size_t i = 0, row_ind = 0; i < A_data_length; ++row_ind )
    {
      immutable i_next = i + rd;

      row = A_data[ i..i_next ];

      if (filter_fun( row_ind, row ))
        {
          immutable j_next = j + rd;
          if (j < i)
            {
              // in-place copy
              A_data[ j..j_next ][] = row[];
            }
          j = j_next;
        }

      i = i_next;
    }
  }
  
  /* Truncate in a single step. This way we spare ourselves an
     appender, and `mapfilter_inplace_fun` can be @nogc
  */
  A = Matrix( [ 0UL ]~A.dim[ 1..$ ]
                , A_data[ 0..j ]
              );
}




MatrixT!T subset_row_mapfilter
( alias mapfilter_inplace_fun, T )(in MatrixT!T A )
/*
  bool mapfilter_inplace_fun( row_ind, A_row, ret_row ))

  - false: filter out the row `row_ind` (i.e. do nothing).

  - true: keep and map `A_row`, new value written in `ret_row`.
*/
{
  auto ret = A.clone;
  
  immutable rd = A.restdim;

  auto   A_data = A.data;
  auto ret_data = ret.data;
  
  immutable A_data_length = A_data.length;

  size_t i_ret = 0;

  if (0 < A_data_length)
  {
    size_t i_ret_next = i_ret + rd;
    T[] ret_row = ret_data[ i_ret..i_ret_next ];
    
    for (size_t i_A = 0 , row_ind = 0;
         i_A < A_data_length;
         ++row_ind)
      {
        immutable i_A_next = i_A + rd;
        
        auto A_row = A_data[ i_A..i_A_next ];
        
        if (mapfilter_inplace_fun( row_ind, A_row, ret_row ))
          {
            // Prepare next iteration: next output row
            i_ret       = i_ret_next;
            i_ret_next += rd;
            
            if (i_ret < A_data_length)
              ret_row     = ret_data[ i_ret..i_ret_next ];
          }
        
        i_A = i_A_next;
      }
  }

  /* Truncate in a single step. This way we spare ourselves an
     appender, and `mapfilter_inplace_fun` can be @nogc
  */
  ret = Matrix( [ 0UL ]~ret.dim[ 1..$ ]
                    , ret_data[ 0..i_ret ]
                    );
  
  return ret;
}








MatrixT!T transpose( T )
( in MatrixT!T A ) pure nothrow @safe
{
  auto ret = MatrixT!T( [A.ncol, A.nrow] );
  transpose_inplace_nogc( A, ret );
  return ret;
}

void transpose_inplace_nogc( T )
  ( in ref MatrixT!T A
    , ref MatrixT!T ret ) pure nothrow @safe @nogc
{
  
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

void _spit_d( T )
  ( MaybeMSTT!T maybe_mstt
    , scope void delegate(const(char)[]) sink
    , in string tab
    , in ref size_t[] dim
    , in ref T[] data
    )
{
  size_t i_data;
  _spit_d!T( maybe_mstt, sink, tab, dim, data, 0, i_data );
}
  
void _spit_d( T )
  ( MaybeMSTT!T maybe_mstt
    , scope void delegate(const(char)[]) sink
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

      if (maybe_mstt.isNull)
        {
          sink( format( "%(%+17.14g,%),\n", data[ i_data..new_i_data ] ) );
        }
      else
        {
          sink( format( "%(%17s,%),\n"
                        , data[ i_data..new_i_data ]
                        .enumerate
                        .map!( x => maybe_mstt.get()( i_dim, i_data, x.index, x.value ) ) ) );  
        }
      
      i_data = new_i_data;
      return;
    }

  if (i_dim + 2 == dim_length)
    sink( "\n" );

  immutable d = dim[ i_dim ];
  foreach (_; 0..d)
    _spit_d!T( maybe_mstt
               , sink, tab, dim, data, i_dim + 1, i_data );
}


string _direct_code( in string fname, in string op ) pure
// Returns code that declares 3 functions named `fname`,
// `fname~"_inplace"` and `fname~"_inplace_nogc"`.
//
// e.g. direct multiplication of two matrices (like .* in octave)
// i.e. element by element.
{
  return `Matrix `~fname~`( in Matrix A, in Matrix B ) pure nothrow @safe
    {
      Matrix RET = Matrix( A.dim );
      `~fname~`_inplace_nogc( A, B, RET );
      return RET;
    }
  
  void `~fname~`_inplace( in ref Matrix A, in ref Matrix B
                               , ref Matrix RET
                               ) pure nothrow @safe
  {
    RET.setDim( A.dim );
    `~fname~`_inplace_nogc( A, B, RET );
  }
  
  void `~fname~`_inplace_nogc( in ref Matrix A, in ref Matrix B
                               , ref Matrix RET
                               ) pure nothrow @safe @nogc
  {
    debug
      {
        assert( A.dim == B.dim );
        assert( A.dim == RET.dim );
      }
      
    RET.data[] = A.data[] `~op~` B.data[];
  }
  `;
}



string _redcol_code( in string fname, in string op ) pure
// Returns code that declares two functions named `fname` and
// `fname~"_inplace"`.
//
// Reduction of columns to a single column, like e.g. in lisp (- 10 2 3 4) => 1
{
  return `Matrix `~fname~`( in Matrix A ) pure nothrow @safe
    {
      Matrix RET = Matrix( [A.nrow, 1] );
      `~fname~`_inplace_nogc( A, RET );
      return RET;
    }
  
  void `~fname~`_inplace( in ref Matrix A
                               , ref Matrix RET
                               ) pure nothrow @safe
  {
    RET.setDim( [A.nrow, 1] );
    `~fname~`_inplace_nogc( A, RET );
  }
  
  void `~fname~`_inplace_nogc( in ref Matrix A
                               , ref Matrix RET
                               ) pure nothrow @safe @nogc
  {
    debug
      {
        assert( A.nrow == RET.nrow );
        assert( 1 == RET.restdim );
      }

    auto A_data   = A.data;
    auto RET_data = RET.data;
    
    immutable n  = A.nrow;
    immutable rd = A.restdim;

    if (rd == 1)
      {
        // degenerate case
        RET_data[] = A_data[];
      }
    else
      {
        // general case
        for (size_t iA = 0, iR = 0; iR < n; ++iR)
          {
            immutable iA_next = iA + rd;

            double    x = A_data[ iA++ ];
            while (iA < iA_next)
              x = x `~op~` (A_data[ iA++ ]);

            RET_data[ iR ] = x;
          }
      }
  }
  `;
}



unittest  // ------------------------------
{
  import std.stdio;

  writeln;
  writeln( "unittest starts: "~__FILE__ );
  stdout.flush;
  
  immutable verbose = false;

  import std.exception : assumeUnique;
  
  size_t[] buffer;
  
  {
    // Automatic dimension (at most one `0` value).
    auto A = Matrix( [ 2, 0 ]
                        , [ 1.0, 2.0, 3.0, 4.0,
                            5.0, 6.0, 7.0, 8.0 ]
                         );

    auto B = Matrix( [ 2, 4 ]
                           , [ 1.0, 2.0, 3.0, 4.0,
                               5.0, 6.0, 7.0, 8.0 ]
                         );

    if (verbose)
      {
        writeln( "A: ", A );
        writeln( "B: ", B );
        stdout.flush;
      }

    assert( A == B );
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
    auto A = Matrix( [0, 4]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0  ] );

    A.append_data( [ 13.0, 14.0, 15.0, 16.0,
                     17.0, 18.0, 19.0, 20.0 ] );
    
    assert( A == Matrix( [ 5, 4 ]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0 ] )
            );
  }


  {
    auto A = Matrix( [0, 4]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0  ] );

    A.append_data( [ [ 13.0, 14.0, 15.0, 16.0 ],
                     [ 17.0, 18.0, 19.0, 20.0 ] ] );
    
    assert( A == Matrix( [ 5, 4 ]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0 ] )
            );
  }

  {
    auto A = Matrix( [0, 4]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0  ] );

    A.appendfill_new_columns( double.nan, 3 );

    assert( A == Matrix( [0, 7]
                         , [ 1.0, 2.0, 3.0, 4.0, double.nan, double.nan, double.nan,
                             5.0, 6.0, 7.0, 8.0, double.nan, double.nan, double.nan,
                             9.0, 10.0, 11.0, 12.0, double.nan, double.nan, double.nan,  ] ) );
  }

  
  {
    auto A = Matrix( [4, 4], 0.0 );
    diag_inplace_nogc( [1.0, 2.0, 3.0, 4.0], A );

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
    diag_inplace_nogc( 1.5, A );

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

    dot_inplace_YT_nogc( ma, mbT, mc );
    
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
    import std.algorithm : fold;
    
    auto A = Matrix( [ 4, 3 ], [ 1, 2, 3,
                                 4, 5, 6,
                                 7, 8, 9,
                                 10, 11, 12 ] );

    double[] fun( double[] a, in double[] b ) pure @safe
    {
      // In-place find because we know the seed is duplicated
      a[] += b[];
      return a;
    }

    auto result = fold_rows!(fun)( A );

    assert( result
            == [ 1+4+7+10, 2+5+8+11, 3+6+9+12 ] );
  }

  {
    import std.algorithm : fold;
    
    auto A = Matrix( [ 4, 3 ], [ 1, 2, 3,
                                 4, 5, 6,
                                 7, 8, 9,
                                 10, 11, 12 ] );

    double fun2( in double ret, in double[] row ) pure @safe
    {
      return ret + row.fold!"a*b";
    }

    
    auto result = fold_rows!(fun2)( A, 0.0 );

    assert( result
            == 1*2*3 + 4*5*6 + 7*8*9 + 10*11*12 );
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

    interleave_inplace( [ A, B, A ], C, buffer );

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

    interleave_inplace( [ A, B, A ], C, buffer );

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
    
    interleave_inplace( [ A, B, A ], C, buffer );

    assert( C == Matrix
            ([4, 7]
             ,[ +0.1, +0.2, +1, +2, +3, +0.1, +0.2,
                +0.3, +0.4, +4, +5, +6, +0.3, +0.4,
                +0.5, +0.6, +7, +8, +9, +0.5, +0.6,
                +0.7, +0.8, +10, +11, +12, +0.7, +0.8,
                ]));

  }


  {
    // Functional variant
    
    auto A = Matrix( [ 4, 1 ], [ 0.1,
                                 0.3,
                                 0.5,
                                 0.7 ] );
    
    auto B = Matrix( [ 4, 3 ], [ 1, 2, 3,
                                 4, 5, 6,
                                 7, 8, 9,
                                 10, 11, 12 ] );

    auto C = interleave( [ A, B, A ] );

    assert( C == Matrix
            ([4, 5]
             ,[ +0.1, +1, +2, +3, +0.1,
                +0.3, +4, +5, +6, +0.3,
                +0.5, +7, +8, +9, +0.5,
                +0.7, +10, +11, +12, +0.7,
                ]));

  }

  {
    // Functional variant
    
    auto A = Matrix( [ 4 ], [ 0.1,
                              0.3,
                              0.5,
                              0.7 ] );
    
    auto B = Matrix( [ 4, 3 ], [ 1, 2, 3,
                                 4, 5, 6,
                                 7, 8, 9,
                                 10, 11, 12 ] );

    auto C = interleave( [ A, B, A ] );

    assert( C == Matrix
            ([4, 5]
             ,[ +0.1, +1, +2, +3, +0.1,
                +0.3, +4, +5, +6, +0.3,
                +0.5, +7, +8, +9, +0.5,
                +0.7, +10, +11, +12, +0.7,
                ]));

  }

  {
    // Functional variant
    
    auto A = Matrix( [ 4, 2 ], [ 0.1, 0.2,
                                 0.3, 0.4,
                                 0.5, 0.6,
                                 0.7, 0.8 ] );
    
    auto B = Matrix( [ 4, 3 ], [ 1, 2, 3,
                                 4, 5, 6,
                                 7, 8, 9,
                                 10, 11, 12 ] );

    auto C = interleave( [ A, B, A ] );

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

    assert( subset_row( A, [0,3,4])
            == Matrix( [ 0, 3 ]
                       , [ 1.0, 2.0, 3.0,
                           10.0, 11.0, 12.0,
                           13.0, 14.0, 15.0 ]
                       ));
  }



  {
    // Functional variant
    
    auto A = Matrix( [0, 3]
                     , [ 1.0, 2.0, 3.0,
                         4.0, 5.0, 6.0,
                         7.0, 8.0, 9.0,
                         10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0 ] );

    bool filter_fun_0( in size_t ind, in double[] row )
      pure nothrow @safe @nogc
    {
      
      return row[ 0 ] % 2 == 0;
    }

    assert( subset_row_filter!filter_fun_0( A )
            == Matrix( [ 0, 3 ]
                       , [ // 1.0, 2.0, 3.0,
                          4.0, 5.0, 6.0,
                          // 7.0, 8.0, 9.0,
                          10.0, 11.0, 12.0,
                          // 13.0, 14.0, 15.0
                           ] )
            );
  }


  {
    // Functional variant

    auto A = Matrix( [0, 3]
                     , [ 1.0, 2.0, 3.0,
                         4.0, 5.0, 6.0,
                         7.0, 8.0, 9.0,
                         10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0 ] );
    
    bool filter_fun_1( in size_t ind, in double[] row )
      pure nothrow @safe @nogc
    {
      
      return row[ 0 ] % 2 != 0;
    }

    assert( subset_row_filter!filter_fun_1( A )
            == Matrix( [ 0, 3 ]
                       , [ 1.0, 2.0, 3.0,
                          // 4.0, 5.0, 6.0,
                          7.0, 8.0, 9.0,
                          // 10.0, 11.0, 12.0,
                          13.0, 14.0, 15.0
                           ] )
            );
  }

  
  {
    // Functional variant

    auto A = Matrix( [0, 3]
                     , [ 1.0, 2.0, 3.0,
                         4.0, 5.0, 6.0,
                         7.0, 8.0, 9.0,
                         10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0 ] );
    
    bool filter_fun_2( in size_t ind, in double[] row )
      pure nothrow @safe @nogc
    {
      
      return true;
    }

    assert( subset_row_filter!filter_fun_2( A )
            == Matrix( [ 0, 3 ]
                       , [ 1.0, 2.0, 3.0,
                           4.0, 5.0, 6.0,
                           7.0, 8.0, 9.0,
                           10.0, 11.0, 12.0,
                           13.0, 14.0, 15.0
                           ] )
            );
  }

  
  {
    // Functional variant

    auto A = Matrix( [0, 3]
                     , [ 1.0, 2.0, 3.0,
                         4.0, 5.0, 6.0,
                         7.0, 8.0, 9.0,
                         10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0 ] );
    
    bool filter_fun_3( in size_t ind, in double[] row )
      pure nothrow @safe @nogc
    {
      
      return false;
    }

    assert( subset_row_filter!filter_fun_3( A )
            == Matrix( [ 0, 3 ]
                       , [ ] )
            );
  }




  
  {
    // In-place variant

    auto A = Matrix( [0, 3]
                     , [ 1.0, 2.0, 3.0,
                         4.0, 5.0, 6.0,
                         7.0, 8.0, 9.0,
                         10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0 ] );

    bool filter_fun_0i( in size_t ind, in double[] row )
      pure nothrow @safe @nogc
    {
      
      return row[ 0 ] % 2 == 0;
    }

    subset_row_filter_inplace!filter_fun_0i( A );
      
      assert( A == Matrix( [ 0, 3 ]
                           , [ // 1.0, 2.0, 3.0,
                              4.0, 5.0, 6.0,
                              // 7.0, 8.0, 9.0,
                              10.0, 11.0, 12.0,
                              // 13.0, 14.0, 15.0
                           ] )
              );
  }


  {
    // In-place variant
    
    auto A = Matrix( [0, 3]
                     , [ 1.0, 2.0, 3.0,
                         4.0, 5.0, 6.0,
                         7.0, 8.0, 9.0,
                         10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0 ] );
    
    bool filter_fun_1i( in size_t ind, in double[] row )
      pure nothrow @safe @nogc
    {
      
      return row[ 0 ] % 2 != 0;
    }

    subset_row_filter_inplace!filter_fun_1i( A );
    
    assert( A == Matrix( [ 0, 3 ]
                         , [ 1.0, 2.0, 3.0,
                             // 4.0, 5.0, 6.0,
                             7.0, 8.0, 9.0,
                             // 10.0, 11.0, 12.0,
                             13.0, 14.0, 15.0
                             ] )
            );
  }

  
  {
    // In-place variant
    
    auto A = Matrix( [0, 3]
                     , [ 1.0, 2.0, 3.0,
                         4.0, 5.0, 6.0,
                         7.0, 8.0, 9.0,
                         10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0 ] );
    
    bool filter_fun_2i( in size_t ind, in double[] row )
      pure nothrow @safe @nogc
    {
      
      return true;
    }

    subset_row_filter_inplace!filter_fun_2i( A );
    
      assert( A == Matrix( [ 0, 3 ]
                           , [ 1.0, 2.0, 3.0,
                               4.0, 5.0, 6.0,
                               7.0, 8.0, 9.0,
                               10.0, 11.0, 12.0,
                               13.0, 14.0, 15.0
                               ] )
              );
  }
  
  
  {
    // In-place variant
    
    auto A = Matrix( [0, 3]
                     , [ 1.0, 2.0, 3.0,
                         4.0, 5.0, 6.0,
                         7.0, 8.0, 9.0,
                         10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0 ] );
    
    bool filter_fun_3i( in size_t ind, in double[] row )
      pure nothrow @safe @nogc
    {
      
      return false;
    }

    subset_row_filter_inplace!filter_fun_3i( A );
    
    assert( A == Matrix( [ 0, 3 ]
                         , [ ] )
            );
  }
  



  
  {
    // filter, then map, in one step
    
    auto A = Matrix( [0, 3]
                      , [ 1.0, 2.0, 3.0,
                         4.0, 5.0, 6.0,
                         7.0, 8.0, 9.0,
                         10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0 ] );

    bool mapfilter_inplace_fun_0
      ( in size_t ind, in double[] in_row, ref double[] out_row )
      pure nothrow @safe @nogc
    {
      
      if (in_row[ 0 ] % 2 == 0)
        {
          out_row[] = 7.0 * in_row[] + 0.1234;
          return true;
        }

      return false;
    }

    double[] tmp = [ 4.0, 5.0, 6.0,
                     // 7.0, 8.0, 9.0,
                     10.0, 11.0, 12.0,
                     // 13.0, 14.0, 15.0
                     ];
    tmp[] = 7.0 * tmp[] + 0.1234;
    
    assert( subset_row_mapfilter!mapfilter_inplace_fun_0( A )
            == Matrix( [ 0, 3 ], tmp )
            );
  }


  {
    // map, then filter, in one step
    
    auto A = Matrix( [0, 3]
                     , [ 1.0, 2.0, 3.0,
                         4.0, 5.0, 6.0,
                         7.0, 8.0, 9.0,
                         10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0 ] );

    bool mapfilter_inplace_fun_1
      ( in size_t ind, in double[] in_row, ref double[] out_row )
      pure nothrow @safe @nogc
    {
      

      out_row[] = 7.0 * in_row[] + 0.1234;

      if (out_row[ 0 ] > 50.0)
        {
          return true;
        }

      return false;
    }

    double[] tmp = [ 4.0, 5.0, 6.0,
                     7.0, 8.0, 9.0,
                     10.0, 11.0, 12.0,
                     13.0, 14.0, 15.0
                     ];
    tmp[] = 7.0 * tmp[] + 0.1234;

    while (tmp[ 0 ] <= 50.0)
      tmp = tmp[ 3..$ ];
    
    assert( subset_row_mapfilter!mapfilter_inplace_fun_1( A )
            == Matrix( [ 0, 3 ], tmp )  
            );
  }



  

  {
    // map, then filter, in one step
    
    auto A = Matrix( [0, 3]
                     , [] );

    bool mapfilter_inplace_fun_2
      ( in size_t ind, in double[] in_row, ref double[] out_row )
      pure nothrow @safe @nogc
    {
      

      out_row[] = 7.0 * in_row[] + 0.1234;

      if (out_row[ 0 ] > 50.0)
        {
          return true;
        }

      return false;
    }

    double[] tmp = [];
    
    assert( subset_row_mapfilter!mapfilter_inplace_fun_2( A )
            == Matrix( [ 0, 3 ], tmp )  
            );
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
    assert( A.dim == B.dim );
    assert( A.data == B.data );
  }

  {
    auto A = Matrix( [2, 3], [ 1.0, 2.0, 3.0,
                               4.0, 5.0, 6.0 ]
                     );
    
    Matrix fclone( ref Matrix a )
    {
      Matrix q = a.clone;
      return q;
    }

    auto B = fclone(A);
    A.data[] = 0.0;

    assert( A != B );
    assert( A.dim == B.dim );
    assert( A.data != B.data );
  }

  {
    auto A = Matrix( [ 0, 4 ]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0,
                         21.0, 22.0, 23.0, 24.0,
                         25.0, 26.0, 27.0, 28.0,
                         29.0, 30.0, 31.0, 32.0 ] );

    A.set_ind_inplace_nogc( 2, [-1.0, -2.0, -3.0, -4.0, -5.0, -6.0, -7.0, -8.0] );

    assert( A == Matrix( [0, 4]
                         , [ 1.0, 2.0,   -1.0, 4.0,
                             5.0, 6.0,   -2.0, 8.0,
                             9.0, 10.0,  -3.0, 12.0,
                             13.0, 14.0, -4.0, 16.0,
                             17.0, 18.0, -5.0, 20.0,
                             21.0, 22.0, -6.0, 24.0,
                             25.0, 26.0, -7.0, 28.0,
                             29.0, 30.0, -8.0, 32.0 ] ) );
  }

  {
    auto A = Matrix( [ 0, 4 ]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0,
                         21.0, 22.0, 23.0, 24.0,
                         25.0, 26.0, 27.0, 28.0,
                         29.0, 30.0, 31.0, 32.0 ] );

    A.slice( 2, 5 );

    assert( A == Matrix( [0, 4]
                         , [ 9.0, 10.0, 11.0, 12.0,
                             13.0, 14.0, 15.0, 16.0,
                             17.0, 18.0, 19.0, 20.0,
                             ] ) );
  }


  {
    auto A = Matrix( [ 0, 4 ]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0,
                         21.0, 22.0, 23.0, 24.0,
                         25.0, 26.0, 27.0, 28.0,
                         29.0, 30.0, 31.0, 32.0 ] );

    A.slice( 2 );

    assert( A == Matrix( [0, 4]
                         , [ 9.0, 10.0, 11.0, 12.0,
                             13.0, 14.0, 15.0, 16.0,
                             17.0, 18.0, 19.0, 20.0,
                             21.0, 22.0, 23.0, 24.0,
                             25.0, 26.0, 27.0, 28.0,
                             29.0, 30.0, 31.0, 32.0
                             ] ) );
  }

  

  {
    auto A = Matrix( [ 0, 4 ]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0,
                         21.0, 22.0, 23.0, 24.0,
                         25.0, 26.0, 27.0, 28.0,
                         29.0, 30.0, 31.0, 32.0 ] );

    A.slice( -2 );

    assert( A == Matrix( [0, 4]
                         , [ 25.0, 26.0, 27.0, 28.0,
                             29.0, 30.0, 31.0, 32.0
                             ] ) );
  }


  {
    auto A = Matrix( [ 0, 4 ]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0,
                         21.0, 22.0, 23.0, 24.0,
                         25.0, 26.0, 27.0, 28.0,
                         29.0, 30.0, 31.0, 32.0 ] );

    A.slice( -4, -2 );

    assert( A == Matrix( [0, 4]
                         , [ 17.0, 18.0, 19.0, 20.0,
                             21.0, 22.0, 23.0, 24.0,
                             ] ) );
  }

  {
    auto A = Matrix( [ 0, 4 ]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0,
                         21.0, 22.0, 23.0, 24.0,
                         25.0, 26.0, 27.0, 28.0,
                         29.0, 30.0, 31.0, 32.0 ] );

    const removed = A.splice( 1, 5 );

    assert( removed == [ 5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0,
                         21.0, 22.0, 23.0, 24.0,
                         ] );
       
    assert( A == Matrix( [0, 4]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         25.0, 26.0, 27.0, 28.0,
                         29.0, 30.0, 31.0, 32.0 ] ) );
  }

  {
    auto A = Matrix( [ 0, 4 ]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0,
                         21.0, 22.0, 23.0, 24.0,
                         25.0, 26.0, 27.0, 28.0,
                         29.0, 30.0, 31.0, 32.0 ] );

    const removed = A.splice( -7, 5 );

    assert( removed == [ 5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0,
                         21.0, 22.0, 23.0, 24.0,
                         ] );
       
    assert( A == Matrix( [0, 4]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         25.0, 26.0, 27.0, 28.0,
                         29.0, 30.0, 31.0, 32.0 ] ) );
  }


  {
    auto A = Matrix( [ 0, 4 ]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0,
                         21.0, 22.0, 23.0, 24.0,
                         25.0, 26.0, 27.0, 28.0,
                         29.0, 30.0, 31.0, 32.0 ] );

    immutable inserted = assumeUnique
      (  [ -0.1, -0.2, -0.3, -0.4,
           -0.5, -0.6, -0.7, -0.8,
           -0.9, -0.10, -0.11, -0.12,
           ] );
    
    const removed = A.splice( 1, 5, inserted );

    assert( removed == [ 5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0,
                         21.0, 22.0, 23.0, 24.0,
                         ] );
       
    assert( A == Matrix( [0, 4]
                         , [ 1.0, 2.0, 3.0, 4.0, ]
                         ~ inserted 
                         ~ [ 25.0, 26.0, 27.0, 28.0,
                             29.0, 30.0, 31.0, 32.0 ] ) );
  }
  
  

  {
    auto A = Matrix( [ 0, 4 ]
                     , [ 1.0, 2.0, 3.0, 4.0,
                         5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0,
                         21.0, 22.0, 23.0, 24.0,
                         25.0, 26.0, 27.0, 28.0,
                         29.0, 30.0, 31.0, 32.0 ] );

    immutable inserted = assumeUnique
      (  [ -0.1, -0.2, -0.3, -0.4,
           -0.5, -0.6, -0.7, -0.8,
           -0.9, -0.10, -0.11, -0.12,
           ] );
    
    const removed = A.splice( -7, 5, inserted );

    assert( removed == [ 5.0, 6.0, 7.0, 8.0,
                         9.0, 10.0, 11.0, 12.0,
                         13.0, 14.0, 15.0, 16.0,
                         17.0, 18.0, 19.0, 20.0,
                         21.0, 22.0, 23.0, 24.0,
                         ] );
       
    assert( A == Matrix( [0, 4]
                         , [ 1.0, 2.0, 3.0, 4.0, ]
                          ~ inserted 
                         ~ [ 25.0, 26.0, 27.0, 28.0,
                             29.0, 30.0, 31.0, 32.0 ] ) );
  }

  
  {
    auto A = Matrix( [0, 4],
                     [
                      1.0, 2.0, 4.0, 10.0,
                      1.0, 8.0, 19.0, 11.0,
                      1.0, 3.0, 7.0, 2.0,
                      1.0, 3.0, 4.0, 8.0
                      ]
                     );
    sort_inplace( A );

    assert( A == Matrix( [0, 4],
                         [
                          1.0, 2.0, 4.0, 10.0,
                          1.0, 3.0, 4.0, 8.0,
                          1.0, 3.0, 7.0, 2.0,
                          1.0, 8.0, 19.0, 11.0
                          ]
                         ) );
  }

  {
    auto A = Matrix();
    sort_inplace( A ); // does nothing because A empty, and must not crash
  }

  writeln( "unittest passed: "~__FILE__ );
}
