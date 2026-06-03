# cc-manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一个纯 Bash CLI `ccm`,管理多个 Claude Code 环境(每个 profile 一个 `.env`),一条命令加载 profile 并启动 `claude`,支持启动时覆盖模型,并提供顺手的新建/编辑/查看/删除与跨 Linux/macOS 的自适应安装。

**Architecture:** 单一可执行脚本 `ccm` 通过子命令分发(run/list/new/edit/show/rm/env/help/version)。所有路径以 `CCM_HOME`(默认 `~/.cc-manager`,可被环境变量覆盖以便测试)为根。`run` 用 `set -a; source profile.env; set +a` 注入环境,应用模型覆盖后 `exec claude`。`install.sh` 自适应探测 bin 目录。测试用纯 bash harness + 假 `claude` 桩,无外部依赖。

**Tech Stack:** Bash (≥4,`#!/usr/bin/env bash`),zsh 补全,无第三方依赖。

---

## File Structure

| 文件 | 职责 |
|---|---|
| `ccm` | 主脚本:常量、辅助函数、各子命令、main 分发 |
| `template.env` | profile 模板(仅占位符 + 注释) |
| `completions/_ccm` | zsh 补全 |
| `install.sh` | 初始化 `~/.cc-manager` + 探测 bin 目录 + 软链 + 补全提示 |
| `tests/helpers.sh` | 测试断言框架 + 临时环境/假 claude 桩 |
| `tests/test_ccm.sh` | 集成测试(调用 ccm 实际行为) |
| `README.md` | 用法 |

**脚本内部契约(所有任务共享,务必一致):**
- 环境根:`CCM_HOME="${CCM_HOME:-$HOME/.cc-manager}"`
- `PROFILES_DIR="$CCM_HOME/profiles"`,`TEMPLATE="$CCM_HOME/template.env"`
- 辅助函数命名:`_die <code> <msg>`、`_ensure_skeleton`、`_profile_path <name>`、`_mask <token>`
- 子命令函数命名:`cmd_run`、`cmd_list`、`cmd_new`、`cmd_edit`、`cmd_show`、`cmd_rm`、`cmd_env`、`usage`
- 退出码:成功 0;用法错误 2;profile 不存在 1;缺 claude 127

---

## Task 1: 项目骨架 + 模板 + 测试框架

**Files:**
- Create: `cc-manager/ccm`
- Create: `cc-manager/template.env`
- Create: `cc-manager/tests/helpers.sh`
- Create: `cc-manager/tests/test_ccm.sh`

- [ ] **Step 1: 写最小可执行 ccm 骨架(只含常量、_die、usage、version、main 分发)**

Create `ccm`:

```bash
#!/usr/bin/env bash
# cc-manager — 管理多个 Claude Code 环境
set -o pipefail

CCM_VERSION="0.1.0"
CCM_HOME="${CCM_HOME:-$HOME/.cc-manager}"
PROFILES_DIR="$CCM_HOME/profiles"
TEMPLATE="$CCM_HOME/template.env"

_die() { # _die <code> <msg...>
  local code="$1"; shift
  printf 'cc-manager: %s\n' "$*" >&2
  exit "$code"
}

usage() {
  cat <<'EOF'
cc-manager (ccm) — 管理多个 Claude Code 环境

用法:
  ccm run <profile> [--opus M] [--sonnet M] [--haiku M] [--subagent M] [-- <claude args>]
  ccm list | ls
  ccm new <profile>
  ccm edit <profile>
  ccm show <profile> [--raw]
  ccm rm <profile>
  ccm env <profile>
  ccm help | -h | --help
  ccm version | --version
EOF
}

main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    help|-h|--help) usage ;;
    version|--version) echo "ccm $CCM_VERSION" ;;
    *) _die 2 "未知命令: $cmd(运行 'ccm help')" ;;
  esac
}

main "$@"
```

- [ ] **Step 2: 创建 template.env(仅占位符)**

Create `template.env`:

