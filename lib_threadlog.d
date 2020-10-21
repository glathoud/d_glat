module d_glat.lib_threadlog;

public import std.file : append;
public import std.conv : to;

import core.thread;
import std.path;
import std.process;
import std.stdio;

/*
  Multithreading logging tools for easier multithreading debugging.
  These tools write logging into several `THREADLOG` files, one file
  per thread.

  The Boost license applies to this file, see ./LICENSE

  Guillaume Lathoud, 2020
  glat@glat.info
 */


string THREADLOG()
{
  return buildPath( expandTilde( "~/tmp" ), to!string(thisThreadID)~"_tfln.log" );
}
  
string xxx_threadlog_append( in string name ) pure
/*
  Code to be mixin'ed, that prints an expression and its value into
  a `THREADLOG` file (one separate file for each thread). 

  Useful for multithreading debugging. Example of use:

  mixin(xxx_threadlog_append(`1.234 + my_variable`));
 */
{
  return xxx_threadlog_append_code( `"`~name~`:"` )
    ~ xxx_threadlog_append_code( `to!string( `~name~` )~"\n"` )
    ;
}

string xxx_threadlog_append_code( in string code ) pure
/*
  Code to be mixin'ed, that evaluates and prints an expression
  `code`, along with its origin file and line, into a `THREADLOG`
  file (one separate file for each thread).

  Useful for multithreading debugging. Examples of use:

  mixin(xxx_threadlog_append(`"some text"`));

  mixin(xxx_threadlog_append(`1.234*abc`));

  mixin(xxx_threadlog_append(`"some text: "~to!string(1.234*abc)`));
 */
{
  return `std.file.append( THREADLOG, (__FILE__ ~ "@line:" ~ std.conv.to!string( __LINE__ )~": ") ~ (`~code~`) ~ "\n" ); `;
}
