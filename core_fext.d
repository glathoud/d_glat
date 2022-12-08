module d_glat.core_fext;

/*
  Fast Explicit Tail Calls for the D language
  
  This library offers a function `mdecl` to generate optimized code
  out of function declarations and bodys. Tail calls should be
  explicitely marked with `return mret!fun(a,b,c)` and will be
  replaced (Tail Call Elimination - TCE).

  Mutual recursion is supported.  

  For examples, see the unit tests further below.

  Debugging: instead of `mdecl`, `mdeclD` can be used to deactivate
  TCE for easier debugging.
  
  Note: this library follows closely the idea of fext.js
  http://glat.info/fext
  
  The Boost License applies, as described in the file ./LICENSE
  
  By Guillaume Lathoud, 2019
  glat@glat.info
*/

import std.algorithm.searching : findSplit;

import std.algorithm : all,each,filter,map;
import std.array;
import std.conv : to;
import std.exception : enforce;
import std.range : zip;
import std.string : strip;

alias StringArr = string[];
alias ArgOfName = StringArr[string];

alias StringSet = bool[string];
alias ArgsetOfName = StringSet[string];

alias mdeclD = mdecl!true;

string mdecl( bool fext_debug = false )(in string[] arr ...) pure 
// TCE (Tail Call Elimination) when `fext_debug==false`
// Original, unmodified code when `fext_debug==true`
{
  assert(arr.length>1, "At least one function declaration needed");
  assert(0 == arr.length % 2, "[decl,body, decl,body, ... ]");

  scope string[] name_arr;
  scope string[string] decl_of_name;
  scope ArgOfName arg_of_name;
  scope ArgsetOfName argset_of_name;
  scope string[string] argtype_of_argname;
  
  alias BlockArr = Block!fext_debug[];
  alias BlockArrOfName = BlockArr[string];

  scope BlockArrOfName block_arr_of_name;

  immutable top_switch_label = "_fext_";

  void check_set_argtype( in string argname, in string argtype )
  {
    if (auto p = argname in argtype_of_argname)
      {
        assert( *p == argtype, "Same argument names must have the same type, or use a different name. Argname: `"~argname
                ~"`, conflicting types: `"~(*p)~"` and `"~argtype~"`." );
      }
    else
      {
        argtype_of_argname[ argname ] = argtype;
      }
  }

  string drop_dflt_init( in string s ) pure @safe
  {
    if (auto x = s.findSplit( "=" ))
      return x[ 0 ].strip;

    return s;
  }

  
  
  for (size_t i = 0, i_end = arr.length; i < i_end; )
    {
      scope string decl = arr[ i++ ];
      scope string body = arr[ i++ ];

      string   name;
      scope string[] arg;
      {
        scope auto x = decl.findSplit( "(" );
        name = x[ 0 ].strip.split( " " )[ $-1 ];

        scope auto x2 = x[ 2 ];
        immutable size_t close_paren = (){
          foreach_reverse( j,c; x2 )
            {
              if (c == ')')
                  return j;
            }
          return size_t.max;
        }();

        immutable size_t open_paren = (){
          size_t encaps = 1;
          foreach_reverse (j,c; x2[ 0..close_paren ])
          {
            if (c == ')')
              ++encaps;

            else if (c == '('  &&  --encaps == 0)
              return j+1;
          }
          return 0;
        }();

        assert( close_paren < size_t.max );
        assert( open_paren < close_paren, to!string(open_paren)~" "~to!string(close_paren)~" \n"~x2~" \n"~x2[open_paren..close_paren] );

        scope auto raw_arg = x2[ open_paren..close_paren ]
          .split( "," )
          .map!drop_dflt_init
          ;
        
        arg = raw_arg.map!`a.strip.split( " " )[ $-1 ]`.array;

        
        scope auto argtype = raw_arg.map!`a.strip.split( " " )[ $-2 ]`.array;

        zip( arg,argtype ).each!( x => check_set_argtype( x[ 0 ], x[ 1 ] ) );
      }

      
      name_arr ~= name;
      decl_of_name[ name ] = decl;
      arg_of_name[ name ] = arg;

      arg.each!( x => argset_of_name[ name ][ x ] = true );
      
      Block!fext_debug[] block_arr;
      
      string rest_body = body;
      while (true)
        {
          if (scope auto split = rest_body.findSplit("return mret!"))
            {
              string before = split[ 0 ];
              
              scope auto paren = split[ 2 ].findSplit("(");
              
              scope auto mret_name = paren[ 0 ];
              
              scope auto param = paren[ 2 ].findSplit( ");" );
              
              scope string mret_param = param[ 0 ];
              
              rest_body = param[ 2 ];
              
              block_arr ~= Block!fext_debug( top_switch_label, arg_of_name, before, mret_name, mret_param );
              
              continue;
            }
          
          block_arr ~= Block!fext_debug( top_switch_label, arg_of_name, rest_body, "", "" );
          
          rest_body = "";
          
          break;
        }
      
      enforce( rest_body.all!`a==' ' || a=='\n'`, rest_body );

      block_arr_of_name[ name ] = block_arr;
    }

  scope auto decl = decl_of_name[ name_arr[ 0 ] ];

      
  immutable SWITCH_I = "_switch_i_";

  immutable selfrec = 1 == name_arr.length;
  
  return fext_debug
    
    ? name_arr.map!
    (name => decl_of_name[ name ]~"{\n"
     ~(block_arr_of_name[ name ].map!"a.toString()".join( " " ))
     ~"}").join("\n")
    
    : name_arr.map!
    (name => decl_of_name[ name ]~"{\n"
     ~(arg_of_name[ name ].length < 2
       // Single argument => no need for intermediary variables
       ? ""
       // Multiple arguments => intermediary variables
       : arg_of_name[ name ].map!(x => argtype_of_argname[x]~" "~_fext_arg(x)~"; ").join("")
       )
     ~(argtype_of_argname
       .keys
       .filter!(x => !(x in argset_of_name[ name ]))
       .map!(x => argtype_of_argname[x]~" "~x~", "~_fext_arg(x)~"; ")
       .join(""))

     ~(selfrec

       // Self-recursion
       
       ? "while (true) { "
       ~block_arr_of_name[ name_arr[ 0 ] ].map!"a.toString".join( " " )
       ~" assert(false,`all must end with a tail call`);"
       ~" break;"
       ~"}"

       // Mutual recursion
       
       : "enum _FextCase_ { "~([name] ~ (name_arr.filter!(x => x != name).array)).map!( x => _fext_case( x ) ).join( "," )~" } "
       ~"auto "~SWITCH_I~" = _FextCase_."~_fext_case(name)~"; "
       ~top_switch_label~": final switch( "~SWITCH_I~" ) {\n"
       ~(map!( name => "  case _FextCase_."~_fext_case(name)~": "
               ~(block_arr_of_name[ name ].map!"a.toString".join( " " ))
               ~" assert(false,`all must end with a tail call`);"
               ~" break;"
               )
         (name_arr)
         )
       .join("\n")
       ~"}"
       )
     
     ~"assert( false, `bug` );}"
     ).join( "\n" )
    ;
}

