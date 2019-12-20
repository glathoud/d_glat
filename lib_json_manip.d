module d_glat.lib_json_manip;

/* Utilities to manipulate `JSONValue`s

By Guillaume Lathoud - glat@glat.info

Boost license, as described in the file ./LICENSE
*/

public import d_glat.core_json;

import d_glat.core_sexpr;
import d_glat.lib_json_manip;
import std.algorithm;
import std.array;
import std.conv;
import std.digest.sha;
import std.exception;
import std.format : format;
import std.json;
import std.stdio;
import std.typecons;

immutable string JSON_P_CALC = "(calc)";

JSONValue json_ascii_inplace( ref JSONValue jv )
/*
  Conveniently replace non-ASCII chars with "~".

Return the same instance `jv`, modified.

How: Modify in-place all strings in `jv` (recursive walk) to ensure
all chars are <= 126, thus ensuring ASCII. Useful when packing
unreliable strings, that may lead to a subsequent UTF-8 decoding error
when calling `jv.toString`.
 */
{
  json_walk!( json_ascii_inplace_iter )( jv );

  return jv;
}

private void json_ascii_inplace_iter( in Jsonplace place, ref JSONValue jv2 )
{
  immutable ubyte some_max = 126; 
  
  if (JSON_TYPE.STRING == jv2.type)
    {
      ubyte[] arr  = cast( ubyte[] )( jv2.str );
      ubyte[] arr2 = arr.map!( x => min( x, some_max ) ).array;
      jv2.str = cast( string )( arr2 );
    }
}

