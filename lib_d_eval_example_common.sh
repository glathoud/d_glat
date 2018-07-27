#!/usr/bin/env sh

RUNNER=$1

CODE_0=`cat <<EOF
import d_glat_common.lib_d_eval;
import std.stdio;

writeln("xxx123");

alias FnT = extern (C) int function(int,int,int,bool);

FnT fn = d_eval!FnT(
"dynfun","extern (C) int dynfun( int a, int b, int c, bool d ) { return a*100+b*10+c+(d ? 7000 : 0); }"
);

writeln("fn(3,2,1,false): ", fn( 3, 2, 1, false ) );
writeln("fn(3,2,1,true): ", fn( 3, 2, 1, true ) );
assert( fn( 3, 2, 1, true ) == 7321 );

EOF`

# Remove newlines
CODE=$(echo "$CODE_0" | tr '\n' ' ' | tr '\r' ' ')

# Execute
cd "$(dirname $0)"/..
"$RUNNER" --eval="$CODE"
