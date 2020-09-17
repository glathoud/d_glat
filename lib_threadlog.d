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
  return `append( THREADLOG, "\n`~name~`:\n" );
  append( THREADLOG, to!string( `~name~`) );
  `;
}
