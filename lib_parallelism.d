module d_glat.lib_parallelism;

public import std.parallelism : TaskPool;
public import std.range : iota;

void parallel_or_single( T )( in bool do_parallel, in T[] todo_arr, void delegate( in T one ) fun )
{
  parallel_or_single!T( totalCPUs, todo_arr, fun );
}

void parallel_or_single( T )( in size_t n_parallel, in T[] todo_arr, void delegate( in T one ) fun )
{
  if (1 < n_parallel)
    {
      scope auto taskpool = new TaskPool( n_parallel - 1 ); // -1 because the main thread will also be available to do work
      
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


string parallel_or_single_code( in string T, in string n_parallel, in string todo_arr, string delegate( in string ) do_one )
// When having strange OutOfMemory issues, consider using `mixin(parallel_or_single_code(...))`
{
    return `if (1 < `~n_parallel~`)
      {
        auto __taskpool__ = new TaskPool( `~n_parallel~` - 1 ); // -1 because the main thread will also be available to do work
        
        immutable __todo_len__ = `~todo_arr~`.length;
        try
          {
            foreach (__i__; __taskpool__.parallel( __todo_len__.iota )) // detour via 'iota' to prevent some rare memory leak issues
              `~do_one( todo_arr~`[ __i__ ]` )~`;
          }
        finally
          {
            __taskpool__.finish; // Try to make sure we exit
          }
      }
    else
      {
        foreach (__one__; `~todo_arr~`)
          `~do_one( `__one__`)~`;
      }
    `;
  }
