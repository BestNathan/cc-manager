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
  # 优先级候选(在 PATH 且可写)
  for c in "$HOME/.local/bin" "$HOME/bin" "$brewbin" "/usr/local/bin"; do
    [ -n "$c" ] || continue
    if _in_path "$c" && [ -w "$c" ]; then printf '%s\n' "$c"; return; fi
  done
  # 退化:扫描 PATH 中任意可写目录
  local oldifs="$IFS"; IFS=':'
  for c in $PATH; do
    [ -n "$c" ] || continue
    if [ -w "$c" ]; then IFS="$oldifs"; printf '%s\n' "$c"; return; fi
  done
  IFS="$oldifs"
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
