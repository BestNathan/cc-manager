#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/helpers.sh"
CCM_BIN="$HERE/../ccm"

setup

# version
out="$(run_ccm version)"
assert_eq "version 输出" "ccm 0.1.0" "$out"

# help 含 run 用法
out="$(run_ccm help)"
assert_contains "help 含 run" "ccm run <profile>" "$out"

teardown
finish
