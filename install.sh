#!/usr/bin/env bash
# cc-manager 安装脚本(Linux / macOS)
#
# 用法:
#   本地安装(L已 clone):
#     ./install.sh
#
#   远程一键安装(curl 管道):
#     curl -fsSL https://raw.githubusercontent.com/BestNathan/cc-manager/main/install.sh | bash
#
#   Clone 源码安装(自动 clone + install):
#     curl -fsSL https://raw.githubusercontent.com/BestNathan/cc-manager/main/install.sh | bash -s -- --clone
#     或: CCM_CLONE=1 ./install.sh
#     或: ./install.sh --clone
#     源码将 clone 到 ~/.cc-manager/src(可被 CCM_SRC_DIR 覆盖)
set -o pipefail

CCM_HOME="${CCM_HOME:-$HOME/.cc-manager}"
CCM_REPO="${CCM_REPO:-https://github.com/BestNathan/cc-manager.git}"
CCM_BRANCH="${CCM_BRANCH:-main}"
CCM_SRC_DIR="${CCM_SRC_DIR:-$CCM_HOME/src}"

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

# ---------------------------------------------------------------------------
# 远程下载(需要 curl 或 wget)
# ---------------------------------------------------------------------------
_remote_fetch() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest" 2>/dev/null && return 0
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$url" -O "$dest" 2>/dev/null && return 0
  fi
  return 1
}

# 判断脚本是否通过管道传入(piped)而非从本地文件执行
_is_piped() {
  # $0 为 bash/zsh 或为空说明是管道模式
  case "$0" in bash|zsh|*/bash|*/zsh|""|"-bash"|"-zsh") return 0 ;; esac
  # 标准输入是管道但脚本文件不存在
  [ ! -f "$0" ] && return 0
  return 1
}

# 管道模式下从远程下载必要文件到临时目录
_download_remote() {
  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/ccm-install.XXXXXX")"
  echo "→ 下载必要文件到 $tmpdir ..."

  local base="https://raw.githubusercontent.com/BestNathan/cc-manager/$CCM_BRANCH"
  local files=("ccm" "install.sh" "template.env" "env_ref.txt" "completions/_ccm")
  for f in "${files[@]}"; do
    mkdir -p "$tmpdir/$(dirname "$f")"
    if ! _remote_fetch "$base/$f" "$tmpdir/$f"; then
      echo "✗ 下载失败: $base/$f" >&2
      rm -rf "$tmpdir"
      return 1
    fi
  done
  printf '%s\n' "$tmpdir"
  return 0
}

# Clone 源码到 CCM_SRC_DIR
_clone_repo() {
  echo "→ Clone 仓库 $CCM_REPO → $CCM_SRC_DIR ..."
  if [ -d "$CCM_SRC_DIR/.git" ]; then
    echo "✓ 仓库已存在,拉取最新代码..."
    git -C "$CCM_SRC_DIR" pull --rebase --quiet 2>/dev/null || true
  else
    git clone --quiet --branch "$CCM_BRANCH" "$CCM_REPO" "$CCM_SRC_DIR" 2>/dev/null
    if [ $? -ne 0 ]; then
      echo "✗ Clone 失败,请检查网络或手动: git clone $CCM_REPO $CCM_SRC_DIR" >&2
      return 1
    fi
    echo "✓ Clone 完成"
  fi
  printf '%s\n' "$CCM_SRC_DIR"
  return 0
}

# ---------------------------------------------------------------------------
# 安装主逻辑
# ---------------------------------------------------------------------------
_install() {
  local src_dir="$1"

  # 1. 骨架
  mkdir -p "$CCM_HOME/profiles" "$CCM_HOME/completions"
  if [ ! -f "$CCM_HOME/template.env" ]; then
    cp "$src_dir/template.env" "$CCM_HOME/template.env"
  fi
  if [ -f "$src_dir/env_ref.txt" ]; then
    cp "$src_dir/env_ref.txt" "$CCM_HOME/env_ref.txt"
    echo "✓ 已安装环境变量参考: $CCM_HOME/env_ref.txt"
  fi
  if [ -f "$src_dir/completions/_ccm" ]; then
    cp "$src_dir/completions/_ccm" "$CCM_HOME/completions/_ccm"
    echo "✓ 已更新 zsh 补全: $CCM_HOME/completions/_ccm"
  fi

  # 2. bin 目录 + 软链
  local bindir; bindir="$(detect_bin_dir)"
  mkdir -p "$bindir"
  ln -sf "$src_dir/ccm" "$bindir/ccm"
  chmod +x "$src_dir/ccm"
  echo "✓ 已链接: $bindir/ccm -> $src_dir/ccm"

  # 3. PATH 提示
  if ! _in_path "$bindir"; then
    echo "⚠ $bindir 不在 PATH。请在 $(_shell_rc) 追加:"
    echo "    export PATH=\"$bindir:\$PATH\""
  fi

  # 4. zsh 补全自动安装
  local rc="$(_shell_rc)"
  if [ "${SHELL##*/}" = zsh ] && command -v zsh >/dev/null 2>&1; then
    local fpath_line="fpath=($CCM_HOME/completions \$fpath)"
    local compinit_line="autoload -Uz compinit && compinit"
    if ! grep -qF "$fpath_line" "$rc" 2>/dev/null; then
      echo "$fpath_line" >> "$rc"
      echo "✓ 已自动写入 zsh 补全配置到 $rc"
    fi
    if ! grep -qF "compinit" "$rc" 2>/dev/null; then
      echo "$compinit_line" >> "$rc"
      echo "✓ 已自动写入 compinit 到 $rc"
    fi
    # 刷新 zsh 补全缓存,确保新补全立即生效
    rm -f ~/.zcompdump ~/.zcompdump.r* 2>/dev/null
    echo "✓ zsh 补全缓存已清理,下次启动 zsh 将加载最新补全"
  else
    echo "✓ 补全已放到 $CCM_HOME/completions/_ccm"
    echo "  在 $rc 追加(若未配置 fpath):"
    echo "    fpath=($CCM_HOME/completions \$fpath)"
    echo "    autoload -Uz compinit && compinit"
  fi

  echo "✓ 完成。试试: ccm list"
}

main() {
  # 解析参数
  local do_clone=0
  for arg in "$@"; do
    case "$arg" in --clone) do_clone=1 ;; esac
  done
  # 环境变量也可触发 clone 模式
  [ "${CCM_CLONE:-}" = "1" ] && do_clone=1

  local src_dir=""

  if [ "$do_clone" -eq 1 ]; then
    # Clone 模式:clone 源码再安装
    src_dir="$(_clone_repo)" || exit 1
    _install "$src_dir"
    echo ""
    echo "📁 源码在: $src_dir"
    echo "   cd $src_dir && git pull 更新"
    return
  fi

  if _is_piped; then
    # 管道模式:下载必要文件到临时目录,再安装
    src_dir="$(_download_remote)" || exit 1
    _install "$src_dir"
    return
  fi

  # 本地模式:从脚本所在目录读取
  src_dir="$(cd "$(dirname "$0")" && pwd)"
  if [ ! -f "$src_dir/ccm" ]; then
    echo "✗ 未找到 ccm 可执行文件,请确认:" >&2
    echo "  - 在 cc-manager 仓库根目录执行 ./install.sh" >&2
    echo "  - 或使用 --clone 自动 clone 仓库" >&2
    exit 1
  fi
  _install "$src_dir"
}

# 测试时只想加载函数,不执行 main
if [ -z "$CCM_INSTALL_LIB_ONLY" ]; then main "$@"; fi
