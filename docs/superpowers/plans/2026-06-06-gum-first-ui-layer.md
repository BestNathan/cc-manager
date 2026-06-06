# gum-first UI 层 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ccm` 所有面向用户的输出收敛为 gum-first 渲染:gum 可用时由 gum 渲染(交互 + 上色),不可用时回退到现有 ANSI/`printf`,行为与字节输出在回退路径下保持不变。

**Architecture:** 拆分两个能力门(`_has_gum` 渲染门 / `_gum_interactive` 交互门);新增集中式交互原语(`_ui_input/_ui_password/_ui_confirm/_ui_pick`)替换现有重复的 `_ui_gum_*` + shell 变体;每个渲染面(list/show/消息)用 `if _has_gum` 分派,gum 分支新增、else 分支保留现有代码逐字不变;新增 `_resolve_profile_arg` 在缺参时弹 gum 选择器。

**Tech Stack:** 纯 Bash;charm.sh/gum 0.17.x;现有自研测试框架(`tests/helpers.sh` 的 `assert_eq`/`assert_contains` + fake `claude` 桩)。

**关键不变量(贯穿全程):** 回退路径(`CCM_NO_GUM=1`)的输出必须与当前逐字一致——现有 ~27 条断言在每个 commit 后必须全绿。gum 路径是新增行为,单独用 fake `gum` 桩测试。

---

## File Structure

| 文件 | 职责 |
|------|------|
| `ccm` | 能力门、`_ui_*` 交互原语、渲染面 gum 分派、`_resolve_profile_arg`、向导合并。所有改动集中于此单文件(项目本就是扁平单脚本)。 |
| `tests/helpers.sh` | 把 `run_ccm` 的死变量 `CCM_NO_DIALOG=1` 改为 `CCM_NO_GUM=1`;新增 `make_gum_stub` 生成 fake gum 桩。 |
| `tests/test_ccm.sh` | 现有断言不动(经回退路径保持绿);文件末尾新增 gum 路径与选择器断言。`_timed_run` 内联的 env 同步改为 `CCM_NO_GUM=1`。 |
| `tests/test_ui.sh`(新) | 单元测试能力门与渲染原语(source `ccm` 后直接调函数)。 |
| `tests/run_all.sh` | 注册 `test_ui.sh`。 |
| `install.sh` | 确保 `gum` 在可选依赖 `_OPT_DEPS` 中。 |
| `completions/_ccm` | 核对:无新增子命令/flag,**不改**。 |

---

## Task 1: 测试夹具切换到 CCM_NO_GUM + gum 桩工厂

**为什么先做:** 现有测试只因 `[ -t 0 ]` 偶然走回退。后续任务移除该耦合后,测试若不强制 `CCM_NO_GUM=1` 会在有 `/dev/tty` 的终端里读真实 tty 而挂起。必须先让回退路径在测试中确定化。

**Files:**
- Modify: `tests/helpers.sh:32-34`(`run_ccm`)
- Modify: `tests/helpers.sh`(新增 `make_gum_stub`,追加到文件末尾 `finish` 之前)
- Modify: `tests/test_ccm.sh:134`(`_timed_run` 内的 env)

- [ ] **Step 1: 改 `run_ccm` 用 `CCM_NO_GUM=1`**

把 `tests/helpers.sh` 的 `run_ccm` 改为:

```bash
# 在隔离环境里跑 ccm:CCM_HOME=sandbox,PATH 前置桩目录,强制走 shell 回退(无 gum)
run_ccm() {
  CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" CCM_NO_GUM=1 bash "$CCM_BIN" "$@"
}
```

- [ ] **Step 2: 同步改 `test_ccm.sh` 的 `_timed_run`**

`tests/test_ccm.sh:134` 行内的 `CCM_NO_DIALOG=1` 改为 `CCM_NO_GUM=1`:

```bash
  ( CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" CCM_NO_GUM=1 bash "$CCM_BIN" "$@" >/dev/null 2>&1 ) &
```

- [ ] **Step 3: 新增 `make_gum_stub` 到 `helpers.sh`**

在 `teardown()` 之后追加:

```bash
# 生成一个 fake gum:把 argv 记到 GUM_STUB_OUT,并模拟输出。
# 用法:make_gum_stub <dir>;调用方负责把 <dir> 前置到 PATH。
# 渲染类(style/format/join/log):把最后一个参数原样回显到 stdout(便于断言"经 gum 渲染")。
# 交互类(input/filter):回显 GUM_STUB_REPLY(默认空)。confirm:按 GUM_STUB_CONFIRM(默认0)返回退出码。
make_gum_stub() {
  local dir="$1"
  cat >"$dir/gum" <<'STUB'
#!/usr/bin/env bash
echo "GUM $*" >>"${GUM_STUB_OUT:-/dev/null}"
sub="$1"; shift
case "$sub" in
  style|format|join|log) printf '[gum]%s\n' "${*: -1}" ;;
  input|filter|write)    printf '%s\n' "${GUM_STUB_REPLY:-}" ;;
  confirm)               exit "${GUM_STUB_CONFIRM:-0}" ;;
  *)                     : ;;
esac
STUB
  chmod +x "$dir/gum"
}
```

