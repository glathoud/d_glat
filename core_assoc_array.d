module d_glat_common.core_assoc_array;

import std.stdio;

/*
  Tools for associative arrays. Boost License, see file ./LICENSE

  By Guillaume Lathoud, 2018
 */

// To get/initialize associative arrays having more than one dimension

T* aa_getInit( T )( ref T[string] aa, in string key, lazy T def_val = T.init )
{
  auto p = key in aa;
  if (p)
    return p;

  return &(aa[ key ] = def_val);
}

unittest
{
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

    string[string] def_val() { return [ "y0":"z0" ]; }
    
    // Implicit: `!(string[string])`
    auto c_of_b = c_of_b_of_a.aa_getInit( "x", /*custom def_val*/def_val );
    (*c_of_b)[ "y" ] = "z";
    (*c_of_b)[ "y0" ] = "z2";

    typeof(c_of_b_of_a) expected;
    expected["x"] = ["y":"z", "y0":"z2"];

    assert( c_of_b_of_a ==    expected );
  }
}
