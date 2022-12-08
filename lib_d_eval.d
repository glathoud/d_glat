module d_glat.lib_d_eval;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.sys.posix.dlfcn;
import d_glat.core_assoc_array;
import d_glat.core_process;
import std.algorithm;
import std.array;
import std.compiler;
import std.conv;
import std.file;
import std.path;
import std.regex : ctRegex;
import std.stdio;
import std.string;

void*[string][string] fnptr_of_code_of_compiler;

private immutable string dfltCompiler =
  Vendor.digitalMars == vendor  ?  "dmd"
  :  Vendor.llvm     == vendor  ?  "ldmd2"
  :  Vendor.gnu      == vendor  ?  "gdc"
  :  ""
  ;

T d_eval( T )( in string fname, in string code
               , in string compiler = dfltCompiler )
/*
  Dynamic code compilation (supports DMD and LDC). To compile your
  main, you'll probably need:

  With DMD:

  -L-ldl -defaultlib=libphobos2.so

  With LDC:
  
  -L-ldl -defaultlib=libphobos2.so
  -L"$LDC_DIR/lib/libphobos2-ldc-shared.so.2.0.80"

  LDC must have been compiled to output shared libraries, see the
  step-by-step instructions as of 2018-07 in ./lib_d_eval.md

  glat@glat.info
 */
{
  assert( 0 < compiler.length, "d_eval needs a compiler." );

  scope auto fnptr_of_code = aa_getInit( fnptr_of_code_of_compiler
                                   , compiler );
  if (code !in *fnptr_of_code)
    {
      assert( code.canFind( "extern" )  && (code.canFind( "(C)" ))
              , "`code` should contain functions declared with "
              ~" `extern (C)`, for an example see "
              ~(__FILE__[0..$-2]~"_example_rdmd.sh (DMD)")
              ~" or "
              ~(__FILE__[0..$-2]~"_example_rdmd2.sh (LDC)")
              );

      // A directory
      static string tmpdirname;
      if (tmpdirname.length < 1)
        {
          for( uint i = 0; true; ++i)
            {
              tmpdirname = buildPath
                ( tempDir, "dir" ~ to!string( i ) );
              
              if (!exists( tmpdirname ))
                break;
            }
          tmpdirname.mkdirRecurse;
        }

      // A codefile in the directory
      string tmpfilename_base;
      string tmpfilename_d;
      {
        auto rx = ctRegex!`[^a-z0-9]+`;
        string somename = code.split( "\n" )[ 0 ][ 0..min(100,$) ]
          .replaceAll( rx, "_" );

        if (somename.length < 1)
          somename = "somename";

        for (uint i = 0; true; ++i)
          {
            tmpfilename_base = buildPath
              ( tmpdirname, somename~'_'~to!string( i ) );

            tmpfilename_d = tmpfilename_base~".d";
            
            if (!exists( tmpfilename_d ))
              break; 
          }
        
        std.file.write( tmpfilename_d, code );
      }

      // Try to find the shared Phobos library
      // (esp. for LDC)

      string maybe_phobos_shared
        = buildPath
        ( dirName( compiler ), "..", "lib"
          , "libphobos2-ldc-shared.so"
          );

      string[] Lopt = 
        exists( maybe_phobos_shared )
        ?  [ `-L"`~maybe_phobos_shared~`"` ]
        :  []
        ;

      writeln( "Lopt: ", Lopt );
      
      assertExecute
        ( [ compiler, "-O", "-c", tmpfilename_d, "-fPIC" ]
          ~ Lopt
          );

      string tmpfn( in string ext )
      {
        return tmpfilename_base ~ ext;
      }

       assertExecute
        ( [ compiler, "-O", "-of"~tmpfn(".o")
            , "-c", tmpfilename_d, "-fPIC" ]
          ~ Lopt
          );
      
      assertExecute
        ( [ compiler, "-O", "-of"~tmpfn(".so"), tmpfn(".o")
            , "-shared", "-defaultlib=libphobos2.so" ]
          ~ Lopt
          );
      
      auto tmpfn_so = tmpfn(".so");
      
      void* lh = dlopen( toStringz( tmpfn_so ), RTLD_LAZY);
      if (!lh)
        {
          fprintf(core.stdc.stdio.stderr
                  , "dlopen error: %s\n", dlerror());
          exit(1);
        }
      // printf(toStringz( tmpfn_so~" is loaded\n" ));

      (*fnptr_of_code)[ code ] = dlsym( lh, toStringz( fname ) );
    }
  
  return cast( T )( (*fnptr_of_code)[ code ]);
}
