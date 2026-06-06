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

# new 生成文件 + 权限 600(用 8 个空行接受默认值)
printf '\n\n\n\n\n\n\n\n' | run_ccm new fresh >/dev/null 2>&1
assert_eq "new 生成文件" "yes" "$([ -f "$SANDBOX/profiles/fresh.env" ] && echo yes || echo no)"
perm="$(stat -f '%Lp' "$SANDBOX/profiles/fresh.env" 2>/dev/null || stat -c '%a' "$SANDBOX/profiles/fresh.env")"
assert_eq "new 权限 600" "600" "$perm"

# 重复 new 报错(退出码非 0)
printf '\n\n\n\n\n\n\n\n' | run_ccm new fresh >/dev/null 2>&1
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

# env 输出绝对路径
cat >"$SANDBOX/profiles/envtest.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://gw.example.com"
EOF
out="$(run_ccm env envtest)"
assert_eq "env 输出路径" "$SANDBOX/profiles/envtest.env" "$out"

# rm 输入 y 删除
printf 'y\n' | CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" bash "$CCM_BIN" rm envtest >/dev/null 2>&1
assert_eq "rm 后文件消失" "no" "$([ -f "$SANDBOX/profiles/envtest.env" ] && echo yes || echo no)"

# rm 输入 n 保留
cat >"$SANDBOX/profiles/keep.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://gw.example.com"
EOF
printf 'n\n' | CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" bash "$CCM_BIN" rm keep >/dev/null 2>&1
assert_eq "rm n 保留文件" "yes" "$([ -f "$SANDBOX/profiles/keep.env" ] && echo yes || echo no)"

# 非法 profile 名(路径穿越)应被拒绝,退出码 2
run_ccm show '../evil' >/dev/null 2>&1
assert_eq "拒绝路径穿越 ../" "2" "$?"
run_ccm env 'a/b' >/dev/null 2>&1
assert_eq "拒绝含斜杠名" "2" "$?"

# 准备一个完整 profile
cat >"$SANDBOX/profiles/work.env" <<'EOF'
export ANTHROPIC_AUTH_TOKEN="sk-token-xyz"
export ANTHROPIC_BASE_URL="https://gw.example.com"
export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-8"
export ANTHROPIC_DEFAULT_OPUS_MODEL_NAME="claude-opus-4-8"
export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-4-6"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku-4-5-20251001"
EOF

# 基本启动:env 被注入到(假)claude
OUT="$SANDBOX/run1.txt"
CLAUDE_STUB_OUT="$OUT" run_ccm run work >/dev/null 2>&1
assert_contains "run 注入 token" "TOKEN=sk-token-xyz" "$(cat "$OUT")"
assert_contains "run 注入 base" "BASE=https://gw.example.com" "$(cat "$OUT")"
assert_contains "run 默认 opus" "OPUS=claude-opus-4-8" "$(cat "$OUT")"

# 模型覆盖:--opus 同时改 MODEL 与 MODEL_NAME
OUT="$SANDBOX/run2.txt"
CLAUDE_STUB_OUT="$OUT" run_ccm run work --opus claude-opus-4-7 >/dev/null 2>&1
assert_contains "覆盖 opus model" "OPUS=claude-opus-4-7" "$(cat "$OUT")"
assert_contains "覆盖 opus name" "OPUS_NAME=claude-opus-4-7" "$(cat "$OUT")"

# --subagent 覆盖
OUT="$SANDBOX/run3.txt"
CLAUDE_STUB_OUT="$OUT" run_ccm run work --subagent claude-opus-4-7 >/dev/null 2>&1
assert_contains "覆盖 subagent" "SUBAGENT=claude-opus-4-7" "$(cat "$OUT")"

# -- 之后参数透传给 claude
OUT="$SANDBOX/run4.txt"
CLAUDE_STUB_OUT="$OUT" run_ccm run work -- --resume foo >/dev/null 2>&1
assert_contains "透传 argv" "ARGV=--resume foo" "$(cat "$OUT")"

# 不存在的 profile:退出码 1 且列出可用
run_ccm run nope >/dev/null 2>&1
assert_eq "run 不存在退出码1" "1" "$?"
out="$(run_ccm run nope 2>&1)"
assert_contains "run 不存在列出 work" "work" "$out"

# 缺 profile 名:退出码 2
run_ccm run >/dev/null 2>&1
assert_eq "run 缺名退出码2" "2" "$?"

