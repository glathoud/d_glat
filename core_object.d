module d_glat.core_object;

import d_glat.core_assert;

string single_key_of(T)( in T o )
{
  mixin(alwaysAssertStderr(`o.keys.length == 1`));
  return o.keys[ 0 ];
}
