module d_glat.lib_bitmanip;

T reverse_bit(T)( in T x, in size_t nbit )
{
  T y = x & ( ~ ( ( 1 << nbit ) - 1 ) );
  for ( T a = 0; a < nbit; a++ ) {
    if ( x & ( 1 << ( nbit - 1 - a ) ) ) {
      y |= ( 1 << a );  // set bit to 1
    }
  }
  return y;
}
