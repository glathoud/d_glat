module d_glat_common.lib_modified_slice;

import std.stdio;

class ModifiedSlice(T)
{
  immutable size_t nmodif_max;
  enum NMODIF_MAX_DFLT = 100;

  alias sli this;
  
  this( in ModifiedSlice!T in_modsli, in size_t nmodif_max = NMODIF_MAX_DFLT )
    {
      /*
        No need for `.dup` here => performance gain.  Safety
        guaranteed by the `.dup` in `_flatten_modif_if_needed`.
      */
      this.sli        = cast( T[] )( in_modsli.sli );
      
      this.nmodif_max = nmodif_max;
    }
  
  this( in T[] in_sli, in size_t nmodif_max = NMODIF_MAX_DFLT )
    {
      // In this particular case the `.dup` is needed for safety.
      this.sli = in_sli.dup;
      
      this.nmodif_max = nmodif_max;
    }
  
  this( in size_t nmodif_max = NMODIF_MAX_DFLT )
    {
      this.nmodif_max = nmodif_max;
    }

  bool opEquals( in ModifiedSlice!T other ) const
  {
    if (this.length != other.length)
      return false;
                     
    foreach (k; 0..other.length)
      if (this[ k ] != other[ k ])
        return false;

    return true;
  }

  bool opEquals( in T[] other ) const
  {
    if (this.length != other.length)
      return false;
                     
    foreach (k, v; other)
      if (this[ k ] != v)
        return false;

    return true;
  }

  
  T opIndex( size_t i ) const
  {
    if (auto p = i in modif)
      return *p;

    return sli[ i ];
  }

  
  T opIndexAssign( T value, size_t i )
  {
    modif[ i ] = value;

    _flatten_modif_if_needed();
    
    return value;
  }

  auto opUnary(string s)() if (s == "~")
    {
      assert( false
              , "~= is not supported: a fixed length is assumed."
              );
    }
  
 private:
  T[]       sli;
  T[size_t] modif;  

  
  void _flatten_modif_if_needed()
  {
    if (modif.length > nmodif_max)
      {
        sli = sli.dup;
        foreach (k, v; modif)
          sli[ k ] = v;
        
        modif.clear;
      }
  }

}

unittest
{
  import std.stdio;
  import std.path;

  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  {
    int[] a = [ 1, 3, 5, 7, 9, 11, 123, 456 ];
    auto  b = a.idup;
    auto  c = new ModifiedSlice!int( b, 3 );
    auto  d = new ModifiedSlice!int( c, 3 );
    
    void do_one_and_check( in size_t i, in int v )
    {
      bool is_change = a[ i ] != v;
      assert( is_change );

      a[ i ] = v;

      bool is_equal_to_init = a == b;
      
      assert( a != c );
      assert( a != d );
      
      c[ i ] = v;

      assert( is_equal_to_init  ?  a == b  :  a != b );
      assert( a == c );
      assert( is_equal_to_init  ?  c == b  :  c != b );
      assert( a != d );

      d[ i ] = v;

      assert( is_equal_to_init  ?  a == b  :  a != b );
      assert( a == c );
      assert( is_equal_to_init  ?  c == b  :  c != b );
      assert( a == d );
      assert( is_equal_to_init  ?  d == b  :  d != b );
    }

    do_one_and_check( 2, 10 );

    do_one_and_check( 2, 5 );

    do_one_and_check( 3, 15 );

    do_one_and_check( 5, 151 );

    do_one_and_check( 0, -1512 );

    // Check safety when "modifying" the original T[] slice
    // directly.
    
    {
      auto e = new ModifiedSlice!int( a );

      assert( a != b );
      assert( a == e );

      a[ 1 ] = 12345;

      assert( a != b );
      assert( a != e );
    }
    
  }
  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
