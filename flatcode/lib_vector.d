module d_glat.flatcode.lib_vector;

import std.algorithm;
import std.math;

void vecneg( T )( in ref T[] A
                  , ref T[] B ) 
{
  pragma( inline, true );

  foreach( k, v; A )
      B[ k ] = -v;
}

void vecadd( T )( in ref T[] A, in ref T[] B
                  , ref T[] C ) 
{
  pragma( inline, true );

  foreach( k, v; A )
      C[ k ] = v + B[ k ];
}

void vecdotprod( T )( in ref T[] A, in ref T[] B
                      , ref T s
                      )
{
  pragma( inline, true );

  s = 0; 
  foreach( k, v; A )
    s += v * B[ k ];
}

void vecinfnorm( T )( in ref T[] A
                      , ref T s ) 
{
  pragma( inline, true );
  
  s = 0;
  foreach( k, v ; A )
    s = max( s, abs( v ) );
}

void vecscal( T )( in ref T[] A, in T s
                   , ref T[] B
                   ) 
{

  pragma( inline, true );

  foreach( k, v; A )
    B[ k ] = v * s;
}


void vecscaladd( T )( in ref T[] A, in T s
                      , in ref T[] B
                      , ref T[] C ) 
{
  pragma( inline, true );
  
  foreach( k, v; A )
    C[ k ] = v * s + B[ k ];
}

void vecsubdotprod( T )( in ref T[] A, in ref T[] B
                         , in ref T[] C
                         , ref T s ) 
{

  pragma( inline, true );

  s = 0;
  foreach( k, v; A )
    s += (v - B[ k ]) * C[ k ];
}


void vecsubscal( T )( in ref T[] A, in ref T[] B
                      , in T s
                      , ref T[] C ) 
{
  pragma( inline, true );
  
  foreach( k, v; A )
    C[ k ] = (v - B[ k ]) * s;
}


void vecsumsq( T )( in ref T[] A
                    , ref T s ) 
{
  pragma( inline, true );
  
  s = 0;
  foreach( k, v; A )
    s += v * v;
}

void vecswap( T )( ref T[] A, ref T[] B ) 
{
  pragma( inline, true );
  
  T[] tmp = A;
  A = B;
  B = tmp;
}
