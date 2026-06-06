# 设计: gum-first UI 抽象层

## 概述

将 `ccm` 的所有面向用户的输出统一到一个 `_ui_*` 抽象层:**gum 可用时全部由 gum 渲染,gum 缺失时回退到现有的 ANSI/`printf` 方式**。目标是消除散落在各命令里的直接 `printf` / `_cc_*` 调用,让 UI 行为收敛到单一出口,同时保留项目"零依赖也能跑"的承诺。

视觉风格为**极简上色**(只用 gum 的上色/对齐,不引入边框、表格),性能上要求**批量渲染**(每个渲染原语最多 fork 一次 gum)。

### 背景

前置 bug 已修复:gum 的交互界面渲染到 stderr,旧代码用 `2>/dev/null` / `>/dev/null 2>&1` 把 gum 的 TUI 丢进黑洞,导致 gum 装了也永远走 shell 回退。修复方式是把 gum 的 stderr 指向 `/dev/tty`。本设计在此基础上重构整个 UI 层。

## 设计决策(已确认)

| 决策 | 选择 |
|------|------|
| 范围 | 全部 UI 走 gum,gum 缺失回退 printf(双路径) |
| 视觉 | 极简上色,无边框/表格,批量渲染 |
| 选择器 | 缺 profile 参数时弹 gum 选择器,gum 缺失回退用法报错 |
| 架构 | 集中式 `_ui_*` 抽象层(连非交互上色也走 gum) |

## 架构

### 能力检测(三档)

```bash
# 渲染门: gum 二进制存在且未被禁用
_has_gum()         { [ -z "${CCM_NO_GUM:-}" ] && command -v gum >/dev/null 2>&1; }

# 交互门: 在渲染门基础上,额外要求 /dev/tty 可用
_gum_interactive() { _has_gum && { : < /dev/tty; } 2>/dev/null; }

# 上色开关: 沿用现有 _cc_on —— 仅当输出 fd 是 TTY 时上色;管道输出纯文本
```

这一拆分同时收编了旧 `_has_gum` 用 `[ -t 0 ]` 门控的缺陷:渲染只看二进制 + 输出是否 TTY,交互单独看 `/dev/tty`,两者不再混用。

### 三级回退

每个 `_ui_*` 原语内部按以下顺序降级,调用方无需关心:

1. **gum** —— `_has_gum`(渲染)/ `_gum_interactive`(交互)为真
2. **ANSI** —— gum 不可用但输出是 TTY,用现有 `_cc_*` 上色
3. **纯文本** —— 输出非 TTY(管道/重定向),不带任何控制序列

### gum 交互调用约定

所有 gum 交互命令统一:`stdin < /dev/tty`、TUI(stderr)`2>/dev/tty`、结果从 stdout 取(input/filter)或退出码取(confirm)。禁止把 gum 的 stderr 重定向到 `/dev/null`。

## 组件

### `_ui_*` 抽象层(唯一出口)

约束:
- 所有命令只调 `_ui_*`,不再直接 `printf` / `gum` / `_cc_*`(`_die` 等底层除外)。
- 每个**渲染**原语最多 fork 一次 gum(批量,杜绝逐 token fork)。

**交互原语**(额外要求 `/dev/tty`,否则回退):

| 原语 | gum 路径 | 回退路径 |
|------|---------|---------|
| `_ui_input <label> <hint> <initial>` | `gum input` | `read` |
| `_ui_password <label> <hint>` | `gum input --password` | `read -s` / `read` |
| `_ui_confirm <prompt>` → 退出码 | `gum confirm` | `read [Y/n]` |
| `_ui_pick <prompt>`(从 stdin 读候选) | `gum filter`(可搜索) | 编号菜单 `read` |

**渲染原语**(单色/整块,一次 gum style 调用):

| 原语 | 职责 |
|------|------|
| `_ui_title <text>` | 标题/段落头(bold + 主色) |
| `_ui_msg <ok\|warn\|err\|info> <text>` | 状态行(✓/⚠/✖/ℹ + 对应色) |
| `_ui_kv <key> <val> ...` | 对齐的键值块(`ccm show`) |
| `_ui_rows <row> ...` | 列表块(`ccm list`) |
| `_ui_timeline <cur> <total> <label...>` | 向导步骤指示条 |

