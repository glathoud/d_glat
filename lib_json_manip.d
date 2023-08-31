module d_glat.lib_json_manip;

/* Utilities to manipulate `JSONValue`s

By Guillaume Lathoud - glat@glat.info

Boost license, as described in the file ./LICENSE
*/

public import d_glat.core_json;
public import std.json;

import d_glat.core_cast;
import d_glat.core_sexpr;
import d_glat.lib_json_manip;
import std.algorithm;
import std.array;
import std.conv;
import std.digest.sha;
import std.exception;
import std.format : format;
import std.math;
import std.stdio;
import std.traits : isSomeString;
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
  
  if (JSONType.string == jv2.type)
    {
      ubyte[] arr  = cast( ubyte[] )( jv2.str );
      ubyte[] arr2 = arr.map!( x => min( x, some_max ) ).array;
      jv2.str = cast( string )( arr2 );
    }
}

JSONValue json_deep_copy( in ref JSONValue j )
{
  final switch (j.type)
    {
    case JSONType.string: return JSONValue( j.str ); 
    case JSONType.array: return JSONValue( j.array.map!json_deep_copy.array ); 
    case JSONType.object:
      JSONValue ret = parseJSON( "{}" );
      foreach (k,v; j.object)
        ret.object[ k ] = v.json_deep_copy;
      return ret;
      
    case JSONType.null_: return JSONValue(null);
    case JSONType.integer: return JSONValue(j.integer);
    case JSONType.uinteger: return JSONValue(j.uinteger);
    case JSONType.float_: return JSONValue(j.floating);
    case JSONType.true_: return JSONValue(true);
    case JSONType.false_: return JSONValue(false);
    }
}

JSONValue json_flatten_array( in ref JSONValue j )
{
  assert( j.type == JSONType.array );
  auto ret = json_array();
  _json_flatten_push( ret, j );
  return ret;
}

private void _json_flatten_push
( ref JSONValue ret, in ref JSONValue j )
{
  if ( j.type == JSONType.array )
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
  scope auto digest = makeDigest!SHA1;
  void sink( in string s ) { digest.put( cast(ubyte[])( s ) ); }
  json_walk_sorted( j, &sink );

  immutable ret = format( "%(%02x%)", digest.finish );
  return ret;
}


T json_get_opt_copy(T/*string | JSONValue*/)( in T j_in_0, in string[] place_str_arr )
{
  return json_get_opt_copy!T( j_in_0, place_str_arr.map!"[a]".array );
}

T json_get_opt_copy(T/*string | JSONValue*/)( in T j_in_0, in Jsonplace[] place_arr )
// Returns a subset reduced to `place_arr` (if available - no error if not available).
// For each match, a json_deep_copy is done
//
// Differences with json_get_places (./core_json.d):
// 
// (1) always returns an object or array, even if there is no match at all
// 
// (2) deep-copy all matches
{
  static immutable is_string = isSomeString!T;

  static if (is_string)
    scope JSONValue j_in = parseJSON( j_in_0 );
  else
    scope JSONValue j_in = j_in_0;

  
  JSONValue j_ret = j_in.type == JSONType.object  ?  json_object()
    :  j_in.type == JSONType.array ?  json_array()
    :  parseJSON("null"); // should fail
  
  foreach (place; place_arr)
    {
      scope auto j_maybe = json_get_place( j_in, place );
      if (!j_maybe.isNull)
	json_set_place( j_ret, place, json_deep_copy( j_maybe.get ) );
    }

  
  static if (is_string)
    return j_ret.toString;
  else
    return j_ret;
}

