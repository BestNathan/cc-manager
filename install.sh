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

  # 4. zsh 补全自动安装
  local rc="$(_shell_rc)"
  if [ "${SHELL##*/}" = zsh ] && command -v zsh >/dev/null 2>&1; then
    local fpath_line="fpath=($CCM_HOME/completions \$fpath)"
    local compinit_line="autoload -Uz compinit && compinit"
    local need_write=0
    if ! grep -qF "$fpath_line" "$rc" 2>/dev/null; then
      echo "$fpath_line" >> "$rc"
      need_write=1
    fi
    if ! grep -qF "compinit" "$rc" 2>/dev/null; then
      echo "$compinit_line" >> "$rc"
      need_write=1
    fi
    if [ "$need_write" -eq 1 ]; then
      echo "✓ 已自动写入 zsh 补全配置到 $rc"
    else
      echo "✓ zsh 补全配置已存在,跳过"
    fi
  else
    echo "✓ 补全已放到 $CCM_HOME/completions/_ccm"
    echo "  在 $rc 追加(若未配置 fpath):"
    echo "    fpath=($CCM_HOME/completions \$fpath)"
    echo "    autoload -Uz compinit && compinit"
  fi

  echo "✓ 完成。试试: ccm list"
}

# 测试时只想加载函数,不执行 main
if [ -z "$CCM_INSTALL_LIB_ONLY" ]; then main "$@"; fi
