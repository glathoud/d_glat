module d_glat.core_param_restriction;

import d_glat.core_assoc_array;
import std.array : appender, array, split;
import std.exception : assumeUnique, enforce;
import std.math : isNaN;
import std.conv : to, ConvException;
import std.traits; // xxx : isCallable, isNumeric;

/*
  Parameter restriction : verify that parameter values are within
  expected ranges of numbers/lists of numbers or strings.

  Use at your own risk. Boost license, see file ./LICENSE

  Guillaume Lathoud, 2023 and later
  glat@glat.info
*/

alias ParamRestrictionAll  = ParamRestriction!true;
alias ParamRestrictionSome = ParamRestriction!false;

class ParamRestriction(bool check_all = true)
{
  NumberTester[string] number_testers;
  StringTester[string] string_testers;
  
  this( in string spec )
    /* parse `spec`. Examples:
       
       ""  
       "v0^..0.007_zz^20..80" // defines name "v0" with range ..0.007, and name "zz" with range 20..80
       "abq^20..40^60..80" 
       "rpi^1^2^3^5^8^11^20..30"  // match isolated values and one range 20..30
       "sp^ab^ew^gor12^325__other^1..^-1e4..10^121^-34..-11.123"  // "sp" has string values

       Notes:

       "20..40" means "from 20 included to 40 included".
       
       At the (lower) value level: OR

       "abq^20..40^60..80" means "for parameter abq, accept values
       from 20 to 40 *OR* from 60 to 80.

       At the (higher) test level: AND
       
       "sp^ab^ew^gor12^325__other^1..^-1e4..10^121^-34..-11.123"
       defines two tests, on "sp" and on "other". AND: both tests must
       succeed.
    */
    {
      foreach (one; spec.split( "_" ))
        {
          if (0 < one.length)
            parse_one( one );
        }
    }
  
  void parse_one( in string s )
  {
    scope auto arr = assumeUnique( s.split( "^" ).array );
    immutable name = arr[ 0 ];
    try
      {
        // number values
        scope auto ab_app = appender!(NumberAB[]);
        foreach (s_ab; arr[ 1..$ ])
          {
            scope auto ab2 = assumeUnique( s_ab.split( ".." ).array );
            if (ab2.length == 1) // single value
              {
                immutable v = to!double( ab2[ 0 ] );
                ab_app.put( NumberAB( v, v ) );
              }
            else if (ab2.length == 2) // range from..to, omit one for "open-ended" interval
              {
                immutable sa = ab2[ 0 ];
                immutable sb = ab2[ 1 ];
                immutable a = sa.length == 0  ?  double.nan  :  to!double( sa );
                immutable b = sb.length == 0  ?  double.nan  :  to!double( sb );
                ab_app.put( NumberAB( a, b ) );
              }
            else
              {
                throw new ConvException("Fallback to StringTester");
              }
          }
        scope NumberTester nt = {ab_arr : ab_app.data};
        enforce( name !in number_testers, new Exception( "NumberTester already defined for "~name ) );
        number_testers[ name ] = nt;
      }
    catch (ConvException e)
      {
        // string values
        scope StringTester st = {s_set : aa_set_of_array( arr[ 1..$ ] )};
        enforce( name !in string_testers, new Exception( "StringTester already defined for "~name ) );
        string_testers[ name ] = st;
      }
  }
};


bool matches(alias modifier_fun = false, bool check_all = true, T)
  ( in ParamRestriction!check_all param_tester, in T name_v_aa )
