# gum 向导重写 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 基于 gum 原生组件重写 `ccm new`(3步) 和 `ccm edit`(菜单→子表单→diff)，字段标签从 `--header` 改为 `--prompt` 消除渲染冲突。

**Architecture:** 新增 `_gum_field` 统一字段输入（gum `--prompt` 同行标签 + 回退 read），`_interactive_new`/`_interactive_edit` 各自实现流程，删除 `_ui_wizard_timeline` 和旧的 `_interactive_profile`。保留全部回退路径和公共 helper。

**Tech Stack:** Bash, gum (choose/filter/input/confirm/style), 现有 `_ui_say`/`_ui_confirm`/`_add_custom_env_vars_read`/`_write_profile`

**Files:**
- Modify: `ccm` — 删除旧函数 + 新增函数 + 更新 cmd_new/cmd_edit 分派
- Modify: `tests/helpers.sh` — 更新 gum stub 支持 `--prompt`/`choose`
- Modify: `tests/test_ccm.sh` — 调整 new 测试的 stdin 行数，新增 edit 测试
- Modify: `tests/test_ui.sh` — 新增 `_gum_field` 原语测试

---

### Task 1: Delete old wizard functions

**Files:**
- Modify: `ccm` — 删除 `_ui_wizard_timeline` (lines 421-458) 和 `_interactive_profile` (lines 460-590区域)

- [ ] **Step 1: Delete `_ui_wizard_timeline`**

删除函数定义 (当前 ~lines 421-458):
```bash
_ui_wizard_timeline() { ... }
```

- [ ] **Step 2: Delete `_interactive_profile`**

删除整个函数 (当前 ~lines 460-590，含 5-step wizard 全部逻辑)。

- [ ] **Step 3: Syntax check after deletion**

Run: `bash -n ccm`
Expected: no output (pass)

- [ ] **Step 4: Verify tests break (old tests reference deleted functions)**

Run: `bash tests/run_all.sh`
Expected: FAIL on new/edit tests (functions deleted, not yet replaced)

- [ ] **Step 5: Commit**

```bash
git add ccm
git commit -m "refactor: delete _ui_wizard_timeline and _interactive_profile

Prep for gum-native wizard redesign.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Add `_gum_field` — unified field input with `--prompt`

**Files:**
- Modify: `ccm` — 在 `_ui_password_quiet` 之后插入 `_gum_field`

- [ ] **Step 1: Add `_gum_field` function**

Insert after `_ui_password_quiet` (after line ~329):

```bash
# 统一字段输入: gum --prompt 同行标签 + 回退 read
# 用法: _gum_field <prompt> <initial> [--password] -> 结果写 stdout
# 空输入返回 initial(回退路径), gum 路径 gum 本身处理空值
_gum_field() { # _gum_field <prompt> <initial> [--password] -> 结果写 stdout
  local prompt="$1" initial="$2" pw=0
  [ "${3:-}" = "--password" ] && pw=1
  if _gum_interactive; then
    local tmp; tmp="$(mktemp)" || return 1
    local -a args=(--prompt "$prompt")
    [ -n "$initial" ] && args+=(--value "$initial")
    [ "$pw" -eq 1 ] && args+=(--password)
    if gum input "${args[@]}" < /dev/tty > "$tmp" 2>/dev/tty; then
      cat "$tmp"; rm -f "$tmp"; return 0
    fi
    rm -f "$tmp"; return 1
  fi
  # ── fallback: plain read ──
  if [ "$pw" -eq 1 ]; then
    printf '  %s' "$(_cc_d "$prompt")" >&2
    local ans
    IFS= read -rs ans || return 1
    if [ -z "$ans" ]; then printf '%s\n' "$initial"; else printf '%s\n' "$ans"; fi
    return 0
  fi
  printf '  %s' "$(_cc_d "$prompt")" >&2
  local ans
  IFS= read -r ans || return 1
  if [ -z "$ans" ]; then printf '%s\n' "$initial"; else printf '%s\n' "$ans"; fi
}
```

- [ ] **Step 2: Syntax check**

Run: `bash -n ccm`
Expected: no output

- [ ] **Step 3: Add `_gum_field` tests to test_ui.sh**

在 `tests/test_ui.sh` 末尾（`teardown` 之前）添加:

```bash
# _gum_field 回退路径 (CCM_NO_GUM=1)
export CCM_NO_GUM=1
out="$(printf '\n' | _gum_field "Name: " "DEFLT")"
assert_eq "_gum_field 空回车保留默认" "DEFLT" "$out"
out="$(printf 'ALICE\n' | _gum_field "Name: " "DEFLT")"
assert_eq "_gum_field 输入覆盖" "ALICE" "$out"
out="$(printf 'secret\n' | _gum_field "Pwd: " "" "--password")"
assert_eq "_gum_field password 读取" "secret" "$out"
out="$(printf '\n' | _gum_field "Pwd: " "DEFAULT_TOKEN" "--password")"
assert_eq "_gum_field password 空回车保留默认" "DEFAULT_TOKEN" "$out"
unset CCM_NO_GUM

