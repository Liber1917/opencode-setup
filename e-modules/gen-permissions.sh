#!/usr/bin/env bash
# opencode-setup · E-Ⅰ 权限红线模板生成器
# v3 (2026-09-08): 新增 --sandbox 沙箱档(第三档模板)
# v2 (2026-08-28): 修复两个 benchmark 实测 bug
#   ① 移除 JSON comment 键(opencode schema 拒绝)
#   ② webfetch 用 Action 字符串(非对象)
#   ③ 新增双模板: --headless 无头/benchmark 友好版
#      (无头模式 ask=auto-reject, 原交互红线会导致 agent 寸步难行)
# 用法: gen-permissions.sh [--headless|--sandbox] [输出路径]
# 三档模板:
#   (默认)     交互选档 — 终端([ -t 0 ])上先问权限档位: 1 标准(=交互版 59 条:
#              14 deny/6 ask/39 allow, 高风险弹窗确认) / 2 沙箱; 回车/非法×3
#              =标准档。非交互(管道/curl|bash/无头 CI)不问, 直接标准档, 零变化。
#   --headless 无头版 — benchmark/CI: 7 条红线 deny + 其余全 allow
#   --sandbox  沙箱版 — 一次性容器/VM 等本机破坏可复原的隔离环境:
#              删本机破坏类 deny(隔离边界已覆盖), 保留网络不可逆类 deny
#              (隔离挡得住本机破坏, 挡不住网络不可逆), ask 归零
#              (docker/pip/npm 等免手动点弹窗)。
#              适用边界: 不是全 bypass——网络红线仍在。
# 环境变量: PERMISSION_MODE=headless|sandbox 与对应 flag 等价(CI 直选)。

set -euo pipefail
MODE="${PERMISSION_MODE:-interactive}"
OUT=""
for a in "$@"; do
  case "$a" in
    --headless) MODE=headless ;;
    --sandbox) MODE=sandbox ;;
    -h|--help)
      cat << 'HELP'
用法: gen-permissions.sh [--headless|--sandbox] [输出路径]

模板三档:
  (默认)      交互选档 — 终端上问权限档位: 1 标准(=交互版 59 条: 14 deny/
              6 ask/39 allow, 高风险弹窗确认) / 2 沙箱; 回车/非法×3=标准档;
              非交互(管道)不问, 直落标准档, 零行为变化
  --headless  无头版 — benchmark/CI 无头跑, 7 条红线 deny + 其余全 allow
  --sandbox   沙箱版 — 容器/隔离环境, 删本机破坏类红线(隔离已覆盖),
              保留网络不可逆红线(隔离挡不住网络), ask 归零免手动点; 不是全 bypass

环境变量: PERMISSION_MODE=headless|sandbox 与对应 flag 等价(CI 直选)
HELP
      exit 0 ;;
    *) OUT="$a" ;;
  esac
done
case "$MODE" in
  interactive|headless|sandbox) ;;
  *) echo "错误: 未知 PERMISSION_MODE='$MODE' (合法值: headless|sandbox; 留空=交互版)" >&2; exit 1 ;;
esac

