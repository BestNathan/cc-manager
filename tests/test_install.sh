#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/helpers.sh"

# 仅加载函数,不执行安装动作
CCM_INSTALL_LIB_ONLY=1 . "$HERE/../install.sh"

TESTS_RUN=0; TESTS_FAIL=0

# CCM_BIN_DIR 显式覆盖优先
out="$(CCM_BIN_DIR=/tmp/explicitbin detect_bin_dir)"
assert_eq "显式 CCM_BIN_DIR 优先" "/tmp/explicitbin" "$out"

# 候选目录在 PATH 且可写时被选中(~/.local/bin 优先)
tmphome="$(mktemp -d)"
mkdir -p "$tmphome/.local/bin"
out="$(HOME="$tmphome" PATH="$tmphome/.local/bin:/usr/bin:/bin" detect_bin_dir)"
assert_eq "选中候选 ~/.local/bin(在PATH且可写)" "$tmphome/.local/bin" "$out"

# 候选都不在 PATH 时兜底 ~/.local/bin
out="$(HOME="$tmphome" PATH="/usr/bin:/bin" detect_bin_dir)"
assert_eq "兜底 ~/.local/bin" "$tmphome/.local/bin" "$out"
rm -rf "$tmphome"

# 显式覆盖即使非 PATH 也返回该值
out="$(CCM_BIN_DIR=/usr/lo detect_bin_dir)"
assert_eq "显式覆盖即使非PATH" "/usr/lo" "$out"

finish
