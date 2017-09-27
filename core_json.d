/**
 By Guillaume Lathoud
 glat@glat.info
 
 Distributed under the Boost License, see file ./LICENSE
*/

module d_glat_common.core_json;

import std.conv;
import std.exception;
import std.json;
import std.stdio;

double get_double_of_json( in JSONValue jv )
{
  return jv.type == JSON_TYPE.INTEGER  
    ?  cast( double )( jv.integer )

    :  jv.type == JSON_TYPE.UINTEGER
    ?  cast( double )( jv.uinteger )
    
    :  jv.floating
    ;
}

long get_long_of_json( in JSONValue jv )
{
  if (jv.type == JSON_TYPE.INTEGER)
    return cast( long )( jv.integer );

  if (jv.type == JSON_TYPE.UINTEGER)
    return cast( long )( jv.uinteger );

  enforce( jv.type == JSON_TYPE.FLOAT
           , "get_long_of_json: expects an INTEGER, UINTEGER"
           ~ " or FLOAT. Got instead: " ~ jv.type
           );

  // Make sure the value is an integer
  
  auto jvf  = jv.floating;
  long ret  = cast( long )( jvf );
  auto diff = cast( typeof( jvf ))( ret ) - jvf;
  if (diff != 0)
    {
      throw new Exception
        (
         "get_long_of_json: even the FLOAT value must be "
         ~ "an integer. Got instead: " ~ to!string( jvf )
         );
    }
  
  return ret;  
}


JSONValue json_array()
{
  return parseJSON( "[]" );
}

JSONValue json_object()
{
  return parseJSON( "{}" );
}


double json_get_double( in JSONValue jv )
{
  return get_double_of_json( jv );
}

string json_get_string( in JSONValue jv )
{
  assert( jv.type == JSON_TYPE.STRING );
  return jv.str; 
}

bool json_get_bool( in JSONValue jv )
{
  if (jv.type == JSON_TYPE.TRUE)
    return true;

  if (jv.type == JSON_TYPE.FALSE)
    return false;

  assert( false, "bug or wrong data" );
}