- [ ] **Step 4: 跑现有测试确认仍全绿**

Run: `bash tests/run_all.sh`
Expected: 全部 `ok`,`0 failed`(回退路径行为不变)。

- [ ] **Step 5: Commit**

```bash
git add tests/helpers.sh tests/test_ccm.sh
git commit -m "test: 测试夹具改用 CCM_NO_GUM 强制回退 + 新增 gum 桩工厂"
```

---

## Task 2: 拆分能力门 `_has_gum`(渲染)/ `_gum_interactive`(交互)

**Files:**
- Modify: `ccm:257-264`(`_has_gum`)
- Create: `tests/test_ui.sh`
- Modify: `tests/run_all.sh`

- [ ] **Step 1: 写失败测试**

创建 `tests/test_ui.sh`:

```bash
#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/helpers.sh"
CCM_BIN="$HERE/../ccm"
setup

# source ccm 的函数定义(ccm 末尾的 main "$@" 在被 source 且无参数时会执行 help,
# 用 CCM_SOURCED 短路;见 Task 2 Step 3 对 main 调用的保护)
CCM_SOURCED=1 . "$CCM_BIN"

# 渲染门:有 gum 二进制即真(不要求 tty)
PATH="$STUBDIR:$PATH"; make_gum_stub "$STUBDIR"
assert_eq "_has_gum 有gum为真" "0" "$(_has_gum; echo $?)"
assert_eq "CCM_NO_GUM=1 渲染门为假" "1" "$(CCM_NO_GUM=1; _has_gum; echo $?)"

# 交互门:无 /dev/tty 时为假(测试进程 stdin 是脚本,/dev/tty 行为依环境,
# 这里只断言 CCM_NO_GUM=1 必为假)
assert_eq "CCM_NO_GUM=1 交互门为假" "1" "$(CCM_NO_GUM=1; _gum_interactive; echo $?)"

teardown
finish
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/test_ui.sh`
Expected: FAIL —— `_gum_interactive: command not found`,且 source 可能触发 `main` 执行(下一步修复)。

- [ ] **Step 3: 实现能力门 + 保护 source**

把 `ccm:257-264` 的 `_has_gum` 替换为:

```bash
_has_gum() { # 渲染门:gum 可执行且未被禁用(不要求 TTY,gum style/format 输出 ANSI 到管道也可)
  [ -z "${CCM_NO_GUM:-}" ] && command -v gum >/dev/null 2>&1
}

_gum_interactive() { # 交互门:在渲染门基础上额外要求 /dev/tty 可用(gum input/confirm/filter 需要)
  _has_gum && { : < /dev/tty; } 2>/dev/null
}
```

并把 `ccm` 末尾的 `main "$@"`(`ccm:1172` 附近)改为可被 source 短路:

```bash
[ -n "${CCM_SOURCED:-}" ] || main "$@"
```

- [ ] **Step 4: 注册并跑测试**

在 `tests/run_all.sh` 中加入 `test_ui.sh`(仿照现有 `test_*.sh` 的 source/执行方式)。

Run: `bash tests/test_ui.sh`
Expected: PASS(4 条 ok)。

Run: `bash tests/run_all.sh`
Expected: 全绿(含原有 test_ccm.sh)。

- [ ] **Step 5: Commit**

```bash
git add ccm tests/test_ui.sh tests/run_all.sh
git commit -m "feat: 拆分 _has_gum(渲染) 与 _gum_interactive(交互) 能力门"
```

---

## Task 3: 集中式交互原语(替换重复的 _ui_gum_* 与 shell 变体)

**目标接口(后续任务依赖,签名固定):**
- `_ui_input <label> <hint> <initial>` → 结果写 `stdout`;Esc/失败 → 非 0。
- `_ui_password <label> <hint>` → 结果写 `stdout`;非 0 表示取消。
- `_ui_confirm <prompt>` → 退出码:0=确认,1=取消。
- `_ui_pick <prompt>`(候选从 `stdin` 逐行读)→ 选中项写 `stdout`;非 0=取消/无选择。

**Files:**
- Modify: `ccm`(在现有 `_ui_gum_input`/`_ui_gum_confirm` 附近,约 `ccm:266-333`)新增上述 4 个原语;保留现有 `_ui_gum_input` 等暂不删(Task 5 合并向导时删)。
- Modify: `tests/test_ui.sh`(追加交互原语的回退路径断言)

- [ ] **Step 1: 写失败测试(回退路径,确定化)**

在 `tests/test_ui.sh` 的 `teardown` 之前追加:

