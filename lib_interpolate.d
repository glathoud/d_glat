module d_common.lib_interpolate;

double interpolate( in double a, in double b, in double prop )
{
  pragma( inline, true );
  return a + prop * (b-a);
}
