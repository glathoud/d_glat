#!/usr/bin/env sh

RUNNER="$(dirname $(which dmd))/rdmd"
./lib_d_eval_example_common.sh "$RUNNER"
