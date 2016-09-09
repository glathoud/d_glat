module d_common.core_web;

import etc.c.curl : CurlOption;

import std.net.curl;

char[] get_url_ssl_unsafe( in string url )
{
  // http://forum.dlang.org/post/vwvkbubufexgeuaxhqfl@forum.dlang.org
  auto conn = HTTP();
  conn.handle.set( CurlOption.ssl_verifypeer, 0 );
  return  get( url, conn );
}