### 合并重复的向导

现 `_interactive_profile` 内有两套并行向导(`_ui_gum_wizard` 与 shell 版 `_ui_wizard_*`)。重构后**合并为一套**,统一基于 `_ui_*` 原语,gum/回退分支下沉到原语内部。删除 `_ui_gum_wizard`、`_ui_gum_input`、`_ui_gum_confirm`、`_ui_wizard_content`、`_ui_wizard_confirm` 等重复实现,消除逻辑漂移。

### profile 选择器

新增 `_resolve_profile_arg <cmd> [name]`:

- 给了 `name` → 走现有校验(存在性、非法字符)后返回。
- 未给 `name`:
  - `_gum_interactive` 为真 → 列出所有 profile,经 `_ui_pick` 让用户选择,返回所选。
  - 否则 → `_die 2` 输出原用法错误。

接入命令:`run`、`rm`、`edit`、`show`、`backup-restore`。`new` 不接入(它需要用户输入新名字,不是从已有列表选)。

## 数据流

```
cmd_* ──► _resolve_profile_arg(可选) ──► _ui_*  ──► [_gum_interactive/_has_gum?]
                                                      ├─ 是 ─► gum (stdin</dev/tty, stderr>/dev/tty)
                                                      ├─ 否 + TTY ─► _cc_* ANSI
                                                      └─ 否 + 管道 ─► 纯文本
```

## 错误处理

- gum 交互进程退出码非 0(用户按 Esc/Ctrl-C)→ 视为取消,原语 `return 1`,调用方按取消处理。
- gum 渲染失败 → 不应发生(渲染不需 TTY);若发生则原语回退到 ANSI/纯文本,不中断命令。
- `CCM_NO_GUM=1` → 强制全程回退,等价于 gum 未安装。
- 选择器在无候选(零个 profile)时 → 走原"无 profile"提示,不弹空选择器。

## 性能

- 硬约束:每个渲染原语 ≤1 次 gum 子进程。`list`/`show`/`help` 等整屏输出先在 bash 内合成文本,再一次性交给 `gum style`。
- 禁止在循环里逐行/逐 token 调 `gum`。

## 测试

- **回退路径(主):** 测试环境设 `CCM_NO_GUM=1`(或 PATH 中无 gum),现有 ~27 条断言全部经回退路径保持绿色,保证 gum 缺失时行为不回归。
- **gum 路径(新):** 新增 fake `gum` stub(仿照现有 fake `claude`),记录 argv 到临时文件;断言:
  - 各交互原语在 gum 可用时以预期参数调用 gum(如 `--password`、`filter` 候选来自 stdin)。
  - 各渲染原语调用 `gum style` 且符合"≤1 次 fork"约定。
  - `_resolve_profile_arg` 在缺参 + gum 可用时调用选择器;缺参 + 无 gum 时报用法错误。
- **门控:** 验证 `_has_gum` / `_gum_interactive` 在 `CCM_NO_GUM=1`、无 `/dev/tty` 等条件下的返回值。

## 文件映射

| 文件 | 操作 | 职责 |
|------|------|------|
| `ccm` | 修改 | 新增 `_ui_*` 抽象层;拆分 `_has_gum` / `_gum_interactive`;合并向导为单套;新增 `_resolve_profile_arg` 并接入 run/rm/edit/show/backup-restore;将所有 `cmd_*` 输出收口到 `_ui_*` |
| `tests/helpers.sh` | 修改 | 新增 fake `gum` stub;提供 gum 可用/不可用两种测试夹具 |
| `tests/test_ccm.sh` | 修改 | 新增 gum 路径与选择器断言;确保回退路径断言不回归 |
| `install.sh` | 修改 | 确保 gum 在可选依赖 `_OPT_DEPS` 列表中 |
| `completions/_ccm` | 不变 | 无新增子命令/flag;选择器为缺参行为,不影响补全 |

## 范围之外(YAGNI)

- 不引入边框、表格、卡片等富视觉(已选极简)。
- 不改 `ccm run` 的 `exec claude` 行为。
- 不做与本目标无关的重构。
- `new` 命令不接入选择器(需新名字输入,非选择)。