private struct Block( bool fext_debug )
{
  immutable string   top_switch_label;
  const ArgOfName    arg_of_name; // Populate `arg_of_name` with all dependencies (e.g. mutual recursion), then later call .toString
  immutable string   before;
  immutable string   mret_name;  // Optional
  immutable string   mret_param; // Optional

  private string _str;
  
  
  string toString() pure
  {
    if (0 == _str.length)
      {
        immutable bool selfrec = 1 == arg_of_name.keys.length;
    
        scope auto ap = appender!(string[]);

        ap.put( before );

        immutable has_name = 0 < mret_name.length;
        if (!has_name)
          {
            enforce( 0 == mret_param.length );
          }
        else
          {
            scope auto impl_arg = arg_of_name[ mret_name ];
            scope auto mret_arg = mret_param.split( "," );
            
            enforce( mret_arg.length == impl_arg.length );
            
            static if (fext_debug)
              {
                ap.put( "return "~mret_name~"("~mret_param~");");
              }
            else
              {
                ap.put( "/* return mret!"~mret_name~"("~mret_param~"); */ {" );

                if (mret_arg.length < 2)
                  {
                    // Single argument => no need for intermediary variables

                    
                    foreach (i,impl_one; impl_arg)
                      ap.put( impl_one~" = "~mret_arg[i]~"; " );
                  }
                else
                  {
                    // Multiple arguments => intermediary variables

                    foreach (i,impl_one; impl_arg)
                      ap.put( _fext_arg( impl_one )~" = "~mret_arg[i]~"; " );
                    
                    foreach (i,impl_one; impl_arg)
                      ap.put( impl_one~" = "~_fext_arg( impl_one )~"; " );
                  }

                if (selfrec)
                  ap.put( "continue;" );
                else
                  ap.put( "goto case _FextCase_."~_fext_case(mret_name)~";" );
                
                ap.put( "}" );
              }
          }
        
        _str = ap.data().join("");
      }

    return _str;
  }

}