# ── 交互档位问句(仅默认档 + 终端 stdin)────────────────────────────
# setup-opencode.sh 步骤12 经命令替换调用本脚本: stdout/stderr 被重定向到
# /dev/null 但 stdin 未重定向——交互装机时问句照常触发, 提示因此写
# /dev/tty(重定向下仍可见), 输入读 stdin(同一终端)。
# 非交互(管道/curl|bash/docker -i 无 -t): [ -t 0 ] 为假, 不问不读,
# 直接标准档, 与历史版本零差异。
if [ "$MODE" = "interactive" ] && [ -t 0 ]; then
  TTY_OUT=/dev/stderr
  if [ -w /dev/tty ]; then TTY_OUT=/dev/tty; fi
  tries=0
  while :; do
    printf '═══ 权限档位 ═══\n 1. 标准 — 未知命令弹窗(日常开发,默认)\n 2. 沙箱 — 免 docker/pip 弹窗;删本机红线,留网络红线(容器/VM 等可复原环境)\n选择 [1]: ' > "$TTY_OUT"
    if ! IFS= read -r ans; then ans=""; break; fi    # EOF(如 Ctrl-D)→ 标准档
    ans=$(printf '%s' "$ans" | tr -d '[:space:]')
    case "$ans" in
      ""|1) break ;;
      2) MODE=sandbox; break ;;
      *)
        tries=$((tries+1))
        if [ "$tries" -ge 3 ]; then
          printf '连续 3 次无效输入, 按标准档继续\n' > "$TTY_OUT"
          break
        fi
        printf '无效输入: %s(请输入 1 或 2, 回车=标准)\n' "$ans" > "$TTY_OUT"
        ;;
    esac
  done
  if [ "$MODE" = "sandbox" ]; then
    printf '→ 沙箱档: 删本机红线, 留网络红线(docker/pip 免弹窗)\n' > "$TTY_OUT"
  else
    printf '→ 标准档\n' > "$TTY_OUT"
  fi
fi

[ -z "$OUT" ] && OUT=/dev/stdout

case "$MODE" in
  headless)
cat > "$OUT" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "bash": {
      "rm -rf *": "deny",
      "rm -fr *": "deny",
      "git push --force*": "deny",
      "git push -f *": "deny",
      "mkfs*": "deny",
      "curl*|*sh": "deny",
      "wget*|*sh": "deny",
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
;;
  sandbox)
# 沙箱档设计裁定(用户批准): 隔离挡得住本机破坏, 挡不住网络不可逆。
#   - 删本机破坏类 deny(rm -rf/mkfs/dd/chmod 777/git reset --hard/
#     crontab -r/sudo rm 等): 容器/VM 边界已覆盖, 可复原。
#   - 保留网络不可逆类 deny: force-push/curl|sh/wget|sh/authorized_keys
#     凭据持久化。
#   - gh release create* 定 deny 而非 ask: 本档 ask 归零无中间态;
#     发布即触发通知/外部镜像抓取, 事后删除收不回已分发的产物,
#     按网络不可逆标准归 force-push 同类。
#   - ask 归零: docker/pip/npm 等全部走 "*" allow 兜底, 免手动点弹窗。
cat > "$OUT" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "bash": {
      "git push --force*": "deny",
      "git push -f *": "deny",
      "curl*|*sh": "deny",
      "wget*|*sh": "deny",
      "cat >> ~/.ssh/authorized_keys*": "deny",
      "gh release create*": "deny",
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
;;
  *)
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
      "ls*": "allow",
      "cat *": "allow",
      "head *": "allow",
      "tail *": "allow",
      "grep*": "allow",
      "find *": "allow",
      "pwd": "allow",
      "echo *": "allow",
      "which *": "allow",
      "env": "allow",
      "date*": "allow",
      "wc *": "allow",
      "sort *": "allow",
      "uniq *": "allow",
      "diff *": "allow",
      "stat *": "allow",
      "file *": "allow",
      "du *": "allow",
      "df *": "allow",
      "ps *": "allow",
      "id*": "allow",
      "uname *": "allow",
      "git status*": "allow",
      "git log*": "allow",
      "git diff*": "allow",
      "git show*": "allow",
      "git branch*": "allow",
      "node --version": "allow",
      "npm --version": "allow",
      "npm test*": "allow",
      "npm run *": "allow",
      "python3 --version": "allow",
      "pytest*": "allow",
      "cargo build*": "allow",
      "cargo test*": "allow",
      "go build*": "allow",
      "go test*": "allow",
      "mkdir *": "allow",
      "touch *": "allow",
      "*": "ask"
    }
  }
}
EOF
;;
esac
case "$MODE" in
  headless) LABEL="(无头版)" ;;
  sandbox)  LABEL="(沙箱版)" ;;
  *)        LABEL="(交互版)" ;;
esac
echo "权限模板已生成$LABEL → $OUT" >&2
