module d_glat.lib_json_modif;

public import d_glat.core_json;
public import d_glat.lib_json_manip;

import d_glat.core_assoc_array;
import d_glat.core_assert;
import std.algorithm : canFind;
import std.array : appender, Appender, array, split;
import std.conv : to;
import std.exception : assumeUnique;
import std.string : splitLines;

/*
  Represent a series of modifications to a JSON.  Provide a tool to
  apply such a series, forbidding or permitting overwrites.

  By Guillaume Lathoud - glat@glat.info
  
  Boost license, as described in the file ./LICENSE
*/

// -------------------- Representation --------------------

struct JsonModif
{
  const Jsonplace where;
  const JSONValue what;
};

alias JsonModifMany = JsonModifManyPO!false;

class JsonModifManyPO( bool permits_overwrite )
{
  // Inner representation
  
  private Appender!(JsonModif[]) jm_app;

  static if (!permits_overwrite) private ModifiedSofar moso;
  
  // API

  JsonModif[] jm_arr() pure const @safe nothrow
    {
      return jm_app.data.dup;
    } 
                                                
  this() { jm_app = appender!(JsonModif[]); }
  this( in JsonModif[] jm_arr ) { this(); push( jm_arr ); }

  void clear() pure nothrow @safe
  {
    jm_app.clear;
  }
  
  bool isEmpty() const pure nothrow @safe
  {
    return jm_app.data.length < 1;
  }
  
  void push( in JsonModifManyPO!permits_overwrite other )
  {
    push( other.jm_arr );
  }
  
  void push( in JsonModif[] jm_arr )
  {
    foreach (jm; jm_arr)
      push( jm );
  }

  void push( in JsonModif jm )
  {
    push( jm.where, jm.what );
  }

  void push(T)( in string dot_where, in T what )
  {
      push( dot_where.split( '.' ).array, what );
  }
  
  void push(T)( in Jsonplace where, in T what )
  {
    static if (!is(T == JSONValue))
      {
        push( where, JSONValue( what ) ); // Convenience wrapper
      }
    else
      {
        // Core implementation for the above wrappers
        
        static if (!permits_overwrite) moso.check_not_yet_and_set( where );
        
        jm_app.put( JsonModif( where, what ) );
      }
  }

  size_t size() const pure @nogc @safe
  {
    return jm_app.data.length;
  }

  
  // Serialization
  
  override string toString() const
  {
    auto c_app = appender!(char[]);
    toString( c => c_app.put( c ) );
    return assumeUnique( c_app.data );
  }
  
  void toString(scope void delegate(const(char)[]) sink) const
  {
    foreach (jm; jm_arr)
      {
        auto where_str = to!string( jm.where );
        auto what_str  = jm.what.toString( JSONOptions.specialFloatLiterals );

        mixin(alwaysAssertStderr(`!where_str.canFind('\n')`));
        mixin(alwaysAssertStderr(`!what_str.canFind('\n')`));
                
        sink( where_str~'\n' );  // single line
        sink( what_str~"\n\n" ); // single line + extra empty line for human readability for debugging
      }
  }
}

static auto jmm_fromString(bool permits_overwrite = false)( in string s )
{
  auto line_arr = s.splitLines;
  immutable n = line_arr.length;
  mixin(alwaysAssertStderr(`0 == n%3`));
      
  auto jmm = new JsonModifManyPO!permits_overwrite;
    
  for (size_t i = 0; i < n;)
    {
      // read
      auto where_str = line_arr[ i++ ];
      auto what_str  = line_arr[ i++ ];
      i++; // human readability for debugging

      // parse
      auto where = to!Jsonplace( where_str );
      auto what  = parseJSON( what_str, -1, JSONOptions.specialFloatLiterals );

      // store
      jmm.push( where, what );
    }

  return jmm;
}

// -------------------- Application --------------------

JSONValue json_modify(bool permits_overwrite)( in JsonModifManyPO!permits_overwrite jmm, in JSONValue j )
{
  auto ret = json_deep_copy( j );
  json_modify_inplace!permits_overwrite( jmm, ret );
  return ret;
}

  
void json_modify_inplace(bool permits_overwrite)( in JsonModifManyPO!permits_overwrite jmm, ref JSONValue j )
{
  foreach (jm; jmm.jm_arr)
    {
      static if (false)
        {
          debug
            {
              import std.stdio;
              writeln("xxx j:", j.toString( JSONOptions.specialFloatLiterals ) );
              writeln("xxx jm.where:", jm.where);
              writeln("xxx jm.what:", jm.what.toString( JSONOptions.specialFloatLiterals ));
            }
        }
      json_set_place( j, jm.where, jm.what );
    }
}