JSONValue json_deep_copy( in ref JSONValue j )
{
  
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
      foreach (ref one ; j.array)
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


JSONValue json_get_replaced_many_places_with_placeholder_string
( in ref JSONValue j
  , in Jsonplace[] place_arr
  , in string      placeholder_string
  )
{
  auto ret = json_deep_copy( j );

  // Modifications
  foreach( ref place ; place_arr )
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


bool json_equals( in JSONValue j0, in JSONValue j1 )
{
  
  return json_get_sorted_hash_material( j0 ) == json_get_sorted_hash_material( j1 );
}









JSONValue json_solve_calc( in ref JSONValue o )
{
  enforce( o.type == JSON_TYPE.OBJECT );

  auto ret = json_deep_copy( o );

  bool modified = true;
  while (modified)
    {
      modified = false;
      ret.json_walk_until!( (place, v) {

          if (place.length > 0  &&  place[ $-1 ] == JSON_P_CALC)
            {
              auto new_v = json_solve_calc_one( ret, v );
              json_set_place( ret, place[ 0..($-1)], new_v );
              modified = true;
            }

          return modified;
        });
    }
  
  return ret;
}

unittest
{
  import std.stdio;
  
  writeln( "unittest starts: "~__FILE__~": json_solve_calc" );

  auto o0 = parseJSON( `{"a":123,"b":{"c":{"(calc)":"(- (* a 2) 7)"}}}` );

  auto o1 = json_solve_calc( o0 );

  assert( o0.toString != o1.toString );
  assert( o1.toString == `{"a":123,"b":{"c":239}}`);
  
  writeln( "unittest passed: "~__FILE__~": json_solve_calc" );

}


JSONValue json_solve_calc_one( in ref JSONValue o
                               , in ref JSONValue v )
{
  enforce( o.type == JSON_TYPE.OBJECT ); 
  enforce( v.type == JSON_TYPE.STRING );
  
  auto e = parse_sexpr( v.str );

  double v_dbl = json_solve_calc_one( o, e );

  JSONValue new_v = JSONValue( v_dbl );
  
  enforce( new_v.toString != v.toString
           , "Forbidden: json_solve_calc_one gave the same output:" ~ new_v.toString~"    from v:"~v.toString
           );

  return new_v;
}

double json_solve_calc_one( in ref JSONValue o
                            , in ref SExpr e
                            )
{
  enforce( o.type == JSON_TYPE.OBJECT );

  enforce( !e.isEmpty );

  if (e.isAtom)
    {
      immutable string s = e.toString;
      if (auto p = s in o.object)
        {
          return json_get_double( *p );
        }
      else
        {
          try
            {
              return to!double( s );
            }
          catch (std.conv.ConvException e)
            {
              stderr.writeln( "json_solve_calc_one: failed to convert to double: \""~s
                              ~"\". Or maybe could not find a value for \""~s~"\" at the top level of o: "
                              ~o.toString
                              );
              throw e;
            }
        }
    }

  assert( e.isList );

  const li = cast( SList )( e );
  
  double[] operands =
    li.rest.map!( x => json_solve_calc_one( o, x ) ).array;

  enforce( 1 < operands.length, li.toString );

  const op = li.first.toString;
  switch (op)
    {
      case "+": return operands.reduce!"a+b";
      case "-": return operands.reduce!"a-b";
      case "*": return operands.reduce!"a*b";
      case "/": return operands.reduce!"a/b";
        
    default:
      throw new Exception
        ( "Unknown operator "~op~" from "~li.toString );
    }
}














void json_walkreadonly( alias iter )( in ref JSONValue j )
{
  json_walkreadonly_until!( _json_walkreadonly_iter_wrap!( iter ) )( j );
}

private bool _json_walkreadonly_iter_wrap( alias iter )
  ( in Jsonplace place, in ref JSONValue v )
{
  iter( place, v );
  return false;
}

bool json_walkreadonly_until( alias test )( in ref JSONValue j )
{
  auto top_place = cast( Jsonplace )( [] );
  
  return _json_walkreadonly_until_sub!( test )( top_place, j );
}

private bool _json_walkreadonly_until_sub( alias test )
  ( in Jsonplace place, in ref JSONValue j )
{
  bool ret = test( place, j );

  if (!ret)
    {
      if (j.type == JSON_TYPE.OBJECT)
        {
          foreach ( k2, ref v2; j.object )
            {
              Jsonplace place2 = cast( Jsonplace )( place ~ k2 );
              ret = ret
                || _json_walkreadonly_until_sub!( test )( place2, v2 )
                ;
              if (ret)
                break;
            }
        }
      else if (j.type == JSON_TYPE.ARRAY)
        {
          foreach ( k2, ref v2; j.array )
            {
              Jsonplace place2 = cast( Jsonplace )
                ( place ~ to!string( k2 ) );
              
              ret = ret
                || _json_walkreadonly_until_sub!( test )( place2, v2 )
                ;
              if (ret)
                break;
            }          
        }
    }
  
  return ret;
}








void json_walk( alias iter )( ref JSONValue j )
{
  json_walk_until!( _json_walk_iter_wrap!( iter ) )( j );
}

private bool _json_walk_iter_wrap( alias iter )
  ( in Jsonplace place, ref JSONValue v )
{
  iter( place, v );
  return false;
}

bool json_walk_until( alias test )( ref JSONValue j )
{
  auto top_place = cast( Jsonplace )( [] );
  
  return _json_walk_until_sub!( test )( top_place, j );
}

private bool _json_walk_until_sub( alias test )
  ( in Jsonplace place, ref JSONValue j )
{
  bool ret = test( place, j );

  if (!ret)
    {
      if (j.type == JSON_TYPE.OBJECT)
        {
          foreach ( k2, ref v2; j.object )
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
          foreach ( k2, ref v2; j.array )
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

string json_white_out_comments( in string extended_json_string )
/*
  Very simple comment removal, that does not care about syntax, double
quotes etc. Simplistic but enough for most practical purposes.
*/
  {
    auto modifiable = cast( char[] )( extended_json_string );
    json_white_out_comments_inplace( modifiable );
    return modifiable.idup;
  }

void json_white_out_comments_inplace( char[] ca ) pure nothrow @safe @nogc
{
  immutable N   = ca.length
    ,       Nm1 = N - 1
    ;
  for (size_t i = 0; i < Nm1; ++i)
    {
      auto ca_i = ca[ i ];
      if (ca_i == '/')
        {
          auto ca_ip1 = ca[ i+1 ];

          if (ca_ip1 == '/')
            {
              while (i < N  &&  !(ca[ i ] == '\r'  ||  ca[ i ] == '\n'))
                ca[ i++ ] = ' ';
            }
          else if (ca_ip1 == '*')
            {
              while (i < N  &&  !(ca[ i ] == '*'  &&  ca[ i+1 ] == '/'))
                ca[ i++ ] = ' ';

              ca[ i ]   = ' ';
              ca[ i+1 ] = ' ';
            }
        }
    }
}
