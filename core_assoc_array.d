module d_glat.core_assoc_array;

import std.stdio;

/*
  Tools for associative arrays. Boost License, see file ./LICENSE

  By Guillaume Lathoud, 2018
 */

// To get/initialize associative arrays having more than one dimension

T* aa_getInit( T, KT )( ref T[KT] aa, in KT key, lazy T def_val = T.init )
{
  auto p = key in aa;
  if (p)
    return p;

  return &(aa[ key ] = def_val);
}

unittest
{
  import std.path;

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

  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
