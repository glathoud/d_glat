module d_glat.lib_math_fixedperm;

/*
  Memory-less, fixed, random-looking permutation of any number of
  indices.

  Implementation: builds upon a mathematical result for memory-less
  permutations of power-of-two arrays of elements:
  https://glat.info/cipo/
  
  Example of usage: 
  
  -- Context: running many simulations across combinations of
  parameter values, distributed across `n_processes`.
  
  -- Issue: say the structure of the simulation and parameters leads
  to having 1 iteration running much slower, every 4 iterations. If
  `n_processes%4==0`, then some of the processes will finish much
  later than the others.
  
  -- Solution 1: use a big-enough, prime number of processes. A bit
  constraining.
  
  -- Solution 2: shuffle the order of the simulations using
     FixedPerm(n): `foreach (i; FixedPerm(n))`
     
  By Guillaume Lathoud, 2022
  glat@glat.info

  The Boost license applies to this file, as described in ./LICENSE
*/

alias FixedPerm = FixedPermT!size_t;

struct FixedPermT( T )
{
  immutable T n;

  this(T2)( in T2 n_0 )
  {
    n = cast(T)( n_0 );

    immutable prev_pow_2 = (){

      T a = 1, b = n;

      while (b)
        {
          a <<= 1;
          b >>= 1;
        }
      
      return a;

    }();

    next_pow_2 = (n == prev_pow_2)  ?  n  :  (prev_pow_2 << 1);

    step = 1;
  }
  

  size_t length() const pure @safe @nogc { return cast(size_t)( n ); }
  
  bool empty() const pure @safe @nogc { return i_in >= n; }

  T front() const pure @safe @nogc { return i_out; }

  void popFront() {
    do {
      i_out = (i_out + step) % next_pow_2;
      step  = (1 + step) % next_pow_2;
    } while (i_out >= n);
    ++i_in;
  }

  private:

  immutable T next_pow_2;
  T i_in = 0, step = 1, i_out = 0;

}

unittest
{
  import std.stdio;
  import std.path;

  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  immutable verbose = false ;

  import std.algorithm;
  import std.range;

  void test_one( in size_t N )
  {
    if (verbose)
      {
        writeln;
        writeln( "begin test_one: ", N );
      }
    
    {
      auto rfp = FixedPerm( N );

      assert(rfp.empty == (N == 0));
    
      foreach (i; rfp) {}
      
      if (verbose)
        {
          writeln("loop done, rfp.i_in:  ", rfp.i_in);
          writeln("loop done, rfp.i_out: ", rfp.i_out);
        }
    }

    {
      auto rfp = FixedPerm( N );
      
      const arr  = rfp.array;
      const arr2 = arr.dup.sort.array;
      
      if (verbose)
        {
          writeln( "arr: ", arr );
          writeln( "arr sorted: ", arr2 );
        }

      assert( (arr == arr2) == (N < 4) );
      assert( arr2 == iota( N ).array );

      // Can repeat usage (because: `struct`)
      {
        auto arr3 = rfp.array;
        assert( arr3.dup.sort.array == arr2 );
        arr3 ~= [12345];
        assert( arr  != arr3 );
        assert( arr2 != arr3 );
      }
    }

    if (verbose)
      {
        writeln( "end test_one: ", N );
      }
  }

  foreach (N; iota( 50 ).array ~ [1235] ~ iota( 4093, 4100 ).array)
    test_one( N );
  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
