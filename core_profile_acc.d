module d_glat.core_profile_acc;

public import std.format : format;

import d_glat.core_assert;
import d_glat.core_string : string_shorten;
import std.algorithm : canFind, map, sort;
import std.array : array, join;
import std.conv : to;
import std.datetime : Duration;
import std.datetime.stopwatch : AutoStart, StopWatch;
import std.stdio : stdout, writeln, writefln;

/*
  Profiling through mixins.



  Example:

  for (i; 0..100)
    do_some();

  mixin(profile_acc_dump); // show aggregated statistics

  void do_some()
  {
    mixin(profile_acc_begin(__FUNCTION__~":"~to!string(__LINE__))); // whole function
    mixin(profile_acc_begin(__FUNCTION__~":"~to!string(__LINE__))); // part
    ...
    mixin(profile_acc_end(":"~to!string(__LINE__))); // part
    mixin(profile_acc_begin(__FUNCTION__~":"~to!string(__LINE__))); // part
    ...
    mixin(profile_acc_end(":"~to!string(__LINE__))); // part
    mixin(profile_acc_begin(__FUNCTION__~":"~to!string(__LINE__))); // part
    ...
    mixin(profile_acc_end(":"~to!string(__LINE__))); // part
    mixin(profile_acc_end(":"~to!string(__LINE__))); // whole function
  }


  
  This may be boring, so a few shortcuts are provided,
  which permit to rewrite the example as:
  
  // top-level
  enum PROFILE_ACC = true; // switch to false to deactivate profiling
  mixin(PROFILE_SHORTCUTS);

  ...

  for (i; 0..100)
    do_some();

  mixin(P_ACC_DUMP);

  void do_some()
  {
    mixin(P_ACC_BEGIN); // whole function
    mixin(P_ACC_BEGIN); // part
    ...
    mixin(P_ACC_END_BEGIN); // part
    ...
    mixin(P_ACC_END_BEGIN); // part
    ...
    mixin(P_ACC_END_BEGIN); // part
    ...
    mixin(P_ACC_END); // part
    mixin(P_ACC_END); // whole function
  }




  The Boost License applies, as described in the file ./LICENSE
  
  By Guillaume Lathoud, 2022
  glat@glat.info
 */

immutable P_ACC_SHORTCUTS = q{
  string P_ACC_BEGIN() pure
  { return PROFILE_ACC  ?  `profile_acc_begin( __FUNCTION__~":"~format("%4d",__LINE__) );`  :  ``; }

  string P_ACC_END_BEGIN() pure { return P_ACC_END()~P_ACC_BEGIN(); }

  string P_ACC_END() pure
  { return PROFILE_ACC  ?  `profile_acc_end( ":"~format("%4d",__LINE__) );`  :  ``; }

  string P_ACC_DUMP() pure
  { return PROFILE_ACC  ?  `profile_acc_dump();`  :  ``; }
};


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

        immutable bnmc = begin_name ~ maybe_comment;

        immutable bnmc_100 = bnmc.string_shorten( 100 );
        
        return format("%100s", bnmc_100) ~ " ("~format("%6.2f", prct)~"%) " ~ to!string(drtn);
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


public:

// ----------------------------------------------------------------------
// memory profiling - temporarily put here

// xxx in the end put it there: module d_glat.core_profile_mem;

import std.algorithm;
import std.stdio;

/*
  To activate this, in your constants do this:
  __pmc.active = true;

  Then you can print once in a while the stats:
  mixin(P_MEM_DUMP);
*/

immutable P_MEM_DUMP = "{if (__pmc_isActive) __pmc_dump();}";

// For structs
immutable P_MEM_RGSTR = "__pmc_register( typeid(this).name );";
immutable P_MEM_FRGT  = "__pmc_forget( typeid(this).name );";

// For classes
class ProfileMemC
{
  this() { mixin(P_MEM_RGSTR); }
  ~this() { mixin(P_MEM_FRGT); }
}



bool __pmc_isActive() @trusted
{
  synchronized (__pmc) { return (cast(__PMC)( __pmc )).active; }
}

void __pmc_register( in string tin ) @trusted
{
  synchronized (__pmc) { (cast( __PMC )(__pmc))._register( tin ); }
}

void __pmc_forget( in string tin ) @trusted
{
  synchronized (__pmc) { (cast( __PMC )(__pmc))._forget( tin ); }
}

void __pmc_dump() @trusted
{
  synchronized (__pmc) { (cast( __PMC )(__pmc))._dump(); }
}


shared __PMC __pmc;

shared static this()
{
  __pmc = new __PMC;
}

private:

class __PMC
{
  bool active = false;
  
  private long[string] _n_of_tin;
  
  void _register( in string tin ) pure @safe
  {
    if (!active)
      return;
    
    _n_of_tin[ tin ] = 1 + _n_of_tin.get( tin, 0 );
  }
  
  void _forget( in string tin ) pure @safe
  {
    if (!active)
      return;
    
    _n_of_tin[ tin ] = -1 + _n_of_tin.get( tin, 0 );
  }

  void _dump()
  {
    stdout.flush;
    writeln;
    writeln("__________________________________profile_mem_dump__________________________________");
    foreach (tin; _n_of_tin.keys.dup.sort)
      {
        immutable tin_70 = tin.string_shorten( 70 );
        writefln(" %70s: %4d", tin_70, _n_of_tin[ tin ]);
      }
    writeln;
    stdout.flush;
  }
  
}
