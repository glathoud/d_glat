module d_glat.lib_threadlog;

public import std.file : append;
public import std.conv : to;

import core.thread;
import std.path;
import std.process;
import std.stdio;


string THREADLOG()
{
  return buildPath( expandTilde( "~/tmp" ), to!string(thisThreadID)~"_tfln.log" );
}
  
string xxx_threadlog_append( in string name ) pure
{
  return xxx_threadlog_append_code( `"`~name~`:"` )
    ~ xxx_threadlog_append_code( `to!string( `~name~` )~"\n"` )
    ;
}

string xxx_threadlog_append_code( in string code ) pure
{
  return `std.file.append( THREADLOG, (__FILE__ ~ "@line:" ~ std.conv.to!string( __LINE__ )~": ") ~ (`~code~`) ~ "\n" ); `;
}

