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

# 首次运行 list 应自动创建骨架
run_ccm list >/dev/null 2>&1
assert_eq "自动建 profiles 目录" "yes" "$([ -d "$SANDBOX/profiles" ] && echo yes || echo no)"
assert_eq "自动建 template.env" "yes" "$([ -f "$SANDBOX/template.env" ] && echo yes || echo no)"

teardown
finish
