module d_glat.core_tristate;

/*
  A minimal tri-state representation.

  By Guillaume Lathoud, 2025
  glat@glat.info

  The Boost license applies to this file, as described in ./LICENSE
 */

enum Tristate : ubyte { UNKNOWN, FALSE, TRUE };

alias TRI_U = Tristate.UNKNOWN
  ,   TRI_F = Tristate.FALSE
  ,   TRI_T = Tristate.TRUE
  ;

bool is_known( in Tristate tri ) pure @safe @nogc nothrow { return tri != TRI_U; }

bool is_false  ( in Tristate tri ) pure @safe @nogc nothrow { return tri == TRI_F; }
bool is_true   ( in Tristate tri ) pure @safe @nogc nothrow { return tri == TRI_T; }
bool is_unknown( in Tristate tri ) pure @safe @nogc nothrow { return tri == TRI_U; }

// So one can write things like `if (mytristate.is_known)`


Tristate toTristate( in bool b ) pure @safe @nogc nothrow { return b ? TRI_T : TRI_F; }

bool toBool( in Tristate tri ) pure @safe @nogc nothrow
{
  if (tri.is_unknown)
    assert( false, "Tristate has unknown value" );

  return tri.is_true;
}