unittest
{
  import std.stdio;
  
  writeln( "unittest starts: "~__FILE__~": json_get_opt_copy" );

  {
    auto o0 = parseJSON( `{"a":123,"b":{"c":456,"d":789},"e":101}` );
    
    auto o1 = json_get_opt_copy( o0, [ ["a"], ["b","d"] ] );
    
    assert( json_equals( o1, parseJSON(`{"a":123,"b":{"d":789}}` ) ) );
  }

  {
    auto o0 = parseJSON( `{"a":123,"b":{"c":456,"d":789},"e":101}` );
    
    auto o1 = json_get_opt_copy( o0, [ "a", "b" ] );
    
    assert( json_equals( o1, parseJSON(`{"a":123,"b":{"c":456,"d":789}}` ) ) );
  }

  writeln( "unittest passed: "~__FILE__~": json_get_opt_copy" );
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
  scope auto app = appender!(char[]);
  void sink( in string s ) { app.put( s ); }
  json_walk_sorted( j, &sink );
  return app.data.idup;
}

void json_walk_sorted( in ref JSONValue j, in void delegate (in string ) sink )
{
  switch (j.type)
    {
    case JSONType.array:

      sink( "__.[[" );

      scope auto j_array = j.array;
      immutable i_last = j_array.length - 1;

      foreach( i, j_one; j_array )
        {
          json_walk_sorted( j_one, sink );
          if (i < i_last)
            sink( JSON_HASH_MATERIAL_SEP );
        }

      sink( "]].__" );
      break;
      
    case JSONType.object:

      sink( "__.{{" );

      scope auto j_object = j.object;
      scope auto     keys = j_object.keys.sort(); // unicity
      immutable i_last = keys.length - 1;

      size_t i = 0;
      foreach (k; keys)
        {
          sink( "\"" );
          sink( k );
          sink( "\":" );
          json_walk_sorted( j_object[ k ], sink );
          if (i < i_last)
            sink( JSON_HASH_MATERIAL_SEP );

          ++i;
        }

      sink( "}}.__" );
      break;
      
    default:
      sink( j.toString );
    }
}


bool json_equals( in JSONValue j0, in string jstr1 )
// Not very efficient but useful for unittests
{
  return json_equals( j0, parseJSON( jstr1 ) );
}

bool json_equals( in string jstr0, in JSONValue j1 )
// Not very efficient but useful for unittests
{
  return json_equals( parseJSON( jstr0 ), j1 );
}

bool json_equals( in string jstr0, in string jstr1 )
// Not very efficient but useful for unittests
{
  return json_equals( parseJSON( jstr0 ), parseJSON( jstr1 ) );
}


bool json_equals( in JSONValue j0, in JSONValue j1 )
{
  if (j0.type != j1.type)
    {
      if ((j0.type == JSONType.integer  &&  j1.type == JSONType.float_
           ||  j1.type == JSONType.integer  &&  j0.type == JSONType.float_

	   ||  j0.type == JSONType.uinteger  &&  j1.type == JSONType.float_
           ||  j1.type == JSONType.uinteger  &&  j0.type == JSONType.float_
	   
	   ||  j0.type == JSONType.integer  &&  j1.type == JSONType.uinteger
           ||  j1.type == JSONType.integer  &&  j0.type == JSONType.uinteger
          
	   )
          &&  json_get_double( j0 ) == json_get_double( j1 )
          )
        {
          return true; // Deal with some parsing instabilities
        }
      
      return false;
    }
  
  final switch (j0.type)
    {
    case JSONType.string: return j0.str == j1.str;

    case JSONType.array:

      if (j0.array.length != j1.array.length)
        return false;

      foreach (i,v0; j0.array)
        {
          if (!json_equals( v0, j1.array[ i ] ))
            return false;
        }

      return true;
      
    case JSONType.object:

      foreach (k; j1.object.keys)
        {
          if (k !in j0.object)
            return false;
        }

      foreach (k,v0; j0.object)
        {
          if (auto pv1 = k in j1.object)
            {
              if (!json_equals( v0, *pv1 ))
                return false;
            }
          else
            {
              return false;
            }
        }
      
      return true;

    case JSONType.null_, JSONType.true_, JSONType.false_: return true;
      
    case JSONType.integer:  return j0.integer  == j1.integer;
    case JSONType.uinteger: return j0.uinteger == j1.uinteger;
    case JSONType.float_:    return j0.floating == j1.floating;
    }
}




JSONValue json_solve_calc( in ref JSONValue o )
{
  bool out_modified = false;
  return json_solve_calc( o, out_modified );
}