# _gum_field gum 路径 (经桩)
make_gum_stub "$STUBDIR"
export GUM_STUB_REPLY="gum-input-val"
out="$(PATH="$STUBDIR:$PATH" GUM_STUB_OUT=/dev/null bash -c 'CCM_SOURCED=1 . "'"$CCM_BIN"'"; _gum_field "Name: " "prev"')"
assert_eq "_gum_field gum 返回桩值" "gum-input-val" "$out"
unset GUM_STUB_REPLY
```

- [ ] **Step 4: Run UI tests**

Run: `bash tests/test_ui.sh`
Expected: all pass including new `_gum_field` tests

- [ ] **Step 5: Commit**

```bash
git add ccm tests/test_ui.sh
git commit -m "feat: add _gum_field — unified prompt input with gum --prompt

Uses gum input --prompt for inline label, fallback to read -r/-rs.
Replaces _ui_input_quiet/_ui_password_quiet for wizard context.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Implement `_interactive_new` — 3-step wizard

**Files:**
- Modify: `ccm` — 在 `_add_custom_env_vars_read` 之后、`cmd_list` 之前添加 `_interactive_new`

- [ ] **Step 1: Add `_interactive_new` function**

```bash
_interactive_new() { # _interactive_new <name>
  local name="$1"
  local pf; pf="$(_profile_path "$name")" || return $?

  # ── Defaults ──────────────────────────────────────────────────────
  local tok="<YOUR_TOKEN_HERE>"
  local url="<https://your-gateway.example.com>"
  local opus="claude-opus-4-8"
  local sonnet="claude-sonnet-4-6"
  local haiku="claude-haiku-4-5-20251001"
  local subagent=""

  local title_text="新建 profile: $name"

  # ── Step 1: 核心配置 (Token + URL + 3 models) ─────────────────────
  _ui_say title "━━━ $title_text ━━━" >&2
  _ui_say dim "Step 1/3 — 核心配置" >&2
  printf '\n' >&2

  tok="$(_gum_field "API Token: " "$tok" --password)" || return 1
  url="$(_gum_field "Base URL: " "$url")" || return 1
  opus="$(_gum_field "Opus 模型: " "$opus")" || return 1
  sonnet="$(_gum_field "Sonnet 模型: " "$sonnet")" || return 1
  haiku="$(_gum_field "Haiku 模型: " "$haiku")" || return 1

  # ── Step 2: 可选配置 ──────────────────────────────────────────────
  _ui_say title "━━━ $title_text ━━━" >&2
  _ui_say dim "Step 2/3 — 可选配置 (ESC 跳过)" >&2
  printf '\n' >&2

  subagent="$(_gum_field "子代理模型 (留空跳过): " "$subagent")" || true
  # gum ESC returns 1, treat as skip (keep previous value)
  [ $? -eq 1 ] && subagent=""

  # Custom env vars via gum filter
  _resolve_env_ref
  local -a ckeys=() cvals=()
  if [ -n "$_ENV_REF" ] && _gum_interactive; then
    while true; do
      local cand_list
      cand_list="$(
        while IFS='|' read -r k c d; do
          [ -z "$k" ] && continue
          local skip=0
          for ek in "${ckeys[@]}"; do
            [ "$ek" = "$k" ] && { skip=1; break; }
          done
          [ "$skip" -eq 1 ] && continue
          printf '%s  —  [%s] %s\n' "$k" "$c" "$d"
        done < <(_search_env_ref "")
      )"
      [ -z "$cand_list" ] && break

      local picked
      picked="$(printf '%s\n' "$cand_list" | gum filter \
        --header "搜索环境变量 (ESC 完成)" --header.foreground 6 \
        --placeholder "输入关键词..." --height 8 --limit 1 2>/dev/tty)" || break
      [ -n "$picked" ] || break

      local key="${picked%% *}"
      if ! printf '%s' "$key" | grep -qE '^[A-Z][A-Z0-9_]*$'; then
        _ui_say warn "无效选择: $key" >&2; continue
      fi

      local desc
      desc="$(grep "^${key}|" "$_ENV_REF" 2>/dev/null | head -1 | cut -d'|' -f3)"
      [ -n "$desc" ] && _ui_say dim "  $desc" >&2

      local val
      val="$(_gum_field "$key: " "")" || continue
      [ -n "$val" ] || { _ui_say dim "值为空，跳过" >&2; continue; }

      ckeys+=("$key"); cvals+=("$val")
      _ui_say ok "✓ $key 已添加" >&2
    done
  fi

  # ── Step 3: 确认 ──────────────────────────────────────────────────
  _ui_say title "━━━━━━━━ 确认配置 ━━━━━━━━" >&2
  printf '\n' >&2
  _ui_say dim "Token:   $(_mask_preview "$tok")" >&2
  _ui_say dim "URL:     $(_mask_preview "$url")" >&2
  _ui_say dim "Opus:    $opus" >&2
  _ui_say dim "Sonnet:  $sonnet" >&2
  _ui_say dim "Haiku:   $haiku" >&2
  _ui_say dim "Subagent: ${subagent:-(未设置)}" >&2
  if [ "${#ckeys[@]}" -gt 0 ]; then
    local ci
    for ci in "${!ckeys[@]}"; do
      _ui_say dim "${ckeys[$ci]}=$(_mask_preview "${cvals[$ci]}")" >&2
    done
  fi
  printf '\n' >&2
  _ui_confirm "确认保存以上配置?" || return 1

  # ── Write profile ─────────────────────────────────────────────────
  _write_profile "$pf" "$tok" "$url" "$opus" "" "$sonnet" "" "$haiku" "" "$subagent"

  # Append custom vars
  if [ "${#ckeys[@]}" -gt 0 ]; then
    local ci
    for ci in "${!ckeys[@]}"; do
      printf 'export %s=%s\n' "${ckeys[$ci]}" "$(printf '%s' "${cvals[$ci]}" | sed "s/'/'\\\''/g")" >> "$pf"
    done
  fi

  printf '\n' >&2
  _ui_say ok "✓ profile $name 已保存" >&2
}
```

