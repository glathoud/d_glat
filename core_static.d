module d_glat.core_static;

/*
  Tool functions to setup static buffers local to a function.

  The Boost license applies, as described in ./LICENSE

  by Guillaume Lathoud, 2019
  glat@glat.info
*/

string static_array_code
( in string name, in string type, in string n ) pure
/*
  Code to setup a static buffer local to a function.


  Example:

  mixin( setup_static_array( `arr`, `double`, `n_elt` ) );

  is equivalent to:

  static double[] arr;
  if (arr.length != n_elt)
    arr.length = new double[ n_elt ];


  Beware that `new` won't be called if `n` has not changed, so you
  won't get the default initialization for sure (e.g. `double.nan`
  for a `double[]`). 

  => If you need initialization to some value, do it yourself.
*/
{
  return `static `~type~`[] `~name~`;
  if (`~name~`.length != (`~n~`))
    `~name~` = new `~type~`[ `~n~` ];
  `;
}



unittest  // ------------------------------
{
  import std.stdio;

  immutable verbose = false;
  
  writeln;
  writeln( "unittest starts: "~__FILE__ );

  {
    int count = 0;
    void f( in size_t n )
    {
      static double[] arr;
      if (arr.length != n)
        {
          ++count;
          if (verbose) writeln( "count: ", count );
          arr = new double[ n ];
        }
    }

    assert( count == 0 );

    f( 10 ); // `arr` reallocated
    assert( count == 1 );
    f( 10 ); // No realloc here
    assert( count == 1 );
    f( 10 ); // No realloc here
    assert( count == 1 );

    f( 20 ); // `arr` reallocated
    assert( count == 2 );
    f( 20 ); // No realloc here
    assert( count == 2 );
    f( 20 ); // No realloc here
    assert( count == 2 );

    f( 10 ); // `arr` reallocated
    assert( count == 3 );
    f( 10 ); // No realloc here
    assert( count == 3 );
    f( 10 ); // No realloc here
    assert( count == 3 );
  }


  
  writeln( "unittest passed: "~__FILE__ );
}