```bash
# 交互原语回退路径(CCM_NO_GUM=1 → 走 read)
export CCM_NO_GUM=1
# _ui_input:留空回车 → 返回 initial
out="$(printf '\n' | _ui_input "Token" "hint" "DEFLT")"
assert_eq "_ui_input 空回车保留默认" "DEFLT" "$out"
out="$(printf 'NEW\n' | _ui_input "Token" "hint" "DEFLT")"
assert_eq "_ui_input 输入覆盖" "NEW" "$out"
# _ui_confirm:y/n
( printf 'y\n' | _ui_confirm "ok?" ); assert_eq "_ui_confirm y=0" "0" "$?"
( printf 'n\n' | _ui_confirm "ok?" ); assert_eq "_ui_confirm n=1" "1" "$?"
# _ui_pick:回退编号菜单,选 2
out="$(printf '2\n' | _ui_pick "选择" <<'OPTS'
alpha
beta
gamma
OPTS
)"
assert_eq "_ui_pick 选第2项" "beta" "$out"
unset CCM_NO_GUM
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/test_ui.sh`
Expected: FAIL —— `_ui_input: command not found` 等。

- [ ] **Step 3: 实现 4 个交互原语**

在 `ccm` 的 `_ui_gum_confirm` 函数定义之后插入:

```bash
_ui_input() { # _ui_input <label> <hint> <initial> -> 结果写 stdout
  local label="$1" hint="$2" initial="$3"
  if _gum_interactive; then
    local tmp; tmp="$(mktemp)" || return 1
    if gum input --header "$label" --header.foreground 6 \
         ${initial:+--value "$initial"} --placeholder "$hint" \
         < /dev/tty > "$tmp" 2>/dev/tty; then
      cat "$tmp"; rm -f "$tmp"; return 0
    fi
    rm -f "$tmp"; return 1
  fi
  # 回退:shell read(从 stdin),空回车保留 initial
  local ans
  printf '  %s' "$(_cc_d "$label (回车保留 ${initial:-空}): ")" >&2
  IFS= read -r ans || return 1
  if [ -z "$ans" ]; then printf '%s\n' "$initial"; else printf '%s\n' "$ans"; fi
}

_ui_password() { # _ui_password <label> <hint> -> 结果写 stdout
  local label="$1" hint="$2"
  if _gum_interactive; then
    local tmp; tmp="$(mktemp)" || return 1
    if gum input --password --header "$label" --header.foreground 6 \
         --placeholder "$hint" < /dev/tty > "$tmp" 2>/dev/tty; then
      cat "$tmp"; rm -f "$tmp"; return 0
    fi
    rm -f "$tmp"; return 1
  fi
  local ans
  printf '  %s' "$(_cc_d "$label: ")" >&2
  IFS= read -r ans || return 1
  printf '%s\n' "$ans"
}

_ui_confirm() { # _ui_confirm <prompt> -> 0=确认 1=取消
  local prompt="$1"
  if _gum_interactive; then
    gum confirm "$prompt" < /dev/tty >/dev/tty 2>&1
    return $?
  fi
  local a
  printf '  %s [Y/n] ' "$prompt" >&2
  IFS= read -r a || return 1
  case "$a" in n|N|no|NO) return 1 ;; *) return 0 ;; esac
}

_ui_pick() { # _ui_pick <prompt>  (候选从 stdin 逐行) -> 选中项写 stdout
  local prompt="$1"
  local -a opts=(); local line
  while IFS= read -r line; do [ -n "$line" ] && opts+=("$line"); done
  [ "${#opts[@]}" -gt 0 ] || return 1
  if _gum_interactive; then
    printf '%s\n' "${opts[@]}" | gum filter --header "$prompt" --header.foreground 6 \
      < /dev/tty 2>/dev/tty
    return $?
  fi
  # 回退:编号菜单
  local i
  printf '  %s\n' "$(_cc_bc "$prompt")" >&2
  for i in "${!opts[@]}"; do printf '    %d) %s\n' "$((i+1))" "${opts[$i]}" >&2; done
  printf '  选择编号: ' >&2
  local n; IFS= read -r n || return 1
  case "$n" in (*[!0-9]*|'') return 1 ;; esac
  [ "$n" -ge 1 ] && [ "$n" -le "${#opts[@]}" ] || return 1
  printf '%s\n' "${opts[$((n-1))]}"
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tests/test_ui.sh`
Expected: PASS(含新增 5 条交互断言)。

- [ ] **Step 5: Commit**

```bash
git add ccm tests/test_ui.sh
git commit -m "feat: 新增集中式交互原语 _ui_input/_ui_password/_ui_confirm/_ui_pick"
```

---

## Task 4: 渲染原语 `_ui_say`(单色行/消息,gum-first)

**接口:** `_ui_say <palette> <text>` — palette ∈ `title|ok|warn|err|info|dim`。结果写 `stdout`(调用方按需 `>&2`)。每次最多 fork 一次 gum。