private string _fext_arg( in string arg ) pure { return "_"~arg~"_"; }

private string _fext_case( in string arg ) pure { return arg; }




unittest // --------------------
{
  import std.stdio;
  
  immutable verbose = false;
  
  writeln;
  writeln( "unittest starts: "~__FILE__ );

  // Self-recursion

  int gcdrec( in int a, in int b ) pure nothrow @safe @nogc
  {
    if (a > b) return gcdrec( a-b, b );
    if (b > a) return gcdrec( b-a, a );
    return a;
  }


  // mixin(mdeclD("int gcd(int a, int b) pure nothrow @safe @nogc",
  mixin(mdecl(`int gcd(int a, int b) pure nothrow @safe @nogc`,
              q{
                if (a > b) return mret!gcd( a-b, b );
                if (b > a) return mret!gcd( b-a, a );
                return a;
              }));



  // Self-recursion with default argument value

  mixin(mdecl(`T[] iota( T )( T begin, T end, Appender!(T[]) ap = appender!(T[]) ) pure nothrow @safe`,
              q{
                if (begin >= end)
                  return ap.data;
             
                ap.put( begin );
                return mret!iota( begin+1, end, ap );
              }
              ));

  // Mutual recursion

  /+
  int isoddrec( in int a ) pure nothrow @safe @nogc
  {
    if (a < 0) return isoddrec( -a );
    if (a > 0) return isevenrec( a-1 );
    return false;
  }

  int isevenrec( in int a ) pure nothrow @safe @nogc
  {
    if (a < 0) return isevenrec( -a );
    if (a > 0) return isoddrec( a-1 );
    return true;
  }

  assert( [-3, -1, 1, 3].all!isoddrec );
  assert( [-4, -2, 0, 2, 4].all!isevenrec );
  assert( [-3, -1, 1, 3].all!(a => !isevenrec(a)) );
  assert( [-4, -2, 0, 2, 4].all!(a => !isoddrec(a)) );
  +/

  // mixin(mdeclD("int isodd(int a) pure nothrow @safe @nogc",
  mixin(mdecl(`int isodd(int a) pure nothrow @safe @nogc`,
              q{
                if (a < 0) return mret!isodd( -a );
                if (a > 0) return mret!iseven( a-1 );
                return false;
              }
              ,`int iseven( int a ) pure nothrow @safe @nogc`,
              q{
                if (a < 0) return mret!iseven( -a );
                if (a > 0) return mret!isodd( a-1 );
                return true;
              }
              ));



  // Test with different argument names

  // mixin(mdeclD(`int isodd2(int a) pure nothrow @safe @nogc`,
  mixin(mdecl(`int isodd2(int a) pure nothrow @safe @nogc`,
              q{
                if (a < 0) return mret!isodd2( -a );
                if (a > 0) return mret!iseven2( a-1 );
                return false;
              }
              ,`int iseven2( int b ) pure nothrow @safe @nogc`,
              q{
                if (b < 0) return mret!iseven2( -b );
                if (b > 0) return mret!isodd2( b-1 );
                return true;
              }
              ));

  if (verbose)
    {
      writeln;
      writeln("-- Self-recursion --");
      
      writeln;
      writeln("mdecl:");
      writeln(mdecl("int gcd(int a, int b) pure nothrow @safe @nogc",
                    q{
                      if (a > b) return mret!gcd( a-b, b );
                      if (b > a) return mret!gcd( b-a, a );
                      return a;
                    }));
      
      writeln;
      writeln("mdeclD:");
      writeln(mdeclD("int gcd(int a, int b) pure nothrow @safe @nogc",
                     q{
                       if (a > b) return mret!gcd( a-b, b );
                       if (b > a) return mret!gcd( b-a, a );
                       return a;
                     }));
    }
  
  assert( 3*5 == gcdrec( 2*3*5*17, 3*5*19 ) );

  assert( 3*5 == gcd( 2*3*5*17, 3*5*19 ) );

  if (verbose)
    {
      writeln;
      writeln( "-- Self-recursion with default argument value --");
      
      writeln;
      writeln(mdecl(`T[] iota( T begin, T end, Appender!(T[]) ap = appender!(T[]) ) pure nothrow @safe`,
                    q{
                      if (begin >= end)
                        return ap.data;
                      
                      ap.put( begin );
                      return mret!iota( begin+1, end, ap );
                    }
                    ));

      writeln(iota(0,10));
    }
    
  assert( iota(0,10) == [0,1,2,3,4,5,6,7,8,9]);


  if (verbose)
    {
      writeln;
      writeln("-- Mutual recursion --");
      
      writeln;
      writeln("mdecl:");
      writeln(mdecl(`int isodd(int a) pure nothrow @safe @nogc`,
                    q{if (a < 0) return mret!isodd( -a );
                      if (a > 0) return mret!iseven( a-1 );
                      return false;
                    }
                    ,`int iseven( int a ) pure nothrow @safe @nogc`,
                    q{if (a < 0) return mret!iseven( -a );
                      if (a > 0) return mret!isodd( a-1 );
                      return true;
                    }
                    ));

  
      writeln;
      writeln("mdeclD:");
      writeln(mdeclD(`int isodd(int a) pure nothrow @safe @nogc`,
                     q{if (a < 0) return mret!isodd( -a );
                       if (a > 0) return mret!iseven( a-1 );
                       return false;
                     }
                     ,`int iseven( int a ) pure nothrow @safe @nogc`,
                     q{if (a < 0) return mret!iseven( -a );
                       if (a > 0) return mret!isodd( a-1 );
                       return true;
                     }
                     ));
    }  

    // assert( isoddrec(999999999)); // Segmentation fault (core dumped)

  assert( [-3, -1, 1, 3].all!isodd );
  assert( [-4, -2, 0, 2, 4].all!iseven );
  assert( [-3, -1, 1, 3].all!(a => !iseven(a)) );
  assert( [-4, -2, 0, 2, 4].all!(a => !isodd(a)) );

  assert( isodd(999999999) ); // No problem with `mdecl`, but with `mdeclD`: Segmentation fault (core dumped)

  if (verbose)
    {
      writeln;
      writeln( "-- Mutual recursion with different argument names --" );

      writeln;
      writeln("mdecl:");
      writeln(mdecl(`int isodd2(int a) pure nothrow @safe @nogc`,
                    q{
                      if (a < 0) return mret!isodd2( -a );
                      if (a > 0) return mret!iseven2( a-1 );
                      return false;
                    }
                    ,`int iseven2( int b ) pure nothrow @safe @nogc`,
                    q{
                      if (b < 0) return mret!iseven2( -b );
                      if (b > 0) return mret!isodd2( b-1 );
                      return true;
                    }
                    ));

      writeln;
      writeln("mdeclD:");
      writeln(mdeclD(`int isodd2(int a) pure nothrow @safe @nogc`,
                     q{
                       if (a < 0) return mret!isodd2( -a );
                       if (a > 0) return mret!iseven2( a-1 );
                       return false;
                     }
                     ,`int iseven2( int b ) pure nothrow @safe @nogc`,
                     q{
                       if (b < 0) return mret!iseven2( -b );
                       if (b > 0) return mret!isodd2( b-1 );
                       return true;
                     }
                     ));
    }
  
  assert( [-3, -1, 1, 3].all!isodd2 );
  assert( [-4, -2, 0, 2, 4].all!iseven2 );
  assert( [-3, -1, 1, 3].all!(a => !iseven2(a)) );
  assert( [-4, -2, 0, 2, 4].all!(a => !isodd2(a)) );

  assert( isodd2(999999999) ); // No problem with `mdecl`, but with `mdeclD`: Segmentation fault (core dumped)

  writeln( "unittest passed: "~__FILE__ );

}
