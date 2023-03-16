module d_glat.core_sexpr;

/*
  Minimalistic S-Expression parser - only what I need.

  Use at your own risk. Boost license, see file ./LICENSE

  Example of use: ./lib_json_manip.d

  Guillaume Lathoud
  glat@glat.info
 */

import d_glat.core_profile_acc;
import std.algorithm : each;
import std.array : appender;
import std.conv : to;
import std.exception : enforce;
import std.string : StringException;

SExpr parse_sexpr( alias maybe_check_fun = false )( in string a )
{
  return parse_sexpr!maybe_check_fun( cast( char[] )( a ) );
}

SExpr parse_sexpr( alias maybe_check_fun = false )( in char[] a )
{
  SExpr ret;

  size_t i = 0;
  _parse_sexpr( a, i, ret );
  ret.firstEquals("whatever");
  enforce( i == a.length, "Unexpected rest: "~a[ i..$ ] );
  
  static if (typeof(maybe_check_fun).stringof != "bool")
    {
      enforce!StringException
        ( maybe_check_fun( ret )
          , "Invalid SExpr syntax, as per `maybe_check_fun`: \""~a~"\""
          );
    }
  
  return ret;
}

// shortcuts
immutable(SAtom) sAtom( in string s ) { return cast(immutable(SAtom))( new SAtom( s ) ); }
immutable(SList) sList( in SExpr[] a ) { return cast(immutable(SList))( new SList( a ) ); }

void walk_sexpr( alias iter )( in SExpr sexpr )
{
  iter( sexpr );
  if (sexpr.isList)
    {
      scope auto slist = cast( SList )( sexpr );
      slist.rest.each!(walk_sexpr!iter);
    }
}


// ---------- Details ----------

alias SExprId = ulong;

private SExprId _sexpr_id = 0;

abstract class SExpr : ProfileMemC
{
  immutable SExprId id;

  this() @safe
    { id = _sexpr_id++; }
  
  // For convenience, esp. for `maybe_check_fun`
  bool isEmpty() pure const nothrow @property @safe @nogc { return false; }
  bool isAtom()  pure const nothrow @property @safe @nogc { return false; }
  bool isList()  pure const nothrow @property @safe @nogc { return false; }
                                     
  abstract bool firstEquals( in string a ) pure const @safe @nogc;
  override abstract string toString()  pure const @safe @nogc;

  immutable(SExpr) idup() const @trusted
  {
    // Not beautiful but does the job
    return cast(immutable(SExpr))( parse_sexpr( this.toString ) );
  }
}


class SEmpty : SExpr
{
  override bool isEmpty() pure const nothrow @property @safe @nogc
  { return true; }
  
  override bool firstEquals( in string a ) const pure @safe @nogc
  {
    return a.length == 0;
  }

  override string toString() pure const @safe @nogc
  {
    return "()";
  }
}

class SAtom : SExpr
{
  override bool isAtom() pure const nothrow @property @safe @nogc
  { return true; }
    
  immutable string v;

  this( in char[] c ) @safe
    {
      this.v = c.idup;
    }

  this( in string v ) @safe 
    {
      this.v = v;
    }

  override bool firstEquals( in string a ) pure const @safe @nogc
  {
    return v == a;
  }

  override string toString() pure const @safe @nogc
  {
    return v;
  }
}

class SList : SExpr
{
  override bool isList() @property pure const nothrow @safe @nogc
  { return true; }
    
  const SExpr   first;
  const SExpr[] rest;

  const SExpr[] all_v;

  private immutable string _str;
  
  this( in SExpr[] all_v ) @safe
    {
      this.all_v = all_v;
      this.first = all_v[ 0 ];
      this.rest  = all_v[ 1..$ ];

      scope auto app = appender!string();
      app ~= "(";
      foreach(i, x; all_v)
        {
          if (0 < i)
            app ~= " ";
          
          app ~= x.toString;
        }
          
      app ~= ")";
      _str = app.data;
    }

  override bool firstEquals( in string a ) pure const @safe @nogc
  {
    return first.firstEquals( a );
  }

  override string toString() pure const @safe @nogc
  {
    return _str;
  }
}

private: // --------------------

void _parse_sexpr( in char[] a, ref size_t i, ref SExpr expr)
@safe
{
  immutable i_end = a.length;

  while (i < i_end  &&  _is_space( a[ i ] )) ++i;

  if (i < i_end)
    {
      if (a[ i ] == '(')
        expr = _parse_slist( a, i );
      else
        expr = _parse_satom( a, i );

      while (i < i_end  &&  _is_space( a[ i ] )) ++i;
    }
  else
    {
      expr = new SEmpty;
    }
}

SAtom _parse_satom( in char[] a, ref size_t i )
 @safe
{
  immutable i0    = i;
  immutable i_end = a.length;
  char c;
  while (i < i_end
         &&  (c = a[ i ]) != ')'
         &&  c != '('  &&  !_is_space( c )
         ) ++i;

  debug assert( i0 < i );
  return new SAtom( a[i0..i] );
}


