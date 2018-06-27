#!/usr/bin/env bash

#!/usr/bin/env bash

set -e

A=$(realpath $PWD/$(dirname $0))
B=$A/..

MODULE_NAME=$(basename $A)


FILE_LIST=$( find . -name '*.d' -exec grep -l unittest {} \; )
IMPORT_LIST=$( ( sed 's:/:.:g' | sed 's:^\.\.::g' | sed "s/^\(.*\).d$/import ${MODULE_NAME}.\1;/g" ) <<< "$FILE_LIST" )
echo $IMPORT_LIST

cd $B
rdmd --force -inline -debug -unittest --eval="${IMPORT_LIST}; import std.stdio; writeln; writeln( \"${MODULE_NAME}: All unittests passed\" )"