```bash
# cc-manager profile — 占位符,请替换为真实值后使用
# 启动: ccm run <本文件名去掉 .env>

export ANTHROPIC_AUTH_TOKEN="<YOUR_TOKEN_HERE>"
export ANTHROPIC_BASE_URL="<https://your-gateway.example.com>"

# 模型映射(按需修改)
export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-8"
export ANTHROPIC_DEFAULT_OPUS_MODEL_NAME="claude-opus-4-8"
export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-4-6"
export ANTHROPIC_DEFAULT_SONNET_MODEL_NAME="claude-sonnet-4-6"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku-4-5-20251001"
export ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME="claude-haiku-4-5-20251001"

# 可选:子代理模型
# export CLAUDE_CODE_SUBAGENT_MODEL="<model-id>"
```

- [ ] **Step 3: 写测试框架 helpers.sh**

Create `tests/helpers.sh`:

```bash
#!/usr/bin/env bash
# 测试辅助:断言 + 隔离环境 + 假 claude 桩
TESTS_RUN=0
TESTS_FAIL=0
CCM_BIN=""        # 由 test_ccm.sh 设置为 ccm 的绝对路径
SANDBOX=""        # 临时 CCM_HOME
STUBDIR=""        # 假 claude 所在目录

setup() {
  SANDBOX="$(mktemp -d)"
  STUBDIR="$(mktemp -d)"
  cat >"$STUBDIR/claude" <<'STUB'
#!/usr/bin/env bash
# 假 claude:把关心的 env 和 argv 写到 CLAUDE_STUB_OUT
{
  echo "OPUS=$ANTHROPIC_DEFAULT_OPUS_MODEL"
  echo "OPUS_NAME=$ANTHROPIC_DEFAULT_OPUS_MODEL_NAME"
  echo "SONNET=$ANTHROPIC_DEFAULT_SONNET_MODEL"
  echo "HAIKU=$ANTHROPIC_DEFAULT_HAIKU_MODEL"
  echo "SUBAGENT=$CLAUDE_CODE_SUBAGENT_MODEL"
  echo "TOKEN=$ANTHROPIC_AUTH_TOKEN"
  echo "BASE=$ANTHROPIC_BASE_URL"
  echo "ARGV=$*"
} >"${CLAUDE_STUB_OUT:-/dev/null}"
STUB
  chmod +x "$STUBDIR/claude"
}

teardown() { rm -rf "$SANDBOX" "$STUBDIR"; }

# 在隔离环境里跑 ccm:CCM_HOME=sandbox,PATH 前置桩目录
run_ccm() {
  CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" EDITOR=true bash "$CCM_BIN" "$@"
}

assert_eq() { # assert_eq <名称> <期望> <实际>
  TESTS_RUN=$((TESTS_RUN+1))
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    TESTS_FAIL=$((TESTS_FAIL+1))
    echo "FAIL - $1"
    echo "      expected: [$2]"
    echo "      actual:   [$3]"
  fi
}

assert_contains() { # assert_contains <名称> <子串> <文本>
  TESTS_RUN=$((TESTS_RUN+1))
  case "$3" in
    *"$2"*) echo "ok   - $1" ;;
    *) TESTS_FAIL=$((TESTS_FAIL+1)); echo "FAIL - $1"; echo "      want substr: [$2]"; echo "      in: [$3]" ;;
  esac
}

finish() {
  echo "----"
  echo "$TESTS_RUN run, $TESTS_FAIL failed"
  [ "$TESTS_FAIL" -eq 0 ]
}
```

- [ ] **Step 4: 写第一个测试(version),验证框架可跑**

Create `tests/test_ccm.sh`:

```bash
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
```

- [ ] **Step 5: 运行测试,应通过**

Run: `cd cc-manager && chmod +x ccm && bash tests/test_ccm.sh`
Expected: 2 行 `ok`,末尾 `2 run, 0 failed`,退出码 0。

- [ ] **Step 6: Commit**

```bash
cd cc-manager
git add ccm template.env tests/
git commit -m "feat: ccm 骨架 + 模板 + 测试框架"
```

---

## Task 2: 自动创建骨架 + _ensure_skeleton / _profile_path

**Files:**
- Modify: `cc-manager/ccm`
- Modify: `cc-manager/tests/test_ccm.sh`