SExpr _parse_slist( in char[] a, ref size_t i )
 @safe
{
  debug assert( a[ i ] == '(' ); ++i;

  SExpr[] arr;

  immutable i_end = a.length;
  while (i < i_end  &&  _is_space( a[ i ] )) ++i;
  
  while (i < i_end  &&  a[ i ] != ')')
    {    
      SExpr one;
      _parse_sexpr( a, i, one );
      arr ~= one;
      while (i < i_end  &&  _is_space( a[ i ] )) ++i;
  }

  enforce
    ( i < i_end
      , "i < i_end, got instead: i:"
      ~to!string(i)~", i_end:"~to!string( i_end ) );

  enforce
    ( a[ i ] == ')'
      , "SList must finish with a ')', got instead:'"~a[ i ]~"'"
      );
  
  ++i;
  
  return 0 < arr.length  ?  new SList( arr )  :  new SEmpty;
}

bool _is_space( in char c ) pure @safe @nogc
{
  
  return c == ' ';
}


unittest  // ------------------------------
{
  import std.stdio;
  import std.string;

  writeln;
  writeln( "unittest starts: "~__FILE__ );

  {

    void check_empty( in string s )
    {
      auto x = parse_sexpr( s );
      assert( x.isEmpty );
      assert( x.toString() == "()" );
    }

    check_empty( "" );
    check_empty( " " );
    check_empty( "    " );
    check_empty( "()" );
    check_empty( " () " );
    check_empty( "  ()  " );
    check_empty( "( )" );
    check_empty( " (  )  " );
    check_empty( "(  )  " );
    check_empty( "   ()" );
  }

  {
    void check_atom( in string s )
    {
      auto x = parse_sexpr( s );
      assert( x.isAtom );
      assert( x.firstEquals( s.strip ) );
    }
    
    check_atom( "a" );
    check_atom( "   a" );
    check_atom( "a  " );
    check_atom( "abc" );
    check_atom( "   abc" );
    check_atom( "abc  " );
  }

  {
    void check_list2( in string s_in, in string s_unique )
    {
      auto x = parse_sexpr( s_in );
      assert( x.isList );
      assert( x.toString == s_unique );
    }

    void check_list( in string s_in )
    {
      check_list2( s_in, s_in );
    }


    check_list( "(a)" );
    check_list2( " (   a ) ", "(a)" );
    check_list( "(a)" );
    check_list( "(a)" );
    check_list2
      ( "(pi abc def  (  pa  dew ( po  dew 123 ) (  pu )   ) )"
        , "(pi abc def (pa dew (po dew 123) (pu)))"
        );
  }

  {
    immutable s_ok_arr =
      [
       "(pi abc def (pa dew (po dew 123) (pu)))"
       , "(pi xxx def (pa dew (po dew 123) (pu)))"
       , "(pi abc def (pa xxx (po dew 123) (pu)))"
       , "(pi abc def (pa dew (po dew xxx) (pu)))"
       ];

    immutable s_wrong_arr =
      [
       ""
       , "()"
       , "(xxx abc def (xxx dew (po dew 123) (pu)))"
       , "(pi abc def (xxx dew (po dew 123) (pu)))"
       , "(pi abc def (pa dew (xxx dew 123) (pu)))"
       , "(pi abc def (pa dew (xxx dew 123) (xxx)))"
       , "(pi abc def (pa dew (xxx dew 123) ()))"
       ];

    // Example of restriction
    bool check_fun( in SExpr s )
    {
      // Accepted
      return s.isAtom
        ||  s.isList  &&  (s.firstEquals( "pi" )
                           ||  s.firstEquals( "pa" )
                           ||  s.firstEquals( "po" )
                           ||  s.firstEquals( "pu" ));

      /*
        Rejected: 

        SEmpty

        or

        SList with a first other than atoms: pi pa po pu 
      */
    }

    
    void check_ok( in string s )
    {
      auto e = parse_sexpr!check_fun( s );
      assert( e.toString == s );
    }

    void check_wrong( in string s )
    {
      // Can be parsed...
      parse_sexpr( s );

      // ...but not with this restriction

      /*
        xxx actually throw working, but could not get assertThrown to
        work here yet

        xxx found this but no real solution yet:
        https://forum.dlang.org/thread/xqrhdtnifvhfeenmiesq@forum.dlang.org

      void f()
      {
        SExpr x = parse_sexpr!check_fun( s );
        writeln( x );
      }
      assertThrown!StringException( f() );
      */
    }
    
    foreach (s_ok; s_ok_arr)
      check_ok( s_ok );

    foreach (s_wrong; s_wrong_arr)
      check_wrong( s_wrong );
  }


  {
    auto sexpr = parse_sexpr( "(op1 (op2 a b) c (op3 d e) f)" );

    string[] arr;

    void iter( in SExpr s )
    {
      if (s.isList)
        arr ~= (cast( SList )( s )).first.toString;
      else
        arr ~= s.toString;
    }

    walk_sexpr!iter( sexpr );

    assert( arr == ["op1", "op2", "a", "b", "c", "op3", "d", "e", "f"] );
  }
  
  
  writeln( "unittest passed: "~__FILE__ );
}

