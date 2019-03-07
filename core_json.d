/**
 By Guillaume Lathoud
 glat@glat.info
 
 Distributed under the Boost License, see file ./LICENSE
*/

module d_glat.core_json;

import d_glat.core_string : string_is_num09;
import std.conv : to;
import std.exception : enforce;
import std.json;
import std.typecons : Nullable;
import std.stdio : stderr,writeln;


alias Jsonplace = string[]; // position in the JSON

double get_double_of_json( in JSONValue jv )
{
  // Uncomment this line to debug your data:
  // import std.stdio; writeln("xxx ____ get_double_of_json jv.type, jv:", jv.type, jv );
  
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

long json_get_long( in JSONValue jv )
{
  return get_long_of_json( jv );
}


string json_get_string( in JSONValue jv )
{
  assert( jv.type == JSON_TYPE.STRING
          , "Expected a STRING, got "~to!string(jv.type)
          ~": "~jv.toPrettyString );
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





JSONValue json_get_place( in ref JSONValue j, in string place_str
                          , in JSONValue j_default )
{
  return json_get_place( j, [ place_str ], j_default );
}


JSONValue json_get_place( in ref JSONValue j, in Jsonplace place
                          , in JSONValue j_default )
{
  auto j_n = json_get_place( j, place );
  return j_n.isNull  ?  j_default  :  j_n;
}


Nullable!JSONValue json_get_place( in ref JSONValue j, in string place_str )
{
  return json_get_place( j, [ place_str ] );
}


Nullable!JSONValue json_get_place( in ref JSONValue j, in Jsonplace place )
{
  Nullable!JSONValue j_ret;

  auto plen = place.length;
  if (plen < 1)
    {
      j_ret = j;
    }
  else
    {
      Nullable!JSONValue j_deeper;
  
      if (j.type == JSON_TYPE.OBJECT)
        {
	  if (auto p = place[ 0 ] in j.object)
	    j_deeper = *p;
        }
      else if (j.type == JSON_TYPE.ARRAY)
        {
	  auto sp0 = place[ 0 ];

	  if (string_is_num09( sp0 ))
	    {
	      auto p0 = to!size_t( place[ 0 ] );
	      if (0 <= p0  &&  p0 < j.array.length)
		j_deeper = j.array[ p0 ];
	    }
	}

      if (!j_deeper.isNull)
        {
          j_ret = json_get_place( j_deeper, place[ 1..$ ] );
        }
    }
  
  return j_ret;
}


bool json_is_integer( in ref Nullable!JSONValue j )
{
  pragma( inline, true );
  return !j.isNull  &&  j.type == JSON_TYPE.INTEGER;
}




bool json_is_string( in ref Nullable!JSONValue j )
// Should work well together with `json_get_place`.
{
  pragma( inline, true );
  return !j.isNull  &&  j.type == JSON_TYPE.STRING;
 }

bool json_is_string_equal( T )( in ref T j, in Jsonplace place, in string s )
{
  pragma( inline, true );
  auto maybe_j = json_get_place( j, place );
  return json_is_string_equal( maybe_j , s );
}


bool json_is_string_equal( T )( in ref T j, in string s )
// Should work well together with `json_get_place`.
{
  pragma( inline, true );
  return json_is_string( j )  &&  j.str == s;
}



bool json_is_true( in ref Nullable!JSONValue j )
{
  pragma( inline, true );
  return !j.isNull  &&  j.type == JSON_TYPE.TRUE;
}



void json_set_place
( /*ref xxx commented out because of issue with -O */ JSONValue j, in string place_str, in JSONValue v )
{
  json_set_place( j, [ place_str ], v );
}


void json_set_place
( /*ref xxx commented out because of issue with -O */ JSONValue j, in Jsonplace place, in JSONValue v )
{
  auto plen = place.length;
  assert( 0 < plen );
  
  auto is_leaf = 1 == plen;

  string    place_0 = place[ 0 ];

  JSONValue j_deeper;
  
  if (j.type == JSON_TYPE.OBJECT)
    {
      if (is_leaf)
          j.object[ place_0 ] = v;

      else
          j_deeper = j.object[ place_0 ];
    }
  else if (j.type == JSON_TYPE.ARRAY)
    {
      if (is_leaf)
          j.array[ to!size_t( place_0 ) ] = v;

      else
          j_deeper = j.array[ to!size_t( place_0 ) ];
    }
  else
    {
      stderr.writeln( "json_set_place: structure mismatch bug" );
      stderr.writeln( "v: ", v );
      stderr.writeln( "place: ", place );
      stderr.writeln( "j: ", j.toPrettyString );
      enforce( false, "json_set_place: structure mismatch bug" );
    }
  
  if (!is_leaf)
      json_set_place( j_deeper, place[ 1..$ ], v );
}