- [ ] **Step 1: 写失败测试 —— 任意命令应自动建出 profiles 目录**

在 `tests/test_ccm.sh` 的 `teardown` 之前追加:

```bash
# 首次运行 list 应自动创建骨架
run_ccm list >/dev/null 2>&1
assert_eq "自动建 profiles 目录" "yes" "$([ -d "$SANDBOX/profiles" ] && echo yes || echo no)"
assert_eq "自动建 template.env" "yes" "$([ -f "$SANDBOX/template.env" ] && echo yes || echo no)"
```

- [ ] **Step 2: 运行,确认失败**

Run: `bash tests/test_ccm.sh`
Expected: 两条新断言 FAIL(因为 list 命令还不存在/未建骨架)。

- [ ] **Step 3: 在 ccm 中加入 _ensure_skeleton、_profile_path,并让 list 占位调用**

在 `ccm` 中 `_die` 之后插入:

```bash
_ensure_skeleton() {
  mkdir -p "$PROFILES_DIR"
  if [ ! -f "$TEMPLATE" ]; then
    cat >"$TEMPLATE" <<'EOF'
# cc-manager profile — 占位符,请替换为真实值后使用
# 启动: ccm run <本文件名去掉 .env>

export ANTHROPIC_AUTH_TOKEN="<YOUR_TOKEN_HERE>"
export ANTHROPIC_BASE_URL="<https://your-gateway.example.com>"

# 模型映射(按需修改)
export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-8"
export ANTHROPIC_DEFAULT_OPUS_MODEL_NAME="claude-opus-4-8"
export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-4-6"
export ANTHROPIC_DEFAULT_SONNET_MODEL_NAME="claude-sonnet-4-6"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku-4-5-20251001"
export ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME="claude-haiku-4-5-20251001"

# 可选:子代理模型
# export CLAUDE_CODE_SUBAGENT_MODEL="<model-id>"
EOF
  fi
}

_profile_path() { printf '%s/%s.env' "$PROFILES_DIR" "$1"; }
```

在 `main` 的 `case` 中,`version` 分支之后、`*)` 之前加入临时 list 分支:

```bash
    list|ls) _ensure_skeleton ;;
```

- [ ] **Step 4: 运行,确认通过**

Run: `bash tests/test_ccm.sh`
Expected: 全 `ok`,`4 run, 0 failed`。

- [ ] **Step 5: Commit**

```bash
git add ccm tests/test_ccm.sh
git commit -m "feat: 自动创建 ~/.cc-manager 骨架"
```

---

## Task 3: ccm list / ls

**Files:**
- Modify: `cc-manager/ccm`
- Modify: `cc-manager/tests/test_ccm.sh`

- [ ] **Step 1: 写失败测试 —— 空目录提示 + 有 profile 时列名与 base_url**

在 `tests/test_ccm.sh` 的 `teardown` 之前追加:

```bash
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
```

- [ ] **Step 2: 运行,确认失败**

Run: `bash tests/test_ccm.sh`
Expected: 新断言 FAIL(list 目前是空操作)。

- [ ] **Step 3: 实现 cmd_list,替换 main 中临时分支**

在 `ccm` 的 `_profile_path` 之后加入:

```bash
cmd_list() {
  _ensure_skeleton
  local found=0 f name url line
  for f in "$PROFILES_DIR"/*.env; do
    [ -e "$f" ] || continue
    found=1
    name="$(basename "$f" .env)"
    line="$(grep -E '^[[:space:]]*export[[:space:]]+ANTHROPIC_BASE_URL=' "$f" | head -1)"
    url="${line#*=}"
    url="${url%\"}"; url="${url#\"}"
    url="${url%\'}"; url="${url#\'}"
    printf '%-20s %s\n' "$name" "${url:-(no base_url)}"
  done
  [ "$found" -eq 1 ] || echo "(暂无 profile,用 'ccm new <name>' 创建)"
}
```

将 `main` 中 `list|ls) _ensure_skeleton ;;` 改为:

```bash
    list|ls) cmd_list ;;
```

