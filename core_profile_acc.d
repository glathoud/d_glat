module d_glat.core_profile_acc;

import d_glat.core_assert;
import std.algorithm : canFind, map, sort;
import std.array : array, join;
import std.conv : to;
import std.datetime : Duration;
import std.datetime.stopwatch : AutoStart, StopWatch;
import std.format : format;
import std.stdio : stdout, writeln, writefln;

/*
  Profiling through mixins.

  Example:

  for (i; 0..100)
    do_some();

  mixin(profile_acc_dump); // show aggregated statistics

  void do_some()
  {
    mixin(profile_acc_begin); // whole function
    mixin(profile_acc_begin); // part
    ...
    mixin(profile_acc_end); // part
    mixin(profile_acc_begin); // part
    ...
    mixin(profile_acc_end); // part
    mixin(profile_acc_begin); // part
    ...
    mixin(profile_acc_end); // part
    mixin(profile_acc_end); // whole function
  }


  The Boost License applies, as described in the file ./LICENSE
  
  By Guillaume Lathoud, 2022
  glat@glat.info
 */


void profile_acc_begin(string profile_name = "")
  ( in string begin_name ) // e.g. __FUNCTION__~":"~to!string(__LINE__)
{
  _get_profile_acc( profile_name ).begin( begin_name );
}

void profile_acc_end(string profile_name = "")
  ( in string comment ) // e.g. ":"~to!string(__LINE__)
{
  _get_profile_acc( profile_name ).end( comment );
}

void profile_acc_dump(string profile_name = "")()
{
  stdout.flush;
  writeln;
  writeln( profile_acc_dumps!profile_name );
  writeln;
  stdout.flush;
}

string profile_acc_dumps(string profile_name = "")()
{
  return _get_profile_acc( profile_name ).toString;
}

private:

ProfileAcc[string] p_acc_of_p_name;

ProfileAcc _get_profile_acc( in string profile_name = "" )
{
  if (auto p = profile_name in p_acc_of_p_name)
    return *p;
  
  return p_acc_of_p_name[ profile_name ] = new ProfileAcc( profile_name );
}

class ProfileAcc
{
  immutable string profile_name;

  this( in string profile_name ) {
    this.profile_name = profile_name;
    global_sw = StopWatch(AutoStart.yes);
  }
  
  void begin( in string begin_name )
  {
    previous_begin_name_r ~= begin_name;
      
    if (auto p = begin_name in sw_of_begin_name)
      (*p).start;
    else
      sw_of_begin_name[ begin_name ] = StopWatch(AutoStart.yes);
  }

  void end( in string comment = "" )
  {    
    mixin(alwaysAssertStderr!`0 < previous_begin_name_r.length`);

    immutable previous_begin_name = previous_begin_name_r[ $-1 ];
    previous_begin_name_r = previous_begin_name_r[ 0..$-1 ];

    sw_of_begin_name[ previous_begin_name ].stop;
    comment_of_begin_name[ previous_begin_name ] = comment;
  }

  override string toString() const
  {
    return _toString();
  }

 private:
  
  string _toString( in string begin_name = "", in Duration global_drtn = Duration.zero ) const
  {
    if (0 < begin_name.length)
      {
        auto drtn = sw_of_begin_name[ begin_name ].peek;
    
        immutable prct =
          100.0 * (cast(double)( drtn.total!"nsecs")) /  (cast(double)( global_drtn.total!"nsecs"));

        immutable comment_0     = comment_of_begin_name.get( begin_name, "" );
        immutable maybe_comment = 0 < comment_0.length  ?  " ("~comment_0~")"  :  "";
        
        return format("%100s", begin_name ~ maybe_comment) ~ " ("~format("%6.2f", prct)~"%) " ~ to!string(drtn);
      }

    auto global_drtn_0 = global_sw.peek;
                
    return ([ "ProfileAcc dump: global duration: "~to!string(global_sw.peek)
              ]
            ~[ "previous_begin_name_r: "~to!string(previous_begin_name_r) ]

            ~sw_of_begin_name.keys.dup.sort
            .map!( begin_name => "  "~_toString( begin_name, global_drtn_0 ) ).array

            )
      .join( '\n' );
  }

  StopWatch global_sw;
  
  string[] previous_begin_name_r;
  
  StopWatch[string] sw_of_begin_name;
  string[string] comment_of_begin_name;
  
};
