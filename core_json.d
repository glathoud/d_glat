/**
 By Guillaume Lathoud
 glat@glat.info
 
 Distributed under the Boost License, see file ./LICENSE
*/

module d_glat.core_json;

import d_glat.core_assert;
import d_glat.core_string : string_is_num09;
import std.algorithm : all, any, each, map;
import std.array : appender, array, split;
import std.conv : to;
import std.exception : enforce;
import std.json;
import std.range : join, zip;
import std.typecons : Nullable;
import std.stdio : stderr,writeln;
import std.traits : hasMember;

alias Jsonplace = string[]; // position in the JSON


private bool   _j_dbl_special_init_done;
private string _j_dbl_special_s_infinity;
private string _j_dbl_special_s_negInfinity;
private string _j_dbl_special_s_nan;

private void _ensure_j_dbl_special()
{
  if (!_j_dbl_special_init_done)
    {
      _j_dbl_special_init_done = true;

      scope auto j = parseJSON("{}");
      j.object["c"] = JSONValue(double.infinity);
      j.object["d"] = JSONValue(-double.infinity);
      j.object["e"] = JSONValue(double.nan);
      
      scope auto js = j.toString( JSONOptions.specialFloatLiterals );

      scope auto j2 = parseJSON( js );

      _j_dbl_special_s_infinity    = j2[ "c" ].str;  // Usually  "Infinite"
      _j_dbl_special_s_negInfinity = j2[ "d" ].str;  // Usually  "-Infinite"
      _j_dbl_special_s_nan         = j2[ "e" ].str;  // Usually  "NaN"
    }
}




double get_double_of_json( bool accept_null = false )( in JSONValue jv )
{
  // Uncomment this line to debug your data:
  // import std.stdio; writeln("xxx ____ get_double_of_json jv.type, jv:", jv.type, jv );

  _ensure_j_dbl_special();
  
  static if (accept_null)
    {
      return jv.type == JSONType.integer  
        ?  cast( double )( jv.integer )
        
        :  jv.type == JSONType.uinteger
        ?  cast( double )( jv.uinteger )

        :  jv.type == JSONType.null_
        ?  double.nan

        :  jv.type == JSONType.string  &&  jv.str == _j_dbl_special_s_infinity
        ?  double.infinity

        :  jv.type == JSONType.string  &&  jv.str == _j_dbl_special_s_negInfinity
        ?  -double.infinity 

        :  jv.type == JSONType.string  &&  jv.str == _j_dbl_special_s_nan
        ?  double.nan

        :  jv.floating
        ;
    }
  else
    {
      return jv.type == JSONType.integer  
        ?  cast( double )( jv.integer )
        
        :  jv.type == JSONType.uinteger
        ?  cast( double )( jv.uinteger )
        
        :  jv.floating
        ;
    }
}

