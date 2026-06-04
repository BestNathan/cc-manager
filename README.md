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
可覆盖的 tier:`--opus` / `--sonnet` / `--haiku` / `--subagent`。

## 配置目录

`~/.cc-manager/`(可用 `CCM_HOME` 覆盖)。profile 文件权限 600。
profile 名不能包含 `/` 或 `..`(防路径穿越)。

## 测试

```bash
bash tests/run_all.sh
```

## 限制

- 仅支持 Linux / macOS。
- token 以明文存于 .env(依赖文件权限),非加密存储。