- [ ] **Step 4: 运行,确认通过**

Run: `bash tests/test_ccm.sh`
Expected: 全 `ok`。

- [ ] **Step 5: Commit**

```bash
git add ccm tests/test_ccm.sh
git commit -m "feat: ccm list/ls"
```

---

## Task 4: ccm new / edit

**Files:**
- Modify: `cc-manager/ccm`
- Modify: `cc-manager/tests/test_ccm.sh`

- [ ] **Step 1: 写失败测试 —— new 生成文件且权限 600;new 已存在则报错;edit 不存在则报错**

在 `tests/test_ccm.sh` 的 `teardown` 之前追加:

```bash
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
```

注:`stat` 在 macOS 用 `-f '%Lp'`,Linux 用 `-c '%a'`,测试已兼容两者。

- [ ] **Step 2: 运行,确认失败**

Run: `bash tests/test_ccm.sh`
Expected: new/edit 相关断言 FAIL(命令未实现 → 走 `_die 2` 退出码 2,不等于期望)。

- [ ] **Step 3: 实现 cmd_new / cmd_edit**

在 `ccm` 的 `cmd_list` 之后加入:

```bash
cmd_new() {
  local name="$1"
  [ -n "$name" ] || _die 2 "用法: ccm new <profile>"
  _ensure_skeleton
  local pf; pf="$(_profile_path "$name")"
  [ -f "$pf" ] && _die 1 "profile '$name' 已存在(用 'ccm edit $name')"
  cp "$TEMPLATE" "$pf"
  chmod 600 "$pf"
  echo "已创建 $pf"
  "${EDITOR:-vi}" "$pf"
}

cmd_edit() {
  local name="$1"
  [ -n "$name" ] || _die 2 "用法: ccm edit <profile>"
  local pf; pf="$(_profile_path "$name")"
  [ -f "$pf" ] || _die 1 "profile '$name' 不存在(用 'ccm new $name')"
  "${EDITOR:-vi}" "$pf"
}
```

在 `main` 的 `case` 中 `list|ls)` 之后加入:

```bash
    new) cmd_new "$@" ;;
    edit) cmd_edit "$@" ;;
```

- [ ] **Step 4: 运行,确认通过**

Run: `bash tests/test_ccm.sh`
Expected: 全 `ok`。

- [ ] **Step 5: Commit**

```bash
git add ccm tests/test_ccm.sh
git commit -m "feat: ccm new/edit"
```

---

## Task 5: ccm show(默认打码 + --raw)

**Files:**
- Modify: `cc-manager/ccm`
- Modify: `cc-manager/tests/test_ccm.sh`

- [ ] **Step 1: 写失败测试 —— show 默认打码,--raw 显示原文**

在 `tests/test_ccm.sh` 的 `teardown` 之前追加:

```bash
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
```

- [ ] **Step 2: 运行,确认失败**

Run: `bash tests/test_ccm.sh`
Expected: show 断言 FAIL。

- [ ] **Step 3: 实现 _mask 与 cmd_show**

在 `ccm` 的 `_profile_path` 之后加入 `_mask`:

```bash
_mask() { # _mask <secret> -> 头4***尾4(过短则全星)
  local s="$1" n=${#1}
  if [ "$n" -le 8 ]; then printf '****'; else printf '%s***%s' "${s:0:4}" "${s: -4}"; fi
}
```

在 `cmd_edit` 之后加入 `cmd_show`:

```bash
cmd_show() {
  local name="" raw=0 a
  for a in "$@"; do
    case "$a" in
      --raw) raw=1 ;;
      -*) _die 2 "未知选项: $a" ;;
      *) [ -z "$name" ] && name="$a" || _die 2 "多余参数: $a" ;;
    esac
  done
  [ -n "$name" ] || _die 2 "用法: ccm show <profile> [--raw]"
  local pf; pf="$(_profile_path "$name")"
  [ -f "$pf" ] || _die 1 "profile '$name' 不存在"
  if [ "$raw" -eq 1 ]; then
    cat "$pf"
    return
  fi
  # 打码:对 ANTHROPIC_AUTH_TOKEN 的值做掩码,其余原样
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *ANTHROPIC_AUTH_TOKEN=*)
        val="${line#*=}"
        val="${val%\"}"; val="${val#\"}"
        val="${val%\'}"; val="${val#\'}"
        printf 'export ANTHROPIC_AUTH_TOKEN="%s"\n' "$(_mask "$val")"
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <"$pf"
}
```