# 取值 flag 缺少参数 -> 退出码 2,且不能挂起
# 用后台子进程 + kill 兜底,避免死循环卡住测试
_timed_run() { # _timed_run <秒> <args...>; 打印退出码,超时则视为失败(码124)
  local secs="$1"; shift
  ( CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" CCM_NO_GUM=1 bash "$CCM_BIN" "$@" >/dev/null 2>&1 ) &
  local pid=$!
  ( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) &
  local killer=$!
  if wait "$pid" 2>/dev/null; then echo 0; else
    local rc=$?
    kill -9 "$killer" 2>/dev/null
    # 被 kill -9 的进程 wait 返回 137;否则返回真实退出码
    if [ "$rc" -eq 137 ]; then echo 124; else echo "$rc"; fi
  fi
  kill -9 "$killer" 2>/dev/null; wait "$killer" 2>/dev/null
}

rc="$(_timed_run 3 run work --opus)"
assert_eq "run --opus 缺值不挂起且退出2" "2" "$rc"

# flag 值不能是另一个 flag
run_ccm run work --sonnet --opus >/dev/null 2>&1
assert_eq "run --sonnet 值为flag报错2" "2" "$?"

# list gum 渲染分支测试
make_gum_stub "$STUBDIR"
cat >"$SANDBOX/profiles/work.env" <<'EOF'
export ANTHROPIC_AUTH_TOKEN="sk-abcd1234efgh5678"
export ANTHROPIC_BASE_URL="https://gw.example.com"
EOF
GUM_STUB_OUT="$SANDBOX/gumlog.txt" CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" bash "$CCM_BIN" list >/dev/null 2>&1
assert_contains "list 走 gum 渲染分支" "GUM style" "$(cat "$SANDBOX/gumlog.txt")"
# 回退路径仍含 work、不泄露 token
out="$(CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" CCM_NO_GUM=1 bash "$CCM_BIN" list)"
assert_contains "list 回退含 work" "work" "$out"
assert_eq "list 回退不泄露 token" "no" "$(printf '%s' "$out" | grep -q 'sk-abcd' && echo yes || echo no)"

# show 在 gum 可用时走 gum 渲染分支(经 GUM_STUB_OUT 日志证明),且仍打码
make_gum_stub "$STUBDIR"
cat >"$SANDBOX/profiles/masktest.env" <<'EOF'
export ANTHROPIC_AUTH_TOKEN="sk-5_nclDqRENf1rPMBiPp8Aw"
export ANTHROPIC_BASE_URL="https://gw.example.com"
EOF
GUM_STUB_OUT="$SANDBOX/gumshow.txt" CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" bash "$CCM_BIN" show masktest >/dev/null 2>&1
assert_contains "show 走 gum 渲染分支" "GUM style" "$(cat "$SANDBOX/gumshow.txt")"
# 回退路径仍打码、不露原 token
out="$(CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" CCM_NO_GUM=1 bash "$CCM_BIN" show masktest)"
assert_eq "show 回退不露原token" "no" "$(printf '%s' "$out" | grep -q 'sk-5_nclDqRENf1rPMBiPp8Aw' && echo yes || echo no)"
assert_contains "show 回退保留头部" "sk-5" "$out"

# rm 成功消息经 _ui_say,在 gum 可用时走 gum 渲染(经 GUM_STUB_OUT 日志证明)
make_gum_stub "$STUBDIR"
cat >"$SANDBOX/profiles/delme.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://gw.example.com"
EOF
printf 'y\n' | GUM_STUB_OUT="$SANDBOX/gumrm.txt" CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" bash "$CCM_BIN" rm delme >/dev/null 2>&1
assert_eq "rm delme 删除成功" "no" "$([ -f "$SANDBOX/profiles/delme.env" ] && echo yes || echo no)"
assert_contains "rm 成功消息经 gum 渲染" "GUM style" "$(cat "$SANDBOX/gumrm.txt")"

# backup-restore 缺 N:在 gum 可用时也应直接用法报错(退出2),不弹选择器
make_gum_stub "$STUBDIR"
cat >"$SANDBOX/profiles/brtest.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://gw.example.com"
EOF
GUM_STUB_OUT="$SANDBOX/gumbr.txt" CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" bash "$CCM_BIN" backup-restore brtest >/dev/null 2>&1
assert_eq "backup-restore 缺N退出2" "2" "$?"
assert_eq "backup-restore 缺N不弹选择器" "no" "$([ -s "$SANDBOX/gumbr.txt" ] && grep -q 'filter' "$SANDBOX/gumbr.txt" && echo yes || echo no)"

teardown
finish
