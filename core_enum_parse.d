module d_glat_common.core_enum_parse;

import std.algorithm;
import std.array;
public import std.exception;

/*
   
  Declare an `enum` (called `enum_name`) and a string parser for it
  (called `parse_method_name`).
  
  
  Example:

    mixin( enum_parse_code( "SomeEnum", "parse_some_enum_str"
                            , "some_enum_name_list"
                            , [ "aaa", "bbb", "ccc", "ddd" ] ) );

  equivalent to:

   immutable some_enum_name_list = [ "aaa", "bbb", "ccc", "ddd" ];

   enum SomeEnum : int {aaa,bbb,ccc,ddd}
  
   SomeEnum parse_some_enum_str( in string s ) pure
    {
      switch (s)
        {
          case "aaa": return SomeEnum.aaa;
          case "bbb": return SomeEnum.bbb;
          case "ccc": return SomeEnum.ccc;
          case "ddd": return SomeEnum.ddd;
          
          default: enforce(false,
               "Unknown method name \""~s~"\"."
               ~" Valid names are: aaa, bbb, ccc, ddd"
               );
            }

      assert(0); // never reached
    }
  
  By Guillaume Lathoud
  glat@glat.info
  
  Distributed under the Boost License, see file ./LICENSE
*/

string enum_parse_code( in   string   enum_name
                        , in string   parse_method_name
                        , in string   s_arr_name
                        , in string[] s_arr ) pure
{
  string s_arr_c = s_arr.map!(a => `"`~a.replace(`"`, `\"`)~`"`)
.join(", ");
  
  return `
  immutable `~s_arr_name~` = [ `~s_arr_c~` ];

  enum `~enum_name~` : int {`~s_arr.join(",")~`}
  
  `~enum_name~` `~parse_method_name~`( in string s ) pure
    {
      switch (s)
        {
          `~s_arr
            .map!( m_s =>
                   `case "`~m_s~`": return `~enum_name~`.`~m_s~`;`
                   )
            .join( "\n" )~`

default: enforce(false,
               "Unknown method name \""~s~"\"."
               ~" Valid names are: `~s_arr.join( ", " )~`"
               );
            }

      assert(0); // never reached
    }
  `;
}

unittest
{
  import std.stdio;
  import std.path;

  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  {
     // pragma(msg, enum_parse_code( "SomeEnum", "parse_some_enum_str" , "some_enum_name_list" , [ "aaa", "bbb", "ccc", "ddd" ] ));

    mixin( enum_parse_code( "SomeEnum", "parse_some_enum_str"
                            , "some_enum_name_list"
                            , [ "aaa", "bbb", "ccc", "ddd" ] ) );

    auto a = SomeEnum.aaa;
    auto b = SomeEnum.bbb;
    auto c = parse_some_enum_str( "ccc" );

    assert( a != b ); assert( a != c ); assert( a != SomeEnum.ddd );
    assert( b != c );
    
    {
      bool failure = false;
      try
        {
          auto z = parse_some_enum_str( "zzz" );
        }
      catch (Exception e)
        {
          failure = true;
        }
      assert( failure );
    }

  }
  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
