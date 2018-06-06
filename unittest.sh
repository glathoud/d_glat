#!/usr/bin/env sh

set -e

A=$(realpath $PWD/$(dirname $0))
B=$A/..

MODULE_NAME=$(basename $A)

cd $B
rdmd -debug -unittest --eval="import ${MODULE_NAME}.unittest_import; import std.stdio; writeln; writeln( \"${MODULE_NAME}: All unittests passed\" )"
