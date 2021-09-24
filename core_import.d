module d_glat.core_import;

string maybeImportC(string modulePath)()
{
  // Thanks to Adam D. Ruppe
  // https://forum.dlang.org/post/zlxpxstpzvcbmtbxgfii@forum.dlang.org

  return `static if (is(typeof((){import `~modulePath~`;}))) { public import `~modulePath~`; }`;
}
