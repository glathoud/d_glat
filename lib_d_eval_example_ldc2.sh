#!/usr/bin/env sh

RUNNER="$(dirname $(which ldc2))/rdmd"
./lib_d_eval_example_common.sh "$RUNNER"
