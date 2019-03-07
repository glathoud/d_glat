module d_glat.flatmatrix.lib_sort_index;

import d_glat.core_static : static_array_code;
import d_glat.flatmatrix.core_matrix;
import std.algorithm : sort;
import std.array : array;
import std.range : iota;

void sort_index_inplace( ref Matrix m )
  nothrow @safe
{
  pragma( inline, true );

  immutable n       = m.dim[ 0 ];
  immutable restdim = m.restdim;

  static int[] indices_init;
  if (indices_init.length != n)
    indices_init = iota( 0, cast( int )( n ) ).array;

  mixin(static_array_code(`index_arr`,`int`,`n`));
  mixin(static_array_code(`value_arr`,`double`,`n`));

  sort_index_inplace
    (
     indices_init, n, restdim, n*restdim
     , index_arr, value_arr
     , m
     );
}


// ---------- Details ----------

void sort_index_inplace
  ( // inputs
   in int[]    indices_init
   , in size_t n
   , in size_t restdim
   , in size_t n_t_restdim
   // intermediary buffers
   , ref int[]    index_arr
   , ref double[] value_arr
   // input & output
   , ref Matrix m
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
            value_arr[ i_buff ] = data[ i_data ];
            i_data += restdim;
          }
      }
      
      // Modify
      
      index_arr
        .sort!((a,b) => value_arr[ a ] < value_arr[ b ]);
      
      // Write
      
      {
        size_t i_data = d;
        foreach (i_buff; 0..n)
          {
            data[ d + index_arr[ i_buff ] * restdim ] =
              cast( double )( i_buff );  // sort_index
          }
      }
      
      debug
        {
          // check
          foreach (i; 0..n)
            {
              immutable v_i = value_arr[ i ];
              immutable sort_index_i
                = data[ d + i * restdim ];
              
              foreach (j; (i+1)..n)
                {
                  immutable v_j = value_arr[ j ];
                  immutable sort_index_j
                    = data[ d + j * restdim ];
                  
                  if (v_i < v_j)
                      assert(sort_index_i < sort_index_j );
                }
            }
        }
    }
}
