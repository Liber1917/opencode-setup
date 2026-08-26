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
    "comment": "E-Ⅰ 权限红线: deny-first 于高危通道, 白名单放行只读; 弹窗目标=常规会话零弹窗",

    "edit": {
      "comment": "edit 限 workspace — 堵 Tier-2 盲区(状态文件经 Edit 工具绕过 bash 审计的教训, Claude auto mode 36.8%)",
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

    "webfetch": {
      "comment": "网络按需; 出网走 ask (一次批准会话内生效, opencode 原生)",
      "*": "ask"
    },

    "bash": {
      "comment": "=== 硬 deny 位(不可被用户级 allow 覆盖; deny 求值优先) ===",
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

      "comment2": "=== 敏感文件写(密钥治理联动) ===",
      "cat >> ~/.ssh/authorized_keys*": "deny",
      "echo*>> ~/.bashrc": "deny",
      "echo*>> ~/.zshrc": "deny",
      "crontab -r*": "deny",

      "comment3": "=== 花钱/发布通道: ask(escalation 语义 — 带 justification 单次放行, 授权不持久) ===",
      "git push": "ask",
      "npm publish*": "ask",
      "pip upload*": "ask",
      "docker push*": "ask",
      "gh release create*": "ask",
      "gh pr merge*": "ask",

      "comment4": "=== 只读白名单(零弹窗目标的主承载) ===",
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

      "comment5": "=== 其余 bash: ask(宽带放行的边界兜底) ===",
      "*": "ask"
    }
  }
}
EOF
echo "权限红线模板已生成 → $OUT" >&2
