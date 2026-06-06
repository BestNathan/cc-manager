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

# 交互原语回退路径(CCM_NO_GUM=1 → 走 read)
export CCM_NO_GUM=1
out="$(printf '\n' | _ui_input "Token" "hint" "DEFLT")"
assert_eq "_ui_input 空回车保留默认" "DEFLT" "$out"
out="$(printf 'NEW\n' | _ui_input "Token" "hint" "DEFLT")"
assert_eq "_ui_input 输入覆盖" "NEW" "$out"
( printf 'y\n' | _ui_confirm "ok?" ); assert_eq "_ui_confirm y=0" "0" "$?"
( printf 'n\n' | _ui_confirm "ok?" ); assert_eq "_ui_confirm n=1" "1" "$?"
out="$(printf 'alpha\nbeta\ngamma\n2\n' | _ui_pick "选择")"
assert_eq "_ui_pick 选第2项" "beta" "$out"
out="$(printf 'secret\n' | _ui_password "Pwd" "hint")"
assert_eq "_ui_password 回退读取" "secret" "$out"
unset CCM_NO_GUM

teardown
finish
