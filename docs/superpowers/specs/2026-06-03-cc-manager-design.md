# cc-manager 设计文档

日期:2026-06-03

## 目标

管理多个 Claude Code 环境(不同服务网关 + 不同 token + 不同模型映射),
提供一个 `ccm` CLI:一条命令加载某个 profile 的环境变量并启动 `claude`,
支持启动时临时覆盖模型,以及顺手地新建/编辑 profile。

## 非目标(YAGNI)

- 不做 GUI / TUI。
- 不做加密存储(token 以明文 .env 存放,依赖文件权限 600)。
- 不做跨机器同步。

## 用户决策(已确认)

- 启动方式:CLI dispatcher(`ccm run <profile>`)。
- 模型选择:profile 内固定默认值,启动时可用 `--opus/--sonnet/--haiku` 覆盖。
- 实现语言:纯 Bash 脚本(零依赖、启动快、source env + exec 最自然)。
- 配置格式:每个 profile 一个 `.env` 文件。
- 配置目录:`~/.cc-manager/`(不用 `~/.config`)。
- 需要顺手的编辑入口(`ccm new` / `ccm edit`)。
- `ccm show` 默认对 token 打码,`--raw` 显示原文。
- 需要 zsh 补全。
- 模板只含占位符 + 注释,不含任何真实 token/url。

## 目录布局

```
~/.cc-manager/
├── profiles/
│   ├── work.env
│   └── personal.env
└── template.env        # 新建 profile 的模板(占位符 + 注释)
```

profile 文件内容形如(占位示例):

```bash
# cc-manager profile
export ANTHROPIC_AUTH_TOKEN="<YOUR_TOKEN>"
export ANTHROPIC_BASE_URL="<https://your-gateway.example.com>"
export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-8"
export ANTHROPIC_DEFAULT_OPUS_MODEL_NAME="claude-opus-4-8"
export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-4-6"
export ANTHROPIC_DEFAULT_SONNET_MODEL_NAME="claude-sonnet-4-6"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku-4-5-20251001"
export ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME="claude-haiku-4-5-20251001"
# 可选:export CLAUDE_CODE_SUBAGENT_MODEL="claude-opus-4-7"
```

## 命令集

| 命令 | 作用 |
|---|---|
| `ccm run <profile> [--opus M] [--sonnet M] [--haiku M] [--subagent M] [-- <claude args>]` | 加载 profile 并 `exec claude`;模型 flag 临时覆盖;`--` 后参数透传给 claude |
| `ccm list` / `ccm ls` | 列出所有 profile(标注 BASE_URL,token 不显示) |
| `ccm new <profile>` | 用 template 生成新文件,chmod 600,打开 `$EDITOR` |
| `ccm edit <profile>` | 打开已有 profile(用 `$EDITOR`) |
| `ccm show <profile> [--raw]` | 打印 profile 内容,默认 token 打码 |
| `ccm rm <profile>` | 删除(交互确认 y/N) |
| `ccm env <profile>` | 仅输出 profile 文件绝对路径,供 `source "$(ccm env work)"` |
| `ccm help` / `-h` / `--help` | 用法 |
| `ccm version` / `--version` | 版本 |

## run 的核心流程

输入示例:`ccm run work --opus claude-opus-4-7 -- --dangerously-skip-permissions`

1. 解析参数:第一个非 flag 实参为 profile 名;`--opus/--sonnet/--haiku/--subagent` 各吃一个值;
   遇到 `--` 后,剩余全部收集为透传给 claude 的参数。
2. 校验 `profiles/<profile>.env` 存在;不存在 → 报错并列出可用 profile,退出码 1。
3. 加载环境:`set -a; source <profile>.env; set +a`(自动 export)。
4. 应用覆盖:
   - `--opus M`   → `ANTHROPIC_DEFAULT_OPUS_MODEL=M`、`ANTHROPIC_DEFAULT_OPUS_MODEL_NAME=M`
   - `--sonnet M` → 对应 SONNET 两个变量
   - `--haiku M`  → 对应 HAIKU 两个变量
   - `--subagent M` → `CLAUDE_CODE_SUBAGENT_MODEL=M`
5. 健全性检查:
   - `ANTHROPIC_AUTH_TOKEN` 或 `ANTHROPIC_BASE_URL` 为空 → 打印 warning(不阻断)。
   - `command -v claude` 不存在 → 报错退出码 127。
