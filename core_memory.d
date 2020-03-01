module d_glat.core_memory;

import core.stdc.stdlib;
import std.array : split;

string localloc( in string name_T_count ) pure @safe
/* Shortcut. Returns code string for mixin. Example:

   mixin(localloc(`myarray,double,N`));

   is equivalent to:

   auto myarray = allocArray!double( N );
   scope(exit) deallocate( myarray );
 */
{
  auto q = name_T_count.split( ',' );
  if (q.length != 3)
    assert( false, "localloc: name_T_count must contain 2 commas." );

  immutable name  = q[ 0 ];
  immutable    T  = q[ 1 ];
  immutable count = q[ 2 ];

  return `auto `~name~` = allocArray!(`~T~`)( `~count~` );
  scope(exit) deallocate(`~name~`);
  `;
}

  

// https://dlang.org/blog/2017/09/25/go-your-own-way-part-two-the-heap/

// Allocate a block of untyped bytes that can be managed
// as a slice.
void[] allocate(size_t size) @nogc
{
    // malloc(0) is implementation defined (might return null 
    // or an address), but is almost certainly not what we want.
    assert(size != 0);

    void* ptr = malloc(size);
    if(!ptr) assert(0, "Out of memory!");
    
    // Return a slice of the pointer so that the address is coupled
    // with the size of the memory block.
    return ptr[0 .. size];
}

T[] allocArray(T)(size_t count) @nogc
{ 
    // Make sure to account for the size of the
    // array element type!
    return cast(T[])allocate(T.sizeof * count); 
}

// Two versions of deallocate for convenience
void deallocate(void* ptr) @nogc
{	
    // free handles null pointers fine.
    free(ptr);
}

void deallocate(void[] mem) @nogc
{ 
    deallocate(mem.ptr); 
}