- [ ] **Step 2: Syntax check**

Run: `bash -n ccm`
Expected: no output

- [ ] **Step 3: Update `cmd_new` to call `_interactive_new`**

Replace the existing `_interactive_profile "new" "$name"` call:

```bash
cmd_new() {
  local name="$1"
  [ -n "$name" ] || _die 2 "用法: ccm new <profile>"
  _ensure_skeleton
  local pf; pf="$(_profile_path "$name")" || exit $?
  [ -f "$pf" ] && _die 1 "profile '$name' 已存在(用 'ccm edit $name')"

  if _interactive_new "$name"; then
    _ui_say ok "✓ 已创建 $pf"
  else
    rm -f "$pf"
    _ui_say err "✖ 已取消" >&2
    exit 1
  fi
}
```

- [ ] **Step 4: Update new test in test_ccm.sh**

The fallback path needs ~7 blank lines (Token/URL/Opus/Sonnet/Haiku/Subagent/confirm). Update from 8 to 10 for safety:

```bash
# new 生成文件 + 权限 600(用 10 个空行接受默认值)
printf '\n\n\n\n\n\n\n\n\n\n' | run_ccm new fresh >/dev/null 2>&1
assert_eq "new 生成文件" "yes" "$([ -f "$SANDBOX/profiles/fresh.env" ] && echo yes || echo no)"
perm="$(stat -f '%Lp' "$SANDBOX/profiles/fresh.env" 2>/dev/null || stat -c '%a' "$SANDBOX/profiles/fresh.env")"
assert_eq "new 权限 600" "600" "$perm"

# 重复 new 报错(退出码非 0)
printf '\n\n\n\n\n\n\n\n\n\n' | run_ccm new fresh >/dev/null 2>&1
assert_eq "重复 new 退出码1" "1" "$?"
```

