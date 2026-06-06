#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/helpers.sh"
CCM_BIN="$HERE/../ccm"
setup

# source ccm 的函数定义(用 CCM_SOURCED 短路 main)
CCM_SOURCED=1 . "$CCM_BIN"

# 渲染门:有 gum 二进制即真(不要求 tty)
PATH="$STUBDIR:$PATH"; make_gum_stub "$STUBDIR"
assert_eq "_has_gum 有gum为真" "0" "$(_has_gum; echo $?)"
assert_eq "CCM_NO_GUM=1 渲染门为假" "1" "$(CCM_NO_GUM=1; _has_gum; echo $?)"

# 交互门:CCM_NO_GUM=1 必为假
assert_eq "CCM_NO_GUM=1 交互门为假" "1" "$(CCM_NO_GUM=1; _gum_interactive; echo $?)"

teardown
finish