| palette | 图标前缀 | gum 前景色 | 回退 `_cc_*` |
|---------|---------|-----------|-------------|
| title | (无) | 6 bold | `_cc_bc` |
| ok | (无,文本自带 ✓) | 2 | `_cc_g` |
| err | (无,文本自带 ✖) | 1 | `_cc_r` |
| warn | (无) | 3 | `_cc_y` |
| info | (无) | 8 | `_cc_d` |
| dim | (无) | 8 | `_cc_d` |

**Files:**
- Modify: `ccm`(交互原语之后新增 `_ui_say`)
- Modify: `tests/test_ui.sh`

- [ ] **Step 1: 写失败测试**

在 `tests/test_ui.sh` 追加(`teardown` 前):

```bash
# 渲染原语:回退路径输出纯文本(管道,无 TTY → _cc_on=0)
out="$(CCM_NO_GUM=1 bash -c '. "'"$CCM_BIN"'"; CCM_SOURCED=1; _ui_say ok "已保存"')"
assert_eq "_ui_say 回退纯文本" "已保存" "$out"
# gum 路径:经 gum 渲染(桩回显 [gum]<text>)
mkdir -p "$STUBDIR"; make_gum_stub "$STUBDIR"
out="$(PATH="$STUBDIR:$PATH" GUM_STUB_OUT=/dev/null bash -c '. "'"$CCM_BIN"'"; CCM_SOURCED=1; _ui_say ok "已保存"')"
assert_contains "_ui_say gum 渲染" "[gum]" "$out"
```

> 说明:`_ui_say` 在 `_has_gum` 为真时用 `gum style`;桩把 `style` 的末参回显为 `[gum]<text>`。

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/test_ui.sh`
Expected: FAIL —— `_ui_say: command not found`。

- [ ] **Step 3: 实现 `_ui_say`**

```bash
_ui_say() { # _ui_say <title|ok|err|warn|info|dim> <text>  -> stdout(单次 gum fork)
  local pal="$1"; shift; local text="$*"
  if _has_gum; then
    case "$pal" in
      title) gum style --bold --foreground 6 -- "$text" ;;
      ok)    gum style --foreground 2 -- "$text" ;;
      err)   gum style --foreground 1 -- "$text" ;;
      warn)  gum style --foreground 3 -- "$text" ;;
      info|dim) gum style --foreground 8 -- "$text" ;;
      *)     gum style -- "$text" ;;
    esac
    return
  fi
  if [ "$_cc_on" -eq 1 ]; then
    case "$pal" in
      title) printf '%s\n' "$(_cc_bc "$text")" ;;
      ok)    printf '%s\n' "$(_cc_g "$text")" ;;
      err)   printf '%s\n' "$(_cc_r "$text")" ;;
      warn)  printf '%s\n' "$(_cc_y "$text")" ;;
      info|dim) printf '%s\n' "$(_cc_d "$text")" ;;
      *)     printf '%s\n' "$text" ;;
    esac
    return
  fi
  printf '%s\n' "$text"
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tests/test_ui.sh`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add ccm tests/test_ui.sh
git commit -m "feat: 新增 gum-first 渲染原语 _ui_say(单色行/消息)"
```

---

## Task 5: 合并向导为单套(基于 _ui_* 原语,删除重复实现)

**目标:** `_interactive_profile` 不再 `if _has_gum` 分派到 `_ui_gum_wizard`。改为单一流程,调 `_ui_input/_ui_password/_ui_confirm`;gum/回退分支由原语内部处理。删除 `_ui_gum_wizard`(`ccm:337-446` 附近)、`_ui_gum_input`(`ccm:266-`)、`_ui_gum_confirm`、`_ui_gum_timeline`、`_ui_wizard_content`、`_ui_wizard_confirm` 等已被原语取代的函数。`_ui_wizard_timeline`(纯展示步骤条)与 `_ui_clear` 保留。

**Files:**
- Modify: `ccm:524-666`(`_interactive_profile` 去掉 gum 分派,改用原语)
- Delete: `ccm` 中 `_ui_gum_input`/`_ui_gum_confirm`/`_ui_gum_timeline`/`_ui_gum_wizard`/`_ui_wizard_content`/`_ui_wizard_confirm`
- Test: `tests/test_ccm.sh`(现有 new/edit 断言,回退路径)

- [ ] **Step 1: 确认现有 new 断言为基线(应已绿)**

Run: `bash tests/test_ccm.sh`
Expected: 全绿(尤其 `new 生成文件`/`new 权限 600`/`重复 new 退出码1`)。这是本任务的回归基线。

- [ ] **Step 2: 删除 gum 分派分支**

删除 `ccm:558-563`:

