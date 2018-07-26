module d_glat_common.d_eval;

import d_glat_common.core_assoc_array;
import std.compiler;
import std.file;
import std.path;
import std.process;
import std.stdio;

void*[string][string] fnptr_of_code_of_compiler;

private immutable string dfltCompiler =
  Vendor.digitalMars == vendor  ?  "dmd"
  :  Vendor.llvm     == vendor  ?  "ldmd2"
  :  Vendor.gnu      == vendor  ?  "gdc"
  :  ""
  ;
T d_eval( T )( in string code, in string compiler = dfltCompiler )
{
  assert( 0 < compiler.length, "d_eval needs a compiler." );

  auto fnptr_of_code = aa_getInit( fnptr_of_code_of_compiler
                                   , compiler );
  if (code !in fnptr_of_code)
    {
      // A directory
      static string tmpdirname;
      if (tmpdirname.length < 1)
        {
          for( uint i = 0; true; ++i)
            {
              tmpdirname = buildPath
                ( tempDir, "dir" ~ to!string( i ) );
              
              if (!os.path.exists( tmpdirname ))
                break;
            }
          tmpdirname.mkdirRecurse;
        }

      // A codefile in the directory
      string tmpfilename;
      {
        auto rx = ctRegex!`[^a-z0-9]`;
        string somecode = code.split( '\n' )[ 0 ][ 0..min(100,$) ]
          .replaceAll( rx, "_" );

        if (somecode.length < 1)
          somecode = "somecode";

        for (uint i = 0; true; ++i)
          {
            tmpfilename = buildPath( tmpdirname
                                     , somecode~'_'~to!string( i )
                                     );
            if (!os.path.exists( tmpfilename ))
              break;
          }
        write( tmpfilename, code );
      }
      
      
    }
  return cast( T )( fnptr_of_code[ code ]);
}
