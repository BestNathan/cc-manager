# cc-manager (`ccm`)

管理多个 Claude Code 环境(不同网关 / token / 模型映射),一条命令加载并启动 `claude`。

## 安装

### 一键远程安装(无需 git clone)

```bash
# 直接下载安装(仅下载必要文件,不留存源码)
curl -fsSL https://raw.githubusercontent.com/BestNathan/cc-manager/main/install.sh | bash
```

### Clone 源码安装

```bash
# 自动 clone 仓库到 ~/.cc-manager/src 并安装
curl -fsSL https://raw.githubusercontent.com/BestNathan/cc-manager/main/install.sh | bash -s -- --clone
# 或手动 clone 后安装:
git clone https://github.com/BestNathan/cc-manager.git && cd cc-manager
./install.sh
```

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CCM_HOME` | `~/.cc-manager` | 配置目录 |
| `CCM_BIN_DIR` | 自动探测 | ccm 软链目标 |
| `CCM_REPO` | 本仓库地址 | clone 模式用的仓库 URL |
| `CCM_BRANCH` | `main` | clone 的分支 |
| `CCM_SRC_DIR` | `$CCM_HOME/src` | clone 模式源码存放路径 |
| `CCM_CLONE` | 空 | 设为 `1` 等同于传 `--clone` |

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
可覆盖的 tier:`--opus` / `--sonnet` / `--haiku` / `--subagent`。

## 配置目录

`~/.cc-manager/`(可用 `CCM_HOME` 覆盖)。profile 文件权限 600。
profile 名不能包含 `/` 或 `..`(防路径穿越)。

## 测试

```bash
bash tests/run_all.sh
```

## 冲突检测

`ccm run` 启动前会自动扫描项目级(`.claude/settings.json`)和用户级(`~/.claude/settings.json`)的 settings 文件。
如果检测到 `env.ANTHROPIC_*` 配置,会打印告警提示。

> **注意**:当 settings.json 中配置了 `env.ANTHROPIC_*` 时,该配置会覆盖 profile 文件中对应的环境变量,导致 profile 中的对应设置**不生效**。
>
> **注意**:动态修改 settings.json 中的 `env` 会**立即影响当前正在运行的 Claude Code 会话**,无需重启。

## 限制

- 仅支持 Linux / macOS。
- token 以明文存于 .env(依赖文件权限),非加密存储。
- settings 冲突检测依赖 `jq`(如无 `jq` 则退化为 grep 匹配,精确度略低)。
