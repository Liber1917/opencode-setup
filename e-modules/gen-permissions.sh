#!/usr/bin/env bash
# opencode-setup · E-Ⅰ 权限红线模板生成器
# 设计依据: harness-env-awareness-spec.md E-0/E-2
#   - 按通道选姿态: bash 用 deny-list(挡高危模式) + 只读白名单; edit 限 workspace
#   - escalation: deny 后带 justification 单次升级, 授权永不持久 (由 opencode 原生 ask 流程承担)
#   - 熔断器: 连续拒绝 → 中止升级给人 (event hook 承担)
#   - 硬 deny 位: settings/自保护, 用户级 allow 不可覆盖 (deny 优先级最高, opencode 原生保证)
# 用法: bash gen-permissions.sh [输出路径]  (默认打印到 stdout)

set -euo pipefail
OUT="${1:-/dev/stdout}"

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
      "curl*|*bash": "deny",
      "wget*|*sh": "deny",
      "sudo rm*": "deny",
      ":(){ :|:& };:": "deny",
      "cat >> ~/.ssh/authorized_keys*": "deny",
      "echo*>> ~/.bashrc": "deny",
      "echo*>> ~/.zshrc": "deny",
      "crontab -r*": "deny",
      "git push": "ask",
      "npm publish*": "ask",
      "pip upload*": "ask",
      "docker push*": "ask",
      "gh release create*": "ask",
      "gh pr merge*": "ask",
      "ls*": "allow",
      "cat*": "allow",
      "head*": "allow",
      "tail*": "allow",
      "grep*": "allow",
      "rg*": "allow",
      "find*": "allow",
      "git status*": "allow",
      "git diff*": "allow",
      "git log*": "allow",
      "git branch*": "allow",
      "node --version*": "allow",
      "npm ls*": "allow",
      "npm test*": "allow",
      "npm run*": "allow",
      "make*": "allow",
      "pytest*": "allow",
      "python --version*": "allow",
      "which*": "allow",
      "wc*": "allow",
      "du*": "allow",
      "ps*": "allow",
      "uname*": "allow",
      "*": "ask"
    }
  }
}
EOF
echo "权限红线模板已生成 → $OUT" >&2
