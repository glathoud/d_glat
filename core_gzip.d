module d_glat.core_gzip;

import std.zlib;

ubyte[] gunzip( in ubyte[] data )
@trusted
{
  auto U = new UnCompress( HeaderFormat.gzip );
  auto d1 = cast( ubyte[] )( U.uncompress( data ) );
  auto d2 = cast( ubyte[] )( U.flush() );
  return d1 ~ d2;
  
  // Old code below
  // 
  // zlib and gzip formats differ (headers), hence the `47`
  // http://www.digitalmars.com/d/archives/digitalmars/D/Trouble_with_std.zlib_140855.html
  //
  // (else we could create an `Uncompress` instance with
  // HeaderFormat.gzip)
  //
  // return cast( ubyte[] )( uncompress( zdata_0, 0, 47 ) );
}

ubyte[] gunzip( in void[] data )
@trusted
{
  return gunzip( cast( ubyte[] )( data ) );
}


// Consider using `std.string.representation` in some use cases.

ubyte[] gzip( in ubyte[] data )
@trusted
{
  auto       C = new Compress( 9, HeaderFormat.gzip );
  auto  gzip_1 = cast( ubyte[] )( C.compress( data ) );
  auto  gzip_2 = cast( ubyte[] )( C.flush() );
  return gzip_1 ~ gzip_2;
}

ubyte[] gzip( void[] data )
@trusted
{
  return gzip( cast( ubyte[] )( data ) );
}