immutable string _ici = `__FILE__ ~ "@line:" ~ to!string( __LINE__ )`;

JSONValue json_solve_calc(bool accept_incomplete = false)( in ref JSONValue o, ref bool out_modified )
{
  enforce( o.type == JSONType.object );

  auto ret = json_deep_copy( o );

  bool modified = true;
  while (modified)
    {
      modified = false;

      bool found_todo = false;
      ret.json_walk_until!( (place, v) {

          if (place.length > 0  &&  place[ $-1 ] == JSON_P_CALC)
            {
              found_todo = true;
              
              scope auto new_v = json_solve_calc_one( ret, v, /*output:*/modified );
              
              if (modified)
                json_set_place( ret, place[ 0..($-1)], new_v );
            }

          return modified;
        });

      static if (!accept_incomplete)
        {
          if (found_todo)
            enforce( modified, mixin(_ici)~" !accept_incomplete => must progress, but here, could not do at least modification. Something is missing, or there is a dependency loop between (calc)'s.");
        }
      
      if (modified)
        out_modified = true;
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
  assert( o1.toString == `{"a":123,"b":{"c":239.0}}`);
  
  writeln( "unittest passed: "~__FILE__~": json_solve_calc" );

}


JSONValue json_solve_calc_one( in ref JSONValue o
                               , in ref JSONValue v
                               )
{
  bool success = false;
  auto ret = json_solve_calc_one( o, v, success );
  enforce( success ); // here, must succeed
  return ret;
}

  
JSONValue json_solve_calc_one( in ref JSONValue o
                               , in ref JSONValue v
                               , ref bool success
                               )
{
  enforce( o.type == JSONType.object ); 
  enforce( v.type == JSONType.string );
  
  scope auto e = parse_sexpr( v.str );

  bool tmp_success = false;

  double v_dbl = json_solve_calc_one( o, e, tmp_success );

  success = tmp_success;
  
  JSONValue new_v;
  if (success)
    {
      new_v = JSONValue( v_dbl );

      enforce( new_v.toString != v.toString
               , "Forbidden: json_solve_calc_one gave the same output:" ~ new_v.toString~"    from v:"~v.toString
               );
    }

  return new_v;
}

double json_solve_calc_one( in ref JSONValue o
                            , in ref SExpr e
                            , ref bool success
                            )
{
  enforce( o.type == JSONType.object );

  enforce( !e.isEmpty );

  if (e.isAtom)
    {
      immutable string s = e.toString;
      if (scope auto p = s in o.object)
        {
          immutable ptyp = p.type;
          immutable tmp_success_0 = (ptyp == JSONType.integer  ||  ptyp == JSONType.float_);
          success = tmp_success_0;
          return success  ?  json_get_double( *p )  :  double.nan;
        }
      else
        {
          try
            {
              auto ret = to!double( s );
              success = true;
              return ret;
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

  scope const li = cast( SList )( e );

  success = true;
  
  scope double[] operands =
    li.rest.map!( (x) {
        bool op_success = false;
        auto ret = json_solve_calc_one( o, x, op_success );
        success = success  &&  op_success;
        return ret;
      }).array;

  immutable nop = operands.length;
  
  success = success  &&  0 < nop;

  enforce( 0 < nop, li.toString );

  const op = li.first.toString;

  if (nop == 1)
    {
      switch (op)
        {
        case "round": return round( operands[ 0 ] );
        default: break;
        }
      throw new Exception( "Unknown (unary?) operator "~op~" from "~li.toString );
    }
  else
    {
      switch (op)
        {
        case "+": return operands.reduce!"a+b";
        case "-": return operands.reduce!"a-b";
        case "*": return operands.reduce!"a*b";
        case "/": return operands.reduce!"a/b";
        default: break;
        }
      
      throw new Exception( "Unknown (binary?) operator "~op~" from "~li.toString );
    }
}














void json_walkreadonly( alias iter )( in ref JSONValue j )
// Deep-walk a JSON.
// 
// If your function iter( Jsonplace place, ref JSONValue jv )
// also wants to store the place information: use `place.(i)dup`
// 
// This way we do not have to (i)dup it here within the generic walk
// implementation => in most cases much faster + less memory/GC =>
// especially faster in a multithreading case, because much less GC.
{
  json_walkreadonly_until!( _json_walkreadonly_iter_wrap!( iter ) )( j );
}

private bool _json_walkreadonly_iter_wrap( alias iter )
  ( in Jsonplace place, in ref JSONValue v )
// If your function iter( Jsonplace place, ref JSONValue jv )
// also wants to store the place information: use `place.(i)dup`
// 
// This way we do not have to (i)dup it here within the generic walk
// implementation => in most cases much faster + less memory/GC =>
// especially faster in a multithreading case, because much less GC.
{
  iter( place, v );
  return false; // never stop, walk the whole JSON
}

bool json_walkreadonly_until( alias test, bool stop_at_first_match = true )( in ref JSONValue j )
/*
  Deep-walk the JSON until reaching a Jsonplace `p` where `true == test( p, v )`,
  in which case the depth walk stops.
  
  Then, (1) if `stop_at_first_match == true` finish here, else (2)
  continue the breadth walk to finish walking the JSON.

  If your test function test( Jsonplace place, ref JSONValue jv )
  also wants to store the place information: use `place.(i)dup`
  
  This way we do not have to (i)dup it here within the generic walk
  implementation => in most cases much faster + less memory/GC =>
  especially faster in a multithreading case, because much less GC.
*/
{
  scope auto top_place = appender!Jsonplace();
  
  return _json_walkreadonly_until_sub!( test, stop_at_first_match )( top_place, j );
}

private bool _json_walkreadonly_until_sub( alias test, bool stop_at_first_match = true )
  ( ref Appender!Jsonplace place_app, in ref JSONValue j )
// If your test function test( Jsonplace place, ref JSONValue jv )
// also wants to store the place information: use `place.(i)dup`
// 
// This way we do not have to (i)dup it here within the generic walk
// implementation => in most cases much faster + less memory/GC =>
// especially faster in a multithreading case, because much less GC.
{
  bool ret = test( place_app.data, j ); 

  if (!ret) // if a match, do not go deeper
    {
      if (j.type == JSONType.object)
        {
          foreach ( k2, ref v2; j.object ) // breadth walk at the lower level
            {
              if (!stop_at_first_match  ||  !ret)
                {
                  place_app.put( k2 );

                  if (_json_walkreadonly_until_sub!( test, stop_at_first_match )( place_app, v2 ))
                    ret = true;
                  
                  place_app.shrinkTo( place_app.data.length - 1 );
                }

              static if (stop_at_first_match)
                {
                  if (ret)
                    break;
                }
            }
        }
      else if (j.type == JSONType.array)
        {
          foreach ( k2, ref v2; j.array ) // breadth walk at the lower level
            {
              if (!stop_at_first_match  ||  !ret)
                {
                  place_app.put( to!string( k2 ) );

                  if (_json_walkreadonly_until_sub!( test, stop_at_first_match )( place_app, v2 ))
                    ret = true;
                  
                  place_app.shrinkTo( place_app.data.length - 1 );
                }
              
              static if (stop_at_first_match)
                {
                  if (ret)
                    break;
                }
            }          
        }
    }

  static if (stop_at_first_match)
    return ret;
  else
    return false;
}

unittest
{
  import std.stdio;
  
  writeln( "unittest starts: "~__FILE__~": json_walkreadonly_until" );

  immutable verbose = false;
  
  { // --- searching for "number" matches
    
    auto j_str = `{"a":123,"b":{"c":456,"d":789,"e":{"f":101}}}`;

    bool iter_number( Appender!(Jsonplace[]) p_app, Jsonplace p, JSONValue j )
    {
      immutable ret = json_equals( j, JSONValue( 456 ) )
        ||  json_equals( j, JSONValue( 101 ) )
        ;

      if (verbose)
        writeln( "iter_number: p,ret: ", p, ret );
    
      if (ret)
        p_app.put( p.dup ); // .(i)dup important, see above comment in `json_walkreadonly_until`

      return ret;
    }

    { // /*stop_at_first_match:*/true

      auto o  = parseJSON( j_str );

      auto p_app = appender!(Jsonplace[]);
      json_walkreadonly_until!((p,j) => iter_number( p_app, p, j ), /*stop_at_first_match:*/true)( o );
      assert( json_equals( o, parseJSON( j_str ) ) ); // check unmodified

      auto p_arr = p_app.data;
      p_arr.sort;

      if (verbose)
        writeln( "xxx app_stop.data", p_arr ); stdout.flush;
      
      assert( p_arr == [cast(Jsonplace)(["b","c"])]  ||  p_arr == [cast(Jsonplace)(["b","e","f"])] );
    }
    
    { // default: /*stop_at_first_match:*/true

      auto o  = parseJSON( j_str );

      auto p_app = appender!(Jsonplace[]);
      json_walkreadonly_until!((p,j) => iter_number( p_app, p, j ))( o );
      assert( json_equals( o, parseJSON( j_str ) ) ); // check unmodified

      auto p_arr = p_app.data;
      p_arr.sort;

      if (verbose)
        writeln( "xxx app_stop.data", p_arr ); stdout.flush;
      
      assert( p_arr == [cast(Jsonplace)(["b","c"])]  ||  p_arr == [cast(Jsonplace)(["b","e","f"])] );
    }

    { // /*stop_at_first_match:*/false

      auto o  = parseJSON( j_str );

      auto p_app = appender!(Jsonplace[]);
      json_walkreadonly_until!((p,j) => iter_number( p_app, p, j ), /*stop_at_first_match:*/false)( o );
      assert( json_equals( o, parseJSON( j_str ) ) ); // check unmodified

      auto p_arr = p_app.data;
      p_arr.sort;

      if (verbose)
        writeln( "xxx app_stop.data", p_arr ); stdout.flush;
      
      assert( p_arr == [cast(Jsonplace)(["b","c"]), cast(Jsonplace)(["b","e","f"])] );
    }
  }



  { // --- searching for "object" matches
    
    auto j_str = `{"a":123
                   ,"b":{"x":333,"c":456,"d":{"x":789},"e":{"x":222,"f":101}}
                   ,"b2":{"x":444,"d2":{"x":777}}}}`;

    bool iter_object( Appender!(Jsonplace[]) p_app, Jsonplace p, JSONValue j )
    {
      immutable ret = j.type == JSONType.object  &&  j.object.keys.canFind( "x" );

      if (verbose)
        writeln( "iter_object: p,ret: ", p, ret );
    
      if (ret)
        p_app.put( p.dup ); // .(i)dup important, see above comment in `json_walkreadonly_until`

      return ret;
    }

    auto o = parseJSON( j_str );
    
    { // /*stop_at_first_match:*/true
      auto p_app = appender!(Jsonplace[]);
      json_walkreadonly_until!((p,j) => iter_object( p_app, p, j ), /*stop_at_first_match:*/true)( o );
      assert( json_equals( o, parseJSON( j_str ) ) ); // check unmodified

      auto p_arr = p_app.data;
      p_arr.sort;

      if (verbose)
        writeln( "xxx app_stop.data", p_arr ); stdout.flush;
      
      assert( p_arr == [cast(Jsonplace)(["b"])]  ||  p_arr == [cast(Jsonplace)(["b2"])] );
    }
    
    { // default: /*stop_at_first_match:*/true
      auto p_app = appender!(Jsonplace[]);
      json_walkreadonly_until!((p,j) => iter_object( p_app, p, j ))( o );
      assert( json_equals( o, parseJSON( j_str ) ) ); // check unmodified

      auto p_arr = p_app.data;
      p_arr.sort;

      if (verbose)
        writeln( "xxx app_stop.data", p_arr ); stdout.flush;
      
      assert( p_arr == [cast(Jsonplace)(["b"])]  ||  p_arr == [cast(Jsonplace)(["b2"])] );
    }

    { // /*stop_at_first_match:*/false
      auto p_app = appender!(Jsonplace[]);
      json_walkreadonly_until!((p,j) => iter_object( p_app, p, j ), /*stop_at_first_match:*/false)( o );
      assert( json_equals( o, parseJSON( j_str ) ) ); // check unmodified

      auto p_arr = p_app.data;
      p_arr.sort;

      if (verbose)
        writeln( "xxx app_stop.data", p_arr ); stdout.flush;
      
      assert( p_arr == [cast(Jsonplace)(["b"]), cast(Jsonplace)(["b2"])] );
    }
  }
  
  writeln( "unittest passed: "~__FILE__~": json_walkreadonly_until" );
}







void json_walk( alias iter )( ref JSONValue j )
// If your test function test( Jsonplace place, ref JSONValue jv )
// also wants to store the place information: use `place.(i)dup`
// 
// This way we do not have to (i)dup it here within the generic walk
// implementation => in most cases much faster + less memory/GC =>
// especially faster in a multithreading case, because much less GC.
{
  json_walk_until!( _json_walk_iter_wrap!( iter ) )( j );
}

private bool _json_walk_iter_wrap( alias iter )
  ( in Jsonplace place, ref JSONValue v )
// If your test function test( Jsonplace place, ref JSONValue jv )
// also wants to store the place information: use `place.(i)dup`
// 
// This way we do not have to (i)dup it here within the generic walk
// implementation => in most cases much faster + less memory/GC =>
// especially faster in a multithreading case, because much less GC.
{
  iter( place, v );
  return false;
}

bool json_walk_until( alias test, bool stop_at_first_match = true )( ref JSONValue j )
// If your test function test( Jsonplace place, ref JSONValue jv )
// also wants to store the place information: use `place.(i)dup`
// 
// This way we do not have to (i)dup it here within the generic walk
// implementation => in most cases much faster + less memory/GC =>
// especially faster in a multithreading case, because much less GC.
{
  scope auto top_place = appender!Jsonplace();
  
  return _json_walk_until_sub!( test, stop_at_first_match )( top_place, j );
}

private bool _json_walk_until_sub( alias test, bool stop_at_first_match = true )
  ( ref Appender!Jsonplace place_app, ref JSONValue j )
// If your test function test( Jsonplace place, ref JSONValue jv )
// also wants to store the place information: use `place.(i)dup`
// 
// This way we do not have to (i)dup it here within the generic walk
// implementation => in most cases much faster + less memory/GC =>
// especially faster in a multithreading case, because much less GC.
{
  bool ret = test( place_app.data, j ); 
  
  if (!ret)
    {
      if (j.type == JSONType.object)
        {
          foreach ( k2, ref v2; j.object )
            {
              if (!stop_at_first_match  ||  !ret)
                {
                  place_app.put( k2 );
                  ret = _json_walk_until_sub!( test, stop_at_first_match )( place_app, v2 );
                  place_app.shrinkTo( place_app.data.length - 1 );
                }

              static if (stop_at_first_match)
                {
                  if (ret)
                    break;
                }
            }
        }
      else if (j.type == JSONType.array)
        {
          foreach ( k2, ref v2; j.array )
            {
              if (!stop_at_first_match  ||  !ret)
                {
                  place_app.put( to!string( k2 ) );
                  ret = _json_walk_until_sub!( test, stop_at_first_match )( place_app, v2 );
                  place_app.shrinkTo( place_app.data.length - 1 );
                }
              
              static if (stop_at_first_match)
                {
                  if (ret)
                    break;
                }
            }          
        }
    }

  static if (stop_at_first_match)
    return ret;
  else
    return false;
}

string json_white_out_comments( in string extended_json_string )
/*
  Very simple comment removal, that does not care about syntax, double
quotes etc. Simplistic but enough for most practical purposes.
*/
  {
    scope auto modifiable = cast( char[] )( extended_json_string );
    json_white_out_comments_inplace( modifiable );
    return modifiable.idup;
  }

auto json_white_out_comments_inplace( char[] ca ) pure nothrow @safe @nogc
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

  return ca;
}
