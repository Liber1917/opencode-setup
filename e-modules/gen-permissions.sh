#!/usr/bin/env bash
# opencode-setup · E-Ⅰ 权限红线模板生成器
# v2 (2026-08-28): 修复两个 benchmark 实测 bug
#   ① 移除 JSON comment 键(opencode schema 拒绝)
#   ② webfetch 用 Action 字符串(非对象)
#   ③ 新增双模板: --headless 无头/benchmark 友好版
#      (无头模式 ask=auto-reject, 原交互红线会导致 agent 寸步难行)
# 用法: gen-permissions.sh [--headless] [输出路径]

set -euo pipefail
HEADLESS=0
for a in "$@"; do [ "$a" = "--headless" ] && HEADLESS=1; done
OUT="${@: -1}"
[ "$OUT" = "--headless" ] && OUT=/dev/stdout

if [ "$HEADLESS" = "1" ]; then
cat > "$OUT" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "bash": {
      "rm -rf *": "deny",
      "rm -fr *": "deny",
      "git push --force*": "deny",
      "git push -f *": "deny",
      "git reset --hard*": "deny",
      "git clean -fdx*": "deny",
      "mkfs*": "deny",
      "dd if=*of=/dev/*": "deny",
      "chmod -R 777*": "deny",
      "curl*|*sh": "deny",
      "wget*|*sh": "deny",
      "sudo rm*": "deny",
      "cat >> ~/.ssh/authorized_keys*": "deny",
      "git push": "ask",
      "npm publish*": "ask",
      "docker push*": "ask",
      "*": "allow"
    },
    "edit": "allow",
    "read": "allow",
    "write": "allow",
    "glob": "allow",
    "grep": "allow",
    "list": "allow",
    "task": "allow",
    "external_directory": "allow",
    "webfetch": "allow",
    "websearch": "allow"
  }
}
EOF
else
cat > "$OUT" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "edit": {
      "~/.config/opencode/**": "allow",
      "~/.claude/**": "allow",
      "/etc/**": "deny",
      "~/.ssh/**": "deny",
      "~/.aws/**": "deny",
      "~/.gnupg/**": "deny",
      "~/.config/opencode/opencode.json": "deny",
      "~/.config/opencode/oh-my-openagent.json": "deny",
      "~/.config/opencode/settings.json": "deny"
    },
    "webfetch": "ask",
    "bash": {
      "rm -rf *": "deny",
      "rm -fr *": "deny",
      "git push --force*": "deny",
      "git push -f *": "deny",
      "git reset --hard*": "deny",
      "git clean -fdx*": "deny",
      "mkfs*": "deny",
      "dd if=*of=/dev/*": "deny",
      "chmod -R 777*": "deny",
      "curl*|*sh": "deny",
      "wget*|*sh": "deny",
      "sudo rm*": "deny",
      "cat >> ~/.ssh/authorized_keys*": "deny",
      "crontab -r*": "deny",
      "git push": "ask",
      "npm publish*": "ask",
      "docker push*": "ask",
      "gh release create*": "ask",
      "gh pr merge*": "ask",
      "*": "ask"
    }
  }
}
EOF
fi
echo "权限模板已生成$( [ "$HEADLESS" = "1" ] && echo '(无头版)' || echo '(交互版)' ) → $OUT" >&2
