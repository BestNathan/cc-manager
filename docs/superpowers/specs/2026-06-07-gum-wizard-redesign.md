# 设计: 基于 gum 重新设计 new/edit 向导流程

## 概述

用 gum 原生组件重新设计 `ccm new` 和 `ccm edit` 的交互流程，解决当前设计的三个问题：

1. **步骤太多** — 5 步线性向导，编辑时每次必须走完全部字段
2. **线性强迫** — edit 无法跳到想改的字段
3. **视觉不统一** — printf 时间轴 + gum input --header 两种渲染路径冲突

新设计：new 精简为 3 步，edit 改为章节菜单+子表单的跳转模式；字段标签从 `--header` 改为 `--prompt`（同行渲染，消除渲染冲突）。

## new 流程（3 步）

### Step 1 — 核心配置

Token + Base URL + Opus/Sonnet/Haiku 模型 ID 合并为一步，逐字段填。

- 组件：`gum input --prompt "label: " --value "$prev"`
- Token 用 `--password` 隐藏输入
- 5 个字段连续填写

### Step 2 — 可选配置

子代理模型 + 自定义环境变量。

- 子代理：`gum input --prompt`，留空跳过
- 自定义变量：`gum filter --height 8 --limit 1` 搜索 env_ref.txt，选中后 `gum input` 填值，循环
- **ESC 整步跳过**（不添加可选配置）

### Step 3 — 确认

展示所有字段摘要（Token 打码），包括已添加的自定义变量。

- 组件：`gum style` 渲染摘要 + `gum confirm` 确认保存
- 确认后写盘 + 旋转备份

## edit 流程（菜单→子表单）

### 主菜单

`gum choose` 列出 4 个章节：

- 身份认证（Token + URL）
- 模型映射（Opus/Sonnet/Haiku）
- 子代理
- 自定义环境变量

底部选项：[确认修改] [取消]

### 子表单

选中章节 → `gum input --prompt --value "$current"` 逐字段编辑，预填当前值。

- [保存] 写回内存，返回菜单
- [返回] 放弃本章节修改，返回菜单

### 变更摘要

[确认修改] 选中时，展示所有发生过变更的字段（变更前→变更后），`gum confirm` 二次确认后写盘 + 旋转备份。

## 渲染策略

**统一使用 gum 原生组件，不再混合 printf 时间轴。**

| 场景 | 组件 | 说明 |
|------|------|------|
| 标题/章节头 | `gum style --bold --foreground 6` | `_ui_say title` 已封装 |
| 字段输入 | `gum input --prompt "label: " --value "$prev"` | `--prompt` 同行标签，替代 `--header` |
| 密码输入 | `gum input --password --prompt "Token: "` | 同上 |
| 菜单选择 | `gum choose` | edit 章节菜单 |
| 环境变量搜索 | `gum filter --height 8 --limit 1` | Step 2 / edit 自定义变量 |
| 确认 | `gum confirm` | `_ui_confirm` 已封装 |
| 状态消息 | `gum style --foreground 2/3/1` | `_ui_say` 已封装 |
| 回退输入 | `read -r` / `read -rs` | 无 gum 时，保持现有回退行为 |

### --prompt vs --header

`gum input --prompt` 将标签放在输入框左侧同行（`label: [_]`），不额外占行。相比 `--header`（标签单独一行在输入上方），不会出现 header 行与 wizard timeline 争抢终端渲染区域的冲突。整个页面渲染统一由 gum 管理。

## 保留/删除/新增

### 保留

`_ui_say`、`_ui_input_quiet`、`_ui_password_quiet`、`_ui_confirm`、`_ui_pick`、gum filter 逻辑、全部回退路径、`_write_profile`、备份轮转、`_parse_env_value`、`_mask_preview`、`_add_custom_env_vars`/`_add_custom_env_vars_read`

### 删除

- `_ui_wizard_timeline` — printf 时间轴，被 gum 原生替代
- `_interactive_profile` — 当前 5 步线性流程，拆分为 new/edit 两套

### 新增

| 函数 | 职责 |
|------|------|
| `_gum_form` | 通用：渲染标题 + 逐字段 `gum input --prompt`，返回填好的值 |
| `_gum_choose_section` | edit：`gum choose` 章节菜单，选中→`_gum_form` 子表单 |
| `_interactive_new` | new：3 步流程 |
| `_interactive_edit` | edit：菜单→子表单→变更摘要→确认 |

## 错误处理

- gum 进程退出码非 0（ESC/Ctrl+C）→ 用户取消，return 1
- gum 未安装 → 回退到现有 `read` 流程
- `CCM_NO_GUM=1` → 强制回退
- 新增字段数量保持可控，不引入新的故障模式

## 文件影响

| 文件 | 操作 | 职责 |
|------|------|------|
| `ccm` | 修改 | 新增/替换函数，重写 `cmd_new`/`cmd_edit` 分派 |
| `completions/_ccm` | 不变 | 命令签名未变 |
| `tests/` | 新增 | `_gum_form`、`_interactive_new`、`_interactive_edit` 的单元测试 |
