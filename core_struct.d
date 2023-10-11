module d_glat.core_struct;

import std.algorithm : canFind, map;
import std.array : split;
import std.range : join;
import std.string : strip;

/*
  A few tool functions for structs and classes

  By Guillaume Lathoud, 2023
  glat@glat.info

  The Boost license applies to this file, as described in ./LICENSE
 */

string set_thisC( in string csv_0 ) pure
{
  return set_structC( "this", csv_0 );
}

string set_structC( in string sname, in string csv_0 ) pure
{
  auto csv = csv_0.strip;

  if (csv[ 0 ] == '{')
    return set_structC( sname, csv[ 1..$-1 ] );

  return csv.split( ',' )
    .map!((a) => a.canFind( '=' )  ?  sname~"."~a~";"  :  sname~"."~(a.strip)~" = "~(a.strip)~";\n")
    .join( "" )
    ;            
}


string struct_initC( in string StructName, in string v_name, in string csv_0 ) pure
// Example of use:
//
// mixin(struct_initC("MyStruct", "s", "{a, b, c:d}"));
{
  return StructName~' '~v_name~" = "~struct_initC( csv_0 )~';';
}


string struct_initC( in string csv_0 ) pure
// "{a, b, c:d}" => code string equivalent to "{a:a, b:b, c:d}"
{
  auto csv = csv_0.strip;

  if (csv[ 0 ] == '{')
    return csv[ 0 ]~struct_initC( csv[ 1..$-1 ] )~csv[ $-1 ];
  
  return csv.split( ',' )
    .map!`a.canFind( ':' )  ?  a  :  a~" : "~a.strip`
    .join( ",\n" )
    ;            
}

