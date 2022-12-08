module d_glat.lib_assoc_array_big_sortable;

import d_glat.core_assert;
import d_glat.lib_search_bisection;
import std.algorithm : merge, multiwayMerge, remove, sort;
import std.array : array, insertInPlace;
import std.stdio;
import std.traits : isBoolean;

/**
   Memory-efficient associative array for huge numbers of elements
   (millions).  

   Typical usage: create such an associative array in big chunks
   (*not* one (k,v) at a time), then later use it mostly read-only.
   
   
   Requisite: the elements'keys should be sortable.

   Optionally you can pass a `V merge_two(V a,V b)` function/lambda to
   merge values that have the same key (instead of forgetting old
   values).
   
   By Guillaume Lathoud, 2022 and later
   glat@glat.info

   The Boost License applies, see file ./LICENSE
 */

struct AABSElt(V,K) {
  V v;
  K k;
}

struct AssocArrayBigSortable(V,K,alias merge_two_v = false) // K should be a natively sortable type (works with `<`, `>`) ; Optional `V merge_two(V a,V b)` to merge old and new values 
{
  alias Elt = AABSElt!(V,K);

  // ---------- Additional API to get/set blocks of data (many at once)

  const(Elt[]) get_sorted_elt_arr() const pure { return _srtd_arr; }

  typeof(this) merge_elt_arr_inplace( in Elt[] elt_arr )
  {
    static if (is( typeof(merge_two_v) == bool))
      {
        // Generic use case (no merge): overwrite old values, like a
        // standard associative array.
        
        if (0 < _srtd_arr.length)
          {
            scope AssocArrayBigSortable!(V,K,merge_two_v) tmp;
            tmp.merge_elt_arr_inplace( elt_arr );
            
            {
              size_t new_length = _srtd_arr.length;
              for (size_t i = _srtd_arr.length; i--;)
                {
                  if (tmp.has( _srtd_arr[ i ]))
                    {
                      _srtd_arr.remove( i );
                      --new_length;
                    }
                }
              _srtd_arr.length = new_length;
            }
          }
        
        _srtd_arr.assumeSafeAppend() ~= elt_arr;
        _srtd_arr.sort!((a,b) => a.k < b.k);
      }
    else
      {
        // Merge use case: merge old and new values.

        _srtd_arr.assumeSafeAppend() ~= elt_arr;
        _srtd_arr.sort!((a,b) => a.k < b.k);
    
        if (1 < _srtd_arr.length)
          {
            scope auto next = _srtd_arr[ $-1 ];
            for (size_t i = _srtd_arr.length-1; i--;)
              {
                scope auto elt = _srtd_arr[ i ];
                if (elt.k == next.k)
                  {
                    scope Elt new_elt = {v:merge_two_v( elt.v, next.v ), k:elt.k};
                    _srtd_arr[ i ] = new_elt;
                    _srtd_arr      = _srtd_arr.remove( i+1 );
                  }
                next = _srtd_arr[ i ];
              }
          }
      }
    
    return this;
  }
  
  // ---------- Associative array-like interface (parts we need)
  
  void clear() nothrow @safe
  {
    _srtd_arr.length = 0;
  }
  
  bool has( in K k ) const @trusted
  {
    auto ind = search_bisection_exact( (i)=>_srtd_arr[i].k, k, 0, _srtd_arr.length-1 );
    return 0 <= ind;
  }

  alias length = opDollar;

  int opApply(int delegate(ref K, ref const V) dg) const
  {
    assert( false, "xxx todo");
  }

  int opApplyReverse(int delegate(ref K, ref const V) dg) const
  {
    assert( false, "xxx todo");    
  }
  
  size_t opDollar() const pure @safe @nogc nothrow { return _srtd_arr.length; }

  V* opBinaryRight(string op)( in K k )
  {
    static if (op == "in")
      {
        auto ind = search_bisection_exact( (i)=>_srtd_arr[i].k, k, 0, _srtd_arr.length-1 );

        return 0 <= ind  ?  &(_srtd_arr[ ind ].v)  :  null;
      }
    else static assert( false, mixin(_dhere)~"Operator not implemented: "~op );
  }

  V opIndex( in K k ) const @trusted
  {
    auto ind = search_bisection_exact( (i)=>_srtd_arr[i].k, k, 0, _srtd_arr.length-1 );
    debug mixin(alwaysAssertStderr!`0 <= ind`);
    return _srtd_arr[ ind ].v;
  }

  /*
    Note: we are NOT defining opIndexAssign( V v, in K k ) to make it
    clear that one-by-one insertion would be quite costly.  Thus
    prefer bulk update through the `merge_elt_arr_inplace` method.
  */
  
 private: // ----------------------------------------

  Elt[] _srtd_arr;
}
