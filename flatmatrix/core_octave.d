module d_glat.flatmatrix.core_octave;

/*
  Tools to manipulate strings of data to and from Octave
  (MATLAB-like).

  The Boost License applies, see file ./LICENSE

  By Guillaume Lathoud, 2022 and later
  glat@glat.info
 */

import d_glat.flatmatrix.core_matrix;
import d_glat.lib_json;
import std.algorithm : map;
import std.array : array, join;
import std.format : format;
import std.json;
import std.range : chunks;
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
  
  return parseJSON( tmp
                    , -1
                    , JSONOptions.specialFloatLiterals
                    ).array.map!((a) => cast(T)( json_get_double( a ))).array;
}



string mstr_of_mat(T/*typically float or double*/)( in MatrixT!T m )
{
  immutable nrow = m.nrow;
  immutable rd   = m.restdim;
  return "["~(m.data.chunks( rd ).map!((ch) => format("%(%.14g %)", ch)).join( ";" ))~"]";
}
