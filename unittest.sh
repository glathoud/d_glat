#!/usr/bin/env sh

set -e

A=$PWD/$(dirname $0)
B=$A/..
cd $B
rdmd -debug -unittest $A/unittest.d
