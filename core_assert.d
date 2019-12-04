module d_glat.core_assert;

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
