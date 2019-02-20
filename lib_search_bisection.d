module d_glat.lib_search_bisection;

import std.math;
import std.stdio;

/**
   Convenience wrapper for the T=string use case.

   Useful e.g. to replace an associative array with key type string
   with a flat, sorted array and bisection, especially for large
   sizes, in which as of 2018-10 the associative array eats too much
   RAM.
   
   Guillaume Lathoud
   glat@glat.info

   Distributed under the Boost License, see file ./LICENSE
*/

bool search_bisection_string
( alias fun, T = string
  , alias T_prop_between_code = (sv,sav,sbv) => `0.5`
  , alias T_equal_code = (sa,sb) => `(`~sa~`)`~`==(`~sb~`)`
  , alias T_le_code    = (sa,sb) => `(`~sa~`)`~`<=(`~sb~`)`
  , alias T_lt_code    = (sa,sb) => `(`~sa~`)`~`<(`~sb~`)`
  )
  ( in T v, in ulong a0, in ulong b0
    , out size_t ind0, out size_t ind1, out double prop )
{
  return search_bisection!( fun, T, T_prop_between_code, T_equal_code, T_le_code, T_lt_code )
    ( v, a0, b0, ind0, ind1, prop );
}

/**
   Search sorted values accessible through `fun( ulong ) -> double`
   between indices `a0` and `b0` included.

   Implementation: bisection.

   Returns `true` if found, `false` otherwise.

   Guillaume Lathoud
   glat@glat.info

   Distributed under the Boost License, see file ./LICENSE

**/

bool search_bisection
( alias fun, T = double
  , alias T_prop_between_code = (sv,sav,sbv) => `(`~sv~` - `~sav~`) / (`~sbv~` - `~sav~`)`
  , alias T_equal_code = (sa,sb) => `(`~sa~`)`~`==(`~sb~`)`
  , alias T_le_code    = (sa,sb) => `(`~sa~`)`~`<=(`~sb~`)`
  , alias T_lt_code    = (sa,sb) => `(`~sa~`)`~`<(`~sb~`)`
  )
  ( in T v, in ulong a0, in ulong b0
    , out size_t ind0, out size_t ind1, out double prop )
{
  size_t a = a0;
  size_t b = b0;

  if (a > b)
    {
      ind0 = ind1 = size_t.max;
      return false;
    }
  else if (mixin(T_lt_code( `v`, `fun( a )` )))
    {
      ind0 = ind1 = a0;
      prop = 0;
      return false;
    }
  else if (mixin(T_lt_code( `fun( b )`, `v` )))
    {
      ind0 = ind1 = b0;
      prop = 1.0;
      return false;
    }

  long bma;
  while ((bma = b - a) >= 0)
    {
      T av = fun( a );
      T bv = fun( b );

      if (mixin(T_equal_code( `av`, `v` )))
        {
          // Found exactly at one point
          ind0 = ind1 = a;
          prop = 0;
          return true;
        }
      else if (mixin(T_equal_code( `bv`, `v` )))
        {
          // Found exactly at one point
          ind0 = ind1 = b;
          prop = 0;
          return true;
        }
      else if (!(mixin(T_le_code( `av`, `v` ))  &&  mixin(T_le_code( `v`, `bv` ))))
        {
          // Not found
          break;
        }
      else if (1 == bma)
        {
          // Found between two points
          ind0 = a;
          ind1 = b;
          prop = mixin(T_prop_between_code( `v`, `av`, `bv` ));
          return true;
        }
      
      // Not found yet

      size_t m  = (a + b) >> 1;
      T mv = fun( m );

      if (a < m  &&  mixin(T_le_code( `mv`, `v` )))
        {
          a = m;
          continue;
        }

      if (m < b  &&  mixin(T_le_code( `v`, `mv` )))
        {
          b = m;
          continue;
        }
      
      break;
    }
  
  return false;
}

