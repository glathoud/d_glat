/**

 By Guillaume Lathoud
 glat@glat.info

 Distributed under the Boost License, see file ./LICENSE

*/
module d_glat.lib_interpolate;

T interpolate( T )( in T a, in T b, in T prop ) pure nothrow @safe @nogc
{
  
  return a + prop * (b-a);
}
