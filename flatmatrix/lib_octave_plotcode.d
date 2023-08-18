module d_glat.flatmatrix.lib_octave_plotcode;

public import d_glat.flatmatrix.core_octave;

import d_glat.core_string;
import d_glat.core_struct;
import std.format;
import std.range;

/*
  Tools to manipulate strings of data to and from Octave
  (MATLAB-like), e.g. to prepare code to display graph.

  The Boost License applies, see file ./LICENSE

  By Guillaume Lathoud, 2023 and later
  glat@glat.info
 */

alias MPlotXY = MPlotXYT!double;

struct MPlotXYT(T)
{
  const string xname, yname;
  const(T[]) xdata, ydata;
  const string style = ".";
  const string title = "";
  
  string getCode() const
  {
    immutable xlabel = xname.replace( "_", "\\_" );
    immutable ylabel = yname.replace( "_", "\\_" );

    immutable title_1 = string_default( title, "x:"~xlabel~", y:"~ylabel );
    
    return [
            xname~" = ["~format( "%(%20.14g %)", xdata )~"];"
            , yname~" = ["~format( "%(%20.14g %)", ydata )~"];"
            , mixin(_tli!"figure; plot(${xname}, ${yname}, '${style}'); xlabel('${xlabel}'); ylabel('${ylabel}'); title('${title_1}')")
            , ""
            ].join( "\n" );
  }

}
