module d_glat.lib_json_modif;

public import d_glat.core_json;
public import d_glat.lib_json_manip;

import d_glat.core_assert;
import std.algorithm : canFind;
import std.array : appender;
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

class JsonModifMany
{
  JsonModif[] jm_arr;

  this() {}
  this( JsonModif[] jm_arr ) { this.jm_arr = jm_arr; }

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
        auto what_str  = jm.what.toString;

        mixin(alwaysAssertStderr(`!where_str.canFind('\n')`));
        mixin(alwaysAssertStderr(`!what_str.canFind('\n')`));
                
        sink( where_str~'\n' );  // single line
        sink( what_str~"\n\n" ); // single line + extra empty line for human readability for debugging
      }
  }
}

struct JsonModif
{
  Jsonplace where;
  JSONValue what;
};

static auto jmm_fromString( in string s )
{
  auto line_arr = s.splitLines;
  immutable n = line_arr.length;
  mixin(alwaysAssertStderr(`0 == n%3`));
      
  auto jm_app = appender!(JsonModif[]);
    
  for (size_t i = 0; i < n;)
    {
      // read
      auto where_str = line_arr[ i++ ];
      auto what_str  = line_arr[ i++ ];
      i++; // human readability for debugging

      // parse
      auto where = to!Jsonplace( where_str );
      auto what  = parseJSON( what_str );

      // store
      JsonModif jm = {
      where : where
      , what : what
      };

      jm_app.put( jm );
    }

  // build
  return new JsonModifMany( jm_app.data );
}

// -------------------- Application --------------------

JSONValue json_modify( in JSONValue j, in JsonModifMany jmm, bool forbid_overwrites = true )
{
  auto ret = json_deep_copy( j );
  json_modify_inplace( ret, jmm, forbid_overwrites );
  return ret;
}

private struct Modified
{
  Modified[string] subset;
}


void json_modify_inplace( ref JSONValue j, in JsonModifMany jmm, bool forbid_overwrites = true )
{



    
}