在 `main` 的 `case` 中 `edit)` 之后加入:

```bash
    show) cmd_show "$@" ;;
```

- [ ] **Step 4: 运行,确认通过**

Run: `bash tests/test_ccm.sh`
Expected: 全 `ok`。

- [ ] **Step 5: Commit**

```bash
git add ccm tests/test_ccm.sh
git commit -m "feat: ccm show(默认打码 token,--raw 原文)"
```

---

## Task 6: ccm rm / env

**Files:**
- Modify: `cc-manager/ccm`
- Modify: `cc-manager/tests/test_ccm.sh`

- [ ] **Step 1: 写失败测试 —— env 输出路径;rm 经 stdin 确认后删除**

在 `tests/test_ccm.sh` 的 `teardown` 之前追加:

```bash
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
```

- [ ] **Step 2: 运行,确认失败**

Run: `bash tests/test_ccm.sh`
Expected: env/rm 断言 FAIL。

- [ ] **Step 3: 实现 cmd_env / cmd_rm**

在 `ccm` 的 `cmd_show` 之后加入:

```bash
cmd_env() {
  local name="$1"
  [ -n "$name" ] || _die 2 "用法: ccm env <profile>"
  local pf; pf="$(_profile_path "$name")"
  [ -f "$pf" ] || _die 1 "profile '$name' 不存在"
  printf '%s\n' "$pf"
}

cmd_rm() {
  local name="$1"
  [ -n "$name" ] || _die 2 "用法: ccm rm <profile>"
  local pf; pf="$(_profile_path "$name")"
  [ -f "$pf" ] || _die 1 "profile '$name' 不存在"
  printf "确认删除 profile '%s'? [y/N] " "$name"
  local ans; read -r ans
  case "$ans" in
    y|Y|yes|YES) rm -f "$pf"; echo "已删除 $name" ;;
    *) echo "已取消" ;;
  esac
}
```

在 `main` 的 `case` 中 `show)` 之后加入:

```bash
    rm) cmd_rm "$@" ;;
    env) cmd_env "$@" ;;
```

- [ ] **Step 4: 运行,确认通过**

Run: `bash tests/test_ccm.sh`
Expected: 全 `ok`。

- [ ] **Step 5: Commit**

```bash
git add ccm tests/test_ccm.sh
git commit -m "feat: ccm rm/env"
```

---

## Task 7: ccm run(核心:参数解析 + source + 模型覆盖 + 检查 + exec)

**Files:**
- Modify: `cc-manager/ccm`
- Modify: `cc-manager/tests/test_ccm.sh`

- [ ] **Step 1: 写失败测试 —— 启动注入 env、模型覆盖、--透传、不存在报错**

在 `tests/test_ccm.sh` 的 `teardown` 之前追加:

```bash
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
```

- [ ] **Step 2: 运行,确认失败**

Run: `bash tests/test_ccm.sh`
Expected: run 相关断言 FAIL。

- [ ] **Step 3: 实现 cmd_run**

在 `ccm` 的 `cmd_rm` 之后加入:

