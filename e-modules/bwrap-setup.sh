#!/usr/bin/env bash
# opencode-setup · B 档 bwrap 沙箱一键脚本
# 依据: spec E-2 B 档 — 复用现成轮子(不造轮子), 提供检测+安装+包装器
# 方案: 优先 clavinculis(质量最高: 三档 profile/合成/etc/密钥 mask);
#       不可用时降级 opencode-bwrap(didvc, 简单直接)。
# 诚实边界: bwrap 管 bash 子进程的 文件系统, 不管网络与 harness 内进程
#           (网络默认放行——LLM API 要用; 需要网络白名单请用 devcontainer C 档)

set -euo pipefail
BIN="${BIN_DIR:-$HOME/.local/bin}"

usage(){ echo "用法: $0 [--uninstall]"; exit "${1:-0}"; }

install_clavinculis() {
  echo "→ 安装 clavinculis (Claude Code/OpenCode/Codex 通用沙箱包装器)"
  # 从 GitHub release 拉静态二进制; 失败则提示手动
  local url="https://ghfast.top/https://github.com/rafal-k/clavinculis/releases/latest/download/clavinculis-linux-x86_64"
  curl -fsSL --connect-timeout 12 --max-time 60 -o "$BIN/clavinculis" "$url" \
    && chmod +x "$BIN/clavinculis" \
    && echo "✓ clavinculis → $BIN/clavinculis" \
    || { echo "⚠ clavinculis 下载失败, 可手动: https://github.com/rafal-k/clavinculis/releases"; return 1; }
}

install_opencode_bwrap() {
  echo "→ 降级方案: opencode-bwrap (didvc)"
  local url="https://ghfast.top/https://raw.githubusercontent.com/didvc/opencode-bwrap/main/opencode-bwrap"
  curl -fsSL --connect-timeout 12 --max-time 60 -o "$BIN/opencode-bwrap" "$url" \
    && chmod +x "$BIN/opencode-bwrap" \
    && echo "✓ opencode-bwrap → $BIN/opencode-bwrap" \
    || echo "⚠ 下载失败, 手动: https://github.com/didvc/opencode-bwrap"
}

make_wrapper() {
  # 生成 opencode-sandbox 命令: 项目目录内以沙箱启动 opencode
  cat > "$BIN/opencode-sandbox" << 'EOF'
#!/usr/bin/env bash
# 沙箱内启动 opencode — 只读挂载工作目录, 其余 HOME 隐藏
# 用法: opencode-sandbox [opencode 参数...]
set -euo pipefail
if command -v clavinculis >/dev/null 2>&1; then
  exec clavinculis --tool opencode --profile strict "$@"
elif command -v opencode-bwrap >/dev/null 2>&1; then
  exec opencode-bwrap "$@"
else
  echo "✗ 未找到沙箱包装器 (clavinculis/opencode-bwrap)" >&2
  echo "  请先运行: bash bwrap-setup.sh" >&2
  exit 1
fi
EOF
  chmod +x "$BIN/opencode-sandbox"
  echo "✓ 包装器 opencode-sandbox → $BIN/opencode-sandbox"
}

uninstall() {
  rm -f "$BIN/clavinculis" "$BIN/opencode-bwrap" "$BIN/opencode-sandbox"
  echo "✓ 已移除 bwrap 相关包装器"
}

main() {
  case "${1:-install}" in
    --uninstall|-u) uninstall; exit 0;;
    install|-i|"")
      mkdir -p "$BIN"
      # 前置: bwrap 系统依赖
      if ! command -v bwrap >/dev/null 2>&1; then
        echo "→ 安装 bubblewrap 系统依赖 (需 sudo)"
        sudo apt-get install -y bubblewrap 2>/dev/null \
          || sudo pacman -S --noconfirm bubblewrap 2>/dev/null \
          || echo "⚠ 请手动安装 bubblewrap"
      fi
      install_clavinculis || install_opencode_bwrap
      make_wrapper
      echo ""
      echo "✓ 完成。用法:"
      echo "    cd 项目目录 && opencode-sandbox"
      echo "  诚实边界: 沙箱管文件系统, 不管网络/harness 内进程。"
      echo "  需要网络白名单/更强隔离 → devcontainer (C 档)。"
      ;;
    *) usage 1;;
  esac
}
main "$@"