// xxx todo: add support for lambda modifier_fun (for some reason not
// working yet - so for now you have to e.g. declare a real function)
{
  with (param_tester)
    {
      static if (check_all)
        {
          // The names in `spec` must all be present in `name_v_aa`.
          static foreach(TESTERS; ["number_testers", "string_testers"])
          {
            foreach (name, ref tester; mixin(TESTERS))
              {
                auto p = name in name_v_aa;
                if (p is null)
                  return false;
              
                if (!tester.test( mixin(isCallable!modifier_fun  ?  "modifier_fun( *p )" : "*p") ))
                  return false; // AND: all tests must succeed
              }
          }
        }
      else
        {
          // Only check the available names of `name_v_aa`. They don't
          // have to cover all names of `number_test` and `string_test`.
          foreach (name, ref v; name_v_aa)
            {
              if (auto pnt = name in number_testers)
                {
                  if (!pnt.test( mixin(isCallable!modifier_fun  ?  "modifier_fun( v )" : "v") ))
                    return false; // AND: all tests must succeed
                }
              else if (auto pst = name in string_testers)
                {
                  if (!pst.test( mixin(isCallable!modifier_fun  ?  "modifier_fun( v )" : "v") ))
                    return false; // AND: all tests must succeed
                }
            }
        }
    }
  return true;
}




struct NumberAB { double a, b; };
  
struct NumberTester
{
  NumberAB[] ab_arr;
  
  bool test( in string s ) const 
  {
    double v;
    try
      {
        v = to!double( s );
      }
    catch (ConvException e)
      {
        return false;
      }

    return test( v );
  }

  bool test(T)( in T v ) const if(isNumeric!T)
  {
    foreach (ref ab; ab_arr)
      {
        // `double.nan` value means "open-ended"
        if ((isNaN( ab.a )  ||  ab.a <= v)
            &&  (isNaN( ab.b )  ||  v <= ab.b))
          {
            return true; // OR: one match is enough
          }
      }
    return false; // ..but at least one must match
  }
};

struct StringTester
{
  bool[string] s_set;

  bool test( in string s ) const
  {
    return s_set.get( s, false );
  }

  bool test(T)( in T v ) const if(isNumeric!T)
  {
    return false;
  }
};


