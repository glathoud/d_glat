/**
 By Guillaume Lathoud
 glat@glat.info
 
 Distributed under the Boost License, see file ./LICENSE
*/
module d_glat.core_parse_number;

import std.format : formattedRead;
import std.regex : ctRegex, replaceAll;
import std.typecons;

alias MaybeDouble = Nullable!double;

MaybeDouble parseGermanDouble( in string s )
{
  auto commaRx = ctRegex!( `\,` );
  auto dotRx   = ctRegex!( `\.` );

  auto s2 = s.replaceAll( dotRx, "" ).replaceAll( commaRx, "." );
  
  double x;
  MaybeDouble ret;

  try {
    auto n_success = formattedRead( s2, "%f", &x );
    if (0 < n_success)
      ret = x;
  }
  catch (std.conv.ConvException e)
    {
      
    }
  
  return ret;
}
