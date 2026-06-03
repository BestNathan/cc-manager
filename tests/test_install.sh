#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/helpers.sh"

# 仅加载函数,不执行安装动作
CCM_INSTALL_LIB_ONLY=1 . "$HERE/../install.sh"

TESTS_RUN=0; TESTS_FAIL=0

# CCM_BIN_DIR 显式覆盖优先
out="$(CCM_BIN_DIR=/tmp/explicitbin detect_bin_dir)"
assert_eq "显式 CCM_BIN_DIR 优先" "/tmp/explicitbin" "$out"

# PATH 段精确匹配:构造一个在 PATH 且可写的临时目录
tmpbin="$(mktemp -d)"
out="$(PATH="$tmpbin:/usr/bin:/bin" HOME=/nonexistent_home_xyz detect_bin_dir)"
assert_eq "选中 PATH 中可写目录" "$tmpbin" "$out"
rm -rf "$tmpbin"

# 显式覆盖即使非 PATH 也返回该值
out="$(CCM_BIN_DIR=/usr/lo detect_bin_dir)"
assert_eq "显式覆盖即使非PATH" "/usr/lo" "$out"

finish