```bash
  # ── Dispatch to gum UI if available ─────────────────────────────
  if _has_gum; then
    _ui_gum_wizard "$mode" "$name" "$existing_file" \
      "$tok" "$url" "$opus" "$opus_n" "$sonnet" "$sonnet_n" "$haiku" "$haiku_n" "$subagent"
    return $?
  fi
```

- [ ] **Step 3: 把向导步骤内容改用原语**

将 `_interactive_profile` 中各 `_ui_wizard_content` 调用替换为 `_ui_input`/`_ui_password`。Token 步骤用 `_ui_password`,其余用 `_ui_input`;确认步骤用 `_ui_confirm`。例如 Step 1/2:

```bash
  # Step 1: Auth
  _ui_wizard_timeline 1 "$step_total" "${step_labels[@]}"
  result_tok="$(_ui_password "API Token" "sk-ant-...")" || return 1
  [ -n "$result_tok" ] || result_tok="$tok"
  result_url="$(_ui_input "Base URL" "https://api.example.com/v1" "$url")" || return 1

  # Step 2: Models
  _ui_clear
  _ui_wizard_timeline 2 "$step_total" "${step_labels[@]}" "$auth_summary"
  result_opus="$(_ui_input "Opus 模型 ID" "claude-opus-4-8" "$opus")" || return 1
  result_sonnet="$(_ui_input "Sonnet 模型 ID" "claude-sonnet-4-6" "$sonnet")" || return 1
  result_haiku="$(_ui_input "Haiku 模型 ID" "claude-haiku-4-5-..." "$haiku")" || return 1
```

Step 3(子代理)用 `_ui_input "子代理模型 (留空使用默认)" "" "$subagent"`;Step 5 确认改为:

```bash
  _ui_say title "━━━━━━━━ 确认配置 ━━━━━━━━" >&2
  _ui_say dim  "Token: $(_mask_preview "$result_tok")" >&2
  _ui_say dim  "URL:   $(_mask_preview "$result_url")" >&2
  _ui_say dim  "Opus:  $result_opus" >&2
  _ui_say dim  "Sonnet:$result_sonnet" >&2
  _ui_say dim  "Haiku: $result_haiku" >&2
  _ui_confirm "确认保存以上配置?" || return 1
```

> 注:`_ui_password` 在回退路径返回空字符串时,用 `[ -n ... ] || result_tok="$tok"` 保留原值(回退测试用 8 个空行接受默认值,见 `test_ccm.sh:37`)。

- [ ] **Step 4: 删除被取代的函数**

删除 `_ui_gum_input`、`_ui_gum_confirm`、`_ui_gum_timeline`、`_ui_gum_wizard`、`_ui_wizard_content`、`_ui_wizard_confirm` 的完整定义。`bash -n ccm` 确认无语法错误,`grep -n '_ui_gum_\|_ui_wizard_content\|_ui_wizard_confirm' ccm` 确认无残留调用。

Run: `bash -n ccm`
Expected: 无输出(语法 OK)。

- [ ] **Step 5: 跑回归测试**

Run: `bash tests/run_all.sh`
Expected: 全绿。特别确认 `new 生成文件`/`new 权限 600` 仍过(回退路径用 stdin 空行接受默认)。

- [ ] **Step 6: Commit**

```bash
git add ccm
git commit -m "refactor: 合并 gum/shell 双向导为单套,统一走 _ui_* 原语"
```

---

## Task 6: `_resolve_profile_arg` + 接入缺参选择器

**接口:** `_resolve_profile_arg <usage_msg> [name]` → 解析出的 profile 名写 `stdout`,退出码 0;缺名且 `_gum_interactive` → 用 `_ui_pick` 让用户选;缺名且非交互 → `_die 2 <usage_msg>`;无任何 profile → 走原"缺名"用法错误。

**Files:**
- Modify: `ccm`(新增 `_resolve_profile_arg`;接入 `cmd_run`/`cmd_rm`/`cmd_edit`/`cmd_show`/`cmd_backup_restore`)
- Modify: `tests/test_ccm.sh`(末尾新增选择器断言)

- [ ] **Step 1: 写失败测试**

在 `tests/test_ccm.sh` 的 `teardown` 前追加:

```bash
# 缺名 + 无 gum → 退出码 2(行为不变)
run_ccm run >/dev/null 2>&1
assert_eq "run 缺名无gum退出2" "2" "$?"

# 缺名 + gum 可用 → 弹选择器(桩 filter 回显 GUM_STUB_REPLY=work)
make_gum_stub "$STUBDIR"
cat >"$SANDBOX/profiles/work.env" <<'EOF'
export ANTHROPIC_AUTH_TOKEN="sk-token-xyz"
export ANTHROPIC_BASE_URL="https://gw.example.com"
EOF
OUT="$SANDBOX/pick.txt"
# 注意:不设 CCM_NO_GUM;但交互门需 /dev/tty,CI 下可能无 → 该断言仅在有 tty 时有意义。
# 为可测,这里改测渲染门可达的 rm 确认路径见 Task 9;选择器交互的 E2E 依赖 pty,标注为手测。
echo "（手测项见计划说明）" >/dev/null
```

