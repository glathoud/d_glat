module d_glat.core_assoc_array;

import std.algorithm : fold;
import std.array : Appender, appender, join;
import std.conv : to;
import std.exception : assumeUnique;
import std.stdio;
import std.traits : isBasicType, isSomeString;

/*
  Tools for associative arrays. Boost License, see file ./LICENSE

  By Guillaume Lathoud, 2018
 */

T* aa_getInit( T, KT )( ref T[KT] aa, in KT key, lazy T def_val = T.init )
// To get/initialize associative arrays having more than one dimension
{
  auto p = key in aa;
  if (p)
    return p;

  return &(aa[ key ] = def_val);
}


size_t[T] aa_ind_of_array(T)( in T[] arr ) pure nothrow @safe 
{ 
  size_t[T] ret;
  foreach (ind, v; arr)
    ret[ v ] = ind;

  return ret;
}

immutable(size_t[T]) aaimm_ind_of_array(T)( in T[] arr )
pure nothrow @trusted
{
  return cast(immutable(size_t[T]))( aa_ind_of_array!T( arr ) );
}



U[T] aa_indmod_of_array(T, U)( U delegate( in size_t ind ) indmodfun, in T[] arr ) 
// Modified index values
{ 
  U[T] ret;
  foreach (ind, v; arr)
    ret[ v ] = indmodfun( ind );

  return ret;
}


U[T] aa_indmod_of_array(T, U)( U delegate( in size_t ind, in T ) indmodfun, in T[] arr )
// Modified index values
{ 
  U[T] ret;
  foreach (ind, v; arr)
    ret[ v ] = indmodfun( ind, v );

  return ret;
}



string aa_pretty( T )( in T aa ) 
{
  auto app = appender!(string[]);
  aa_pretty_inplace( aa, "", app );
  auto ret = app.data.join( "\n" );
  app.clear;
  return ret;
}

void aa_pretty_inplace( T )
  ( in T aa, in string indent_prefix, ref Appender!(string[]) app )
{
  if (indent_prefix.length < 1)
    app.put( indent_prefix~"[" );
  
  immutable ip2 = indent_prefix~"  ";

  foreach (k,v; aa)
    {
      static if (isBasicType!(typeof(v))  ||  isSomeString!(typeof(v)))
        {
          app.put( ip2~to!string(k)~" : "~to!string(v)~", " );
        }
      else
        {
          app.put( ip2~to!string(k)~" : [" );
          
          aa_pretty_inplace( v, ip2, app );
        }
    }
  app.put( indent_prefix~"]" );
}


bool[T] aa_set_intersection(T)( in bool[T][] arr ... ) pure @safe
{
  immutable n = arr.length;
  if (n == 0)
    {
      bool[T] ret; // empty set
      return ret;
    }
  else if (n == 1)
    {
      bool[T] ret;
      foreach (k,v; arr[ 0 ])
        ret[ k ] = v;

      return ret;
    }
  else if (n == 2)
    {
      auto a = arr[ 0 ]
        ,  b = arr[ 1 ]
        ;        
      bool[T] ret;
      foreach (k,v; a)
        {
          if (auto p = k in b)
            if (*p == v)
              ret[ k ] = v;
        }
      return ret;
    }
  else
    {
      auto seed = aa_set_intersection!T( arr[ 0 ] );

      return arr[1..$].fold!(aa_set_intersection!T)( seed );
    }
}


bool[T] aa_set_of_array(T)( in T[] arr ) pure nothrow @safe 
{ 
  bool[T] ret;
  foreach (v; arr)
    ret[ v ] = true;

  return ret;
}

U[T] aa_setmod_of_array(T,U)( U delegate( in T ) modfun, in T[] arr )
// Modified set values
{ 
  U[T] ret;
  foreach (ind,v; arr)
    ret[ v ] = modfun( v );

  return ret;
}

U[T] aa_setmod_of_array(T,U)( U delegate( in size_t, in T ) modfun, in T[] arr )
// Modified set values
{ 
  U[T] ret;
  foreach (ind,v; arr)
    ret[ v ] = modfun( ind, v );

  return ret;
}

U[T] aa_set_union(T,U)( in U[T][] arr ... ) pure @safe
{
  U[T] ret;
  foreach (one; arr)
    {
      foreach(k,v; one)
        ret[ k ] = v;
    }
  return ret;
}


