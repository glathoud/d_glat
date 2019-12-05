module d_glat.flatmatrix.lib_sortindex;

/*
  Replace, on each dimension, the data with its sorted index values.

  Guillaume Lathoud, 2019
  glat@glat.info

  The Boost License apply to this file, as described in file
  ../LICENSE
*/

public import d_glat.flatmatrix.core_matrix;

import core.exception : AssertError;
import d_glat.core_array : ensure_length;
import std.algorithm : any, sort;
import std.array : array;
import std.conv : to;
import std.math : isNaN;
import std.range : iota;
import std.stdio;

alias Buffer_sortindex_inplace = Buffer_sortindex_inplaceT!double;
class Buffer_sortindex_inplaceT(T)
{
  int[] indices_init;
  int[] index_arr;
  T[] value_arr;
}


MatrixT!T sortindex( T )( in MatrixT!T a )
pure nothrow @safe
// Functional wrapper around `sortindex_inplace_dim`
{
  pragma( inline, true );

  MatrixT!T b;
  auto buffer = new Buffer_sortindex_inplaceT!T;

  sortindex_inplace_dim( a, b, buffer );

  return b;
}

void sortindex_inplace_dim( T )
  ( in ref MatrixT!T a
    , ref MatrixT!T b
    , ref Buffer_sortindex_inplaceT!T buffer
    )
  pure nothrow @safe
{
  pragma( inline, true );

  b.setDim( a.dim );
  sortindex_inplace( a, b, buffer );
}

void sortindex_inplace( T )
  ( in ref MatrixT!T a
    , ref MatrixT!T b
    , ref Buffer_sortindex_inplaceT!T buffer
    )
  pure nothrow @safe
{
  pragma( inline, true );

  b.data[] = a.data[];
  sortindex_inplace( b, buffer);
}


void sortindex_inplace( T )( ref MatrixT!T m
                             , ref Buffer_sortindex_inplaceT!T buffer)
  pure nothrow @safe
{
  pragma( inline, true );

  immutable n       = m.dim[ 0 ];
  immutable restdim = m.restdim;

  auto indices_init = (ref int[] arr )
    {
      if (arr.length != n)
        arr = iota( 0, cast( int )( n ) ).array;

      return arr;
    }( buffer.indices_init );
 
  auto index_arr    = ensure_length( n, buffer.index_arr );
  auto value_arr    = ensure_length( n, buffer.value_arr );
 
  sortindex_inplace
    (
     indices_init, n, restdim, n*restdim
     , index_arr, value_arr
     , m
     );
}


// ---------- Details ----------

void sortindex_inplace( T )
  ( // inputs
   in int[]    indices_init
   , in size_t n
   , in size_t restdim
   , in size_t n_t_restdim
   // intermediary buffers
   , ref int[]    index_arr
   , ref T[] value_arr
   // input & output
   , ref MatrixT!T m
    )
  pure nothrow @safe
{
  pragma( inline, true );

  debug
    {
      assert( 0 < n);
      assert( 0 < restdim);
      assert( n == indices_init.length);
      assert( n == value_arr.length);
      assert( n == m.dim[ 0 ]);
      assert( restdim == m.restdim);
      assert( n_t_restdim == n * restdim);
    }

  auto data = m.data;
  
  foreach (d; 0..restdim)
    {
      // Read
      
      index_arr[] = indices_init[];
      
      {
        size_t i_data = d;
        foreach (i_buff; 0..n)
          {
            T v = data[ i_data ];
            static if (is( T == double )
                       ||  is( T == float )
                       ||  is( T == real ))
              {
                if (isNaN( v ))
                  v = -T.infinity;
              }
            
            value_arr[ i_buff ] = v;
            i_data += restdim;
          }
      }
      
      // Modify

      index_arr
        .sort!((a,b) => value_arr[ a ] < value_arr[ b ]);
      
      // Write
      
      {
        foreach (i_buff; 0..n)
          {
            data[ d + index_arr[ i_buff ] * restdim ] =
              cast( T )( i_buff );  // sortindex
          }
      }
      
      debug
        {
          // check
          foreach (i; 0..n)
            {
              immutable v_i = value_arr[ i ];
              immutable sortindex_i
                = data[ d + i * restdim ];
              
              foreach (j; (i+1)..n)
                {
                  immutable v_j = value_arr[ j ];
                  immutable sortindex_j
                    = data[ d + j * restdim ];
                  
                  if (v_i < v_j)
                    assert( sortindex_i < sortindex_j );
                }
            }
        }
    }
}


unittest  // ------------------------------
{
  import std.stdio;

  import std.algorithm;

  writeln;
  writeln( "unittest starts: "~__FILE__ );

  immutable verbose = true;

  auto buffer = new Buffer_sortindex_inplace;

  {
    auto a = Matrix( [ 0, 5 ]
                     , [ 1.0,   2.0, 4.0,  8.0, 16.0,
                         7.0, 8.0, 9.0, 10.0, 11.0,
                         10.0, 9.0, 8.0, 7.0, 6.0 ] );

    Matrix b;

    sortindex_inplace_dim( a, b, buffer );

    assert( b == Matrix( [ 0, 5 ]
                         , [ 0.0,   0.0, 0.0, 1.0, 2.0,
                             1.0, 1.0, 2.0, 2.0, 1.0,
                             2.0, 2.0, 1.0, 0.0, 0.0 ] ));


  
      
  }



  {

    // Functional variant
    auto a = Matrix( [ 0, 5 ]
                     , [ 1.0,   2.0, 4.0,  8.0, 16.0,
                         7.0, 8.0, 9.0, 10.0, 11.0,
                         10.0, 9.0, 8.0, 7.0, 6.0 ] );


    auto b = sortindex( a );

    assert( b == Matrix( [ 0, 5 ]
                         , [ 0.0,   0.0, 0.0, 1.0, 2.0,
                             1.0, 1.0, 2.0, 2.0, 1.0,
                             2.0, 2.0, 1.0, 0.0, 0.0 ] ));


  
      
  }

  writeln( "unittest passed: "~__FILE__ );
}
