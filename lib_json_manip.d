module d_glat_common.lib_json_manip;

public import d_glat_common.core_json;

import std.algorithm;
import std.array;
import std.conv;
import std.digest.sha;
import std.exception;
import std.format;
import std.json;
import std.stdio;
import std.typecons;

alias Jsonplace = string[]; // position in the JSON

JSONValue json_deep_copy( in ref JSONValue j )
{
  pragma( inline, true );
  return j.toString.parseJSON;
}

JSONValue json_flatten_array( in ref JSONValue j )
{
  assert( j.type == JSON_TYPE.ARRAY );
  auto ret = json_array();
  _json_flatten_push( ret, j );
  return ret;
}

private void _json_flatten_push
( ref JSONValue ret, in ref JSONValue j )
{
  if ( j.type == JSON_TYPE.ARRAY )
    {
      foreach (one ; j.array)
        _json_flatten_push( ret, one );
    }
  else
    {
      ret.array ~= j;
    }
}


string json_get_hash( in ref JSONValue j )
// 40-byte hash of sorted `j` (sorted for unicity).
{
  string sorted_str_json;
  return json_get_hash( j, sorted_str_json );
}

string json_get_hash( in ref JSONValue j
                      , out string sorted_str_json )
// 40-byte hash of sorted `j` (sorted for unicity).
{
  sorted_str_json = json_get_sorted_hash_material( j );
  return format( "%(%02x%)", sha1Of( sorted_str_json ) );
}

JSONValue json_get_place( in ref JSONValue j, in Jsonplace place
                          , in JSONValue j_default )
{
  auto j_n = json_get_place( j, place );
  return j_n.isNull  ?  j_default  :  j_n;
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
	  auto p0 = to!size_t( place[ 0 ] );
	  if (0 <= p0  &&  p0 < j.array.length)
	    j_deeper = j.array[ p0 ];
        }

      if (!j_deeper.isNull)
        {
          j_ret = json_get_place( j_deeper, place[ 1..$ ] );
        }
    }
  
  return j_ret;
}

JSONValue json_get_replaced_many_places_with_placeholder_string
( in ref JSONValue j
  , in Jsonplace[] place_arr
  , in string      placeholder_string
  )
{
  auto ret = json_deep_copy( j );

  // Modifications
  foreach( place ; place_arr )
    json_set_place( ret, place, JSONValue( placeholder_string ) );
    
  return ret;
}

private immutable string JSON_HASH_MATERIAL_SEP = "__.#.__";
string json_get_sorted_hash_material( in ref JSONValue j )
{
  switch (j.type)
    {
    case JSON_TYPE.ARRAY:
      
      return "__.[["
        ~ (j.array.map!( json_get_sorted_hash_material )
           .join( JSON_HASH_MATERIAL_SEP )
           )
        ~ "]].__";

      
    case JSON_TYPE.OBJECT:

      return "__.{{"
        ~ (j.object.keys.sort()
           .map!( k => json_get_sorted_hash_material
                  ( j.object[ k ] )
                  )
           .join( JSON_HASH_MATERIAL_SEP )
           )
        ~ "}}.__";
      
      
    default: return j.toString;
    }
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
( ref JSONValue j, in Jsonplace place, in JSONValue v )
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
          j.array[ to!ulong( place_0 ) ] = v;

      else
          j_deeper = j.array[ to!ulong( place_0 ) ];
    }
  else
    {
      enforce( false, "json_set_place: structure mismatch bug" );
    }
  
  if (!is_leaf)
    json_set_place( j_deeper, place[ 1..$ ], v );
}


void json_walk( alias iter )( in ref JSONValue j )
{
  json_walk_until!( _json_walk_iter_wrap!( iter ) )( j );
}

private bool _json_walk_iter_wrap( alias iter )
  ( in Jsonplace place, in ref JSONValue v )
{
  pragma( inline, true );
  iter( place, v );
  return false;
}

bool json_walk_until( alias test )( in ref JSONValue j )
{
  auto top_place = cast( Jsonplace )( [] );
  
  return _json_walk_until_sub!( test )( top_place, j );
}

private bool _json_walk_until_sub( alias test )
  ( in Jsonplace place, in ref JSONValue j )
{
  bool ret = test( place, j );

  if (!ret)
    {
      if (j.type == JSON_TYPE.OBJECT)
        {
          foreach ( k2,v2; j.object )
            {
              Jsonplace place2 = cast( Jsonplace )( place ~ k2 );
              ret = ret
                || _json_walk_until_sub!( test )( place2, v2 )
                ;
              if (ret)
                break;
            }
        }
      else if (j.type == JSON_TYPE.ARRAY)
        {
          foreach ( k2,v2; j.array )
            {
              Jsonplace place2 = cast( Jsonplace )
                ( place ~ to!string( k2 ) );
              
              ret = ret
                || _json_walk_until_sub!( test )( place2, v2 )
                ;
              if (ret)
                break;
            }          
        }
    }
  
  return ret;
}
