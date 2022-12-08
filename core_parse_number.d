/**
 By Guillaume Lathoud
 glat@glat.info
 
 Distributed under the Boost License, see file ./LICENSE
*/
module d_glat.core_parse_number;

import std.conv : ConvException, to;
import std.format : formattedRead;
import std.regex : ctRegex, replaceAll;
import std.typecons;

alias MaybeDouble = Nullable!double;

bool isParsableDouble( in string s )
{
  auto md = parseDouble( s );
  return !md.isNull;
}

MaybeDouble parseDouble( in string s )
{
  MaybeDouble ret;
  try {
    ret = to!double( s );
  } catch (ConvException e ) {
 }

  return ret;
}



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
  catch (ConvException e)
    {
      
    }
  
  return ret;
}




unittest
{
  import std.stdio;
  import std.math : abs;
  import std.path;

  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  immutable verbose = false;

  assert(isParsableDouble( "1234567.4" ));
  assert(!isParsableDouble( "abcdefgh" ));
  assert(1e-10 > abs( 1234567.4 - parseDouble( "1234567.4" ).get ));
  assert(1e-10 > abs( 1234567.4 - parseGermanDouble( "1.234.567,4" ).get ));
  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