6. `exec claude "${claude_args[@]}"`(用 exec 替换进程,保证信号与退出码透传)。

## 错误处理

| 场景 | 行为 |
|---|---|
| profile 不存在 | stderr 报错 + 列出可用 profile,退出 1 |
| 未提供 profile 名 | 打印 run 用法,退出 2 |
| 缺 token / base_url | stderr warning,继续启动 |
| `claude` 不在 PATH | stderr 报错,退出 127 |
| `$EDITOR` 未设置 | fallback 到 `vi` |
| `~/.cc-manager` 不存在 | 任意命令首次运行时自动创建骨架 |

## 安装(install.sh)

支持 Linux 与 macOS(不支持 Windows)。安装时**自适应探测**目标 bin 目录,不写死。

1. 创建 `~/.cc-manager/profiles/` 与 `~/.cc-manager/template.env`(若不存在)。
2. **选择 bin 目录**(详见下方算法),将 `ccm` 软链到 `<bin_dir>/ccm`。
3. 安装 zsh 补全文件 `_ccm` 到 `~/.cc-manager/completions/`,并提示在 `~/.zshrc`
   中加入 `fpath` 与 `compinit`(或追加一行 source)。
4. 不写入任何真实 token;不覆盖已存在的 profile;不主动调用 sudo。

### bin 目录探测算法(跨 Linux/macOS)

1. **显式覆盖**:`--bin-dir <path>` 或环境变量 `CCM_BIN_DIR` 优先于一切。
2. **自动探测**:按优先级取第一个「已在 `$PATH` 中**且**可写」的目录:
   1. `$HOME/.local/bin`(XDG / 用户级通用首选)
   2. `$HOME/bin`
   3. `$(brew --prefix)/bin`(若存在 Homebrew —— mac `/opt/homebrew/bin` 或 Linuxbrew,且可写)
   4. `/usr/local/bin`(仅当可写,不主动 sudo)
3. **兜底**:若以上都不满足,使用 `$HOME/.local/bin`(创建之),并检测当前 shell
   (`$SHELL`:zsh→`~/.zshrc`;bash→Linux `~/.bashrc` / macOS `~/.bash_profile`)
   打印一行 `export PATH="$HOME/.local/bin:$PATH"` 供用户追加。
4. 判定「在 PATH 中」用精确分段匹配(`:$PATH:` 包含 `:$dir:`),避免子串误判。
5. 安装结束打印最终选定的 bin 目录与该目录是否已生效于当前 PATH。

## zsh 补全(_ccm)

- 补全子命令:run / list / ls / new / edit / show / rm / env / help / version。
- 对 `run/edit/show/rm/env` 的 profile 参数:列出 `profiles/*.env` 去掉后缀的名字。
- 对 `run` 的 `--opus/--sonnet/--haiku/--subagent/--` flag 补全。

## 组件与文件清单

| 文件 | 职责 |
|---|---|
| `ccm` | 主脚本:参数解析 + 各子命令分发 + run 启动逻辑 |
| `template.env` | profile 模板(占位符 + 注释) |
| `completions/_ccm` | zsh 补全脚本 |
| `install.sh` | 安装/初始化 |
| `README.md` | 用法说明 |

## 测试策略

纯 bash,用一个 `tests/test_ccm.sh`(或 bats 若可用)覆盖:

- `ccm list` 在空目录/有 profile 时输出正确。
- `ccm new` 生成文件且权限 600。
- `ccm show` 默认打码、`--raw` 不打码。
- `ccm run <不存在>` 退出码 1 且列出可用 profile。
- run 的参数解析:模型覆盖正确写入对应 env;`--` 后参数正确收集
  (用一个假的 `claude` 桩脚本打印 env 与 argv 来断言,不真正联网)。
- `ccm env` 输出正确路径。
- install.sh bin 目录探测:`CCM_BIN_DIR` / `--bin-dir` 覆盖生效;PATH 段匹配
  用精确分段(`:$PATH:`)而非子串(可用注入假 PATH 的方式断言选中目录)。

## 安全

- profile 文件权限 600(含 new 创建时)。
- `show` 默认打码 token(保留前 4 后 4,中间 `***`)。
- 不把 token 写入日志/补全缓存。
