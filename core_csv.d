module d_glat.core_csv;

import core.exception;
import d_glat.core_assoc_array;
import d_glat.core_gzip;
import std.algorithm : map;
import std.array : appender, Appender, array, replace;
import std.conv : to;
import std.csv : csvReader;
import std.file;
import std.stdio;
import std.string : endsWith;

/*
  Extract and convert selected columns of a CSV file (possibly gzipped).

  The CSV file must have a header line.
  White spaces are tolerated (ignored).

  By Guillaume Lathoud, 2023
  glat@glat.info

  The Boost license applies to this file, as described in ./LICENSE
 */

enum CSV_DFLT_DELIM = ',';

T[] v_arr_of_csv_fn(string FIELD, T)( in string csv_fn, in char delimiter = CSV_DFLT_DELIM )
// Read one column of a CSV file (with header), and convert it to T[].
// If `csv_fn` ends with ".gz", it is automatically gunzipped.
{
  return v_arr_arr_of_csv_fn!([FIELD], T)( csv_fn, delimiter )[ 0 ];
}

T[][] v_arr_arr_of_csv_fn(string[] FIELD_ARR, T)
  ( in string csv_fn, in char delimiter = CSV_DFLT_DELIM )
// Read selected columns of a CSV file (with header), and convert it to T[].
// If `csv_fn` ends with ".gz", it is automatically gunzipped.
{
  scope auto data_0  = std.file.read( csv_fn );
  scope auto data    = csv_fn.endsWith( ".gz" )  ?  gunzip( data_0 )  :  data_0;

  return v_arr_arr_of_csv_data!(FIELD_ARR, T, typeof(data))( data, delimiter );
}

T[] v_arr_of_csv_data(string FIELD, T, D)( in D csv_data, in char delimiter = CSV_DFLT_DELIM )
{
  return v_arr_arr_of_csv_data!([FIELD], T, D)( csv_data, delimiter )[ 0 ];
}

T[][string] v_arr_of_field_of_csv_data(string[] FIELD_ARR, T, D)
  ( in csv_data, in char delimiter = CSV_DFLT_DELIM )
{
  // compute
  scope auto v_arr_arr = v_arr_arr_of_csv_data!(FIELD_ARR, T, D)( csv_data, delimiter );

  // store
  T[][string] v_arr_of_field;
  
  static foreach (K, FIELD; FIELD_ARR)
    v_arr_of_field[ FIELD ] = v_arr_arr[ K ];
  
  return v_arr_of_field;
}


T[][] v_arr_arr_of_csv_data(string[] FIELD_ARR, T, D)
  ( in D csv_data, in char delimiter = CSV_DFLT_DELIM )
{
  scope auto records = csvReader!(string[string])(cast( string )( csv_data ), null, delimiter );

  alias A = Appender!(T[]);
  scope auto v_app_arr = new A[ FIELD_ARR.length ];

  string VNAME( in size_t K ) { return "v"~to!string( K )~"_app"; }

  static foreach (K; 0..FIELD_ARR.length)
  {
    mixin(`scope auto `~VNAME( K )~` = appender!(T[]);`);
    mixin(`v_app_arr[ K ] = `~VNAME( K )~`;`);
  }

  size_t ir = 0;
  try
    {
      foreach (record0; records)
        {
          scope auto record = aa_strip_keys_values( record0 );
          static foreach (K, FIELD; FIELD_ARR)
          {{
              immutable v = mixin(`to!T( record[ "`~FIELD~`" ] )`);
              mixin(VNAME( K )~`.put( v );`);
            }}
        }
      ir++;
    }
  catch (core.exception.ArrayIndexError aie)
    {
      stderr.writeln();
      stderr.writefln( "!! ------- core_csv -------- At record #%d, caught ArrayIndexError (maybe mismatch number of columns <=> header columns, e.g. compare number of separator occurences): %s", ir, to!string( aie ));
      stderr.flush;
      throw aie;
    }

  return v_app_arr.map!"a.data".array;
}

unittest
{
  import std.stdio;
  import std.path;

  writeln;
  writeln( "unittest starts: ", baseName( __FILE__ ) );

  immutable verbose = false;

  writeln( "unittest passed: ", baseName( __FILE__ ) );
}