- [ ] **Step 5: Run tests**

Run: `bash tests/run_all.sh`
Expected: all tests pass (edit tests may still fail since edit not yet implemented)

- [ ] **Step 6: Commit**

```bash
git add ccm tests/test_ccm.sh
git commit -m "feat: _interactive_new — 3-step gum-native wizard

Step 1: 核心配置 (Token+URL+3 models), Step 2: 可选配置 (subagent+custom vars),
Step 3: 确认摘要+confirm. 字段统一用 _gum_field --prompt 同行标签.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Implement `_interactive_edit` — menu → subform → diff

**Files:**
- Modify: `ccm` — 在 `_interactive_new` 之后添加 `_interactive_edit`

- [ ] **Step 1: Add `_interactive_edit` function**

```bash
_interactive_edit() { # _interactive_edit <name> <profile_file>
  local name="$1" pf="$2"

  # ── Load current values ───────────────────────────────────────────
  local tok url opus opus_n sonnet sonnet_n haiku haiku_n subagent
  tok="$(_parse_env_value "$pf" ANTHROPIC_AUTH_TOKEN)"
  url="$(_parse_env_value "$pf" ANTHROPIC_BASE_URL)"
  opus="$(_parse_env_value "$pf" ANTHROPIC_DEFAULT_OPUS_MODEL)"
  opus_n="$(_parse_env_value "$pf" ANTHROPIC_DEFAULT_OPUS_MODEL_NAME)"
  sonnet="$(_parse_env_value "$pf" ANTHROPIC_DEFAULT_SONNET_MODEL)"
  sonnet_n="$(_parse_env_value "$pf" ANTHROPIC_DEFAULT_SONNET_MODEL_NAME)"
  haiku="$(_parse_env_value "$pf" ANTHROPIC_DEFAULT_HAIKU_MODEL)"
  haiku_n="$(_parse_env_value "$pf" ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME)"
  subagent="$(_parse_env_value "$pf" CLAUDE_CODE_SUBAGENT_MODEL)"
  [ "$opus_n" = "$opus" ] && opus_n=""
  [ "$sonnet_n" = "$sonnet" ] && sonnet_n=""
  [ "$haiku_n" = "$haiku" ] && haiku_n=""

  # Track originals for diff
  local orig_tok="$tok" orig_url="$url" orig_opus="$opus"
  local orig_sonnet="$sonnet" orig_haiku="$haiku" orig_subagent="$subagent"

  # ── Load custom vars ──────────────────────────────────────────────
  local -a ckeys=() cvals=()
  local -a orig_ckeys=() orig_cvals=()
  if [ -f "$pf" ]; then
    while IFS= read -r line; do
      local ekey eval
      ekey="$(printf '%s' "$line" | sed -n 's/^[[:space:]]*export[[:space:]]*\([A-Z_][A-Z0-9_]*\)=.*/\1/p')"
      [ -n "$ekey" ] || continue
      eval="$(printf '%s' "$line" | sed -n "s/^[[:space:]]*export[[:space:]]*${ekey}=[\"']\{0,1\}\([^\"'#]*\)[\"']\{0,1\}$/\1/p")"
      case "$ekey" in
        ANTHROPIC_AUTH_TOKEN|ANTHROPIC_BASE_URL|\
        ANTHROPIC_DEFAULT_OPUS_MODEL|ANTHROPIC_DEFAULT_OPUS_MODEL_NAME|\
        ANTHROPIC_DEFAULT_SONNET_MODEL|ANTHROPIC_DEFAULT_SONNET_MODEL_NAME|\
        ANTHROPIC_DEFAULT_HAIKU_MODEL|ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME|\
        CLAUDE_CODE_SUBAGENT_MODEL) continue ;;
      esac
      ckeys+=("$ekey"); cvals+=("$eval")
      orig_ckeys+=("$ekey"); orig_cvals+=("$eval")
    done < "$pf"
  fi

  local title_text="编辑 profile: $name"

  # ── Main menu loop ────────────────────────────────────────────────
  while true; do
    _ui_say title "━━━ $title_text ━━━" >&2
    printf '\n' >&2

    local section
    if _gum_interactive; then
      section="$(printf '%s\n' \
        "身份认证" \
        "模型映射" \
        "子代理" \
        "自定义环境变量" \
        "确认修改" \
        "取消" \
        | gum choose --header "选择要编辑的章节" --header.foreground 6 2>/dev/tty)" || { section="取消"; }
    else
      # Fallback: numbered list
      _ui_say dim "1) 身份认证  2) 模型映射  3) 子代理  4) 自定义变量" >&2
      _ui_say dim "5) 确认修改  6) 取消" >&2
      local choice
      printf '  选择: ' >&2
      IFS= read -r choice
      case "$choice" in
        1) section="身份认证" ;;
        2) section="模型映射" ;;
        3) section="子代理" ;;
        4) section="自定义环境变量" ;;
        5) section="确认修改" ;;
        *) section="取消" ;;
      esac
    fi

    case "$section" in
      身份认证)
        _ui_say title "━━━ 身份认证 ━━━" >&2; printf '\n' >&2
        tok="$(_gum_field "API Token: " "$tok" --password)" || continue
        url="$(_gum_field "Base URL: " "$url")" || continue
        _ui_say ok "✓ 身份认证已更新" >&2
        ;;
      模型映射)
        _ui_say title "━━━ 模型映射 ━━━" >&2; printf '\n' >&2
        opus="$(_gum_field "Opus 模型: " "$opus")" || continue
        sonnet="$(_gum_field "Sonnet 模型: " "$sonnet")" || continue
        haiku="$(_gum_field "Haiku 模型: " "$haiku")" || continue
        _ui_say ok "✓ 模型映射已更新" >&2
        ;;
      子代理)
        _ui_say title "━━━ 子代理 ━━━" >&2; printf '\n' >&2
        subagent="$(_gum_field "子代理模型 (留空使用默认): " "$subagent")" || continue
        _ui_say ok "✓ 子代理已更新" >&2
        ;;
      自定义环境变量)
        _resolve_env_ref
        _add_custom_env_vars "$pf" ckeys cvals
        # _add_custom_env_vars sets _CUSTOM_KEYS/_CUSTOM_VALS globals
        ckeys=("${_CUSTOM_KEYS[@]}")
        cvals=("${_CUSTOM_VALS[@]}")
        ;;
      确认修改)
        # ── Build diff ─────────────────────────────────────────────
        local has_diff=0
        _ui_say title "━━━━━━━━ 变更摘要 ━━━━━━━━" >&2
        printf '\n' >&2

        _diff_line() {
          local label="$1" old="$2" new="$3"
          if [ "$old" != "$new" ]; then
            has_diff=1
            _ui_say dim "  $label: $(_cc_r "$old") → $(_cc_g "$new")" >&2
          else
            _ui_say dim "  $label: $new (未变)" >&2
          fi
        }

        _diff_line "Token" "$orig_tok" "$tok"
        _diff_line "URL" "$orig_url" "$url"
        _diff_line "Opus" "$orig_opus" "$opus"
        _diff_line "Sonnet" "$orig_sonnet" "$sonnet"
        _diff_line "Haiku" "$orig_haiku" "$haiku"
        _diff_line "Subagent" "$orig_subagent" "$subagent"

        # Custom vars diff
        local ci
        for ci in "${!ckeys[@]}"; do
          local old_val="" new_val="${cvals[$ci]}"
          local cj
          for cj in "${!orig_ckeys[@]}"; do
            [ "${orig_ckeys[$cj]}" = "${ckeys[$ci]}" ] && { old_val="${orig_cvals[$cj]}"; break; }
          done
          _diff_line "${ckeys[$ci]}" "$old_val" "$new_val"
        done

        printf '\n' >&2

        if [ "$has_diff" -eq 0 ]; then
          _ui_say dim "(无变更)" >&2
        fi

        _ui_confirm "确认保存以上修改?" || continue

        # ── Write profile ─────────────────────────────────────────
        _write_profile "$pf" "$tok" "$url" "$opus" "" "$sonnet" "" "$haiku" "" "$subagent"
        if [ "${#ckeys[@]}" -gt 0 ]; then
          local ci
          for ci in "${!ckeys[@]}"; do
            printf 'export %s=%s\n' "${ckeys[$ci]}" "$(printf '%s' "${cvals[$ci]}" | sed "s/'/'\\\''/g")" >> "$pf"
          done
        fi

        printf '\n' >&2
        _ui_say ok "✓ profile $name 已保存" >&2
        return 0
        ;;
      *)
        _ui_say dim "已取消" >&2
        return 1
        ;;
    esac
  done
}
```

**Note:** 上面的 `_diff_line` 嵌套函数里修改 `has_diff` 需要 `has_diff` 声明在 `_diff_line` 定义之前且不加 `local`。调整: `has_diff=0` 放在函数定义前，`_diff_line` 内部引用外层变量。

- [ ] **Step 2: Syntax check**

Run: `bash -n ccm`
Expected: no output (if `_diff_line` scoping issue, fix by moving `has_diff` init before `_diff_line` def and removing nested `local`)

- [ ] **Step 3: Fix `_diff_line` scoping**

The nested function `_diff_line` cannot access `has_diff` if it's declared `local` in the outer scope and referenced inside a function that doesn't have its own `local has_diff`. Bash functions see variables from the calling scope, but `local` restricts to the function scope.

**Fix:** Inline the diff comparison instead of using a nested function. Replace `_diff_line` calls with direct comparisons:

```bash
# Instead of _diff_line "Token" "$orig_tok" "$tok"
if [ "$orig_tok" != "$tok" ]; then
  has_diff=1
  _ui_say dim "  Token: $(_cc_r "$(_mask_preview "$orig_tok")") -> $(_cc_g "$(_mask_preview "$tok")")" >&2
