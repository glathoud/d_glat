module d_glat.core_csv;

import d_glat.core_assoc_array;
import d_glat.core_gzip;
import std.algorithm : map;
import std.array : appender, Appender, array;
import std.conv : to;
import std.csv : csvReader;
import std.file;
import std.string : endsWith;

/*
  Extract and convert selected columns of a CSV file (possibly gzipped).

  The CSV file must have a header line.
  White spaces are tolerated (ignored).

  By Guillaume Lathoud, 2023
  glat@glat.info

  The Boost license applies to this file, as described in ./LICENSE
 */

T[] v_arr_of_csv_fn(string FIELD, T)( in string csv_fn )
// Read one column of a CSV file (with header), and convert it to T[].
// If `csv_fn` ends with ".gz", it is automatically gunzipped.
{
  return v_arr_arr_of_csv_fn!([FIELD], T)( csv_fn )[ 0 ];
}

T[][] v_arr_arr_of_csv_fn(string[] FIELD_ARR, T)( in string csv_fn )
// Read one column of a CSV file (with header), and convert it to T[].
// If `csv_fn` ends with ".gz", it is automatically gunzipped.
{
  scope auto data_0  = std.file.read( csv_fn );
  scope auto data    = csv_fn.endsWith( ".gz" )  ?  gunzip( data_0 )  :  data_0;

  return v_arr_arr_of_csv_data!(FIELD_ARR, T, typeof(data))( data );
}

T[] v_arr_of_csv_data(string FIELD, T, D)( in D csv_data )
{
  return v_arr_arr_of_csv_data!([FIELD], T, D)( csv_data )[ 0 ];
}
  
T[][] v_arr_arr_of_csv_data(string[] FIELD_ARR, T, D)( in D csv_data )
{
  scope auto records = csvReader!(string[string])(cast( string )( csv_data ), null);

  alias A = Appender!(T[]);
  scope auto v_app_arr = new A[ FIELD_ARR.length ];
  static foreach (K; 0..FIELD_ARR.length)
    {
      immutable VNAME = "v"~to!string( K )~"_app";
      mixin(`scope auto `~VNAME~` = appender!(T[]);`);
      mixin(`v_app_arr[ K ] = `~VNAME~`;`);
    }
  
  foreach (record0; records)
    {
      scope auto record = aa_strip_keys_values( record0 );
      static foreach (K, FIELD; FIELD_ARR)
        mixin(`v`~to!string( K )~`_app.put( to!T( record[ "`~FIELD~`" ] ) );`);
    }

  return v_app_arr.map!"a.data".array;
}
