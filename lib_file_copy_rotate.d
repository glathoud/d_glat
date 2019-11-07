/**
 By Guillaume Lathoud
 glat@glat.info
 
 Distributed under the Boost License, see file ./LICENSE
*/
module d_glat.lib_file_copy_rotate;

import d_glat.core_file;
import d_glat.core_glob;
import std.algorithm : map, sort;
import std.array : array;
import std.datetime;
import std.datetime.systime;
import std.file;
import std.path : baseName;
import std.range : enumerate;

string[] file_copy_fetch
(string prefix = ".save-")
  ( in string filename )
{
  immutable fipr = filename~prefix;

  return dirSA( fipr~'*' ).sort.array;
}

bool file_copy_rotate
( string   units = "weeks"
  , size_t[] max_interval_arr = [1,2,4,8,16,32]
  , string   prefix = ".save-" )
( in string  filename )
/*
  Manages a series of copies of `filename` to ensure a maximum time
  `max_interval` between consecutive files (in `units`).

  This can be useful to rotate log files, or manage copies of a any
  file updated over time, and that with increasing time intervals.
  
  Returns `true` if a file system modification was done (copy and/or
  delete), `false` otherwise.
*/
{
  assert( 0 < filename.length );
  assert( 0 < prefix.length );

  immutable fipr = filename~prefix;

  bool ret_modified = false;

  auto modificationTime = get_modification_time( filename );
  auto dt_now           = cast( DateTime )( modificationTime );
  
  auto save_arr = _grab_and_sort( fipr );

  long first_dur_max = max_interval_arr[ 0 ];
  
  auto first_duration = 0 < save_arr.length
    ?  (dt_now - save_arr[ 0 ].dt).total!units
    :  long.max
    ;

  if (first_duration > first_dur_max)
    {
      ret_modified = true;
      
      immutable new_filename = fipr~(dt_now.toISOExtString);
      std.file.copy( filename, new_filename );

      save_arr = _grab_and_sort( fipr );
    }
  
  const rest_dur_max = max_interval_arr[ 1..$ ];
  
  immutable nmax = 1 + rest_dur_max.length;

  while (save_arr.length > nmax)
    {
      immutable n = save_arr.length, nm1 = n-1;
      
      auto delta_arr = save_arr
        .enumerate
        .map!( x => x.index < nm1

               ?  (x.value.dt - save_arr[ x.index + 1 ].dt)
               .total!units

               :  long.max
               )
        .array;

      bool removed_one = false;
      foreach (i; 0..nm1)
        {
          // If we removed i+1, we would have `would_be`
          auto would_be = delta_arr[ i ] + delta_arr[ i+1 ];

          if (i >= rest_dur_max.length  ||  would_be < rest_dur_max[ i ])
            {
              ret_modified = true;
              removed_one  = true;
              immutable fn = save_arr[ i+1 ].fn;
              std.file.remove( fn );
              break;
            }
        }

      assert( removed_one );
      
      save_arr = _grab_and_sort( fipr );
    }

  return ret_modified;
}

private:

struct DtFn
{
  DateTime dt;
  string   fn;
};

DtFn[] _grab_and_sort( in string fipr )
{
  immutable fullpath_glob_expr = fipr~'*';

  return dirSA( fullpath_glob_expr )
    .map!( fn =>
           DtFn( _get_datetime_of_filename( fipr, fn )
                 , fn
                 )
           )
    .array
    .sort!"a.dt > b.dt"
    .array;
}


DateTime _get_datetime_of_filename( in string fipr, in string fn )
{
immutable fipr_bn = baseName( fipr )
  , fn_bn = baseName( fn )
  , rest = fn_bn[ fipr_bn.length..$ ]
  ;
return DateTime.fromISOExtString( rest );
}


/*

# To test in a shell window:

echo > xxx.txt

# Then repetitively call:

echo -n "x" >> xxx.txt; rdmd -i -debug -g -gs -gf -link-defaultlib-debug --eval 'import d_glat.lib_file_copy_rotate; file_copy_rotate!("seconds")("xxx.txt")' ; ls -lrt xxx.txt*

# Then have a look at:

head xxx.txt*

 */