```bash
usage_run() {
  echo "用法: ccm run <profile> [--opus M] [--sonnet M] [--haiku M] [--subagent M] [-- <claude args>]" >&2
}

cmd_run() {
  local profile="" opus="" sonnet="" haiku="" subagent=""
  local passthrough=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --opus)     opus="$2";     shift 2 ;;
      --sonnet)   sonnet="$2";   shift 2 ;;
      --haiku)    haiku="$2";    shift 2 ;;
      --subagent) subagent="$2"; shift 2 ;;
      --) shift; passthrough=("$@"); break ;;
      -*) usage_run; exit 2 ;;
      *)  if [ -z "$profile" ]; then profile="$1"; shift; else _die 2 "多余参数: $1"; fi ;;
    esac
  done

  if [ -z "$profile" ]; then usage_run; exit 2; fi

  local pf; pf="$(_profile_path "$profile")"
  if [ ! -f "$pf" ]; then
    echo "cc-manager: profile '$profile' 不存在,可用:" >&2
    cmd_list >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  . "$pf"
  set +a

  if [ -n "$opus" ];     then export ANTHROPIC_DEFAULT_OPUS_MODEL="$opus";     export ANTHROPIC_DEFAULT_OPUS_MODEL_NAME="$opus"; fi
  if [ -n "$sonnet" ];   then export ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet"; export ANTHROPIC_DEFAULT_SONNET_MODEL_NAME="$sonnet"; fi
  if [ -n "$haiku" ];    then export ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku";   export ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME="$haiku"; fi
  if [ -n "$subagent" ]; then export CLAUDE_CODE_SUBAGENT_MODEL="$subagent"; fi

  [ -n "$ANTHROPIC_AUTH_TOKEN" ] || echo "cc-manager: 警告 — ANTHROPIC_AUTH_TOKEN 为空" >&2
  [ -n "$ANTHROPIC_BASE_URL" ]   || echo "cc-manager: 警告 — ANTHROPIC_BASE_URL 为空" >&2

  command -v claude >/dev/null 2>&1 || _die 127 "未找到 'claude' 命令(请确认已安装并在 PATH 中)"

  exec claude "${passthrough[@]}"
}
```

在 `main` 的 `case` 中 `env)` 之后加入:

```bash
    run) cmd_run "$@" ;;
```

- [ ] **Step 4: 运行,确认通过**

Run: `bash tests/test_ccm.sh`
Expected: 全 `ok`,`<N> run, 0 failed`。

- [ ] **Step 5: Commit**

```bash
git add ccm tests/test_ccm.sh
git commit -m "feat: ccm run — 加载 profile、模型覆盖、透传、exec claude"
```

---

## Task 8: zsh 补全 _ccm

**Files:**
- Create: `cc-manager/completions/_ccm`

- [ ] **Step 1: 写补全脚本**

Create `completions/_ccm`:

```zsh
#compdef ccm
# cc-manager zsh 补全

_ccm_profiles() {
  local dir="${CCM_HOME:-$HOME/.cc-manager}/profiles"
  local -a names
  names=()
  local f
  for f in "$dir"/*.env(N); do
    names+=("${${f:t}:r}")
  done
  compadd -- $names
}

_ccm() {
  local -a subcmds
  subcmds=(run list ls new edit show rm env help version)
  if (( CURRENT == 2 )); then
    compadd -- $subcmds
    return
  fi
  local cmd="${words[2]}"
  case "$cmd" in
    run)
      # profile 名 + 模型 flag
      if [[ "${words[CURRENT]}" == --* ]]; then
        compadd -- --opus --sonnet --haiku --subagent --
      else
        _ccm_profiles
      fi
      ;;
    edit|show|rm|env)
      _ccm_profiles
      ;;
  esac
}

_ccm "$@"
```

- [ ] **Step 2: 语法自检(zsh 能加载且无报错)**

Run: `zsh -c 'autoload -Uz compinit; compinit -u; fpath=(cc-manager/completions $fpath); source cc-manager/completions/_ccm; echo OK'`
Expected: 打印 `OK`,无语法错误。

- [ ] **Step 3: 手动功能验证(可选,非阻断)**

说明:在装好后,于交互 zsh 中输入 `ccm run <Tab>` 应补全 profile 名。此为人工验证项,记录于 README。

- [ ] **Step 4: Commit**

```bash
git add completions/_ccm
git commit -m "feat: zsh 补全 _ccm"
```

---

## Task 9: install.sh(自适应 bin 目录)

**Files:**
- Create: `cc-manager/install.sh`
- Create: `cc-manager/tests/test_install.sh`

- [ ] **Step 1: 写失败测试 —— bin 目录探测函数(可独立 source)**

Create `tests/test_install.sh`:

