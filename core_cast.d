module d_glat.core_cast;

/*
  Shortcuts to cast.

  By Guillaume Lathoud
  glat@glat.info

  Distributed under the Boost License, see file ./LICENSE
 */

string _cimmut( string varname )() pure nothrow @safe
/* Example of use:
   
   auto imm_q = mixin(_cimmut!`q`);

   equivalent to:

   auto imm_q = cast(immutable(typeof(q)))( q );
 */
{
  return `(cast(immutable(typeof(`~varname~`)))( `~varname~` ))`;
}
