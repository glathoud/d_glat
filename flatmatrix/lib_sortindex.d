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
import d_glat.core_static : static_array_code;
import std.algorithm : any, sort;
import std.array : array;
import std.conv : to;
import std.math : isNaN;
import std.range : iota;
import std.stdio;

void sortindex_inplace_dim( T )( in ref MatrixT!T a
                                 , ref MatrixT!T b )
nothrow @safe
{
  pragma( inline, true );

  b.setDim( a.dim );
  sortindex_inplace( a, b );
}

void sortindex_inplace( T )( in ref MatrixT!T a, ref MatrixT!T b )
nothrow @safe
{
  pragma( inline, true );

  b.data[] = a.data[];
  sortindex_inplace( b );
}


void sortindex_inplace( T )( ref MatrixT!T m )
nothrow @safe
{
  pragma( inline, true );

  immutable n       = m.dim[ 0 ];
  immutable restdim = m.restdim;

  static int[] indices_init;
  if (indices_init.length != n)
    indices_init = iota( 0, cast( int )( n ) ).array;

  mixin(static_array_code(`index_arr`,`int`,`n`));
  mixin(static_array_code(`value_arr`,`T`,`n`));

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