```bash
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

# 子串不应误判:dir 是 PATH 中某段的子串但非整段时不应选中
# /usr/lo 不是 /usr/local/bin 的整段 -> 不会被当作命中
out="$(CCM_BIN_DIR=/usr/lo detect_bin_dir)"  # 显式覆盖,确认函数仍返回显式值
assert_eq "显式覆盖即使非PATH" "/usr/lo" "$out"

finish
```

- [ ] **Step 2: 运行,确认失败**

Run: `bash tests/test_install.sh`
Expected: 报错(install.sh / detect_bin_dir 不存在)。

- [ ] **Step 3: 写 install.sh**

Create `install.sh`:

```bash
#!/usr/bin/env bash
# cc-manager 安装脚本(Linux / macOS)
set -o pipefail

CCM_HOME="${CCM_HOME:-$HOME/.cc-manager}"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

# 判断目录是否为 PATH 的精确一段
_in_path() {
  case ":$PATH:" in *":$1:"*) return 0 ;; *) return 1 ;; esac
}

# 探测安装 bin 目录:显式覆盖 > PATH中且可写的候选 > 兜底 ~/.local/bin
detect_bin_dir() {
  if [ -n "$CCM_BIN_DIR" ]; then printf '%s\n' "$CCM_BIN_DIR"; return; fi
  local brewbin=""
  if command -v brew >/dev/null 2>&1; then brewbin="$(brew --prefix)/bin"; fi
  local c
  for c in "$HOME/.local/bin" "$HOME/bin" "$brewbin" "/usr/local/bin"; do
    [ -n "$c" ] || continue
    if _in_path "$c" && [ -w "$c" ]; then printf '%s\n' "$c"; return; fi
  done
  printf '%s\n' "$HOME/.local/bin"
}

# 检测当前 shell 的 rc 文件(用于 PATH 提示)
_shell_rc() {
  case "${SHELL##*/}" in
    zsh) printf '%s\n' "$HOME/.zshrc" ;;
    bash)
      if [ "$(uname -s)" = "Darwin" ]; then printf '%s\n' "$HOME/.bash_profile";
      else printf '%s\n' "$HOME/.bashrc"; fi ;;
    *) printf '%s\n' "$HOME/.profile" ;;
  esac
}

main() {
  # 1. 骨架
  mkdir -p "$CCM_HOME/profiles" "$CCM_HOME/completions"
  if [ ! -f "$CCM_HOME/template.env" ]; then
    cp "$SRC_DIR/template.env" "$CCM_HOME/template.env"
  fi
  cp "$SRC_DIR/completions/_ccm" "$CCM_HOME/completions/_ccm"

  # 2. bin 目录 + 软链
  local bindir; bindir="$(detect_bin_dir)"
  mkdir -p "$bindir"
  ln -sf "$SRC_DIR/ccm" "$bindir/ccm"
  chmod +x "$SRC_DIR/ccm"
  echo "✓ 已链接: $bindir/ccm -> $SRC_DIR/ccm"

  # 3. PATH 提示
  if ! _in_path "$bindir"; then
    echo "⚠ $bindir 不在 PATH。请在 $(_shell_rc) 追加:"
    echo "    export PATH=\"$bindir:\$PATH\""
  fi

  # 4. 补全提示
  echo "✓ 补全已放到 $CCM_HOME/completions/_ccm"
  echo "  在 $(_shell_rc) 追加(若未配置 fpath):"
  echo "    fpath=($CCM_HOME/completions \$fpath)"
  echo "    autoload -Uz compinit && compinit"

  echo "✓ 完成。试试: ccm list"
}

# 测试时只想加载函数,不执行 main
if [ -z "$CCM_INSTALL_LIB_ONLY" ]; then main "$@"; fi
```

- [ ] **Step 4: 运行,确认通过**

Run: `bash tests/test_install.sh`
Expected: 全 `ok`,`<N> run, 0 failed`。

- [ ] **Step 5: Commit**

```bash
chmod +x install.sh
git add install.sh tests/test_install.sh
git commit -m "feat: install.sh — 自适应探测 bin 目录(Linux/macOS)"
```

---

