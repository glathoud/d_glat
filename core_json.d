/**
 By Guillaume Lathoud
 glat@glat.info
 
 Distributed under the Boost License, see file ./LICENSE
*/

module d_glat_common.core_json;

import std.json;
import std.stdio;

double get_double_of_json( in JSONValue jv )
{
  // Uncomment this line to debug your data:
  // writeln("xxx ____ get_double_of_json jv.type, jv:", jv.type, jv );
  
  return jv.type == JSON_TYPE.INTEGER  
    ?  cast( double )( jv.integer )
    :  jv.floating
    ;
}
