module d_glat.core_octave;

/*
  Tools to manipulate strings of data to and from Octave
  (MATLAB-like).

  The Boost License applies, see file ./LICENSE

  By Guillaume Lathoud, 2022
  glat@glat.info
 */

import d_glat.lib_json;
import std.algorithm : map;
import std.array : array;
import std.json;
import std.string : replace;

string mstr_of_arr(T/*typically float or double*/)( in T[] arr )
{
  return JSONValue( arr ).toString( JSONOptions.specialFloatLiterals ).replace( `"NaN"`, "nan" ).replace( `"Infinite"`, "Inf" ).replace( `"-Infinite"`, "-Inf" );
}

T[] arr_of_mstr(T = double/*typically float or double*/)( in string s )
{
  scope immutable tmp = s.replace("-nan","\"NaN\"").replace("nan","\"NaN\"")
    .replace("-Inf","\"-Infinite\"").replace("Inf","\"Infinite\"");

  import std.stdio;
  writeln("xxx ____ tmp: ", tmp);
  
  return parseJSON( tmp
                    , -1
                    , JSONOptions.specialFloatLiterals
                    ).array.map!((a) => cast(T)( json_get_double( a ))).array;
}
