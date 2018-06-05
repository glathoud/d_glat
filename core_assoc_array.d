module d_glat_common.core_assoc_array;

import std.stdio;

/*
  Tools for associative arrays. Boost License, see file ./LICENSE

  By Guillaume Lathoud, 2018
 */

// To get/initialize associative arrays having more than one dimension

T* getInit2( T )( ref T[string] aa, in string key )
{
  auto p = key in aa;
  if (p)
    return p;

  return &(aa[ key ] = T.init );
}

unittest
{
  string[string][string] c_of_b_of_a;

   auto c_of_b = c_of_b_of_a.getInit2!(string[string])( "x" );
   (*c_of_b)[ "y" ] = "z";

   assert("x" in c_of_b_of_a);
   assert("z" == c_of_b_of_a["x"]["y"]);
}