> **测试现实:** gum 交互(filter/confirm)读 `/dev/tty`,自动化测试无 pty 时 `_gum_interactive` 为假,无法驱动真实 gum 选择器。因此**自动化只断言"缺名+无 gum→退出2"不回归**;选择器的真实弹出列入手动验收(计划末尾"手动验收"清单)。`_resolve_profile_arg` 的纯逻辑(给名字时原样返回、非法名拒绝)用下方 Step 可测分支覆盖。

- [ ] **Step 2: 跑测试确认基线**

Run: `bash tests/test_ccm.sh`
Expected: `run 缺名无gum退出2` = ok(当前 `cmd_run` 已对缺名 `_die 2`,基线即绿)。

- [ ] **Step 3: 实现 `_resolve_profile_arg`**

```bash
_resolve_profile_arg() { # _resolve_profile_arg <usage_msg> [name] -> 选定名写 stdout
  local usage="$1" name="${2:-}"
  if [ -n "$name" ]; then printf '%s\n' "$name"; return 0; fi
  # 缺名:列出已有 profile
  local -a names=(); local f
  for f in "$PROFILES_DIR"/*.env; do
    [ -e "$f" ] || continue
    names+=("$(basename "$f" .env)")
  done
  if [ "${#names[@]}" -gt 0 ] && _gum_interactive; then
    local picked
    picked="$(printf '%s\n' "${names[@]}" | _ui_pick "选择 profile")" || _die 2 "$usage"
    [ -n "$picked" ] || _die 2 "$usage"
    printf '%s\n' "$picked"; return 0
  fi
  _die 2 "$usage"
}
```

- [ ] **Step 4: 接入各命令**

`cmd_run`(`ccm:1072` 起)开头解析 profile 名处改为先 `name="$(_resolve_profile_arg "用法: ccm run <profile> [--opus M] ... [-- claude参数]" "$name")" || exit $?`。同理:
- `cmd_rm`:`_resolve_profile_arg "用法: ccm rm <profile>" "$1"`
- `cmd_edit`:`_resolve_profile_arg "用法: ccm edit <profile>" "$1"`
- `cmd_show`:在解析完 `--raw`/`name` 后,若 `name` 为空则 `name="$(_resolve_profile_arg "用法: ccm show <profile> [--raw]")" || exit $?`
- `cmd_backup_restore`:`_resolve_profile_arg "用法: ccm backup-restore <profile> [n]" "$1"`

> 保持各命令原有的"非法名拒绝(退出 2)"与"不存在(退出 1)"校验不变,顺序在 `_resolve_profile_arg` 之后。

- [ ] **Step 5: 跑回归测试**

Run: `bash tests/run_all.sh`
Expected: 全绿。特别确认 `run 缺名退出码2`、`run 不存在退出码1`、`拒绝路径穿越`、`拒绝含斜杠名` 不回归。

- [ ] **Step 6: Commit**

```bash
git add ccm tests/test_ccm.sh
git commit -m "feat: 缺 profile 参数时弹 gum 选择器(_resolve_profile_arg),无 gum 回退用法错误"
```

---

## Task 7: cmd_list 经 gum 渲染(回退字节不变)

**Files:**
- Modify: `ccm:839-853`(`cmd_list`)
- Modify: `tests/test_ccm.sh`(新增 gum 路径断言)

- [ ] **Step 1: 写失败测试(gum 路径)**

在 `tests/test_ccm.sh` 末尾追加:

```bash
# list 在 gum 可用时经 gum 渲染(桩回显 [gum])
make_gum_stub "$STUBDIR"
cat >"$SANDBOX/profiles/work.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://gw.example.com"
EOF
out="$(CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" bash "$CCM_BIN" list)"
assert_contains "list gum 渲染" "[gum]" "$out"
assert_contains "list gum 含 work" "work" "$out"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/test_ccm.sh`
Expected: FAIL —— `list gum 渲染` 找不到 `[gum]`(当前 list 直接 printf)。

- [ ] **Step 3: 改写 cmd_list**

```bash
cmd_list() {
  _ensure_skeleton
  local found=0 f name url line
  local -a rows=()
  for f in "$PROFILES_DIR"/*.env; do
    [ -e "$f" ] || continue
    found=1
    name="$(basename "$f" .env)"
    line="$(grep -E '^[[:space:]]*export[[:space:]]+ANTHROPIC_BASE_URL=' "$f" | head -1)"
    url="${line#*=}"; url="${url%\"}"; url="${url#\"}"; url="${url%\'}"; url="${url#\'}"
    rows+=("$(printf '%-20s %s' "$name" "${url:-(no base_url)}")")
  done
  if [ "$found" -ne 1 ]; then
    echo "(暂无 profile,用 'ccm new <name>' 创建)"
    return
  fi
  if _has_gum; then
    printf '%s\n' "${rows[@]}" | gum style --foreground 7
  else
    printf '%s\n' "${rows[@]}"
  fi
}
```

