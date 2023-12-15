module d_glat.flatmatrix.core_octave_code;

/*
  Tools to manipulate strings of data to and from Octave
  (MATLAB-like).

  The Boost License applies, see file ./LICENSE

  By Guillaume Lathoud, 2022 and later
  glat@glat.info
 */

import d_glat.core_assert;
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



string mstr_of_mat(T/*typically float or double*/)( in MatrixT!T m, bool newlines = false )
// newlines: false better when passing code to an octave instance
// newlines: true better e.g. for .m file output, to have something humanly readable
{
  immutable nrow = m.nrow;
  immutable rd   = m.restdim;
  immutable snl  = newlines ? "\n" : "";
  return "["~snl~(m.data.chunks( rd ).map!((ch) => format("%(%.14g %);", ch)).join( snl ))~snl~"]";
}



string mstr_of_mact_arr( MAction[] mact_arr, in bool newlines = false )
{
  return mact_arr.map!((a) => a.getCode( newlines )~'\n').join("");
}


// ---------- Generic actions to generate code, used e.g. by ./lib_octave_exec.d ---------- 

abstract class MAction { abstract string getCode( in bool newline = false ) const; }


immutable mClearAll = cast(immutable(MExec))( mExec( "clear('all');" ) );


MExec mExec( in string s ) { return new MExec( s ); } // Convenience wrapper
class MExec : MAction
{
  immutable string action;
  
  this( in string action ) { this.action = action; }

  override string getCode( in bool newlines = false ) const { return action; }
}


alias mSet = mSetT!double;
alias MSet = MSetT!double;

MSetT!T mSetT(T)( in string vname, in MatrixT!T m ) { return new MSetT!T( vname, m ); } // Convenience
class MSetT(T) : MAction
{
  immutable string vname;
  const MatrixT!T m;
  
  this( in string vname, in MatrixT!T m ) {
    this.vname = vname;     mixin(alwaysAssertStderr!`0 < vname.length`);
    this.m = m;             mixin(alwaysAssertStderr!`m.dim.length == 2`);
  }

  override string getCode( in bool newlines = false ) const
  {
    return vname~"="~mstr_of_mat( m, newlines )~";";
  }
}


alias mPrintMatrix = mPrintMatrixT!double;
alias MPrintMatrix = MPrintMatrixT!double;

MPrintMatrixT!T mPrintMatrixT(T)( in string vname ) { return new MPrintMatrixT!T( vname ); } // Conve.
class MPrintMatrixT(T) : MAction
{
  immutable string vname;

  this( in string vname ) { this.vname = vname; mixin(alwaysAssertStderr!`0 < vname.length`); }

  override string getCode( in bool newlines = false ) const
  {
    immutable snl = newlines ? "\n" : "";
    return "disp(sprintf('%d ',size("~vname~")));"~snl~"format long g;"~snl~"disp("~vname~");"~snl~"disp(\"\\n\")";
  }
}