unittest
{
  import std.array;
  import std.path;
  import std.string;

  immutable verbose = false;
  
  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  {
    string[string][string] c_of_b_of_a;

    // Implicit: `!(string[string])`
    auto c_of_b = c_of_b_of_a.aa_getInit( "x" );
    (*c_of_b)[ "y" ] = "z";
    
    assert("x" in c_of_b_of_a);
    assert("z" == c_of_b_of_a["x"]["y"]);
  }

  {
    string[string][string] c_of_b_of_a;
    
    // Explicit: `!(string[string])`
    auto c_of_b = c_of_b_of_a.aa_getInit!(string[string])( "x" );
    (*c_of_b)[ "y" ] = "z";
    
    assert("x" in c_of_b_of_a);
    assert("z" == c_of_b_of_a["x"]["y"]);
  }

  {
    string[string][string] c_of_b_of_a;

    // Implicit: `!(string[string])`
    auto c_of_b = c_of_b_of_a.aa_getInit( "x", /*custom def_val*/[ "y0":"z0" ] );
    (*c_of_b)[ "y" ] = "z";
    
    assert("x" in c_of_b_of_a);
    assert("z" == c_of_b_of_a["x"]["y"]);

    typeof(c_of_b_of_a) expected;
    expected["x"] = ["y":"z", "y0":"z0"];

    typeof(c_of_b_of_a) notExpected;
    notExpected["x"] = ["y":"z", "y0":"z1"];

    assert( c_of_b_of_a ==    expected );
    assert( c_of_b_of_a != notExpected );
  }


  {
    string[string][string] c_of_b_of_a;

    uint call_count = 0;
    string[string] def_val() { call_count++; return [ "y0":"z0" ]; }
    
    // Implicit: `!(string[string])`
    assert( call_count == 0 );
    {
      auto c_of_b = c_of_b_of_a.aa_getInit( "x", /*custom def_val*/def_val );
      assert( call_count == 1 );
      (*c_of_b)[ "y" ] = "z";
      (*c_of_b)[ "y0" ] = "z2";
      
      typeof(c_of_b_of_a) expected;
      expected["x"] = ["y":"z", "y0":"z2"];
      
      assert( c_of_b_of_a ==    expected );
    }

    {
      auto c_of_b = c_of_b_of_a.aa_getInit( "x", /*custom def_val*/def_val );
      assert( call_count == 1 );  // because `def_val` lazy input parameter
      (*c_of_b)[ "y" ] = "q";
      (*c_of_b)[ "y0" ] = "q2";
      
      typeof(c_of_b_of_a) expected;
      expected["x"] = ["y":"q", "y0":"q2"];
      
      assert( c_of_b_of_a ==    expected );
    }

  }


  {
    string[] input = [ "AAAA", "BBBB", "CCCC", "DDDD" ];
    auto output = aa_ind_of_array( input );

    size_t[string] expected_output = ["AAAA": 0, "BBBB": 1, "CCCC": 2, "DDDD": 3];
    
    if (verbose)
      {
        writeln( "input ", input );
        writeln( "output ", output );
      }
    
    assert( output == expected_output );
  }

  {
    string[] input = [ "AAAA", "BBBB", "CCCC", "DDDD" ];
    auto output = aaimm_ind_of_array( input );

    size_t[string] expected_output_0 = ["AAAA": 0, "BBBB": 1, "CCCC": 2, "DDDD": 3];
    auto expected_output = cast( immutable( size_t[string] ) )( expected_output_0 );
        
    if (verbose)
      {
        writeln( "input ", input );
        writeln( "output ", output );
      }
    
    assert( output == expected_output );
  }


  {
    auto a = [ "p":true, "q":true, "r":true ];
    auto b = [           "q":true, "r":true, "s": true ];
    auto c = [                     "r":true, "s": true, "t": true ];

    assert( aa_set_union( a, b ) == aa_set_of_array( "pqrs".split("").array ) );
    assert( aa_set_union( a, c ) == aa_set_of_array( "pqrst".split("").array ) );
    assert( aa_set_union( b, c ) == aa_set_of_array( "qrst".split("").array ) );
    assert( aa_set_union( a, b, c ) == aa_set_of_array( "pqrst".split("").array ) );
    
    assert( aa_set_intersection( a, b ) == aa_set_of_array( "qr".split("").array ) );
    assert( aa_set_intersection( a, c ) == aa_set_of_array( "r".split("").array ) );
    assert( aa_set_intersection( b, c ) == aa_set_of_array( "rs".split("").array ) );
    assert( aa_set_intersection( a, b, c ) == aa_set_of_array( "r".split("").array ) );
  }
  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
