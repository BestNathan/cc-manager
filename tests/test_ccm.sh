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

# 空 profiles 提示
out="$(run_ccm list)"
assert_contains "空列表提示" "暂无 profile" "$out"

# 放一个 profile 后能列出
mkdir -p "$SANDBOX/profiles"
cat >"$SANDBOX/profiles/work.env" <<'EOF'
export ANTHROPIC_AUTH_TOKEN="sk-abcd1234efgh5678"
export ANTHROPIC_BASE_URL="https://gw.example.com"
EOF
out="$(run_ccm list)"
assert_contains "列出 work" "work" "$out"
assert_contains "列出 base_url" "https://gw.example.com" "$out"
assert_eq "list 不泄露 token" "no" "$(printf '%s' "$out" | grep -q 'sk-abcd' && echo yes || echo no)"

# new 生成文件 + 权限 600(EDITOR=true 避免真打开编辑器)
run_ccm new fresh >/dev/null 2>&1
assert_eq "new 生成文件" "yes" "$([ -f "$SANDBOX/profiles/fresh.env" ] && echo yes || echo no)"
perm="$(stat -f '%Lp' "$SANDBOX/profiles/fresh.env" 2>/dev/null || stat -c '%a' "$SANDBOX/profiles/fresh.env")"
assert_eq "new 权限 600" "600" "$perm"

# 重复 new 报错(退出码非 0)
run_ccm new fresh >/dev/null 2>&1
assert_eq "重复 new 退出码1" "1" "$?"

# edit 不存在的 profile 报错
run_ccm edit nope >/dev/null 2>&1
assert_eq "edit 不存在退出码1" "1" "$?"

cat >"$SANDBOX/profiles/masktest.env" <<'EOF'
export ANTHROPIC_AUTH_TOKEN="sk-5_nclDqRENf1rPMBiPp8Aw"
export ANTHROPIC_BASE_URL="https://gw.example.com"
EOF

out="$(run_ccm show masktest)"
assert_eq "show 默认不露原 token" "no" "$(printf '%s' "$out" | grep -q 'sk-5_nclDqRENf1rPMBiPp8Aw' && echo yes || echo no)"
assert_contains "show 打码保留头部" "sk-5" "$out"
assert_contains "show 打码有星号" "***" "$out"

out="$(run_ccm show masktest --raw)"
assert_contains "show --raw 显示原文" "sk-5_nclDqRENf1rPMBiPp8Aw" "$out"

teardown
finish
