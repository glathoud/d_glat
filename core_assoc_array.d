module d_glat.core_assoc_array;

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
  pragma( inline, true );

  size_t[T] ret;
  foreach (ind, v; arr)
    ret[ v ] = ind;

  return ret;
}

immutable(size_t[T]) aaimm_ind_of_array(T)( in T[] arr )
pure nothrow @trusted
{
  pragma( inline, true );
  return cast(immutable(size_t[T]))( aa_ind_of_array!T( arr ) );
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


unittest
{
  import std.path;

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

  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