## Task 10: README + 全量测试 runner

**Files:**
- Create: `cc-manager/README.md`
- Create: `cc-manager/tests/run_all.sh`

- [ ] **Step 1: 写 run_all.sh 聚合测试**

Create `tests/run_all.sh`:

```bash
#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
fail=0
for t in "$HERE"/test_*.sh; do
  echo "== $(basename "$t") =="
  bash "$t" || fail=1
done
exit "$fail"
```

- [ ] **Step 2: 运行全量测试**

Run: `cd cc-manager && bash tests/run_all.sh`
Expected: 两个测试文件均 `0 failed`,退出码 0。

- [ ] **Step 3: 写 README.md**

Create `README.md`:

````markdown
# cc-manager (`ccm`)

管理多个 Claude Code 环境(不同网关 / token / 模型映射),一条命令加载并启动 `claude`。

## 安装

```bash
git clone <repo> cc-manager && cd cc-manager
./install.sh                 # 自动探测 bin 目录(Linux/macOS)
# 或指定: CCM_BIN_DIR=~/.local/bin ./install.sh
```

按提示把 bin 目录与补全 `fpath` 加入你的 shell rc,然后 `exec $SHELL`。

## 用法

```bash
ccm new work                 # 从模板创建并打开编辑器填 token/url
ccm list                     # 列出所有 profile(token 不显示)
ccm show work                # 查看(token 打码);--raw 看原文
ccm run work                 # 加载 work 并启动 claude
ccm run work --opus claude-opus-4-7        # 临时覆盖 opus 模型
ccm run work -- --resume                   # -- 之后透传给 claude
ccm edit work                # 编辑
ccm rm work                  # 删除(确认)
ccm env work                 # 输出 profile 路径: source "$(ccm env work)"
```

## profile 文件

位于 `~/.cc-manager/profiles/<name>.env`,内容为 `export KEY=VAL`。
模型覆盖会同时设置 `ANTHROPIC_DEFAULT_<TIER>_MODEL` 与 `..._MODEL_NAME`。

## 配置目录

`~/.cc-manager/`(可用 `CCM_HOME` 覆盖)。profile 文件权限 600。

## 测试

```bash
bash tests/run_all.sh
```

## 限制

- 仅支持 Linux / macOS。
- token 以明文存于 .env(依赖文件权限),非加密存储。
````

- [ ] **Step 4: 提交**

```bash
chmod +x tests/run_all.sh
git add README.md tests/run_all.sh
git commit -m "docs: README + 全量测试 runner"
```

- [ ] **Step 5: 真实冒烟(可选,人工)**

说明:`ccm new smoke` 填入真实网关与 token 后 `ccm run smoke -- --version`,确认 claude 用对了 base_url。此为人工验证项,不在自动测试内。

---

## Self-Review

**Spec coverage:**
- 目录布局 → Task 1/2(骨架自动创建) ✓
- run + 模型覆盖 + 透传 → Task 7 ✓
- list/new/edit/show(打码)/rm/env → Task 3/4/5/6 ✓
- token 打码 + --raw → Task 5 ✓
- zsh 补全 → Task 8 ✓
- install.sh 自适应 bin 目录(显式覆盖/PATH精确匹配/兜底/shell rc 提示) → Task 9 ✓
- 错误处理(不存在=1、缺名=2、缺 claude=127、缺 token 仅 warning) → Task 7 ✓
- 测试策略(假 claude 桩、打码、参数解析、bin 探测) → Task 1/5/7/9 ✓
- README → Task 10 ✓
- 模板仅占位符 → Task 1/2 ✓

**Placeholder scan:** 无 TBD/TODO;每个代码步骤含完整代码与可运行命令。✓

**Type/命名一致性:** `CCM_HOME`、`PROFILES_DIR`、`TEMPLATE`、`_die`、`_ensure_skeleton`、`_profile_path`、`_mask`、`cmd_*`、`detect_bin_dir`、`_in_path`、`usage_run` 在各任务间一致;run 的模型 flag 同步写 `*_MODEL` 与 `*_MODEL_NAME` 与 spec 一致。✓