unittest
{
  import std.array;
  import std.path;
  import std.string;
  import std.stdio;
  
  immutable verbose = false;
  
  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  {
    immutable spec = "";
    const pt = new ParamRestrictionAll( spec );

    string[string] name_v_aa = ["abc":"123", "def":"xyz"];
    assert( pt.matches( name_v_aa ) );
  }

  {
    immutable spec = "v0^..0.007_zz^20..80";
    const pt = new ParamRestrictionAll( spec );

    if (verbose)
        writeln( spec, " pt:", pt );
    
    {
      string[string] name_v_aa = ["abc":"123", "def":"xyz"];
      assert( !pt.matches( name_v_aa ) );
    }

    {
      assert( !pt.matches( ["abc":"123", "def":"xyz"] ) );
      assert( !pt.matches( ["abc":123, "def":456] ) );
      assert( !pt.matches( ["abc":cast(double)(123.0), "def":cast(double)(456.0)] ) );

      assert( pt.matches( ["abc":123, "def":456, "v0":0.005, "zz":60] ) );
      assert( pt.matches( ["abc":"123", "def":"456", "v0":"0.005", "zz":"60"] ) );

      assert( !pt.matches( ["abc":123, "def":456, "v0":0.009, "zz":60] ) );
      assert( !pt.matches( ["abc":"123", "def":"456", "v0":"0.009", "zz":"60"] ) );

      assert( !pt.matches( ["abc":123, "def":456, "v0":0.005, "zz":100] ) );
      assert( !pt.matches( ["abc":"123", "def":"456", "v0":"0.005", "zz":"100"] ) );

      assert( !pt.matches( ["abc":123, "def":456, "v0":0.005 ] ) );
      assert( !pt.matches( ["abc":"123", "def":"456", "v0":"0.005"] ) );
    }
  }

  {
    immutable spec = "v0^..0.007_zz^20..80";
    const pt = new ParamRestrictionSome( spec );
    
    {
      assert( pt.matches( ["abc":"123", "def":"xyz"] ) );
      assert( pt.matches( ["abc":123, "def":456] ) );
      assert( pt.matches( ["abc":cast(double)(123.0), "def":cast(double)(456.0)] ) );

      assert( pt.matches( ["abc":123, "def":456, "v0":0.005, "zz":60] ) );
      assert( pt.matches( ["abc":"123", "def":"456", "v0":"0.005", "zz":"60"] ) );

      assert( !pt.matches( ["abc":123, "def":456, "v0":0.009, "zz":60] ) );
      assert( !pt.matches( ["abc":"123", "def":"456", "v0":"0.009", "zz":"60"] ) );

      assert( !pt.matches( ["abc":123, "def":456, "v0":0.005, "zz":100] ) );
      assert( !pt.matches( ["abc":"123", "def":"456", "v0":"0.005", "zz":"100"] ) );

      assert( pt.matches( ["abc":123, "def":456, "v0":0.005 ] ) );
      assert( pt.matches( ["abc":"123", "def":"456", "v0":"0.005"] ) );
    }
  }

  {
    immutable spec = "abq^20..40^60..80";
    const pt = new ParamRestrictionAll( spec );

    {
      assert( !pt.matches(["abc":"123"]));
      assert( !pt.matches(["abc":123]));
      assert( !pt.matches(["abc":123, "abq":10]));
      assert( !pt.matches(["abc":123, "abq":19]));
      assert( pt.matches(["abc":123, "abq":20]));
      assert( pt.matches(["abc":123, "abq":30]));
      assert( pt.matches(["abc":"123", "abq":"40"]));
      assert( !pt.matches(["abc":123, "abq":41]));
      assert( !pt.matches(["abc":123, "abq":50]));
      assert( !pt.matches(["abc":123, "abq":59]));
      assert( pt.matches(["abc":123, "abq":60]));
      assert( pt.matches(["abc":"123", "abq":"70"]));
      assert( pt.matches(["abc":123.0, "abq":80.0]));
      assert( !pt.matches(["abc":123, "abq":90]));
    }
  }

  {
    immutable spec = "rpi^1^2^3^5^8^11^20..30";  // match isolated values and one range 20..30
    const pt = new ParamRestrictionAll( spec );

    assert( !pt.matches( ["rpi":0.0] ) );
    assert( pt.matches( ["rpi":1.0] ) );
    assert( pt.matches( ["rpi":1] ) );
    assert( !pt.matches( ["rpi":1.1] ) );
    assert( pt.matches( ["rpi":3.0] ) );
    assert( pt.matches( ["rpi":11.0] ) );
    assert( !pt.matches( ["rpi":"12"] ) );
    assert( !pt.matches( ["rpi":19.9999] ) );
    assert( pt.matches( ["rpi":"20.0"] ) );
    assert( pt.matches( ["rpi":"20"] ) );
    assert( pt.matches( ["rpi":20.0] ) );
    assert( pt.matches( ["rpi":20] ) );
    assert( pt.matches( ["rpi":20.7] ) );
    assert( pt.matches( ["rpi":"27"] ) );
    assert( pt.matches( ["rpi":"29.345"] ) );
    assert( pt.matches( ["rpi":"30"] ) );
    assert( !pt.matches( ["rpi":"30.00001"] ) );
    assert( !pt.matches( ["rpi":32] ) );
  }

  {
    const pt =  // "sp" has string values
      new ParamRestrictionSome( "sp^ab^ew^gor12^325__other^-1e4..10^121^-34..-11.123" ); 

    assert( !pt.matches( ["other":-1e5]));
    assert( pt.matches( ["other":0]));
    assert( pt.matches( ["other":"5.678"]));
    assert( pt.matches( ["other":9]));
    assert( pt.matches( ["other":"10"]));
    assert( !pt.matches( ["other":"120.5"]));
    assert( pt.matches( ["other":"121"]));
    assert( pt.matches( ["other":121]));
    assert( !pt.matches( ["other":121.0001]));
    assert( !pt.matches( ["other":122]));

    assert( pt.matches( ["sp":"ab"]));
    assert( !pt.matches( ["sp":"abc"]));
    assert( !pt.matches( ["sp":"gor"]));
    assert( pt.matches( ["sp":"gor12"]));
    assert( pt.matches( ["sp":"325"]));
    assert( !pt.matches( ["sp":325])); // 325: must be a string "325"

    assert( pt.matches( ["sp":"ab", "other": "121"]) );
    assert( pt.matches( ["sp":"325", "other": "121"]) );
    assert( !pt.matches( ["sp":325, "other": 121]) ); // 325: must be a string "325"
  }
    
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