unittest
{
  import std.stdio;
  import std.path;

  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  {
    // Numbers
    
    double[] arr = [ -10.0, 0.0, 0.5, 5.0, 7.0, 123.0 ];

    bool   ret;
    size_t ind0, ind1;
    double prop;

    {
      ret = search_bisection
        !( a => arr[ a ] )
        ( arr[ 0 ] - 1, 0, arr.length-1
          , ind0, ind1, prop
          );
      assert( ret == false );
    }

    {
      ret = search_bisection
        !( a => arr[ a ] )
        ( arr[ $-1 ] + 1, 0, arr.length-1
          , ind0, ind1, prop
          );
      assert( ret == false );
    }

    {
      void check_in_arr_value( in size_t k, in double v )
      {
        ret = search_bisection
          !( a => arr[ a ] )
          ( v, 0, arr.length-1
            , ind0, ind1, prop
            );
        
        assert( ret == true );
        assert( ind0 == k );
        assert( ind1 >= ind0 );
        assert( prop == 0.0 );
      }

      foreach (k,v; arr)
        {
          check_in_arr_value( k, v );
        }
    }

    {
      foreach (true_prop; [ 0.2, 0.5, 0.7 ])
        {
          foreach (true_ind0; 0..arr.length-1)
            {
              auto true_ind1 = true_ind0 + 1;
              auto v = arr[ true_ind0 ] + true_prop * (arr[ true_ind1 ] - arr[ true_ind0 ]);

              ret = search_bisection
                !( a => arr[ a ] )
                ( v, 0, arr.length-1
                  , ind0, ind1, prop
                  );

              assert( ret == true );
              assert( ind0 == true_ind0 );
              assert( ind1 == true_ind1 );
              assert( 1e-10 > abs( prop - true_prop ));
            }

        }

    }

  }

  {
    // Strings

    string[][] arr = [ [ "abcde", "x0" ]
                       , [ "adert", "x1" ]
                       , [ "gtizutor", "x2" ]
                       , [ "pqwer", "x3" ]
                       , [ "zzzyyy", "x4" ]
                       ];

    bool   ret;
    size_t ind0, ind1;
    double prop;

    {
      ret = search_bisection!( a => arr[ a ][ 0 ]
                               , string
                               , (sv,avc,sbv) => `0.5`
                               )
        ( "aaa", 0, arr.length - 1
          , ind0, ind1, prop
          );

      assert( ret == false );
    }

    {
      ret = search_bisection!( a => arr[ a ][ 0 ]
                               , string
                               , (sv,avc,sbv) => `0.5`
                               )
        ( "ZZZZ", 0, arr.length - 1
          , ind0, ind1, prop
          );

      assert( ret == false );
    }

    {
      void s_check_in_arr_value( in size_t k, in string[] v )
      {
        ret = search_bisection
          !( a => arr[ a ][ 0 ]
             , string
             , (sv,avc,sbv) => `0.5`
             )
          ( v[ 0 ], 0, arr.length-1
            , ind0, ind1, prop
            );
        
        assert( ret == true );
        assert( ind0 == k );
        assert( ind1 >= ind0 );
        assert( prop == 0.0 );
      }

      foreach (k,v; arr)
        {
          s_check_in_arr_value( k, v );
        }
    }    

    {
      foreach (true_ind0; 0..arr.length-1)
        {
          auto true_ind1 = true_ind0 + 1;
          auto true_prop = 0.5;
          auto v0 = arr[ true_ind0 ][ 0 ] ~ "a";

          ret = search_bisection
            !( a => arr[ a ][ 0 ]
               , string
               , (sv,avc,sbv) => `0.5`
               )
            ( v0, 0, arr.length-1
              , ind0, ind1, prop
              );

          assert( ret == true );
          assert( ind0 == true_ind0 );
          assert( ind1 == true_ind1 );
          assert( prop == true_prop );
        }
    }


  }
  


  {
    // Strings: test the wrapper

    string[][] arr = [ [ "abcde", "x0" ]
                       , [ "adert", "x1" ]
                       , [ "gtizutor", "x2" ]
                       , [ "pqwer", "x3" ]
                       , [ "zzzyyy", "x4" ]
                       ];

    bool   ret;
    size_t ind0, ind1;
    double prop;

    {
      ret = search_bisection_string!( a => arr[ a ][ 0 ] )
        ( "aaa", 0, arr.length - 1
          , ind0, ind1, prop
          );

      assert( ret == false );
    }

    {
      ret = search_bisection_string!( a => arr[ a ][ 0 ] )
        ( "ZZZZ", 0, arr.length - 1
          , ind0, ind1, prop
          );

      assert( ret == false );
    }

    {
      void s2_check_in_arr_value( in size_t k, in string[] v )
      {
        ret = search_bisection_string
          !( a => arr[ a ][ 0 ] )
          ( v[ 0 ], 0, arr.length-1
            , ind0, ind1, prop
            );
        
        assert( ret == true );
        assert( ind0 == k );
        assert( ind1 >= ind0 );
        assert( prop == 0.0 );
      }

      foreach (k,v; arr)
        {
          s2_check_in_arr_value( k, v );
        }
    }    

    {
      foreach (true_ind0; 0..arr.length-1)
        {
          auto true_ind1 = true_ind0 + 1;
          auto true_prop = 0.5;
          auto v0 = arr[ true_ind0 ][ 0 ] ~ "a";

          ret = search_bisection_string
            !( a => arr[ a ][ 0 ] )
            ( v0, 0, arr.length-1
              , ind0, ind1, prop
              );

          assert( ret == true );
          assert( ind0 == true_ind0 );
          assert( ind1 == true_ind1 );
          assert( prop == true_prop );
        }
    }


  }
  
  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
