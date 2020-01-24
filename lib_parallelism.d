module d_glat.lib_parallelism;

import std.parallelism : TaskPool;
import std.range : iota;

void parallel_or_single( T )( in size_t n_parallel, in T[] todo_arr, void delegate( in T one ) fun )
{
  if (1 < n_parallel)
    {
      auto taskpool = new TaskPool( n_parallel - 1 ); // -1 because the main thread will also be available to do work
      
      immutable todo_len = todo_arr.length;
      try
        {
          foreach (i; taskpool.parallel( todo_len.iota )) // detour via `iota` to prevent some rare memory leak issues
            fun( todo_arr[ i ] );
        }
      finally
        {
          taskpool.finish; // Try to make sure we exit
        }
    }
  else
    {
      foreach (todo; todo_arr)
        fun( todo );
    }
}
