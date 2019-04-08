# d\_glat

Tools for the D language. All distributed under the Boost License, see file [LICENSE](LICENSE).

 * [core\_assoc\_array.d](core_assoc_array.d): convenience tool to
   get/initialize associative arrays having more than one dimension.
   ```D
   T* aa_getInit( T, KT )( ref T[KT] aa, in KT key, lazy T def_val = T.init );
    ```


 * [core\_enum\_parse.d](core_enum_parse.d): code generator to declare an `enum` and a string parser for it.
   ```D
   mixin( enum_parse_code( "SomeEnum", "parse_some_enum_str"
                            , "some_enum_name_list"
                            , [ "aaa", "bbb", "ccc", "ddd" ] ) );
   ```

 * [core\_fext.d](core_fext.d): "fext" stands for "Fast Explicit Tail
   Calls", does Tail Call Elimination (TCE) and supports mutual
   recursion.
   ```D
   mixin(mdecl (<fdecl>,<fbody>, <fdecl>,<fbody>, ... )); // TCE
   mixin(mdeclD(<fdecl>,<fbody>, <fdecl>,<fbody>, ... )); // no TCE, to debug
   ```
   
 * [core\_file.d](core_file.d):
   ```D
   void ensure_dir_exists( in string dir_name );
   void ensure_file_writable_or_exit( in string outfilename, in bool ensure_dir = false );
   ubyte[] ubytedata_of_little_endian_ushortdata( in ushort[] ushortdata );
   ```
   
 * [core\_glob.d](core_glob.d): Extract a `dirEntries` result and convert it into an array of string, in case `foreach( name, dirEntries( ... ))` is not enough.
   ```D
   string[] dirSA( string path, string glob, SpanMode spanMode = SpanMode.breadth, bool followSymlink = false );
   ```

 * [core\_json.d](core_json.d):
  ```D
   alias Jsonplace = string[]; // position in the JSON
   JSONValue json_array()
   JSONValue json_object()
   double json_get_double( in JSONValue jv )
   long json_get_long( in JSONValue jv )
   string json_get_string( in JSONValue jv )
   bool json_get_bool( in JSONValue jv )
   JSONValue json_get_place( in ref JSONValue j, in string place_str
                             , in JSONValue j_default )
   JSONValue json_get_place( in ref JSONValue j, in Jsonplace place
                             , in JSONValue j_default )

   Nullable!JSONValue json_get_place( in ref JSONValue j, in string place_str )
   Nullable!JSONValue json_get_place( in ref JSONValue j, in Jsonplace place )
   
   bool json_is_integer( in ref Nullable!JSONValue j )
   bool json_is_string( in ref Nullable!JSONValue j )
   bool json_is_string_equal( T )( in ref T j, in Jsonplace place, in string s )
   bool json_is_string_equal( T )( in ref T j, in string s )
   bool json_is_true( in ref Nullable!JSONValue j )
   void json_set_place( JSONValue j, in string place_str, in JSONValue v )
   void json_set_place( JSONValue j, in Jsonplace place, in JSONValue v )
   ```

 * [core\_named\_sync.d](core_named_sync.d) Name-based synchronization between threads. For example, to ensure a given file is access by only one thread at a time, `some_variable_name` would be `filename`, a string variable.
   ```D
   mixin(NAMED_SYNC_DO(`some_variable_name`,q{
                // Some code
        }));
   ```
   
 * [core\_parse\_number.d](core_parse_number.d) Take care of those `.` (thousands => ignored) and `,` (comma => replaced with a dot), then try to parse the result into a `double`.
   ```D
   alias MaybeDouble = Nullable!double;
   MaybeDouble parseGermanDouble( in string s );
   ```

 * [core\_process.d](core_process.d)
   ```D
   void assertExecute( in string[] cmd );
   ```

 * [core\_sexpr.d](core_sexpr.d) Minimalistic parser for S-Expressions, optionally constrained by `bool maybe_check_fun( SExpr e )`
   ```D
   SExpr parse_sexpr( alias maybe_check_fun = false )( in string a );
   SExpr parse_sexpr( alias maybe_check_fun = false )( in char[] a );
   ```

 * [core\_static.d](core_static.d) For static variables, typically local buffers inside functions.
   ```D
   mixin( setup_static_array( `arr`, `double`, `n_elt` ) );
   ```

 * [core\_string.d](core_string.d) Regex-free string tools.
   ```D
   bool string_is_num09( in string s );
   ```
 * [core\_web.d](core_web.d)
   ```D
   char[] get_url_ssl_unsafe( in string url )
   ```

 * [flatmatrix/](flatmatrix/) Systematic linear algebra computations for "flat matrices" (flat `double[]` array, dimensions) with an emphasis on performance. Correlation, pair deltas, sort_index, statistics, Singular Value Decomposition (SVD).

 * [lib\_d\_eval.d](lib_d_eval.d) Dynamic code compilation (DMD and LDC).

 * [lib\_interpolate.d](lib_interpolate.d)
   ```D
   T interpolate( in T a, in T b, in T prop )
   ```

 * [lib\_json\_manip.d](lib_json_manip.d) Many tools to manipulate `JSONValue`s.
   ```D
   JSONValue json_ascii_inplace( ref JSONValue jv );
   JSONValue json_deep_copy( in ref JSONValue j );
   JSONValue json_flatten_array( in ref JSONValue j );
   string json_get_hash( in ref JSONValue j );
   string json_get_hash( in ref JSONValue j, out string sorted_str_json );
   JSONValue json_get_replaced_many_places_with_placeholder_string
   ( in ref JSONValue j, in Jsonplace[] place_arr, in string      placeholder_string );

   // Replace SExpr values with computed doubles out of `o`
   JSONValue json_solve_calc( in ref JSONValue o );
   JSONValue json_solve_calc_one( in ref JSONValue o, in ref JSONValue v );
   double json_solve_calc_one( in ref JSONValue o, in ref SExpr e );

   void json_walkreadonly( alias iter )( in ref JSONValue j );
   bool json_walkreadonly_until( alias test )( in ref JSONValue j );
   void json_walk( alias iter )( ref JSONValue j );
   bool json_walk_until( alias test )( ref JSONValue j );

   // Extend the JSON format to permit /**/ and // comments
   string json_white_out_comments( in string extended_json_string );
   void json_white_out_comments_inplace( char[] ca );
   ```

 * [lib\_modified\_slice.d](lib_modified_slice.d) Experiment with modified slices, with dynamic flattening. Still, in the end I prefered simple arrays and a smart algorithm.

 * [lib\_search\_bisection.d](lib_search_bisection.d) Bisection search using `double fun( T v )` as a sort reference.
  ```D
  bool search_bisection_string( alias fun, ... )
  ( in T v, in ulong a0, in ulong b0, out size_t ind0, out size_t ind1, out double prop );

  bool search_bisection( alias fun, T = double, .. )
  ( in T v, in ulong a0, in ulong b0, out size_t ind0, out size_t ind1, out double prop );
  ```

 * [unittest.sh](unittest.sh) Bash script to run unit tests for all (default) or one file.
