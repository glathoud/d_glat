module d_glat.core_memory;

import core.stdc.stdlib;
import std.array : split;

string create(S)( in string name ) pure nothrow @safe
{
  return `auto `~name~` = allocate!`~S.stringof~`;`;
}

string local(S)( in string name ) pure nothrow @safe
{
  return create!S( name )~` scope(exit) deallocate(`~name~`);`;
}

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

  return `auto `~name~` = allocArray!(`~T~`)( `~count~` ); scope(exit) deallocate(`~name~`);`;
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

S* allocate(S)() @nogc
// To allocate a structure
{
  return cast(S*)( S.sizeof.allocate );
}


T[] allocArray(T)(size_t count) @nogc
{ 
    // Make sure to account for the size of the
    // array element type!
    return cast(T[])allocate(T.sizeof * count); 
}

T[] copyArray(T)( in T[] arr ) @nogc
{
  auto ret = allocArray!T( arr.length );
  ret[] = arr[];
  return ret;
}


// Multiple versions of deallocate for convenience

void deallocate(S)( S* ptr ) @nogc
{
  // If implemented: convenience recursive deallocation
  static if(__traits(compiles, __traits(getMember, S, free_nogc)))
    {
      static if(is(typeof(__traits(getMember, S, free_nogc)) == function))
        {
          S.free_nogc();
        }
    }
  
  free( ptr );
}

void deallocate(void[] mem) @nogc
{ 
    deallocate(mem.ptr);
}