else
  _ui_say dim "  Token: $(_mask_preview "$tok") (未变)" >&2
fi
# ... repeat for each field
```

- [ ] **Step 4: Update `cmd_edit` to call `_interactive_edit`**

```bash
cmd_edit() {
  local name; name="$(_resolve_profile_arg "用法: ccm edit <profile>" "$1")" || exit $?
  local pf; pf="$(_profile_path "$name")" || exit $?
  [ -f "$pf" ] || _die 1 "profile '$name' 不存在(用 'ccm new $name')"

  # Backup current file before editing
  _rotate_backups "$pf"

  if _interactive_edit "$name" "$pf"; then
    _ui_say ok "✓ 已更新 $pf"
    if [ -f "${pf}.back.1" ]; then
      _ui_say info "💡 使用 ccm backup-list $name 查看备份记录"
    fi
  else
    _ui_say err "✖ 已取消，未保存更改" >&2
    exit 1
  fi
}
```

- [ ] **Step 5: Run all tests**

Run: `bash tests/run_all.sh`
Expected: all tests pass (including new/edit with CCM_NO_GUM=1 fallback)

- [ ] **Step 6: Fix any test failures**

Common failure causes:
- New test: wrong number of stdin blank lines for fallback path
- Edit test: `edit 不存在退出码1` might need a dummy input for `_resolve_profile_arg`
- `rm delme` test: profile name `delme` must exist (it does from setup)

- [ ] **Step 7: Commit**

```bash
git add ccm
git commit -m "feat: _interactive_edit — menu→subform→diff edit flow

