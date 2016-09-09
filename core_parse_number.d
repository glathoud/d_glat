module d_common.core_parse_number;

import std.format;
import std.regex;
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