> 回退分支 `printf '%s\n' "${rows[@]}"` 输出与原 `printf '%-20s %s\n'` 逐行字节一致;`list 不泄露 token`/`列出 work`/`列出 base_url` 断言不变。gum 分支整列一次性 `gum style`(单次 fork,满足批量约束)。

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tests/run_all.sh`
Expected: 全绿(回退断言 + 新增 gum 断言)。

- [ ] **Step 5: Commit**

```bash
git add ccm tests/test_ccm.sh
git commit -m "feat: ccm list 经 gum 批量渲染,回退保持字节不变"
```

---

## Task 8: cmd_show 经 gum 渲染(回退字节不变)

**策略:** 把 `cmd_show` 现有逐行渲染循环(`ccm:909-958`)整体包进 `else` 分支**逐字不动**(保证 `show 打码保留头部`/`有星号`/`--raw` 等断言),在其上新增 `if _has_gum` 分支:把同样的行内容收集进数组,末尾一次 `gum style` 渲染。

**Files:**
- Modify: `ccm:892-960`(`cmd_show`)
- Modify: `tests/test_ccm.sh`

- [ ] **Step 1: 写失败测试(gum 路径)**

```bash
# show 在 gum 可用时经 gum 渲染,且仍打码 token
make_gum_stub "$STUBDIR"
cat >"$SANDBOX/profiles/masktest.env" <<'EOF'
export ANTHROPIC_AUTH_TOKEN="sk-5_nclDqRENf1rPMBiPp8Aw"
export ANTHROPIC_BASE_URL="https://gw.example.com"
EOF
out="$(CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" bash "$CCM_BIN" show masktest)"
assert_contains "show gum 渲染" "[gum]" "$out"
assert_eq "show gum 不露原token" "no" "$(printf '%s' "$out" | grep -q 'sk-5_nclDqRENf1rPMBiPp8Aw' && echo yes || echo no)"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/test_ccm.sh`
Expected: FAIL —— `show gum 渲染` 无 `[gum]`。

- [ ] **Step 3: 改写 cmd_show 渲染段**

把 `ccm:908`(`# 打码显示` 注释)起到 `done <"$pf"` 结束的整段,改为:收集每行渲染结果到 `local -a lines=()`(用 `lines+=("$(printf ...)")` 替换原来的 `printf ... `,**格式串逐字保留**),循环结束后:

```bash
  if _has_gum; then
    printf '%s\n' "${lines[@]}" | gum style --foreground 7
  else
    printf '%s\n' "${lines[@]}"
  fi
```

> 关键:原循环里每个 `printf '...\n' ...` 改为 `lines+=("$(printf '...' ...)")`(去掉结尾 `\n`,由统一的 `printf '%s\n'` 补)。`_mask` 打码逻辑不动。回退分支 `printf '%s\n' "${lines[@]}"` 与原逐行 printf 字节一致。`--raw` 分支(`ccm:904-907`)保持不变。

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tests/run_all.sh`
Expected: 全绿(`show 打码保留头部`/`show 打码有星号`/`show --raw`/新增 gum 断言)。

- [ ] **Step 5: Commit**

```bash
git add ccm tests/test_ccm.sh
git commit -m "feat: ccm show 经 gum 批量渲染,回退保持字节不变与打码"
```

---

## Task 9: 状态消息收口到 `_ui_say`(成功/取消/错误)

**Files:**
- Modify: `ccm`(`cmd_new:863-867`、`cmd_edit:881-888`、`cmd_rm`、`cmd_backup_restore` 等的成功/取消行)
- Modify: `tests/test_ccm.sh`

- [ ] **Step 1: 写失败测试(gum 路径,rm 确认 + 成功消息)**

```bash
# rm 在 gum 可用时,确认走 gum confirm(桩 GUM_STUB_CONFIRM=0 视为 yes),成功消息经 gum 渲染
# 注:gum confirm 读 /dev/tty,CI 无 pty 时 _gum_interactive 假 → 回退 read。
# 因此这里仅断言"成功消息经 _ui_say 在 gum 渲染门下输出 [gum]"——用渲染门(不需 tty)可达的成功行:
make_gum_stub "$STUBDIR"
cat >"$SANDBOX/profiles/delme.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://gw.example.com"
EOF
out="$(printf 'y\n' | CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" bash "$CCM_BIN" rm delme 2>&1)"
assert_contains "rm 成功消息经 gum" "[gum]" "$out"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/test_ccm.sh`
Expected: FAIL —— `rm 成功消息经 gum` 无 `[gum]`。

- [ ] **Step 3: 替换消息行**

把成功/取消/提示行改用 `_ui_say`(保留 stderr/stdout 流向)。例如 `cmd_new`:

```bash
  if _interactive_profile "new" "$name"; then
    _ui_say ok "✓ 已创建 $pf"
  else
    rm -f "$pf"
    _ui_say err "✖ 已取消" >&2
    exit 1
  fi