gum choose 章节菜单, _gum_field 子表单预填当前值, 保存前展示变更摘要.
回退路径用 numbered list + read.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Update gum stub for choose

**Files:**
- Modify: `tests/helpers.sh` — `make_gum_stub` 添加 `choose` 处理

- [ ] **Step 1: Update `make_gum_stub`**

In the stub's case statement, add `choose`:

```bash
case "$sub" in
  style|format|join|log) printf '[gum]%s\n' "${*: -1}" ;;
  input|filter|write)    printf '%s\n' "${GUM_STUB_REPLY:-}" ;;
  choose)                printf '%s\n' "${GUM_STUB_CHOOSE:-}" ;;  # new
  confirm)               exit "${GUM_STUB_CONFIRM:-0}" ;;
  *)                     : ;;
esac
```

- [ ] **Step 2: Add test for gum choose stub**

In `tests/test_ui.sh` (after gum path tests):

```bash
# gum choose stub
export GUM_STUB_CHOOSE="模型映射"
out="$(printf '身份认证\n模型映射\n子代理\n' | PATH="$STUBDIR:$PATH" GUM_STUB_OUT=/dev/null gum choose 2>/dev/null)"
assert_eq "gum choose stub 返回预设值" "模型映射" "$out"
unset GUM_STUB_CHOOSE
```