// -------------------- private core --------------------

private struct ModifiedSofar
{
  ModifiedSofar[string] subset;
  
  void check_not_yet_and_set( in Jsonplace where )
  {
    immutable w0 = where[ 0 ];
    
    if (1 < where.length)
      {
        auto sub_moso = subset.aa_getInit( w0 );
        sub_moso.check_not_yet_and_set( where[ 1..$ ] );
        return;
      }

    if (w0 in subset)
      {
        stderr.writeln( "lib_json_modif: error: w0: ", w0 );
        stderr.writeln( "lib_json_modif: error: subset: ", subset );
        stderr.flush;
      }
    
    mixin(alwaysAssertStderr(`w0 !in subset`));

    subset[ w0 ] = ModifiedSofar(); // leaf
  }
};


unittest
{
  import std.path;
  import std.stdio;

  import d_glat.core_array;
  import d_glat_priv.core_unittest;
  
  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  immutable verbose = false;

  immutable string _ici = `__FILE__ ~ "@line:" ~ to!string( __LINE__ )`;

  import core.exception : AssertError;
    
  {
    // Wtf#0

    auto j = parseJSON( `{"a":456}` );
    json_set_place( j, "a", parseJSON( `{"abc":123}`) );

    if (verbose) writeln( mixin(_ici), ": j: ", j.toString );

    assert( json_equals( j, `{"a":{"abc":123}}` ) );
  }

  {
    // Wtf#0

    auto j = parseJSON( `{}` );
    json_set_place( j, "a", parseJSON( `{"abc":123}`) );

    if (verbose) writeln( mixin(_ici), ": j: ", j.toString );

    assert( json_equals( j, `{"a":{"abc":123}}` ) );
  }

  
  {
    auto jmm = new JsonModifMany;
    jmm.push( ["a","b","c"], parseJSON( `{"xyz":123}` ) );
    jmm.push( "a.b.d", parseJSON( `{"tuv":456}` ) );
    jmm.push( "e.f.g", parseJSON( `{"rst":789}`) );

    auto j  = parseJSON( `{}` );
    auto j2 = json_modify( jmm, j );
    immutable jstr_expected = `{"a":{"b":{"c":{"xyz":123},"d":{"tuv":456}}},"e":{"f":{"g":{"rst":789}}}}`;

    if (verbose) writeln( mixin(_ici), ": j: ", j.toString );
    if (verbose) writeln( mixin(_ici), ": j2: ", j2.toString );
    
    assert( json_equals( j, parseJSON( `{}` ) ) ); // `j` not modified
    assert( json_equals( j2, parseJSON( jstr_expected ) ) ); // `j2` the copied, modified version of `j` 
    
    json_modify_inplace( jmm, j );
    assert( json_equals( j, parseJSON( jstr_expected ) ) ); // `j` modified
    assert( json_equals( j2, parseJSON( jstr_expected ) ) ); // `j2` remained the same
  }

  {
    auto jmm = new JsonModifMany;
    jmm.push( ["a","b","c"], parseJSON( `{"xyz":123}` ) );
    jmm.push( "a.b.d", parseJSON( `{"tuv":456}` ) );
    assertThrown!(core.exception.AssertError)( jmm.push( "a.b", parseJSON( `{"some":"overwrite"}` ) ) );
  }

  {
    auto jmm = new JsonModifManyPO!(/*permit_overwrite:*/true);
    jmm.push( ["a","b","c"], parseJSON( `{"xyz":123}` ) );
    jmm.push( "a.b.d", parseJSON( `{"tuv":456}` ) );
    jmm.push( "a.b", parseJSON( `{"some":"overwrite"}` ) );

    auto j = parseJSON( `{"x":{"y":"z"}}` );
    json_modify_inplace( jmm, j );

    if (verbose) writeln( mixin(_ici), ": j:", j );
    
    assert( json_equals( j, `{"x":{"y":"z"},"a":{"b":{"some":"overwrite"}}}` ) );
  }

  
  writeln;
  writeln( "unittest passed: ", baseName( __FILE__ ) );
  
}

