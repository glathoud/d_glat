module d_glat.core_assert;

/*
  Assert-like tools.
  
  By Guillaume Lathoud, 2022
  glat@glat.info
  
  Boost Software License version 1.0, see ./LICENSE
*/

public import std.stdio : stderr;

import std.array : replace;

string alwaysAssertStderr(string testcode)() // template!`shortcut`
{
  return alwaysAssertStderr( testcode );
}

string alwaysAssertStderr( in string testcode, in string msgcode_0="" )
// to use with `mixin`. *always* asserts (in release mode as well)
// e.g:  mixin(alwaysAssertStderr(`a<b`, `"a<b not verified for a:"~to!string(a)~" and b:"~to!string(b)`))
{
  immutable msgcode = 0 < msgcode_0.length  ?  msgcode_0  :  '"'~testcode.replace("\"", "\\\"")~'"';

  // Impl. note: we used to have `assert( false, ... )` but that led
  // to issue, not always having a stacktrace (esp. when catching
  // and rethrowing Throwable).
  //
  // Hence we switched to a `throw new Exception` implementation.
  // Now the catching/rethrowing works. 
  return `if (!(`~testcode~`)) { immutable __outmsg = `~msgcode~`; import std.path : baseName; stderr.writeln( baseName(__FILE__), "@", __LINE__, ": ", __outmsg ); stderr.flush; throw new Exception( "alwaysAssertStderr: assert not verified, output message: "~__outmsg ); }`;
}


void assertWrap( bool test, string delegate() pure @safe getS = () { return ""; } )
  pure nothrow @safe
/*
  `nothrow` wrapper around `assert`. Useful when the error message
  is built using things that can throw, e.g. std.conv.to:

  assertWrap( a == b, () => "that did not quite make it for a: "
  ~to!string(a)~" and b: "~to!string(b));  
 */
{
  string s;
  try
    {
      s = getS();
    }
  catch (Exception e)
    {
      assert( false, "assertWrap: bug while calling s()" );
    }

  assert( test, s );
}