long get_long_of_json( in JSONValue jv )
{
  if (jv.type == JSONType.integer)
    return cast( long )( jv.integer );

  if (jv.type == JSONType.uinteger)
    return cast( long )( jv.uinteger );

  enforce( jv.type == JSONType.float_
           , "get_long_of_json: expects an INTEGER, UINTEGER"
           ~ " or FLOAT. Got instead: " ~ to!string(jv.type)~", value: "~jv.toString
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


T[] json_get_array(T)( in JSONValue jv )
{
  enforce( jv.type == JSONType.array );

  scope auto apdr = appender!(T[]);

  foreach (j_one; jv.array)
    {
      static if (is(T == string))
        apdr.put( json_get_string( j_one ) );

      else if (is( T == double))
        apdr.put( json_get_double( j_one ) );

      else if (is( T == long))
        apdr.put( json_get_long( j_one ) );

      else if (is( T == bool ))
        apdr.put( json_get_bool( j_one ) );

      else
        assert( false, "Type not supported: "~(T.stringof) );
    }

  return apdr.data;
}


double json_get_double( bool accept_null = false )( in JSONValue jv )
{
  return get_double_of_json!accept_null( jv );
}

long json_get_long( in JSONValue jv )
{
  return get_long_of_json( jv );
}


string json_get_string( in JSONValue jv )
{
  assert( jv.type == JSONType.string
          , "Expected a STRING, got "~to!string(jv.type)
          ~": "~jv.toPrettyString );
  return jv.str; 
}

bool json_get_bool( in JSONValue jv )
{
  if (jv.type == JSONType.true_)
    return true;

  if (jv.type == JSONType.false_)
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
  scope auto j_n = json_get_place( j, place );
  return j_n.isNull  ?  j_default  :  j_n.get;
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
      scope Nullable!JSONValue j_deeper;
  
      if (j.type == JSONType.object)
        {
	  if (scope auto p = place[ 0 ] in j.object)
	    j_deeper = *p;
        }
      else if (j.type == JSONType.array)
        {
	  scope auto sp0 = place[ 0 ];

	  if (string_is_num09( sp0 ))
	    {
	      scope auto p0 = to!size_t( place[ 0 ] );
	      if (0 <= p0  &&  p0 < j.array.length)
		j_deeper = j.array[ p0 ];
	    }
	}

      if (!j_deeper.isNull)
        {
          j_ret = json_get_place( j_deeper.get, place[ 1..$ ] );
        }
    }
  
  return j_ret;
}


Nullable!JSONValue json_get_places( in ref JSONValue j, in string[] array_of_place_str )
{
  return json_get_places( j, array_of_place_str.map!"[a]".array );
}

Nullable!JSONValue json_get_places( in ref JSONValue j, in Jsonplace[] array_of_place )
/* Select the parts of `j` at each of `array_of_place`.
 
 If some match, return that subset, keeping the same structure as in `j`.

 If none match, returns a "nulled" object (`ret.isNull == true`)

 For a variant that always returns a non-null object, and always deep-copies,
 see json_get_opt_copy in ./lib_json_manip.d
*/
{
  scope auto arr = array_of_place.map!( place => json_get_place( j, place ) );

  Nullable!JSONValue ret;
  if (arr.all!"a.isNull")
    return ret; // "nulled"

  auto tmp = json_object();
  
  zip( array_of_place, arr ).each!( (x){
      if (!x[ 1 ].isNull)
	json_set_place( tmp, x[ 0 ], x[ 1 ].get );
    } );

  ret = tmp; // not "nulled"
  return ret;
}

string json_setC( in string j_obj_name, in string v_name )
// Code for mixin, to set a "simple" field in a JSON Object.
{
  return j_obj_name~`.object["`~v_name~`"] = JSONValue( `~v_name~` );`;
}

string json_setC( in string j_obj_name, in string[] v_name_arr )
// Code for mixin, to set a "simple" field in a JSON Object.
{
  return v_name_arr.map!((v_name) => json_setC( j_obj_name, v_name )).join( "\n" );
}


unittest
{
  import std.stdio;
  
  writeln( "unittest begins: "~__FILE__~": json_get_places" );

  immutable verbose = false;
  
  {
    immutable j_a_str = `"a":{"b":"c"}`;
    immutable j_d_str = `"d":{"e":{"f":"g"}}`;
    immutable j_h_str = `"h":{"i":{"j":{"k":"l"}},"i2":{"j2":{"k2":"l2"}}}`;
    immutable j_m_str = `"m":"n"`;
    
    immutable j_str = "{"~([j_a_str,j_d_str,j_h_str,j_m_str].join(","))~"}";
    JSONValue j  = parseJSON( j_str );

    if (verbose)
	writeln( "j:", j.toString );

    {
      auto      j2 = json_get_places( j, [ "a", "h" ] );
      assert( !j2.isNull );

      auto      j2b = json_get_places( j, [ ["a"], ["h"] ] );
      assert( !j2b.isNull );

      if (verbose)
	{
	  writeln( "j2:", j2.toString );
	  writeln( "j2b:", j2b.toString );
	}
    
      assert( j.toString  == parseJSON( j_str ).toString ); // unchanged
    
      immutable j2_str = parseJSON( "{"~([j_a_str,j_h_str].join(","))~"}" ).toString;
      assert( j2.toString == j2_str );
      assert( j2b.toString == j2_str );
    }

    {
      auto j3 = json_get_places( j, [ ["a"], ["h","i"] ] );
      assert( !j3.isNull );

      if (verbose)
	writeln( "j3:", j3.toString );

      assert( j.toString  == parseJSON( j_str ).toString ); // unchanged
    
      immutable j3_str = parseJSON( "{"~([j_a_str,`"h":{"i":{"j":{"k":"l"}}}`].join(","))~"}" ).toString;
      assert( j3.toString == j3_str );
    }

    {
      auto j4 = json_get_places( j, [ ["z"], ["y","x"] ] );
      assert( j4.isNull );

      if (verbose)
	writeln( "j4:", j4 );
    }

  }

  writeln( "unittest passed: "~__FILE__~": json_get_places" );
}


bool json_is_integer( in ref Nullable!JSONValue j )
{
  return !j.isNull  &&  j.get.type == JSONType.integer;
}




bool json_is_string( in ref Nullable!JSONValue j )
// Should work well together with `json_get_place`.
{
  return !j.isNull  &&  j.get.type == JSONType.string;
}

bool json_is_string_equal( T )( in ref T j, in Jsonplace place, in string s )
{
  static if (is(T == Nullable!JSONValue))
    auto maybe_j2 = json_get_place( j.get, place );
  else
    auto maybe_j2 = json_get_place( j, place );

  return json_is_string_equal( maybe_j2, s );
}


bool json_is_string_equal( T )( in ref T j, in string s )
// Should work well together with `json_get_place`.
{
  static if (hasMember!(T, "get"))
    return json_is_string( j )  &&  j.get.str == s;
  else
    return json_is_string( j )  &&  j.str == s;
}



bool json_is_true( in ref Nullable!JSONValue j )
{
  
  return !j.isNull  &&  j.get.type == JSONType.true_;
}


inout(JSONValue[string]) json_safeObject( inout(JSONValue) j )
pure @trusted
{
  enforce( j.type == JSONType.object );
  return j.object;
}

void json_set_place
( ref JSONValue j, in string place_str, in JSONValue v )
{
  json_set_place( j, place_str.split( "." ).array, v );
}


void json_set_place
( ref JSONValue j, in Jsonplace place, in JSONValue v )
{
  auto plen = place.length;
  assert( 0 < plen );
  
  auto is_leaf = 1 == plen;

  string    place_0 = place[ 0 ];

  if (j.type == JSONType.object)
    {
      if (is_leaf)
        {
          j.object[ place_0 ] = v;
        }
      else
        {
          if (place_0 !in j.object)
            j.object[ place_0 ] = _build_json_object( place[1..$], v );
          else
            json_set_place( j.object[ place_0 ], place[ 1..$ ], v );
        }
    }
  else if (j.type == JSONType.array)
    {
      if (is_leaf)
        j.array[ to!size_t( place_0 ) ] = _build_json_object( place[ 1..$ ], v );

      else
        json_set_place( (j.array[ to!size_t( place_0 ) ]), place[ 1..$ ], v );
    }
  else
    {
      stderr.writeln( "json_set_place: structure mismatch bug" );
      stderr.writeln( "v: ", v );
      stderr.writeln( "place: ", place );
      stderr.writeln( "j: ", j.toPrettyString );
      stderr.flush;
      enforce( false, "json_set_place: structure mismatch bug" );
    }
}

private JSONValue _build_json_object( in Jsonplace place, JSONValue v ) 
{
  if (place.length < 1)
    return v;

  auto ret = parseJSON( `{}` );
  ret.object[ place[ 0 ] ] = _build_json_object( place[ 1..$ ], v );
  return ret;
}



