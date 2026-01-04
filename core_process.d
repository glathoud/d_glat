module d_glat.core_process;

import d_glat.core_assert;
import std.array;
import std.process;

string executeAlwaysAssert( in string[] cmd )
{
  scope auto tmp = execute( cmd );
  mixin(alwaysAssertStderr(`0 == tmp.status`, `tmp.output`));
  return tmp.output;
}

string executeShellAlwaysAssert( in string cmd )
{
  scope auto tmp = executeShell( cmd );
  mixin(alwaysAssertStderr(`0 == tmp.status`, `tmp.output`));
  return tmp.output;
}


string executeAssert( in string[] cmd )
{
  scope auto tmp = executeShell( cmd.join( ' ' ) );
  assert( tmp.status == 0, tmp.output );
  return tmp.output;
}
