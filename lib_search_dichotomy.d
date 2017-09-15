module d_glat_common.lib_search_dichotomy;

/**
 Search sorted values accessible through `fun( ulong ) -> double`
 between indices `a0` and `b0` included.
 
 Returns `true` if found, `false` otherwise.

 Guillaume Lathoud
 glat@glat.info

 Distributed under the Boost License, see file ./LICENSE

**/

bool search_dichotomy( alias fun )
  ( in double v, in ulong a0, in ulong b0
    , out ulong ind0, out ulong ind1, out double prop )
{
  ulong a = a0;
  ulong b = b0;

  if (a > b  ||  v < fun( a )  ||  fun( b ) < v)
    return false;
  
  long bma;
  while ((bma = b - a) >= 0)
    {
      double av = fun( a );
      double bv = fun( b );
      
      if (av == v)
        {
          // Found exactly at one point
          ind0 = ind1 = a;
          prop = 0;
          return true;
        }
      else if (bv == v)
        {
          // Found exactly at one point
          ind0 = ind1 = b;
          prop = 0;
          return true;
        }
      else if (!(av <= v  &&  v <= bv))
        {
          // Not found
          break;
        }
      else if (1 == bma)
        {
          // Found between two points
          ind0 = a;
          ind1 = b;
          prop = (v - av) / (bv - av);
          return true;
        }
      
      // Not found yet

      ulong  m  = (a + b) >> 1;
      double mv = fun( m );

      if (a < m  &&  mv < v)
        {
          a = m;
          continue;
        }

      if (m < b  &&  v < mv)
        {
          b = m;
          continue;
        }
      
      break;
    }

  return false;
}