- [ ] **Step 3: Run UI tests**

Run: `bash tests/test_ui.sh`
Expected: all pass

- [ ] **Step 4: Commit**

```bash
git add tests/helpers.sh tests/test_ui.sh
git commit -m "test: add gum choose to stub, _gum_field tests

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Final integration — run all tests, fix edge cases

**Files:**
- Modify: `ccm`, `tests/test_ccm.sh` — 修复集成测试中发现的问题

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run_all.sh`
Expected: all pass. If any test fails, fix in this task.

- [ ] **Step 2: Fix any edge cases**

Common edge cases:
- **edit with no profiles**: The `_resolve_profile_arg` in `cmd_edit` handles this (shows picker or errors). Verify it still works.
- **new with empty name**: `_profile_path` rejects it.
- **Custom vars with no env_ref.txt**: Should skip gum filter, show empty state.
- **`_gum_field` with special characters in prompt**: `--prompt` value must not break gum's argument parsing. Wrap in quotes.

- [ ] **Step 3: Verify gum path works manually**

Run: `CCM_NO_GUM=0 ccm new test-profile` then cancel.
Run: `CCM_NO_GUM=0 ccm edit <existing>` then cancel.
Expected: no crashes, clean gum UI.

- [ ] **Step 4: Run full test suite one final time**

Run: `bash tests/run_all.sh`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add ccm tests/
git commit -m "fix: integration fixes for gum wizard redesign

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Clean up unused helpers

**Files:**
- Modify: `ccm` — 删除不再被引用的 `_ui_input_quiet` 和 `_ui_password_quiet`

**Check before deleting:** `_ui_input_quiet` 和 `_ui_password_quiet` 如果只有 `_interactive_new`/`_interactive_edit` 在用（通过 `_gum_field`），且旧 `_interactive_profile` 已删除，则可以安全删除。

- [ ] **Step 1: Check references**

```bash
grep -n '_ui_input_quiet\|_ui_password_quiet' ccm
```
Expected: only the function definitions. If used elsewhere, keep.

- [ ] **Step 2: Delete if unused**

Delete `_ui_input_quiet` and `_ui_password_quiet` function definitions.

- [ ] **Step 3: Syntax check + run tests**

Run: `bash -n ccm && bash tests/run_all.sh`
Expected: all pass

- [ ] **Step 4: Commit**

```bash
git add ccm
git commit -m "refactor: remove _ui_input_quiet/_ui_password_quiet (replaced by _gum_field)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

### 1. Spec coverage

- [x] new 3-step flow (core → optional → confirm) — Task 3
- [x] edit menu→subform→diff flow — Task 4
- [x] `gum input --prompt` inline label — Task 2 (`_gum_field`)
- [x] `gum choose` menu — Task 4, Task 5 (stub)
- [x] `gum filter` custom vars — Task 3 (inline in _interactive_new), Task 4
- [x] `gum confirm` — existing `_ui_confirm`
- [x] `gum style` headers — existing `_ui_say`
- [x] Fallback path — all new functions include `_gum_interactive` check + read fallback
- [x] Delete `_ui_wizard_timeline` + `_interactive_profile` — Task 1

### 2. Placeholder scan

No TBD, TODO, or vague instructions. All code shown inline.

### 3. Type consistency

- `_gum_field` signature: `(prompt, initial, [--password])` → stdout value. Consistent across all tasks.
- `_interactive_new` params: `(name)` → calls `_gum_field`, `_write_profile`. Consistent.
- `_interactive_edit` params: `(name, pf)` → calls `_gum_field`, `_write_profile`, `_add_custom_env_vars`. Consistent.
- `cmd_new`/`cmd_edit` dispatch unchanged (same signatures as before).
