module d_common.core_json;

import std.json;

double get_double_of_json( in JSONValue jv )
{
  return jv.type == JSON_TYPE.INTEGER  
    ?  cast( double )( jv.integer )
    :  jv.floating
    ;
}