```

`cmd_edit` 成功:`_ui_say ok "✓ 已更新 $pf"`;取消:`_ui_say err "✖ 已取消，未保存更改" >&2`;备份提示:`_ui_say info "💡 使用 ccm backup-list $name 查看备份记录"`。`cmd_rm` 删除成功行、`cmd_backup_restore` 恢复成功行同理改为 `_ui_say ok ...`。

> 回退路径下 `_ui_say ok "✓ 已创建 $pf"` 输出 `✓ 已创建 <path>`(纯文本或带绿色),与原 `printf '%s %s\n' "$(_cc_g '✓')" "已创建 ..."` 语义一致;现有 test_ccm.sh 未对这些成功消息做字节断言(仅断言文件存在/退出码),故不回归。逐项确认:`grep -n 'printf .*✓\|printf .*✖\|printf .*💡' ccm` 应无残留。

- [ ] **Step 4: 跑回归 + 新测试**

Run: `bash tests/run_all.sh`
Expected: 全绿。

- [ ] **Step 5: Commit**

```bash
git add ccm tests/test_ccm.sh
git commit -m "feat: 状态消息(成功/取消/提示)收口到 _ui_say,gum-first"
```

---

## Task 10: install.sh 把 gum 加入可选依赖

**Files:**
- Modify: `install.sh`(`_OPT_DEPS`)

- [ ] **Step 1: 查看现有 `_OPT_DEPS`**

Run: `grep -n "_OPT_DEPS" install.sh`
Expected: 找到可选依赖数组定义。

- [ ] **Step 2: 加入 gum 条目**

在 `_OPT_DEPS` 中加入(若尚未存在):

```bash
"gum|brew:gum|apt:charm-gum|yum:gum|dnf:gum|pacman:gum"
```

若 `_OPT_DEPS` 格式与此不同,按现有条目格式对齐(包管理器→包名映射)。

- [ ] **Step 3: 语法检查**

Run: `bash -n install.sh`
Expected: 无输出。

Run: `bash tests/test_install.sh`
Expected: 全绿(install 测试不回归)。

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "chore: install.sh 将 gum 加入可选依赖"
```

---

## Task 11: 核对自动补全与文档

**Files:**
- Inspect: `completions/_ccm`
- Modify(如需): `CLAUDE.md`/`README` 提及 gum 可选增强

- [ ] **Step 1: 核对补全无需改动**

Run: `grep -n "new\|edit\|show\|run\|rm\|backup" completions/_ccm | head`
确认:本次未新增子命令或 flag(选择器是"缺参行为"),补全无需变更。若发现缺失的现有子命令补全,顺手补齐(遵守 CLAUDE.md 的补全硬性要求)。

- [ ] **Step 2: 跑全量测试**

Run: `bash tests/run_all.sh`
Expected: 全绿。

- [ ] **Step 3: Commit(如有改动)**

```bash
git add completions/_ccm CLAUDE.md
git commit -m "docs: 核对补全;说明 gum 为可选 UI 增强"
```

---

## 手动验收(自动化无法覆盖的交互项)

在**真实终端**(有 `/dev/tty`)且已装 gum 下验证:

- [ ] `ccm edit default` —— 5 步向导全程显示真实 gum 输入框(Token 隐藏),确认页 `gum confirm`。
- [ ] `ccm run`(不带名字)—— 弹出 `gum filter` 可搜索选择器,选中后正常启动。
- [ ] `ccm rm`(不带名字)—— 弹选择器选中后 `gum confirm` 确认。
- [ ] `ccm list` / `ccm show <name>` —— 输出经 gum 上色,观感与极简设计一致。
- [ ] `CCM_NO_GUM=1 ccm list` / `ccm edit` —— 全部回退到 shell,行为与重构前一致。
- [ ] `ccm list | cat` —— 管道输出为纯文本(无 ANSI 残留)。

---

## Self-Review 记录

- **Spec 覆盖:** 能力门(T2)、`_ui_*` 交互原语(T3)、渲染原语(T4)、合并向导(T5)、选择器(T6)、list/show/消息渲染(T7/8/9)、install(T10)、补全核对(T11)——覆盖 spec 全部组件。
- **类型一致:** 原语签名在 T3/T4 定义后,T5/T6/T9 调用一致(`_ui_input <label> <hint> <initial>`、`_ui_say <palette> <text>`、`_ui_pick` 从 stdin、`_resolve_profile_arg <usage> [name]`)。
- **测试现实:** gum 交互需 pty,自动化只测渲染门路径([gum] 标记)与回退路径(字节不变)+ 退出码;真实交互列入手动验收。已在相关任务显式标注,非隐性裁剪。
