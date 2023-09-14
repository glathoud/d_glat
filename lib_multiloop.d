module d_glat.lib_multiloop;

import std.algorithm : map;
import std.array : join, replicate;

/*
  Generate code for multiple, imbricated, foreach loops for a set of
  parameters `paramname_arr` and their respective possible values
  `v_arr_of_paramname[ paramname ]`.
  
  The innermost loop calls `fname( ...paramvalue_arr... )`.

  Example:

  mixin(multiloopC(["a","b","c"],"v_arr_of_pn","f"));

  is equivalent to:

  foreach (ref a; v_arr_of_pn["a"])
    foreach (ref b; v_arr_of_pn["b"])
      foreach (ref c; v_arr_of_pn["c"])
        f(a,b,c);
  
  By Guillaume Lathoud, 2023
  glat@glat.info

  The Boost license applies to this file, as described in ./LICENSE
 */

string multiloopC( in string[] /*to loop:*/paramname_arr, in string v_arr_of_paramname, in string fname ) pure
{
  return (paramname_arr
          .map!((pn) => "foreach (ref "~pn~"; "~v_arr_of_paramname~"[\""~pn~"\"]){")
          .join("")
          )~fname~"("~(paramname_arr.join(','))~");"
    ~replicate("}",paramname_arr.length);
}
