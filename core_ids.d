module d_glat.core_ids;

import d_glat.core_assert;
import std.array : Appender, appender;
import std.functional : partial;

/*
  Back-and-forth between string ids and numerical ids.

  The Boost License applies, as described in the file ./LICENSE
  
  By Guillaume Lathoud, 2022
  glat@glat.info
 */

struct IDS
{
  size_t id_of_string( in string s )
  {
    if (auto p = s in i_of_s_aa)
      return *p;
    
    return _register_id_of_string( s );
  }

  string string_of_id( in size_t id )
  {
    return s_of_i_app.data[ id ];
  }
    
private:
  size_t[string]      i_of_s_aa;
  Appender!(string[]) s_of_i_app;
  
  size_t _register_id_of_string( in string s )
  {
    debug mixin(alwaysAssertStderr!`s !in i_of_s_aa`);
    
    immutable id = s_of_i_app.data.length;
    
    s_of_i_app.put( s );
    i_of_s_aa[ s ] = id;
    
    return id;
  }

};
