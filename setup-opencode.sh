#!/bin/bash
# ============================================================================
# OpenCode 一键配置脚本
# 使用 Bun 作为运行时，自动安装所有依赖
# 支持 Linux / macOS / WSL
# ============================================================================

SETUP_VERSION="v1.0"  # 动态升级 P0:版本常量,--upgrade 比对用(git 克隆场景以 git describe --tags --always 覆盖)

if [ -z "${BASH_VERSION:-}" ]; then
  echo "检测到非 bash 环境，自动以 bash 重新执行..."
  exec bash "$0" "$@"
fi

set -e
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# 管道/升级场景: ~/.local/bin 可能不在默认 PATH,探测组件前扩入(webmap/opstate/mem0 等安装位)
export PATH="$HOME/.local/bin:$PATH"

# 参数解析(动态升级 P0): --version/--upgrade/-h 即时退出,不进 12 步主流程;
# 未识别参数忽略(与历史行为一致,主流程本就不吃参数)
for _arg in "$@"; do
  case "$_arg" in
    --version)
      if [ -d "$SCRIPT_DIR/.git" ] && command -v git >/dev/null 2>&1; then
        _gc="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || true)"
        echo "setup-opencode.sh $SETUP_VERSION${_gc:+ (git: $_gc)}"
      else
        echo "setup-opencode.sh $SETUP_VERSION"
      fi
      exit 0
      ;;
    --upgrade)
      # P1(动态升级,计划 .omo/plans/dynamic-upgrade.md): 只置旗不退出——
      # 状态还原入口块依赖 CONFIG_DIR 与 detect_components(定义在其后),
      # 故在 P0 基建段落落地(见 upgrade_restore_context),随后落入 12 步主流程
      UPGRADE_MODE=1
      ;;
    -h|--help)
      echo "用法: ./setup-opencode.sh [选项]"
      echo "  (无参数)   默认: 全新安装或幂等重跑(选装: 交互菜单 / INSTALL_* 环境变量)"
      echo "  --upgrade  动态升级已装机器到最新(自动自更新脚本+读状态清单还原选装上下文,不剥已装接线)"
      echo "  --version  打印脚本版本"
      exit 0
      ;;
  esac
done

APT_UPDATED=0   # 确保 apt install 前 lists 就绪(全新容器/镜像跳过测速时仍可装包)
apt_ensure_update() {
  [ "$APT_UPDATED" = 1 ] && return 0
  command -v apt-get >/dev/null 2>&1 || return 0
  timeout -s KILL 180 $SUDO apt-get update -qq >/dev/null 2>&1 || true
  APT_UPDATED=1
}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ------------------------------------------------------------------
# 状态清单(动态升级 P0 基建,计划: .omo/plans/dynamic-upgrade.md): 在场探测
# 组件 + 原子写 $CONFIG_DIR/.setup-state.json,P1 --upgrade 读它还原安装上下文。
# 在场守则(AGENTS.md): 每项写前实测(command -v/文件在场/配置实读),禁止静态
# 猜测;P0 写入与 P1 读取共用同一套探测(单一事实源,清单漂移时不信旧清单)。
# ------------------------------------------------------------------

# 脚本版本: git 克隆场景以 git describe --tags --always 覆盖常量,curl 安装用户无 .git 用常量
resolve_setup_version() {
  local gd=""
  if [ -d "$SCRIPT_DIR/.git" ] && command -v git >/dev/null 2>&1; then
    gd="$(git -C "$SCRIPT_DIR" describe --tags --always 2>/dev/null || true)"
  fi
  printf '%s' "${gd:-$SETUP_VERSION}"
}

# 组件在场探测 → 单行 json 片段("name": true/false, ...),供 write_state_file 组装
detect_components() {
  local out="" k present
  for k in opencode bun node rtk codegraph webmap opstate mem0 skillopt-sleep mineru; do
    if command -v "$k" >/dev/null 2>&1; then present=true; else present=false; fi
    out="${out:+$out, }\"$k\": $present"
  done
  # dcp: 以 opencode.json 实注册为准(与安装段装后验证/收尾汇总同一判据)
  if grep -q 'opencode-dcp' "$CONFIG_DIR/opencode.json" 2>/dev/null; then present=true; else present=false; fi
  out="$out, \"dcp\": $present"
  # gsd: 官方安装器落 command/gsd-*(与步骤 9 同一判据;disabled_mcps 无关)
  if ls "$CONFIG_DIR/command/gsd-"* >/dev/null 2>&1; then present=true; else present=false; fi
  out="$out, \"gsd\": $present"
  # superpowers_router: 路由插件三件套之锚(sp-router.ts)
  if [ -f "$CONFIG_DIR/plugins/sp-router.ts" ]; then present=true; else present=false; fi
  out="$out, \"superpowers_router\": $present"
  # cmolecules_cron: 夜间自进化定时任务在 crontab 实测在册
  if crontab -l 2>/dev/null | grep -Fq 'skillopt-sleep'; then present=true; else present=false; fi
  out="$out, \"cmolecules_cron\": $present"
  printf '%s' "$out"
}

# 组装状态清单并原子写(tmp+rename);python3 缺失降级: 跳过+黄警(下次运行重生成)
write_state_file() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ 无 python3,跳过状态清单写入(状态文件是升级基建,缺了下次重生成)${NC}"
    return 0
  fi
  if python3 - "$CONFIG_DIR" "$(resolve_setup_version)" "$(detect_components)" << 'PYEOF'
import datetime, json, os, sys

config_dir, ver, comps = sys.argv[1], sys.argv[2], sys.argv[3]
state = {}
state["script_version"] = ver
state["installed_at"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
state["components"] = json.loads("{" + comps + "}")

# flags 均从 opencode.json 实读;permission_mode 按权限红线模板特征推断
# (gen-permissions.sh 三档: 标准 59 条/无头 8 条均含 rm -rf*+curl*|*sh deny;
#   沙箱删本机破坏类 deny、留网络不可逆 deny)
state["flags"] = {}
try:
    cfg = json.load(open(os.path.join(config_dir, "opencode.json")))
    if not isinstance(cfg, dict):
        cfg = None
except Exception:
    cfg = None
if cfg is None:
    state["flags"]["model"] = ""
    state["flags"]["permission_mode"] = "unknown"
else:
    state["flags"]["model"] = cfg.get("model", "")
    bash = cfg.get("permission", {}).get("bash", {})
    if not isinstance(bash, dict) or not bash:
        mode = "unknown"
    elif bash.get("curl*|*sh") == "deny" and bash.get("rm -rf *") != "deny":
        mode = "sandbox"
    elif len(bash) == 59:
        mode = "standard"
    elif len(bash) == 8:
        mode = "headless"
    else:
        mode = "custom"
    state["flags"]["permission_mode"] = mode

path = os.path.join(config_dir, ".setup-state.json")
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, path)
PYEOF
  then
    echo -e "${GREEN}✓ 状态清单 → $CONFIG_DIR/.setup-state.json(vP1 升级账本)${NC}"
    return 0
  else
    echo -e "${YELLOW}⚠ 状态清单写入失败(JSON 损坏/目录不可写?),下次运行重生成${NC}"
    return 0
  fi
}

# P1 --upgrade 入口(计划 .omo/plans/dynamic-upgrade.md): 状态清单→UC_*→
# INSTALL_*/CONFIRM_AGPL 环境变量还原,随后正常走 12 步(幂等段自会跳过已装)。
# 依赖 CONFIG_DIR 与 detect_components,故在参数解析(--upgrade 置旗处)之后的
# 主流程里调用;核心是修"裸重跑误剥"——不带开关重跑会走"未选"路径(如剥 mcp.gsd)。
upgrade_restore_context() {
  UPGRADE_MODE=1
  STATE_FILE="$CONFIG_DIR/.setup-state.json"
  if [ -f "$STATE_FILE" ] && command -v python3 >/dev/null 2>&1; then
    cp "$STATE_FILE" "$STATE_FILE.prev" 2>/dev/null || true
    # eval stderr 抑制: 组件名带连字符的键(skillopt-sleep)不是合法 shell 赋值名,
    # 会以 command not found 噪声出场;其余键照常赋值(还原只依赖合法键)
    eval "$(python3 -c "
import json
c=json.load(open('$STATE_FILE')).get('components',{})
f=json.load(open('$STATE_FILE')).get('flags',{})
for k,v in c.items(): print(f'UC_{k}={str(v).lower()}')
print('UC_MODEL='+repr(f.get('model','')))" 2>/dev/null)" 2>/dev/null || true
    echo "✓ 状态清单已读: $(python3 -c "import json;print(json.load(open('$STATE_FILE')).get('script_version','?'))") → $SETUP_VERSION"
  else
    echo "无状态清单(v1.0 前安装?),考古模式现场重建"
    # 考古: 调 P0 探测逻辑重新组装(规格原 sed 单行解析在实测中不可用——
    # detect_components 输出为单行,逐段切分才是可靠重组方式)
    _arch="$(detect_components)"
    IFS=',' read -ra _arch_pairs <<< "$_arch"
    for _p in "${_arch_pairs[@]}"; do
      _k="${_p%%:*}"; _v="${_p##*:}"
      _k="${_k//\"/}"; _k="${_k// /}"; _v="${_v// /}"
      case "$_k" in [a-zA-Z_][a-zA-Z0-9_]*) eval "UC_${_k}=$_v" 2>/dev/null || true ;; esac
    done
  fi
  # 状态→环境变量还原(核心: 修裸重跑误剥)
  [ "${UC_dcp:-false}" = "true" ] && export INSTALL_DCP=1 CONFIRM_AGPL=1
  [ "${UC_mineru:-false}" = "true" ] && export INSTALL_MINERU=1
  [ "${UC_gsd:-false}" = "true" ] && export INSTALL_GSD=1
  [ "${UC_superpowers_router:-false}" = "true" ] && export SUPERPOWERS_ROUTER=1
  [ "${UC_mem0:-false}" = "true" ] || [ "${UC_skillopt:-false}" = "true" ] || [ "${UC_skillopt_sleep:-false}" = "true" ] && export INSTALL_CMODULES=1
  export UPGRADE_MODE
}

# 计时: step_begin 记起点, step_end 输出耗时, EXIT 时打印汇总表便于排查瓶颈
_step_t0=0
STEP_TIMES=()
STEP_NAMES=()
step_begin() { _step_t0=$(date +%s); }
step_end() {
  local n="$1" name="$2" d
  d=$(( $(date +%s) - _step_t0 ))
  STEP_TIMES[$n]="$d"
  STEP_NAMES[$n]="$name"
  echo -e "${BLUE}  - 步骤${n} 耗时 ${d}s${NC}"
}
step_summary() {
  local i total=0
  echo ""
  echo -e "${YELLOW}=== 各环节耗时 ===${NC}"
  for i in $(seq 1 12); do
    [ -z "${STEP_TIMES[$i]:-}" ] && continue
    printf "  [%s/12] %s: %ss\n" "$i" "${STEP_NAMES[$i]}" "${STEP_TIMES[$i]}"
    total=$(( total + STEP_TIMES[$i] ))
  done
  echo -e "${YELLOW}总耗时: ${total}s${NC}"
}
trap step_summary EXIT

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  OpenCode 一键配置脚本 (Bun 版)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ------------------------------------------------------------------
# 目录配置（支持环境变量覆盖）
# ------------------------------------------------------------------
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"

# root 环境无需 sudo；非 root 且有 sudo 时自动补前缀
SUDO=""
if [ "$(id -u)" != "0" ] && command -v sudo &> /dev/null; then
  SUDO="sudo"
fi

echo -e "${BLUE}目标目录:${NC}"
echo "  OpenCode: $CONFIG_DIR"
echo "  Claude:   $CLAUDE_DIR"
echo ""

# P1 --upgrade: 参数解析处只置旗,这里(CONFIG_DIR 与探测函数就绪后)还原选装上下文
if [ "${UPGRADE_MODE:-0}" = "1" ]; then
  # P2 自更新: 先把脚本自身更到最新,再以新版跑升级
  # 防循环: 新版重跑此段时无更新即 NEW_C=0 / curl 下载与自身 diff 相同 → 不 exec,天然终止
  SCRIPT_GIT_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$SCRIPT_GIT_DIR" ]; then
    git -C "$SCRIPT_DIR" fetch origin main >/dev/null 2>&1 || true
    NEW_C="$(git -C "$SCRIPT_DIR" rev-list HEAD..origin/main --count 2>/dev/null || echo 0)"
    if [ "$NEW_C" -gt 0 ]; then
      if git -C "$SCRIPT_DIR" pull --ff-only origin main >/dev/null 2>&1; then
        echo "✓ 脚本自更新: 拉取 $NEW_C 个新提交,重启新版执行升级"
        exec bash "$SCRIPT_DIR/setup-opencode.sh" --upgrade
      else
        echo "⚠ 本地有改动无法 ff-pull,以当前版本继续升级(自更新跳过)"
      fi
    fi
  else
    # curl 安装用户: 下载 main 最新脚本,校验后替换自身重启
    # 双校验防坏文件: bash -n 语法 + 大小>50KB;diff 相同=已是最新 → 不替换不重启
    NEW_SH="$(mktemp)"
    if curl -fsSL --max-time 30 "https://raw.githubusercontent.com/Liber1917/opencode-setup/main/setup-opencode.sh" -o "$NEW_SH" 2>/dev/null \
       || curl -fsSL --max-time 30 "https://gh-proxy.com/https://raw.githubusercontent.com/Liber1917/opencode-setup/main/setup-opencode.sh" -o "$NEW_SH" 2>/dev/null; then
      # 管道安装(curl|bash)陷阱: $0="bash"/无实体脚本,自更新替换(cp 到 $0)不可行;
      # 且管道拉到的本就是 main 最新——跳过自更新,直接以当前内容执行升级
      _pipe_mode=0
      case "$0" in bash|sh|''|/dev/*|*pipe*|*fd/*) _pipe_mode=1 ;; esac
      if [ "$_pipe_mode" = "1" ]; then
        echo "  - 管道模式: 本次已是 main 最新内容,跳过自更新直接升级"
      else
        # 版本前进校验(oct 实测教训: CDN 缓存"合法旧版"放行):
        # 下载侧 SETUP_VERSION 必须 != 本地才替换;同版本=缓存毒,拒替换
        DL_VER="$(grep -m1 '^SETUP_VERSION=' "$NEW_SH" 2>/dev/null | cut -d'"' -f2)"
        if bash -n "$NEW_SH" && [ "$(wc -c < "$NEW_SH")" -gt 50000 ] \
           && ! diff -q "$NEW_SH" "$0" >/dev/null 2>&1 \
           && [ -n "$DL_VER" ] && [ "$DL_VER" != "$SETUP_VERSION" ]; then
          cp "$NEW_SH" "$0" && chmod +x "$0" && rm -f "$NEW_SH"
          echo "✓ 脚本自更新完成(curl): $SETUP_VERSION → $DL_VER,重启新版执行升级"
          exec bash "$0" --upgrade
        elif [ "${DL_VER:-}" = "$SETUP_VERSION" ]; then
          echo "  - 远端与本地同版($SETUP_VERSION,CDN 可能缓存),以当前版本继续升级"
        fi
      fi
      rm -f "$NEW_SH" 2>/dev/null || true
    fi
  fi
  upgrade_restore_context
fi

# 确保 curl（下载依赖）；缺失时尝试 apt 安装，失败仅提示
if ! command -v curl &> /dev/null; then
  echo -e "${YELLOW}⚠ curl 未安装，尝试安装...${NC}"
  if command -v apt-get &> /dev/null && timeout -s KILL 120 apt-get update >/dev/null 2>&1 && timeout -s KILL 120 apt-get install -y curl >/dev/null 2>&1; then
    echo -e "${GREEN}✓ curl 已安装${NC}"
  else
    echo -e "${YELLOW}⚠ curl 安装失败，后续下载步骤可能不可用${NC}"
  fi
fi

# ------------------------------------------------------------------
# 步骤 1: 检测已有配置
# ------------------------------------------------------------------
echo -e "${YELLOW}[1/12] 检测已有配置...${NC}"
step_begin

if [ -f "$CONFIG_DIR/opencode.json" ] || [ -f "$CONFIG_DIR/oh-my-openagent.json" ]; then
  echo -e "${YELLOW}⚠ 发现现有配置文件${NC}"
  # P1 升级模式: 不问覆盖,直接走保留分支(升级只加不破,已装配置以在场为准)
  [ "${UPGRADE_MODE:-0}" = "1" ] && overwrite=n
  if [ -t 0 ] && [ "${UPGRADE_MODE:-0}" != "1" ]; then
    echo -n "是否备份后重新生成? (y/n) [n]: "
    read -r overwrite
    overwrite=${overwrite:-n}
  else
    overwrite=n  # U-10: 管道安装(非交互)默认不覆盖,防 read 吞脚本后续行
    echo -e "${YELLOW}  非交互/升级模式: 保留现有配置${NC}"
  fi
  if [[ $overwrite =~ ^[Yy]$ ]]; then
    backup_dir="$HOME/opencode-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    [ -f "$CONFIG_DIR/opencode.json" ]         && cp "$CONFIG_DIR/opencode.json"         "$backup_dir/"
    [ -f "$CONFIG_DIR/oh-my-openagent.json" ]   && cp "$CONFIG_DIR/oh-my-openagent.json" "$backup_dir/"
    [ -f "$CONFIG_DIR/package.json" ]           && cp "$CONFIG_DIR/package.json"         "$backup_dir/"
    echo -e "${GREEN}✓ 已备份到: $backup_dir${NC}"
  else
    echo "跳过配置生成，使用现有配置。"
    SKIP_CONFIG=1
  fi
fi

# ------------------------------------------------------------------
# 步骤 2: 创建目录结构
# ------------------------------------------------------------------
step_end 1 "检测已有配置"

# ------------------------------------------------------------------
# 交互式选装菜单: 步骤 1 后、任何安装动作前;选中即设 INSTALL_*/SUPERPOWERS_ROUTER,
# 与环境变量路径共用同一组开关(菜单只是交互前端,不引入第二套状态)。
# 门(任一命中即跳过,直接走环境变量语义):
#   ⓪ 升级模式(UPGRADE_MODE=1)——状态清单即答案,不重问(P1)
#   ① SETUP_INTERACTIVE=0 强制关菜单(最高优先级)
#   ② 任一选装变量(INSTALL_GSD/INSTALL_DCP/INSTALL_MINERU/SUPERPOWERS_ROUTER/
#      INSTALL_CMODULES/CONFIRM_AGPL)已在环境中显式设置——用户已给路径,不打扰
#   ③ 非交互终端([ -t 0 ] 为假: curl|bash 管道/CI)——行为与历史版本完全一致;
#      SETUP_FORCE_MENU=1 为无 TTY 调试入口(供回归测试从 stdin 喂输入)
# ------------------------------------------------------------------
interactive_component_menu() {
  # 升级模式不跳过菜单: 已装组件标注[✓],用户可增量勾选新组件(2026-09-12 用户裁定:
  # "升级不应该静默,应该也有选装内容的交互")。非交互管道升级仍走状态清单还原(零打扰)。
  [ "${SETUP_INTERACTIVE:-1}" = "0" ] && return 0
  [ -n "${INSTALL_GSD:-}${INSTALL_DCP:-}${INSTALL_MINERU:-}${SUPERPOWERS_ROUTER:-}${INSTALL_CMODULES:-}${CONFIRM_AGPL:-}" ] && return 0
  if [ "${SETUP_FORCE_MENU:-0}" != "1" ] && [ ! -t 0 ]; then
    # 管道升级: 无 TTY 不能交互,但必须通知用户新增了哪些可选组件(不静默)
    if [ "${UPGRADE_MODE:-0}" = "1" ]; then
      _new_env=""
      [ "${UC_gsd:-false}" != "true" ] && _new_env="${_new_env} INSTALL_GSD=1"
      [ "${UC_dcp:-false}" != "true" ] && _new_env="${_new_env} INSTALL_DCP=1 CONFIRM_AGPL=1"
      [ "${UC_mineru:-false}" != "true" ] && _new_env="${_new_env} INSTALL_MINERU=1"
      [ "${UC_superpowers_router:-false}" != "true" ] && _new_env="${_new_env} SUPERPOWERS_ROUTER=1"
      [ "${UC_mem0:-false}" != "true" ] && [ "${UC_skillopt_sleep:-false}" != "true" ] && _new_env="${_new_env} INSTALL_CMODULES=1"
      if [ -n "$_new_env" ]; then
        echo -e "${BLUE}  ✦ 管道升级无法交互选装,以下组件未装。一键补装(复制执行):${NC}" >&2
        echo -e "${BLUE}    curl -fsSL \"https://gh-proxy.com/https://raw.githubusercontent.com/Liber1917/opencode-setup/main/setup-opencode.sh\" | env $_new_env bash${NC}" >&2
      fi
    fi
    return 0
  fi

  echo ""
  echo -e "${YELLOW}═══════════════════════════════════${NC}"
  echo -e "${YELLOW} 可选组件(全免费,默认都不装)${NC}"
  echo -e "${YELLOW}═══════════════════════════════════${NC}"
  # 升级模式: 已装组件预选标注[✓],输入编号可增减;全新安装: 全[ ]可选
  _mk(){ if [ "${UPGRADE_MODE:-0}" = "1" ] && [ "${UC_$1:-false}" = "true" ]; then echo "[✓]"; else echo "[ ]"; fi; }
  echo " 1. GSD 工作流        $(_mk gsd) 多阶段项目管理(/gsd-* 命令,用户显式驱动)"
  echo " 2. DCP 上下文压缩     $(_mk dcp) 长会话自动压缩(AGPL-3.0,装前需确认)"
  echo " 3. MinerU 文档解析    $(_mk mineru) PDF→Markdown 本地版(免费无限量,磁盘 20GB+)"
  echo " 4. superpowers 路由   $(_mk superpowers_router) 技能清单渐进披露(默认官方急加载)"
  echo " 5. 记忆/自进化     $(_mk mem0) mem0 偏好记忆+SkillOpt 夜间提炼(草稿区审批制)"
  if [ "${UPGRADE_MODE:-0}" = "1" ]; then
    echo " (升级: [✓]=已装保留; 输入编号=新增安装; 直接回车=保持现状)"
  fi
  echo -e "${YELLOW}───────────────────────────────────${NC}"
  echo -n ' 输入要启用的编号(空格分隔,如 "1 3";直接回车=全不装): '

  local attempt answer sel ok picks=""
  for attempt in 1 2 3; do
    answer=""
    read -r answer || answer=""   # stdin 耗尽(EOF)按全不装,不挂死
    if [ -z "${answer//[[:space:]]/}" ]; then
      picks=""
      break
    fi
    ok=1
    picks=""
    for sel in $answer; do
      case "$sel" in
        1|2|3|4|5) picks="$picks$sel " ;;
        *) ok=0 ;;
      esac
    done
    [ "$ok" = "1" ] && break
    picks=""                      # 非法轮次丢弃残留选择("1 x" 不留 1)
    if [ "$attempt" -lt 3 ]; then
      echo -e "${YELLOW}  ⚠ 无效输入 \"${answer}\"(合法: 1-5,空格分隔),请重输(${attempt}/3)${NC}"
      echo -n ' 输入要启用的编号(空格分隔,如 "1 3";直接回车=全不装): '
    else
      echo -e "${YELLOW}  ⚠ 连续 3 次无效输入,按全不装继续${NC}"
    fi
  done

  # 校验通过才落变量,保证非法轮次零残留
  local names=""
  for sel in $picks; do
    case "$sel" in
      1) INSTALL_GSD=1;        names="${names:+$names, }GSD" ;;
      2) INSTALL_DCP=1;        names="${names:+$names, }DCP" ;;
      3) INSTALL_MINERU=1;     names="${names:+$names, }MinerU" ;;
      4) SUPERPOWERS_ROUTER=1; names="${names:+$names, }superpowers路由" ;;
      5) INSTALL_CMODULES=1;   names="${names:+$names, }记忆/自进化" ;;
    esac
  done
  echo ""
  if [ -n "$names" ]; then
    echo -e "${GREEN}→ 将安装: ${names}${NC}"
    [ "${INSTALL_DCP:-0}" = "1" ] && echo -e "${BLUE}  - DCP 的 AGPL 确认将在安装时进行(本菜单不绕过 CONFIRM_AGPL 确认门)${NC}"
  else
    echo -e "${BLUE}  - 未选择任何选装组件(全不装,与默认行为一致)${NC}"
  fi
  echo ""
  return 0
}
# 区分 INSTALL_CMODULES 来源: 环境显式给定(按非交互铁律,装完不问定时,只打印
# 开启命令) vs 菜单选中(装完且 [ -t 0 ] 时交互问)——须在菜单调用前捕获
INSTALL_CMODULES_PRESET="${INSTALL_CMODULES:-0}"
interactive_component_menu

step_begin
echo -e "${YELLOW}[2/12] 创建配置目录...${NC}"
mkdir -p "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR/skills"
mkdir -p "$CLAUDE_DIR"
echo -e "${GREEN}✓ 目录已创建${NC}"

# ------------------------------------------------------------------
# 步骤 3: 生成配置文件
# ------------------------------------------------------------------
step_end 2 "创建配置目录"
if [ "${SKIP_CONFIG:-0}" != "1" ]; then
  step_begin
  echo -e "${YELLOW}[3/12] 生成配置文件...${NC}"

  # opencode.json
  # superpowers 接入方式: 官方急加载(默认) 或 路由模式(渐进披露,-90% token)
  # 注意: 本地插件(sp-router/opencode-env)不进 plugin 数组——数组只认 npm 包,
  # 本地文件靠 ~/.config/opencode/plugins/*.ts 自动发现(rtk.ts 同款姿势)
  if [ "${SUPERPOWERS_ROUTER:-0}" = "1" ]; then
    SP_PLUGIN_LINE=''
  else
    SP_PLUGIN_LINE=', "superpowers@git+https://github.com/jnMetaCode/superpowers-zh.git"'
  fi
  cat > "$CONFIG_DIR/opencode.json" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "zhipuai-coding-plan/glm-5.3",
  "plugin": ["oh-my-openagent@latest"$SP_PLUGIN_LINE],
  "permission": {
    "read": {
      "~/.config/opencode/*": "allow",
      "~/.claude/*": "allow"
    },
    "external_directory": {
      "~/.config/opencode/*": "allow",
      "~/.claude/*": "allow"
    }
  }
}
EOF
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json; c=json.load(open('$CONFIG_DIR/opencode.json')); assert c.get('model') and c.get('plugin'), 'model/plugin 丢失'" \
      && echo -e "${GREEN}  ✓ opencode.json(含 model+plugin,JSON 已校验)${NC}" \
      || { echo -e "${RED}  ✗ opencode.json 生成损坏(JSON 非法或 model/plugin 丢失),中止——静默损坏曾致 403${NC}"; exit 1; }
  else
    echo -e "${YELLOW}  ⚠ 无 python3,跳过 JSON 校验(建议安装后重跑)${NC}"
  fi

  # oh-my-openagent.json
  # 显式 model 必须存在:fallbackChain patch 盖不住 category 解析路径,空配置会
  # 落到源码内置链(anthropic)→ 子代理 403 静默死(2026-08-30 实测坐实)。
  # 换模型: OMO_MODEL=<provider/model> 重跑,或直接编辑本文件。
  # disabled_mcps: 禁 omo 内置白名单里的 grep_app(E-security spec 已记录移除,
  # 职能被本地 AST+web 搜索替代)。opencode.json 侧从未注册过它,单侧禁用即净。
  OMO_MODEL="${OMO_MODEL:-zhipuai-coding-plan/glm-5.3}"
  cat > "$CONFIG_DIR/oh-my-openagent.json" << EOF
{
  "\$schema": "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json",
  "disabled_mcps": ["grep_app"],
  "agents": {
    "hephaestus": {"model": "$OMO_MODEL"},
    "oracle": {"model": "$OMO_MODEL"},
    "librarian": {"model": "$OMO_MODEL"},
    "explore": {"model": "$OMO_MODEL"},
    "multimodal-looker": {"model": "$OMO_MODEL"},
    "prometheus": {"model": "$OMO_MODEL"},
    "metis": {"model": "$OMO_MODEL"},
    "momus": {"model": "$OMO_MODEL"},
    "atlas": {"model": "$OMO_MODEL"},
    "sisyphus-junior": {"model": "$OMO_MODEL"}
  },
  "categories": {
    "visual-engineering": {"model": "$OMO_MODEL"},
    "ultrabrain": {"model": "$OMO_MODEL"},
    "deep": {"model": "$OMO_MODEL"},
    "artistry": {"model": "$OMO_MODEL"},
    "quick": {"model": "$OMO_MODEL"},
    "unspecified-low": {"model": "$OMO_MODEL"},
    "unspecified-high": {"model": "$OMO_MODEL"},
    "writing": {"model": "$OMO_MODEL"}
  }
}
EOF
  echo -e "${GREEN}  ✓ oh-my-openagent.json（agents+categories 显式 model=$OMO_MODEL，堵死回退链路由）${NC}"

  # Claude settings
  if [ ! -f "$CLAUDE_DIR/settings.json" ]; then
    cat > "$CLAUDE_DIR/settings.json" << 'EOF'
{
  "hooks": {
    "SessionStart": [],
    "PostToolUse": [],
    "PreToolUse": []
  }
}
EOF
    echo -e "${GREEN}  ✓ settings.json (Claude)${NC}"
  else
    echo -e "${BLUE}  - settings.json 已存在，跳过${NC}"
  fi
  step_end 3 "生成配置文件"
else
  # 保留现有配置路径(非交互默认/交互选 n): 存量 oh-my-openagent.json 可能
  # 无 disabled_mcps(E-security spec 记录的 grep_app 移除只落在开发者本机,
  # setup 从未写盘)——python3 幂等合并: 现有列表 ∪ ["grep_app"],原子写
  # tmp+rename,用户自设条目不覆盖;无 python3 则跳过并黄警。
  if [ -f "$CONFIG_DIR/oh-my-openagent.json" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$CONFIG_DIR/oh-my-openagent.json" << 'PYEOF' \
      && echo -e "${GREEN}  ✓ disabled_mcps 已含 grep_app(幂等合并,用户自设条目保留)${NC}" \
      || echo -e "${YELLOW}  ⚠ disabled_mcps 合并失败(JSON 损坏?),文件保持原样${NC}"
import json, os, sys
p = sys.argv[1]
with open(p) as f:
    c = json.load(f)
c["disabled_mcps"] = sorted(set(c.get("disabled_mcps", [])) | {"grep_app"})
tmp = p + ".tmp"
with open(tmp, "w") as f:
    json.dump(c, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, p)
PYEOF
  elif [ -f "$CONFIG_DIR/oh-my-openagent.json" ]; then
    echo -e "${YELLOW}  ⚠ 无 python3,跳过 disabled_mcps 幂等合并(建议安装后重跑)${NC}"
  fi
fi

# ------------------------------------------------------------------
# 步骤 4: apt 源测速优化（仅 apt 系系统；官方最快则不动，已自定义则跳过）
# ------------------------------------------------------------------
step_begin
echo -e "${YELLOW}[4/12] apt 源测速优化...${NC}"

if ! command -v apt-get &> /dev/null || [ "$SKIP_APT_MIRROR" = "1" ]; then
  echo -e "${BLUE}  - 非 apt 系统或已跳过（SKIP_APT_MIRROR=1），跳过源优化${NC}"
elif ! command -v curl &> /dev/null; then
  echo -e "${YELLOW}⚠ curl 未安装，跳过 apt 源测速（不影响其他步骤）${NC}"
else
  # 支持两种源文件格式：传统 sources.list / 24.04+ deb822 ubuntu.sources
  APT_SOURCES=""
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do
    [ -f "$f" ] && APT_SOURCES="$f" && break
  done

  if [ -z "$APT_SOURCES" ]; then
    echo -e "${YELLOW}⚠ 未找到 apt 源文件，跳过源优化${NC}"
  else
    # 官方域名未被替换过才执行；FORCE_APT_MIRROR=1 强制重测
    if [ "$FORCE_APT_MIRROR" = "1" ] || grep -Eq 'archive\.ubuntu\.com|security\.ubuntu\.com' "$APT_SOURCES"; then
      APT_CODENAME="$(grep -E '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2)"
      [ -z "$APT_CODENAME" ] && APT_CODENAME="jammy"

      echo -e "${BLUE}  测速中 (发行版 $APT_CODENAME)...${NC}"
      BEST_MIRROR=""
      BEST_SPEED=0
      for M in mirrors.ustc.edu.cn mirrors.aliyun.com mirrors.tuna.tsinghua.edu.cn mirrors.huaweicloud.com mirrors.cloud.tencent.com mirrors.163.com archive.ubuntu.com; do
        # 单次下载测速（速度取两次采样最大值，避免抖动）
        SPEED=0
        for _ in 1 2; do
          S="$(curl -fsSL --connect-timeout 5 --max-time 10 -o /dev/null -w '%{speed_download}' "http://$M/ubuntu/dists/$APT_CODENAME/Release" 2>/dev/null || true)"
          S="${S%.*}"
          [ "${S:-0}" -gt "$SPEED" ] 2>/dev/null && SPEED="$S"
        done
        if [ "${SPEED:-0}" -gt 0 ] 2>/dev/null; then
          echo -e "  ${M}: $((SPEED / 1024)) KB/s"
          if [ "$SPEED" -gt "$BEST_SPEED" ] 2>/dev/null; then
            BEST_SPEED="$SPEED"
            BEST_MIRROR="$M"
          fi
        else
          echo -e "  ${M}: 不可达"
        fi
      done

      if [ -n "$BEST_MIRROR" ]; then
        if [ "$BEST_MIRROR" = "archive.ubuntu.com" ]; then
          echo -e "${GREEN}✓ 官方源最快 ($((BEST_SPEED / 1024)) KB/s)，保持不动${NC}"
        else
          cp "$APT_SOURCES" "${APT_SOURCES}.bak"
          # 仅替换主机名，保留协议与路径（同时覆盖传统与 deb822 格式）
          $SUDO sed -i "s|//archive\.ubuntu\.com|//$BEST_MIRROR|g; s|//security\.ubuntu\.com|//$BEST_MIRROR|g" "$APT_SOURCES"
          echo -e "${GREEN}✓ 已切换至 $BEST_MIRROR ($((BEST_SPEED / 1024)) KB/s)${NC}"
          echo -e "${BLUE}  原文件已备份: ${APT_SOURCES}.bak${NC}"
          # 真实机器常带第三方源(PPA/docker 等),apt 无超时会无限挂起(2026-09-08 jammy 实测)
          if timeout -s KILL 180 $SUDO apt-get update >/dev/null 2>&1; then
            echo -e "${GREEN}✓ apt update 验证通过${NC}"
          else
            echo -e "${YELLOW}⚠ apt update 验证失败/超时，已自动还原原源${NC}"
            $SUDO cp "${APT_SOURCES}.bak" "$APT_SOURCES" 2>/dev/null || true
            echo -e "${YELLOW}  (原源仍可用;如需重试: 跳过本步 SKIP_APT_MIRROR=1,稍后手动 apt-get update 排查第三方源)${NC}"
          fi
        fi
      else
        echo -e "${YELLOW}⚠ 所有源均不可达（网络受限？），保持原配置${NC}"
      fi
    else
      echo -e "${BLUE}  - apt 源已自定义，跳过（FORCE_APT_MIRROR=1 可强制重测）${NC}"
    fi
  fi
fi

# ------------------------------------------------------------------
# 步骤 5: 检查前置依赖
# ------------------------------------------------------------------
step_end 4 "apt 源测速优化"
step_begin
echo -e "${YELLOW}[5/12] 检查前置依赖...${NC}"

# Bun 安装脚本需要 unzip
if ! command -v unzip &> /dev/null; then
  echo -e "${YELLOW}⚠ 缺少 unzip，正在安装...${NC}"
  if command -v apt-get &> /dev/null; then
    apt_ensure_update
    # 判定以 unzip 实际在场为准,不以 apt 退出码为准(oct 实测: 包装进程被信号杀,
    # 但 apt 已完成安装,按退出码判死会误杀整个 setup);失败重试一次再复核
    timeout -s KILL 300 $SUDO apt-get install -y unzip || \
      timeout -s KILL 300 $SUDO apt-get install -y unzip || true
  elif command -v yum &> /dev/null; then
    $SUDO yum install -y unzip
  elif command -v brew &> /dev/null; then
    brew install unzip
  elif command -v apk &> /dev/null; then
    apk add unzip
  else
    echo -e "${RED}✗ 无法自动安装 unzip${NC}"
    echo "  请手动安装后重新运行"
    exit 1
  fi
  echo -e "${GREEN}✓ unzip 安装成功${NC}"
else
  echo -e "${GREEN}✓ unzip 已就绪${NC}"
fi

# OpenCode 引导脚本需要 node（找到原生二进制后会切换到原生运行）
if ! command -v node &> /dev/null; then
  echo -e "${YELLOW}⚠ 缺少 node，正在安装...${NC}"

  # 优先 npmmirror node 二进制（国内快），失败回退发行版包管理器
  NODE_INSTALLED=0
  if command -v curl &> /dev/null && command -v tar &> /dev/null; then
    NODE_ARCH="x64"
    case "$(uname -m)" in
      x86_64) NODE_ARCH="x64" ;;
      aarch64) NODE_ARCH="arm64" ;;
      *) NODE_ARCH="" ;;
    esac
    if [ -n "$NODE_ARCH" ]; then
      NODE_TMP="$(mktemp -d)"
      NODE_FILE=""
      NODE_V=""
      # 优先 LTS 系列（v24 → v22），取目录 JSON 中最新 linux 包名
      for V in latest-v24.x latest-v22.x; do
        NODE_FILE="$(curl -fsSL --connect-timeout 8 --max-time 20 "https://registry.npmmirror.com/-/binary/node/$V/" 2>/dev/null | grep -o "\"name\":\"node-v[0-9.]*-linux-$NODE_ARCH.tar.xz\"" | head -1 | cut -d'"' -f4 || true)"
        if [ -n "$NODE_FILE" ]; then
          NODE_V="$V"
          break
        fi
      done
      if [ -n "$NODE_FILE" ] && curl -fsSL --connect-timeout 8 --max-time 180 -o "$NODE_TMP/node.tar.xz" "https://registry.npmmirror.com/-/binary/node/$NODE_V/$NODE_FILE" 2>/dev/null; then
        :
      fi
      NODE_DIR="$(tar -tJf "$NODE_TMP/node.tar.xz" 2>/dev/null | head -1 | cut -d/ -f1)"
      if [ -n "$NODE_DIR" ] && tar -xJf "$NODE_TMP/node.tar.xz" -C "$NODE_TMP" 2>/dev/null; then
        mkdir -p /usr/local/lib/nodejs
        cp -r "$NODE_TMP/$NODE_DIR" /usr/local/lib/nodejs/
        ln -sf "/usr/local/lib/nodejs/$NODE_DIR/bin/node" /usr/local/bin/node
        ln -sf "/usr/local/lib/nodejs/$NODE_DIR/bin/npm" /usr/local/bin/npm
        ln -sf "/usr/local/lib/nodejs/$NODE_DIR/bin/npx" /usr/local/bin/npx
        NODE_INSTALLED=1
        echo -e "${GREEN}✓ node 安装成功（npmmirror 二进制，$(node --version)）${NC}"
      fi
      rm -rf "$NODE_TMP"
    fi
  fi

  if [ "$NODE_INSTALLED" != "1" ]; then
    echo -e "${YELLOW}npmmirror 下载失败，回退系统包管理器...${NC}"
    if command -v apt-get &> /dev/null; then
      curl -fsSL https://deb.nodesource.com/setup_lts.x | ${SUDO:+$SUDO -E }bash - 2>/dev/null
      apt_ensure_update
      # F1 修复(收官回归 r2/r2c/r3 实测): 裸 timeout 在 set -e 下超时即静默 137 退出,
      # 走不到下方失败引导。比照 pip 回退: 重试一次+||true+由在场判定成败
      timeout -s KILL 300 $SUDO apt-get install -y nodejs || \
        timeout -s KILL 300 $SUDO apt-get install -y nodejs || true
    elif command -v yum &> /dev/null; then
      curl -fsSL https://rpm.nodesource.com/setup_lts.x | ${SUDO:+$SUDO -E }bash - 2>/dev/null
      $SUDO yum install -y nodejs
    elif command -v brew &> /dev/null; then
      brew install node
    else
      echo -e "${RED}✗ 无法自动安装 node${NC}"
      echo "  请手动安装后重新运行"
      exit 1
    fi
  fi

  if command -v node &> /dev/null; then
    echo -e "${GREEN}✓ node 安装成功 ($(node --version))${NC}"
  else
    echo -e "${RED}✗ node 安装失败，请手动安装${NC}"
    exit 1
  fi
else
  echo -e "${GREEN}✓ node 已就绪 ($(node --version))${NC}"
fi

echo -e "${YELLOW}配置 npm 镜像源 ($NPM_REGISTRY)...${NC}"
if ! grep -q "^registry=" "$HOME/.npmrc" 2>/dev/null; then
  echo "registry=$NPM_REGISTRY" >> "$HOME/.npmrc"
  echo -e "${GREEN}✓ npm 镜像源已配置 (npm/npx/bun 共用)${NC}"
else
  echo -e "${BLUE}  - ~/.npmrc 已有 registry 配置，跳过${NC}"
fi

# Python 生态: 无 pip 则用 ensurepip 引导, pip 可用时才配置中科大 PyPI 镜像
if command -v python3 &> /dev/null; then
  PIP_READY=0
  if python3 -m pip --version &> /dev/null; then
    PIP_READY=1
  else
    echo -e "${YELLOW}⚠ 缺少 pip，正在引导安装...${NC}"
    if python3 -m ensurepip --upgrade >/dev/null 2>&1 && python3 -m pip --version &> /dev/null; then
      PIP_READY=1
      echo -e "${GREEN}✓ pip 引导完成 ($(python3 -m pip --version 2>/dev/null | cut -d' ' -f2))${NC}"
    elif command -v apt-get >/dev/null 2>&1; then
      # 精简镜像常裁剪 python3-venv 致 ensurepip 不可用(oct/jammy 实测), 回退 apt 装 python3-pip
      echo -e "${BLUE}  - ensurepip 失败, 回退 apt 安装 python3-pip...${NC}"
      apt_ensure_update
      if timeout -s KILL 300 $SUDO apt-get install -y python3-pip >/dev/null 2>&1 && python3 -m pip --version &> /dev/null; then
        PIP_READY=1
        echo -e "${GREEN}✓ pip 经 apt 回退安装完成 ($(python3 -m pip --version 2>/dev/null | cut -d' ' -f2))${NC}"
      else
        echo -e "${YELLOW}⚠ ensurepip 与 apt 回退均失败（可手动执行: sudo apt install python3-pip）${NC}"
      fi
    else
      echo -e "${YELLOW}⚠ ensurepip 失败（可手动执行: sudo apt install python3-pip）${NC}"
    fi
  fi

  if [ "$PIP_READY" = "1" ]; then
    PIP_CONF="$HOME/.config/pip/pip.conf"
    if [ -f "$HOME/.pip/pip.conf" ]; then
      PIP_CONF="$HOME/.pip/pip.conf"
    fi
    if ! grep -q "index-url" "$PIP_CONF" 2>/dev/null; then
      mkdir -p "$(dirname "$PIP_CONF")"
      printf '[global]\nindex-url = https://mirrors.ustc.edu.cn/pypi/simple\ntrusted-host = mirrors.ustc.edu.cn\n' > "$PIP_CONF"
      echo -e "${GREEN}✓ PyPI 镜像源已配置 (中科大, $PIP_CONF)${NC}"
    else
      echo -e "${BLUE}  - pip 已有 index-url 配置，跳过${NC}"
    fi
  fi
fi

# ------------------------------------------------------------------
# 步骤 6: 安装 Bun 运行时
# ------------------------------------------------------------------
step_end 5 "检查前置依赖"
step_begin
echo -e "${YELLOW}[6/12] 安装 Bun 运行时...${NC}"

ensure_bun() {
  local bun_cmd=""
  if command -v bun >/dev/null 2>&1; then
    bun_cmd="bun"
  elif [ -f "$HOME/.bun/bin/bun" ]; then
    export PATH="$HOME/.bun/bin:$PATH"
    bun_cmd="$HOME/.bun/bin/bun"
  elif [ -f "/usr/local/bin/bun" ]; then
    bun_cmd="/usr/local/bin/bun"
  fi

  if [ -n "$bun_cmd" ] && "$bun_cmd" --version >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Bun 已安装 ($("$bun_cmd" --version))${NC}"
    return 0
  fi

  if [ -n "$bun_cmd" ]; then
    echo -e "${YELLOW}⚠ 检测到损坏的 Bun，清理后重新安装...${NC}"
    rm -f "$HOME/.bun/bin/bun" "$HOME/.bun/bin/bunx"
  fi

  echo "正在安装 Bun（优先 npm 镜像，失败回退 npmmirror 二进制，再回退官方脚本）..."
  if npm i -g bun >/dev/null 2>&1 && command -v bun >/dev/null 2>&1 && bun --version >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Bun 安装成功 ($(bun --version))${NC}"
    return 0
  fi

  echo -e "${YELLOW}⚠ npm 安装失败，尝试 npmmirror 二进制...${NC}"
  if command -v unzip >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    BUN_ARCH="x64"
    case "$(uname -m)" in
      x86_64) BUN_ARCH="x64" ;;
      aarch64) BUN_ARCH="aarch64" ;;
      *) BUN_ARCH="" ;;
    esac
    if [ -n "$BUN_ARCH" ]; then
      BUN_VERSION="$(curl -fsSL --connect-timeout 8 --max-time 20 "https://registry.npmmirror.com/-/binary/bun/" 2>/dev/null | grep -o '"name":"bun-v[0-9.]*/"' | sed 's/"name":"//; s/\/"//' | sort -V | tail -1 || true)"
      BUN_TMP="$(mktemp -d)"
      if [ -n "$BUN_VERSION" ] && curl -fsSL --connect-timeout 8 --max-time 180 -o "$BUN_TMP/bun.zip" "https://registry.npmmirror.com/-/binary/bun/$BUN_VERSION/bun-linux-$BUN_ARCH.zip" 2>/dev/null && unzip -qo "$BUN_TMP/bun.zip" -d "$BUN_TMP" && [ -f "$BUN_TMP/bun-linux-$BUN_ARCH/bun" ]; then
        mkdir -p "$HOME/.bun/bin"
        install -m 0755 "$BUN_TMP/bun-linux-$BUN_ARCH/bun" "$HOME/.bun/bin/bun"
        ln -sf "$HOME/.bun/bin/bun" "$HOME/.bun/bin/bunx"
        export PATH="$HOME/.bun/bin:$PATH"
        rm -rf "$BUN_TMP"
        echo -e "${GREEN}✓ Bun 安装成功 (npmmirror 二进制, $(bun --version))${NC}"
        return 0
      fi
      rm -rf "$BUN_TMP"
    fi
  fi

  echo -e "${YELLOW}⚠ npmmirror 下载失败，回退官方安装脚本...${NC}"
  curl -fsSL https://bun.sh/install | bash
  if [ -f "$HOME/.bun/bin/bun" ]; then
    export PATH="$HOME/.bun/bin:$PATH"
    echo -e "${GREEN}✓ Bun 安装成功 ($(bun --version))${NC}"
  else
    echo -e "${RED}✗ Bun 安装失败，请手动安装: curl -fsSL https://bun.sh/install | bash${NC}"
    exit 1
  fi
}

ensure_bun

if [ ! -f "$HOME/.bunfig.toml" ]; then
  printf '[install]\nregistry = "%s"\n' "$NPM_REGISTRY" > "$HOME/.bunfig.toml"
  echo -e "${GREEN}✓ Bun registry 已配置 ($NPM_REGISTRY)${NC}"
else
  echo -e "${BLUE}  - ~/.bunfig.toml 已存在，跳过${NC}"
fi

# 确保 bun 在 PATH 中
if ! command -v bun &> /dev/null; then
  export PATH="$HOME/.bun/bin:$PATH"
fi

# 如果 shell 配置中还没有 bun 路径，自动写入
BUN_PATH_LINE='export PATH="$HOME/.bun/bin:$PATH"'
if ! grep -q '\.bun/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo "" >> "$HOME/.bashrc"
  echo "# Bun" >> "$HOME/.bashrc"
  echo "$BUN_PATH_LINE" >> "$HOME/.bashrc"
  echo -e "${GREEN}✓ Bun 路径已写入 ~/.bashrc${NC}"
fi
# 确保当前会话也能用
export PATH="$HOME/.bun/bin:$PATH"

# ------------------------------------------------------------------
# 步骤 7: 安装 OpenCode
# ------------------------------------------------------------------
step_end 6 "安装 Bun 运行时"
step_begin
echo -e "${YELLOW}[7/12] 安装 OpenCode...${NC}"

# 确保 Bun 路径优先（避免 WSL 下 Windows npm 版本抢在前）
export PATH="$HOME/.bun/bin:$PATH"

if [ -f "$HOME/.bun/bin/opencode" ]; then
  echo -e "${GREEN}✓ OpenCode 已安装 ($(opencode --version))${NC}"
else
  echo "正在通过 Bun 安装 OpenCode..."
  bun install -g opencode-ai

  if [ -f "$HOME/.bun/bin/opencode" ]; then
    echo -e "${GREEN}✓ OpenCode 安装成功 ($(opencode --version))${NC}"
  else
    echo -e "${RED}✗ OpenCode 安装失败${NC}"
    echo "  请手动安装: bun install -g opencode-ai"
    exit 1
  fi
fi

# 检查是否有 Windows npm 安装的 opencode 冲突
WINDOWS_OPENCODE=$(command -v opencode 2>/dev/null || true)
if [ -n "$WINDOWS_OPENCODE" ] && echo "$WINDOWS_OPENCODE" | grep -q "/mnt/"; then
  echo -e "${YELLOW}⚠ 检测到 WSL 下存在 Windows npm 安装的 opencode${NC}"
  echo "  当前优先级: $HOME/.bun/bin > $WINDOWS_OPENCODE"
  echo "  如果输入 opencode 仍报错，请检查 PATH 顺序"
fi

# ------------------------------------------------------------------
# 步骤 8: 安装 oh-my-openagent 插件
# ------------------------------------------------------------------
step_end 7 "安装 OpenCode"
step_begin
echo -e "${YELLOW}[8/12] 安装 oh-my-openagent 插件...${NC}"

cd "$CONFIG_DIR"
if [ ! -d "node_modules" ] || [ ! -d "node_modules/oh-my-openagent" ]; then
  bun add oh-my-openagent@latest 2>&1 | tail -3
  echo -e "${GREEN}✓ oh-my-openagent 插件安装完成${NC}"
else
  echo -e "${GREEN}✓ oh-my-openagent 插件已存在${NC}"
fi

echo -e "${YELLOW}应用 omo 模型跟随补丁...${NC}"
OMO_PATCH_FILE="$(mktemp /tmp/omo-patch.XXXXXX.mjs)"
cat > "$OMO_PATCH_FILE" << 'OMO_PATCH_EOF'
import { readFileSync, writeFileSync } from "node:fs";

const file = process.argv[2];
if (!file) {
  console.error("usage: node omo-follow-system-default.mjs <dist/index.js>");
  process.exit(1);
}
let src = readFileSync(file, "utf8");
let changed = 0;

const p1Marker = "Model resolved via system default (before hardcoded fallback chain)";
if (!src.includes(p1Marker)) {
  const anchor =
    '      log3("No available model found in user fallback_models, falling through to hardcoded chain");\n' +
    "    }\n" +
    "  }\n" +
    "  if (fallbackChain && fallbackChain.length > 0) {";
  const replacement =
    '      log3("No available model found in user fallback_models, falling through to hardcoded chain");\n' +
    "    }\n" +
    "  }\n" +
    "  if (systemDefaultModel !== undefined) {\n" +
    '    log3("Model resolved via system default (before hardcoded fallback chain)", { model: systemDefaultModel });\n' +
    '    return { model: systemDefaultModel, provenance: "system-default", attempted };\n' +
    "  }\n" +
    "  if (fallbackChain && fallbackChain.length > 0) {";
  if (!src.includes(anchor)) throw new Error("patch1 anchor not found (omo dist changed)");
  src = src.replace(anchor, replacement);
  const tail =
    "  if (systemDefaultModel === undefined) {\n" +
    '    log3("No model resolved - systemDefaultModel not configured");\n' +
    "    return;\n" +
    "  }\n" +
    '  log3("Model resolved via system default", { model: systemDefaultModel });\n' +
    '  return { model: systemDefaultModel, provenance: "system-default", attempted };\n';
  if (!src.includes(tail)) throw new Error("patch1 tail not found");
  src = src.replace(tail, "");
  changed++;
}

const p2Marker = "[resolveModelForDelegateTask] system default before hardcoded chain";
if (!src.includes(p2Marker)) {
  const anchor = "  const fallbackChain = input.fallbackChain;\n" + "  if (fallbackChain && fallbackChain.length > 0) {";
  const replacement =
    "  const systemDefaultModel = normalizeModel(input.systemDefaultModel);\n" +
    "  if (systemDefaultModel) {\n" +
    '    deps.log?.("[resolveModelForDelegateTask] system default before hardcoded chain", { model: systemDefaultModel });\n' +
    "    return { model: systemDefaultModel };\n" +
    "  }\n" +
    "  const fallbackChain = input.fallbackChain;\n" +
    "  if (fallbackChain && fallbackChain.length > 0) {";
  if (!src.includes(anchor)) throw new Error("patch2 anchor not found");
  src = src.replace(anchor, replacement);
  const tail =
    "  const systemDefaultModel = normalizeModel(input.systemDefaultModel);\n" +
    "  if (systemDefaultModel) {\n" +
    "    return { model: systemDefaultModel };\n" +
    "  }\n" +
    "  return;\n";
  if (!src.includes(tail)) throw new Error("patch2 tail not found");
  src = src.replace(tail, "  return;\n");
  changed++;
}

if (changed > 0) {
  writeFileSync(file, src);
  console.log("omo patch applied");
} else {
  console.log("omo patch already applied");
}
OMO_PATCH_EOF

if [ -f "$CONFIG_DIR/node_modules/oh-my-openagent/dist/index.js" ] && node "$OMO_PATCH_FILE" "$CONFIG_DIR/node_modules/oh-my-openagent/dist/index.js"; then
  echo -e "${GREEN}✓ omo 模型跟随补丁已应用（子代理跟随 opencode.json 的 model）${NC}"
else
  echo -e "${YELLOW}⚠ omo 补丁失败（omo 版本可能已变化，子代理将回退硬编码模型链）${NC}"
fi
# 运行时副本: opencode 实际从 ~/.cache/opencode/packages/ 加载插件,该副本不打=补丁运行时无效
CACHE_OKO=0
for RT in "$HOME/.cache/opencode/packages/oh-my-openagent@"*/node_modules/oh-my-openagent/dist/index.js; do
  [ -f "$RT" ] || continue
  if node "$OMO_PATCH_FILE" "$RT"; then CACHE_OKO=1; fi
done
if [ "$CACHE_OKO" = 1 ]; then
  echo -e "${GREEN}✓ omo 运行时副本补丁已应用（~/.cache/opencode/packages/）${NC}"
else
  echo -e "${BLUE}  - 运行时副本未找到（首次启动 opencode 后才生成,届时重跑本脚本补打）${NC}"
fi
rm -f "$OMO_PATCH_FILE"

# superpowers 路由模式: clone vault + 部署轻插件(默认关闭, SUPERPOWERS_ROUTER=1 启用)
if [ "${SUPERPOWERS_ROUTER:-0}" = "1" ] && [ -f "$SCRIPT_DIR/router-modules/sp-router/plugin.js" ]; then
  SP_VAULT="$CONFIG_DIR/sp-vault/superpowers"
  if [ -d "$SP_VAULT/.git" ]; then
    git -C "$SP_VAULT" pull --ff-only >/dev/null 2>&1 || echo -e "${BLUE}  - sp-vault 更新跳过(可手动 git pull)${NC}"
  else
    git clone --depth 1 https://github.com/jnMetaCode/superpowers-zh.git "$SP_VAULT" >/dev/null 2>&1 \
      && echo -e "${GREEN}✓ superpowers vault 已克隆(路由模式)${NC}" \
      || echo -e "${YELLOW}⚠ vault 克隆失败,sp-router 将无技能可读${NC}"
  fi
  mkdir -p "$CONFIG_DIR/plugins"
  # v2 三件套(plugin+matcher+index),缺伴文件则插件降级 v1(oct 实测教训)
  sed "s|__SP_VAULT__|$SP_VAULT/skills|g" "$SCRIPT_DIR/router-modules/sp-router/plugin.js" > "$CONFIG_DIR/plugins/sp-router.ts"
  cp "$SCRIPT_DIR/router-modules/sp-router/matcher.mjs" "$CONFIG_DIR/plugins/matcher.mjs"
  cp "$SCRIPT_DIR/router-modules/sp-router/index.yaml" "$CONFIG_DIR/plugins/index.yaml"
  echo -e "${GREEN}✓ sp-router 已部署 → plugins/sp-router.ts(渐进披露,实测 -90% 起步 token)${NC}"
fi

# ------------------------------------------------------------------
# 步骤 9: 安装 GSD Core 工作流
# ------------------------------------------------------------------
step_end 8 "安装 oh-my-openagent 插件"
step_begin
echo -e "${YELLOW}[9/12] GSD Core 工作流(默认跳过,INSTALL_GSD=1 启用)...${NC}"

# GSD 默认跳过是基准实测定案(完成率零收益/常驻 ~4k tok/模型自发调用 0%),
# 非疏忽——证据链勿删: benchmarks/terminal-bench/{gsd-3arm,nogsd-3arm,gsd-showcase}.md
if [ "${INSTALL_GSD:-0}" != "1" ]; then
  echo -e "${BLUE}  - 已跳过(需要多阶段项目工作流时: INSTALL_GSD=1 重新运行)${NC}"
  # 锚点耦合警告: plugins/gsd-core.js 的 resolveRepoRoot 需要 gsd-core/ 目录做锚点,
  # 单删 gsd-core/ 会让钩子桥报 "NOT enforced"(安全钩子静默失效)。只剥 skills/agents,保 gsd-core/+hooks/
  echo -e "${BLUE}  - 安全钩子层(hooks/ gsd-prompt-guard 等)保留——它是注入防线,与工作流无关${NC}"
  # 剥除历史安装的 mcp.gsd(零历史调用;本地 skills 直读文件不需要它)
  if command -v python3 >/dev/null 2>&1 && [ -f "$CONFIG_DIR/opencode.json" ]; then
    python3 -c "
import json
p='$CONFIG_DIR/opencode.json'
c=json.load(open(p))
if 'gsd' in c.get('mcp',{}):
    del c['mcp']['gsd']
    t=p+'.tmp'; json.dump(c,open(t,'w'),ensure_ascii=False,indent=1)
    import os; os.replace(t,p)
    print('  ✓ 已剥除 mcp.gsd(本地 skills 直读 .planning,无 MCP 依赖)')
" 2>/dev/null || true
  fi
else
  # 检测是否已安装（检查 opencode 命令行目录下是否有 gsd 命令）
  if ls "$CONFIG_DIR/command/gsd-"* &>/dev/null 2>&1; then
    echo -e "${GREEN}✓ GSD Core 命令已存在${NC}"
  else
    if command -v npx &> /dev/null; then
      echo "正在安装 GSD Core（官方继任项目，原生支持 OpenCode）..."
      echo ""

      # GSD Core 官方安装命令
      # 自动检测 OpenCode 配置目录，安装 agent 和 command 到对应目录
      npx --yes @opengsd/gsd-core@latest --opencode --global

      echo ""
      # 安全钩子防线校验(2026-09-01 教训: hooks/ 是注入防线,误删=S1 裸奔)
      if ls "$CONFIG_DIR/hooks/gsd-prompt-guard.js" "$CONFIG_DIR/hooks/gsd-read-guard.js" >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ GSD 安全钩子在位(prompt-guard/read-guard/injection-scanner)${NC}"
      else
        echo -e "${YELLOW}  ⚠ 安全钩子未检测到——检查 hooks/ 目录,勿在无防护下运行对抗场景${NC}"
      fi
      echo -e "${GREEN}✓ GSD Core 安装完成${NC}"
      echo -e "${BLUE}  重启 OpenCode 后即可使用 /gsd-* 命令(用户显式驱动;env 块会注入项目状态)${NC}"
    else
      echo -e "${YELLOW}⚠ npx 未安装，跳过 GSD Core${NC}"
      echo "  确保 Node.js 已安装，然后手动执行:"
      echo "    npx --yes @opengsd/gsd-core@latest --opencode --global"
    fi
  fi
fi

# ------------------------------------------------------------------
# 步骤 10: 安装 CodeGraph MCP（代码图索引）
# ------------------------------------------------------------------
step_end 9 "安装 GSD Core 工作流"
step_begin
echo -e "${YELLOW}[10/12] 安装 CodeGraph MCP...${NC}"

CG_BIN="$(command -v codegraph 2>/dev/null || true)"
if [ -z "$CG_BIN" ]; then
  if command -v npm &> /dev/null; then
    echo -e "${YELLOW}正在安装 codegraph（npmmirror 源，约 30-60s，超时 120s）...${NC}"
    CG_INSTALL_LOG="$(mktemp)"
    # timeout 一律 -s KILL: SIGTERM 对挂起态(T)进程不投递(实测 DCP 安装陷 T 态整链僵死 16 分钟), SIGKILL 必达
    if timeout -s KILL 120 npm i -g --registry="$NPM_REGISTRY" @colbymchenry/codegraph > "$CG_INSTALL_LOG" 2>&1; then
      NPM_PREFIX="$(npm config get prefix)"
      CG_BIN="$NPM_PREFIX/bin/codegraph"
      if [ -x "$CG_BIN" ]; then
        echo -e "${GREEN}✓ codegraph 安装完成 ($CG_BIN)${NC}"
        # 脚本装的 node 为官方二进制布局，全局 bin 可能不在 PATH，补入
        if ! command -v codegraph &> /dev/null; then
          export PATH="$NPM_PREFIX/bin:$PATH"
          if ! grep -q "NPM_PREFIX/bin" "$HOME/.bashrc" 2>/dev/null; then
            echo "" >> "$HOME/.bashrc"
            echo "# npm 全局 bin" >> "$HOME/.bashrc"
            echo "export PATH=\"$NPM_PREFIX/bin:\$PATH\"" >> "$HOME/.bashrc"
          fi
        fi
      else
        echo -e "${YELLOW}⚠ codegraph 安装失败（已装但未找到二进制），跳过 MCP 注册${NC}"
        tail -5 "$CG_INSTALL_LOG"
        echo "  装好后重新运行脚本即可注册 MCP"
        CG_BIN=""
      fi
    else
      echo -e "${YELLOW}⚠ codegraph 安装失败（超时或网络错误），跳过 MCP 注册${NC}"
      tail -5 "$CG_INSTALL_LOG"
      echo "  可手动重试: npm i -g --registry=$NPM_REGISTRY @colbymchenry/codegraph"
      CG_BIN=""
    fi
    rm -f "$CG_INSTALL_LOG"
  else
    echo -e "${YELLOW}⚠ npm 未安装，跳过 codegraph${NC}"
    echo "  手动安装: npm i -g @colbymchenry/codegraph"
  fi
else
  echo -e "${GREEN}✓ codegraph 已存在 ($CG_BIN)${NC}"
fi

# codegraph 可用时才注册 MCP；command 用绝对路径，避免 PATH 问题
if [ -n "$CG_BIN" ] && [ -f "$CONFIG_DIR/opencode.json" ]; then
  if node -e '
    const fs = require("fs");
    const p = process.argv[1];
    const bin = process.argv[2];
    const c = JSON.parse(fs.readFileSync(p, "utf8"));
    c.mcp = c.mcp || {};
    c.mcp.codegraph = { type: "local", command: [bin, "serve", "--mcp"], enabled: true };
    fs.writeFileSync(p, JSON.stringify(c, null, 2) + "\n");
  ' "$CONFIG_DIR/opencode.json" "$CG_BIN" 2>/dev/null; then
    echo -e "${GREEN}✓ codegraph MCP 已注册到 opencode.json (绝对路径)${NC}"
  else
    echo -e "${YELLOW}⚠ codegraph MCP 注册失败，可手动添加${NC}"
  fi
fi

echo -e "${BLUE}  在项目目录运行 'codegraph init' 生成索引${NC}"
echo -e "${BLUE}  重启 OpenCode 后 codegraph_* 工具生效${NC}"

# ------------------------------------------------------------------
# 步骤 11: 安装 RTK（Rust Token Killer，压缩命令输出节省 Token）
# 零认证：版本号走 api.github.com，下载走镜像链（gh-proxy → ghfast → 官方直连）
# ------------------------------------------------------------------
step_end 10 "安装 CodeGraph MCP"
step_begin
echo -e "${YELLOW}[11/12] 安装 RTK（命令输出压缩，节省 Token 开支）...${NC}"

if command -v rtk &> /dev/null; then
  echo -e "${GREEN}✓ rtk 已安装 ($(rtk --version))${NC}"
else
  # 动态获取最新版本号（无需认证），失败则回退已知版本
  RTK_VERSION="$(curl -fsSL --connect-timeout 10 "https://api.github.com/repos/rtk-ai/rtk/releases/latest" 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 || true)"
  [ -z "$RTK_VERSION" ] && RTK_VERSION="v0.45.0"

  # 架构检测: x86_64 用 musl 静态二进制（零依赖），aarch64 用 gnu
  RTK_ASSET=""
  case "$(uname -m)" in
    x86_64)  RTK_ASSET="rtk-x86_64-unknown-linux-musl.tar.gz" ;;
    aarch64) RTK_ASSET="rtk-aarch64-unknown-linux-gnu.tar.gz" ;;
    *) echo -e "${YELLOW}⚠ 不支持的架构 $(uname -m)，跳过 RTK 安装${NC}" ;;
  esac

  if [ -n "$RTK_ASSET" ]; then
    RTK_URL="https://github.com/rtk-ai/rtk/releases/download/$RTK_VERSION/$RTK_ASSET"
    RTK_TMP="$(mktemp -d)"
    RTK_OK=0
    # 镜像链（全部无认证）: gh-proxy.com → ghfast.top → 官方直连
    for MIRROR in "https://gh-proxy.com/" "https://ghfast.top/" ""; do
      echo -e "${BLUE}  尝试下载: ${MIRROR}${RTK_URL}${NC}"
      if curl -fsSL --connect-timeout 12 --max-time 90 -o "$RTK_TMP/rtk.tar.gz" "${MIRROR}${RTK_URL}"; then
        RTK_OK=1
        break
      fi
    done

    if [ "$RTK_OK" = "1" ] && tar -xzf "$RTK_TMP/rtk.tar.gz" -C "$RTK_TMP" && [ -f "$RTK_TMP/rtk" ]; then
      # 优先 /usr/local/bin，非 root 回退 ~/.local/bin
      if install -m 0755 "$RTK_TMP/rtk" /usr/local/bin/rtk 2>/dev/null; then
        echo -e "${GREEN}✓ rtk 安装完成: $(rtk --version)${NC}"
      else
        mkdir -p "$HOME/.local/bin"
        install -m 0755 "$RTK_TMP/rtk" "$HOME/.local/bin/rtk"
        export PATH="$HOME/.local/bin:$PATH"
        echo -e "${GREEN}✓ rtk 安装完成: $(rtk --version)（~/.local/bin）${NC}"
      fi
    else
      echo -e "${YELLOW}⚠ rtk 下载失败（网络受限时可手动从 https://github.com/rtk-ai/rtk/releases 下载）${NC}"
    fi
    rm -rf "$RTK_TMP"
  fi
fi

# OpenCode 集成（幂等，无认证）
if command -v rtk &> /dev/null; then
  if [ -f "$CONFIG_DIR/plugins/rtk.ts" ]; then
    echo -e "${BLUE}  - rtk opencode 插件已存在，跳过 init${NC}"
  else
    printf 'n\n' | rtk init --opencode -g >/dev/null 2>&1 || true
    if [ -f "$CONFIG_DIR/plugins/rtk.ts" ]; then
      echo -e "${GREEN}✓ rtk opencode 插件安装完成（重启 OpenCode 后自动压缩命令输出）${NC}"
    else
      echo -e "${YELLOW}⚠ rtk init 失败，可手动执行: rtk init --opencode -g${NC}"
    fi
  fi
  rtk telemetry disable >/dev/null 2>&1 || true
fi


step_end 11 "安装 RTK"

# ------------------------------------------------------------------
# DCP 上下文压缩插件(选装, INSTALL_DCP=1 启用; 不占步骤号)
# 实测: benchmarks/terminal-bench/dcp-verify.md (末态上下文 -82%/计费当量 -43%)
# AGPL-3.0 不默认装: 网络条款(§13)有源码披露义务风险, 须用户知情确认
# ------------------------------------------------------------------
if [ "${INSTALL_DCP:-0}" != "1" ]; then
  echo -e "${BLUE}  - DCP 上下文压缩: 已跳过(INSTALL_DCP=1 可启用, AGPL-3.0, 见 README)${NC}"
else
  # 许可证知会 ①: 安装前显式提示(硬要求)
  echo -e "${YELLOW}  ⚠ DCP 许可证知会 (AGPL-3.0):${NC}"
  echo "    该插件为 AGPL-3.0 许可证: 未修改使用无义务;"
  echo "    修改并(哪怕服务器)部署需公开修改源码; 部分企业禁用 AGPL。"
  echo "    继续安装即视为你知情并自行决定(详见 README「DCP 上下文压缩」小节)"

  DCP_CONFIRMED=0
  if [ "${CONFIRM_AGPL:-0}" = "1" ]; then
    DCP_CONFIRMED=1
    echo -e "${BLUE}  - CONFIRM_AGPL=1 已显式确认(非交互双变量路径)${NC}"
    [ "${UPGRADE_MODE:-0}" = "1" ] && echo "  (升级模式: 首次安装已确认 AGPL,状态清单留档)"
  elif [ -t 0 ]; then
    echo -n "    确认安装 DCP? (y/n) [n, 10 秒超时自动跳过]: "
    dcp_agree=""
    read -r -t 10 dcp_agree || dcp_agree=""
    if [[ "$dcp_agree" =~ ^[Yy]$ ]]; then
      DCP_CONFIRMED=1
    else
      echo ""
      echo -e "${BLUE}  - 未确认(默认/超时/拒绝), 跳过 DCP 安装${NC}"
    fi
  else
    echo -e "${BLUE}  - 非交互管道且未显式确认, 跳过 DCP 安装(防 curl|bash 误触)${NC}"
  fi

  if [ "$DCP_CONFIRMED" != "1" ]; then
    echo -e "${BLUE}    显式确认方式: INSTALL_DCP=1 CONFIRM_AGPL=1 ./setup-opencode.sh${NC}"
  elif ! command -v opencode >/dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠ opencode 不可用, 跳过 DCP 安装${NC}"
    echo "    手动安装: opencode plugin @tarquinen/opencode-dcp@latest --global"
  else
    # 官方装法(dcp-verify.md 实测一次成功; 大包下载约 3 分钟, 首跑可能超 2 分钟, 上限 10 分钟)
    echo "  正在安装 DCP(大包下载, 超时上限 600s)..."
    if timeout -s KILL 600 opencode plugin @tarquinen/opencode-dcp@latest --global; then
      # 默认 dcp.jsonc(若不存在): 阈值取实测可用配置, 附按模型上下文调整的说明
      if [ ! -f "$CONFIG_DIR/dcp.jsonc" ]; then
        cat > "$CONFIG_DIR/dcp.jsonc" << 'DCP_EOF'
{
  "$schema": "https://raw.githubusercontent.com/Opencode-DCP/opencode-dynamic-context-pruning/master/dcp.schema.json",
  // compress 阈值为实测加速值(dcp-verify.md 实验: glm-5.3 大窗口下默认值 8-12 轮内不可达);
  // 上游默认 minContextLimit=50000 / maxContextLimit=100000。
  // 按所用模型的上下文窗口调整: 大窗口可回调默认(触发更晚, 机制相同), 小窗口建议保持低位。
  "compress": {
    "minContextLimit": 8000,
    "maxContextLimit": 16000,
    "nudgeFrequency": 5,
    "nudgeForce": "soft"
  }
}
DCP_EOF
        echo -e "${GREEN}  ✓ 默认 dcp.jsonc 已写入(阈值 8K/16K, 见文件内注释按模型调整)${NC}"
      else
        echo -e "${BLUE}  - dcp.jsonc 已存在, 保持不动${NC}"
      fi
      # 装后验证: opencode.json plugin 数组应含 opencode-dcp(失败仅告警, 不中止)
      if grep -q 'opencode-dcp' "$CONFIG_DIR/opencode.json" 2>/dev/null; then
        echo -e "${GREEN}  ✓ DCP 已注册到 opencode.json plugin 数组${NC}"
      else
        echo -e "${YELLOW}  ⚠ 未在 opencode.json 检出 opencode-dcp(可能安装异常), 不影响其余步骤${NC}"
      fi
      # 许可证知会 ②: 安装后再提示一次(硬要求)
      echo -e "${BLUE}  - DCP 为 AGPL-3.0: 修改并(哪怕服务器)部署需公开修改源码, 未修改使用无义务${NC}"
      echo -e "${BLUE}  - 重启 OpenCode 后 compress 工具与 /dcp-compress 命令生效${NC}"
    else
      echo -e "${YELLOW}  ⚠ DCP 安装命令失败(网络受限/超时?), 不影响其余步骤, 可手动重试:${NC}"
      echo "    opencode plugin @tarquinen/opencode-dcp@latest --global"
    fi
  fi
fi

# MinerU agent 侧接线(INSTALL_MINERU=1 装完 python 包后调用; 抽函数法可测, 见 tests/test-mineru-wiring.sh)
# 裸 CLI 不会被 agent 自发使用(实测教训), 需显式暴露双路:
#   ① preset-skills/mineru-local 部署 → CONFIG_DIR/skills/(与步骤12 glob 同判据, 幂等)
#   ② Flash MCP 幂等合并进 opencode.json mcp 段(python3 tmp+rename 原子写, 同 disabled_mcps 模式)
#   ③ 隐私知会一行(硬要求) + uv/uvx 缺失黄警不阻断(uvx 是 Python 工具, 与 npm 无关)
mineru_agent_wiring() {
  # ① skill 部署(幂等: 已存在保持不动)
  if [ -f "$SCRIPT_DIR/preset-skills/mineru-local/SKILL.md" ]; then
    if [ -d "$CONFIG_DIR/skills/mineru-local" ]; then
      echo -e "${BLUE}  - skill mineru-local 已存在, 保持不动${NC}"
    else
      mkdir -p "$CONFIG_DIR/skills/mineru-local"
      cp -r "$SCRIPT_DIR/preset-skills/mineru-local/"* "$CONFIG_DIR/skills/mineru-local/"
      echo -e "${GREEN}  ✓ preset-skill 已部署: mineru-local(本地文档解析, agent 即刻可调用)${NC}"
    fi
  else
    echo -e "${YELLOW}  ⚠ 未找到 preset-skills/mineru-local(源码仓库外运行?), skill 部署跳过${NC}"
  fi

  # ② Flash MCP 幂等合并(免 key Flash 档 20 页/10MB; 既有 mcp 条目不覆盖)
  if [ -f "$CONFIG_DIR/opencode.json" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$CONFIG_DIR/opencode.json" << 'PYEOF' \
      && echo -e "${GREEN}  ✓ Flash MCP(mineru-flash)已合并进 opencode.json(重启 OpenCode 生效)${NC}" \
      || echo -e "${YELLOW}  ⚠ Flash MCP 合并失败(opencode.json JSON 损坏?), 手动配置见 README「MinerU 文档解析」${NC}"
import json, os, sys
p = sys.argv[1]
with open(p) as f:
    c = json.load(f)
c.setdefault("mcp", {})
c["mcp"]["mineru-flash"] = {"type": "local", "command": ["uvx", "mineru-open-mcp"], "enabled": True}
tmp = p + ".tmp"
with open(tmp, "w") as f:
    json.dump(c, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, p)
PYEOF
  else
    echo -e "${YELLOW}  ⚠ 跳过 Flash MCP 合并(缺 opencode.json 或 python3), 手动配置见 README「MinerU 文档解析」${NC}"
  fi

  # ③ 隐私知会(硬要求一行) + uv 缺失黄警不阻断
  echo -e "${BLUE}  - 隐私知会: Flash MCP 走云端处理(文档传 mineru.net, 处理后不保留); 本地隐私文档用 mineru CLI${NC}"
  if ! command -v uvx >/dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠ 未检出 uvx(Flash MCP 启动依赖, uv 的运行器), 安装不阻断: curl -LsSf https://astral.sh/uv/install.sh | sh${NC}"
  fi
}

# ------------------------------------------------------------------
# MinerU 文档解析(选装, INSTALL_MINERU=1 启用; 不占步骤号)
# PDF/图片 → Markdown/JSON; 免费分层: Flash 云 API 免装限量 / 本地部署免费无限量
# 云 token 档(免费额度后付费)不自动配置——本脚本只接免费路径, 详见 README「MinerU 文档解析」小节
# ------------------------------------------------------------------
if [ "${INSTALL_MINERU:-0}" != "1" ]; then
  echo -e "${BLUE}  - MinerU 文档解析: 已跳过(免费分层: 轻量用 Flash MCP 免装, 大量用 INSTALL_MINERU=1 本地部署免费无限量, 见 README)${NC}"
else
  # ① 许可证知会(仅打印, 无确认门——Apache-2.0 宽松, 非 AGPL 级风险)
  echo -e "${BLUE}  - MinerU 许可证知会 (Apache-2.0 + 附加条款):${NC}"
  echo "    个人与常规商用免费; MAU>1亿或月收入>\$2000万 需商业授权;"
  echo "    对外在线服务需标注使用了 MinerU(详见 README「MinerU 文档解析」小节)"

  # ② 资源前置检查(不足仅黄警不拦截——装包本身不占大空间, 模型首次运行才下载)
  MINERU_DISK_KB="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2{print $4}' || true)"
  MINERU_MEM_KB="$(awk '/^MemTotal:/{print $2; exit}' /proc/meminfo 2>/dev/null || true)"
  if [ -n "$MINERU_DISK_KB" ] && [ "$MINERU_DISK_KB" -lt 26214400 ]; then
    echo -e "${YELLOW}  ⚠ 磁盘可用 $((MINERU_DISK_KB/1024/1024))GB < 25GB(本地档建议 20GB+), 资源不足仍继续装包(模型首次运行才下载)${NC}"
  fi
  if [ -n "$MINERU_MEM_KB" ] && [ "$MINERU_MEM_KB" -lt 15728640 ]; then
    echo -e "${YELLOW}  ⚠ 内存 $((MINERU_MEM_KB/1024/1024))GB < 15GB(本地档建议 16GB+), 资源不足仍继续装包(模型首次运行才下载)${NC}"
  fi

  # ③ 安装: pip install "mineru[core]"(走步骤5已配置的中科大 PyPI 源; PEP 668 系统自动重试)
  if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠ 无 python3, 跳过 MinerU 安装(手动: python3 -m pip install \"mineru[core]\")${NC}"
  elif ! python3 -m pip --version >/dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠ pip 不可用, 跳过 MinerU 安装(手动: python3 -m ensurepip --upgrade 后 python3 -m pip install \"mineru[core]\")${NC}"
  else
    echo "  正在安装 MinerU(大包含 PyTorch, 走中科大源, 超时上限 900s)..."
    MINERU_PIP_LOG="$(mktemp)"
    timeout -s KILL 900 python3 -m pip install "mineru[core]" 2>&1 | tee "$MINERU_PIP_LOG"
    MINERU_PIP_RC="${PIPESTATUS[0]}"
    if [ "$MINERU_PIP_RC" != "0" ] && grep -qi 'externally-managed' "$MINERU_PIP_LOG"; then
      echo -e "${BLUE}  - 系统启用 PEP 668(externally-managed), 加 --break-system-packages 重试${NC}"
      timeout -s KILL 900 python3 -m pip install --break-system-packages "mineru[core]" 2>&1 | tee "$MINERU_PIP_LOG"
      MINERU_PIP_RC="${PIPESTATUS[0]}"
    fi
    rm -f "$MINERU_PIP_LOG"
    if [ "$MINERU_PIP_RC" = "0" ]; then
      echo -e "${GREEN}  ✓ mineru[core] pip 安装完成${NC}"
    else
      echo -e "${YELLOW}  ⚠ MinerU 安装失败(网络受限/超时?), 不影响其余步骤, 可手动重试:${NC}"
      echo "    python3 -m pip install \"mineru[core]\"   # PEP 668 系统加 --break-system-packages"
    fi
  fi

  # ④ 环境写入: 国内模型源(幂等, 已存在不重复)
  if ! grep -q 'MINERU_MODEL_SOURCE' "$HOME/.bashrc" 2>/dev/null; then
    printf '\n# MinerU 模型源(国内走 modelscope)\nexport MINERU_MODEL_SOURCE=modelscope\n' >> "$HOME/.bashrc"
    echo -e "${GREEN}  ✓ MINERU_MODEL_SOURCE=modelscope 已写入 ~/.bashrc(新终端生效)${NC}"
  else
    echo -e "${BLUE}  - MINERU_MODEL_SOURCE 已存在于 ~/.bashrc, 保持不动${NC}"
  fi

  # ⑤ 验证(容错): mineru --version → import magic_pdf/import mineru, 成功绿√失败黄⚠
  MINERU_OK=0
  if command -v mineru >/dev/null 2>&1 && mineru --version >/dev/null 2>&1; then
    echo -e "${GREEN}  ✓ MinerU 验证通过: $(mineru --version 2>/dev/null | head -1)${NC}"
    MINERU_OK=1
  elif python3 -c "import magic_pdf" >/dev/null 2>&1 || python3 -c "import mineru" >/dev/null 2>&1; then
    echo -e "${GREEN}  ✓ MinerU 验证通过(python 包可导入; mineru CLI 不在当前 PATH 时新开终端可用)${NC}"
    MINERU_OK=1
  fi
  if [ "$MINERU_OK" != "1" ]; then
    echo -e "${YELLOW}  ⚠ MinerU 验证未通过(安装可能失败), 手动安装指引:${NC}"
    echo "    python3 -m pip install \"mineru[core]\"   # PEP 668 系统加 --break-system-packages"
    echo "    文档: https://github.com/opendatalab/MinerU"
  fi

  # ⑥ 模型下载时机提示
  echo -e "${BLUE}  - 模型约数 GB, 首次运行 mineru 时自动从 modelscope 下载${NC}"

  # ⑦ agent 侧接线: mineru-local skill + Flash MCP(装完包 agent 即刻可调用, 不留裸 CLI 零调用面)
  mineru_agent_wiring
fi

# ------------------------------------------------------------------
# 记忆/自进化双通道(选装, INSTALL_CMODULES=1 启用; 不占步骤号)
# 复用 c-modules/c-modules-setup.sh 装器(--all = mem0+SkillOpt),不重复实现。
# 夜间自进化定时任务仅在两条路都真时交互问: 菜单选中(非环境变量预设) + [ -t 0 ];
# 环境变量路径按非交互铁律不问、默认不开启、只打印开启命令一行。
# ------------------------------------------------------------------
if [ "${INSTALL_CMODULES:-0}" != "1" ]; then
  echo -e "${BLUE}  - 记忆/自进化: 已跳过(INSTALL_CMODULES=1 或菜单选 5 可启用, 见 README)${NC}"
else
  CMODULES_INSTALLED=0
  if [ -f "$SCRIPT_DIR/c-modules/c-modules-setup.sh" ]; then
    echo "  正在安装 mem0 + SkillOpt 双通道(c-modules-setup --all)..."
    if bash "$SCRIPT_DIR/c-modules/c-modules-setup.sh" --all; then
      CMODULES_INSTALLED=1
      echo -e "${BLUE}  - mem0 初始化免注册: mem0 init --agent --agent-caller opencode(Agent Mode 自助签发免费 key;数据默认存 mem0 云,自托管可设 MEM0_BASE_URL)${NC}"
      echo -e "${BLUE}  - 契约: 产物只落 skill-drafts/,人工批准(移入 skills/)才生效——自进化无自动生效路径${NC}"
    else
      echo -e "${YELLOW}  ⚠ c-modules 装器执行失败, 可手动重试: bash c-modules/c-modules-setup.sh --all${NC}"
    fi
  else
    echo -e "${YELLOW}  ⚠ 未找到 c-modules/c-modules-setup.sh(源码仓库外运行?)——跳过记忆/自进化${NC}"
  fi

  CMODULES_CRON_LINE='0 3 * * * skillopt-sleep >> ~/.config/opencode/skill-drafts/sleep.log 2>&1'
  if [ "$CMODULES_INSTALLED" = "1" ] && [ "$INSTALL_CMODULES_PRESET" != "1" ] && [ -t 0 ]; then
    echo -n "  是否开启夜间自进化定时任务? (每晚 03:00 扫当天会话→提炼→验证门控→落草稿区待审) [y/N]: "
    cmodules_cron=""
    read -r cmodules_cron || cmodules_cron=""
    echo ""
    if [[ "$cmodules_cron" =~ ^[Yy]$ ]]; then
      if ! command -v skillopt-sleep >/dev/null 2>&1; then
        echo -e "${YELLOW}  ⚠ skillopt-sleep 未安装(pip 缺失?),定时任务不写入;装好后重跑本脚本或手动 crontab -e 加:${NC}"
        echo "    $CMODULES_CRON_LINE"
      elif ! command -v crontab >/dev/null 2>&1; then
        echo -e "${YELLOW}  ⚠ crontab 不可用,手动开启: crontab -e 加行:${NC}"
        echo "    $CMODULES_CRON_LINE"
      elif crontab -l 2>/dev/null | grep -F 'skillopt-sleep' >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ 夜间自进化定时任务已存在(幂等,不重复添加)${NC}"
      elif { crontab -l 2>/dev/null || true; echo "$CMODULES_CRON_LINE"; } | crontab - 2>/dev/null; then
        echo -e "${GREEN}  ✓ 夜间自进化定时任务已写入 crontab(每晚 03:00,日志 ~/.config/opencode/skill-drafts/sleep.log)${NC}"
      else
        echo -e "${YELLOW}  ⚠ crontab 写入失败,手动开启: crontab -e 加行:${NC}"
        echo "    $CMODULES_CRON_LINE"
      fi
    else
      echo -e "${BLUE}  - 未开启(默认);手动开启: crontab -e 加行 '${CMODULES_CRON_LINE}'${NC}"
    fi
  else
    echo -e "${BLUE}  - 夜间自进化默认未开启;开启命令: crontab -e 加行 '${CMODULES_CRON_LINE}'${NC}"
  fi
fi

# ------------------------------------------------------------------
# 步骤 12: 安全/能力增强模块(可选, SKIP_SECURITY=1 跳过)
# 依据 spec: E 方向六模块(权限红线/审计/安全自检/合规) + B 方向环境画像
# e-modules/ 随仓库分发, 安装时部署到 CONFIG_DIR
# ------------------------------------------------------------------
step_begin
echo -e "${YELLOW}[12/12] 安全与能力增强模块...${NC}"

MOD_DIR="$CONFIG_DIR/opencode-setup-modules"
# e-modules 源目录: 优先仓库(SCRIPT_DIR),管道升级回退到已部署的 MOD_DIR
EMOD_SRC="$SCRIPT_DIR/e-modules"
[ -d "$EMOD_SRC" ] || EMOD_SRC="$MOD_DIR"
PERM_TMP=$(mktemp)
_prev_trap() { step_summary; rm -f "$PERM_TMP" 2>/dev/null || true; }
trap _prev_trap EXIT

if [ "$SKIP_SECURITY" = "1" ]; then
  echo -e "${BLUE}  - 已跳过（SKIP_SECURITY=1）${NC}"
elif [ -d "$CONFIG_DIR/opencode-setup-modules" ] && [ -f "$CONFIG_DIR/opencode-setup-modules/audit-init.sh" ]; then
  # 管道升级回退: 仓库不在本地,但上次部署的模块还在配置目录——从那里续命
  MOD_DIR="$CONFIG_DIR/opencode-setup-modules"
  mkdir -p "$MOD_DIR" "$MOD_DIR/devcontainer"
  echo -e "${BLUE}  - 管道升级: 从已部署模块目录续命($MOD_DIR)${NC}"
elif [ -d "$EMOD_SRC" ] && [ -f "$EMOD_SRC/audit-init.sh" ]; then
  # 部署 e-modules 到配置目录
  mkdir -p "$MOD_DIR" "$MOD_DIR/devcontainer"
  cp "$EMOD_SRC/"*.sh "$MOD_DIR/" 2>/dev/null
  cp "$EMOD_SRC/devcontainer/"*.json "$EMOD_SRC/devcontainer/"*.md "$MOD_DIR/devcontainer/" 2>/dev/null
  chmod +x "$MOD_DIR"/*.sh 2>/dev/null

  echo -e "${BLUE}  - e-modules 已部署到 $MOD_DIR${NC}"

  export PERM_TMP
  # ① 权限红线(merge 进 opencode.json 的 permission 段)
  #    模板三档: 默认交互版 / --headless 无头版(benchmark/CI) / --sandbox 沙箱版
  #    (容器/隔离环境: 删本机破坏类 deny、保留网络不可逆 deny、ask 归零免手动点)。
  #    CI 直选: PERMISSION_MODE=sandbox bash setup-opencode.sh(经 gen-permissions.sh 生效)。
  #    档位选择内置在 gen-permissions 交互流程(装机问标准/沙箱),不进选装菜单。
  #    升级分叉(oct 实测 P1 疏漏): 命令替换只重定向 stdout/stderr 吞不掉 stdin
  #    ——--upgrade 走到此档位问句仍弹,光标闪烁卡在等输入。升级语义=保留现有
  #    权限配置(状态清单 flags.permission_mode 已留档),不重问不重生成。
  if [ "${UPGRADE_MODE:-0}" = "1" ]; then
    echo -e "${BLUE}  - 升级模式: 保留现有权限配置(重新生成用 bash $MOD_DIR/gen-permissions.sh)${NC}"
  elif command -v python3 >/dev/null 2>&1; then
    MERGE_OUT=$("$MOD_DIR/gen-permissions.sh" "$PERM_TMP" >/dev/null 2>&1 && python3 - "$CONFIG_DIR/opencode.json" "$PERM_TMP" << 'PYEOF'
import json,sys
p, perm_file = sys.argv[1], sys.argv[2]
try:
    c = json.load(open(p))
except Exception:
    c = {"$schema": "https://opencode.ai/config.json"}
try:
    perm = json.load(open(perm_file))["permission"]
    merged = c.get("permission", {})
    for cat, rules in perm.items():
        if isinstance(rules, dict):
            base = merged.get(cat, {})
            if isinstance(base, str):
                base = {} if rules else base
            for k, v in rules.items():
                # deny 不可被既有 allow 稀释;其余新规则覆盖
                if v == "deny" or k not in base:
                    base[k] = v
            merged[cat] = base
        else:
            merged[cat] = rules
    c["permission"] = merged
    tmp = p + ".tmp"
    json.dump(c, open(tmp, "w"), ensure_ascii=False, indent=1)
    import os; os.replace(tmp, p)
    print("OK")
except Exception as e:
    print(f"SKIP:{e}")
PYEOF
) || MERGE_OUT="SKIP:gen-failed"
    case "$MERGE_OUT" in
      OK) echo -e "${GREEN}  ✓ 权限红线已合并到 opencode.json${NC}" ;;
      *) echo -e "${YELLOW}  ⚠ 权限合并未完成($MERGE_OUT)${NC}" ;;
    esac
  else
    echo -e "${YELLOW}  ⚠ 无 python3，跳过权限合并（可手动运行 $MOD_DIR/gen-permissions.sh）${NC}"
  fi

  # ② 审计
  if "$MOD_DIR/audit-init.sh" init >/dev/null 2>&1; then
    echo -e "${GREEN}  ✓ 审计模块已初始化（JSONL+脱敏+熔断+30天轮转）${NC}"
  else
    echo -e "${YELLOW}  ⚠ 审计模块初始化失败(可手动运行 $MOD_DIR/audit-init.sh)${NC}"
  fi

  # ②b 出环硬门控(evidence-gated completion, AGENTS.md 在场守则的机器执行层)
  #    挂载形态依据: opencode 1.18.29 config schema 无 event 键,TUI/run 双实测
  #    event 命令不触发,无 Stop/session.idle 等价事件 → /completion-gate 斜杠命令形态
  if [ -f "$MOD_DIR/completion-gate.sh" ] && [ -f "$EMOD_SRC/completion-gate.md" ]; then
    mkdir -p "$CONFIG_DIR/commands"
    cp "$EMOD_SRC/completion-gate.md" "$CONFIG_DIR/commands/completion-gate.md"
    echo -e "${GREEN}  ✓ 出环硬门控已部署——宣称完成前跑 /completion-gate(check 阻断,report 仅报告)${NC}"
    echo -e "${BLUE}    用法: $MOD_DIR/completion-gate.sh check|report [workdir](双控实证假成功 44-52%→3%)${NC}"
  fi

  # ③ 安全自检 + AGENT-CARD
  set +e; SEC_OUT=$(cd "$HOME" && "$MOD_DIR/security-check.sh" 2>&1); SEC_RC=$?; set -e
  echo "$SEC_OUT" | sed 's/^/  /'   # UX-3: 完整透出(警告可读才可行动)
  [ $SEC_RC -ne 0 ] && echo -e "${YELLOW}  ⚠ security-check 存在 FAIL 项(退出码 $SEC_RC)${NC}"

  # ④ 合规文档
  "${MOD_DIR}/gen-compliance.sh" >/dev/null 2>&1 && echo -e "${GREEN}  ✓ 合规文档已生成（compliance/COMPLIANCE.md）${NC}" || echo -e "${YELLOW}  ⚠ 合规文档生成跳过${NC}"

  mkdir -p "$CONFIG_DIR/plugins"
  # ④b A-webmap 部署(联网认知 CLI, 装 ~/.local/bin)
  if [ -f "$SCRIPT_DIR/a-modules/webmap" ]; then
    mkdir -p "$HOME/.local/bin"
    cp "$SCRIPT_DIR/a-modules/webmap" "$HOME/.local/bin/webmap" && chmod +x "$HOME/.local/bin/webmap"
    echo -e "${BLUE}  - webmap → ~/.local/bin/webmap(A-联网认知:init/search/install/update)${NC}"
  fi

  # ④c B-opencode-env 插件部署(消息注入 env 块,三 Fragment)
  if [ -f "$SCRIPT_DIR/b-modules/opencode-env/.opencode/plugin.js" ]; then
    cp "$SCRIPT_DIR/b-modules/opencode-env/.opencode/plugin.js" "$CONFIG_DIR/plugins/opencode-env.ts"
    echo -e "${GREEN}  ✓ opencode-env 插件已部署 → plugins/opencode-env.ts(顶层 .ts 自动发现,env/git/codegraph 三片段)${NC}"
  fi

  # ④d D-opstate 部署(声明式状态对账 CLI)
  if [ -f "$SCRIPT_DIR/d-modules/opstate" ]; then
    cp "$SCRIPT_DIR/d-modules/opstate" "$HOME/.local/bin/opstate" 2>/dev/null || { mkdir -p "$HOME/.local/bin"; cp "$SCRIPT_DIR/d-modules/opstate" "$HOME/.local/bin/opstate"; }
    chmod +x "$HOME/.local/bin/opstate"
    echo -e "${BLUE}  - opstate → ~/.local/bin/opstate(D-声明式任务状态对账)${NC}"
  fi

  # ④e E-心跳 部署(实时心跳: 读审计流尾部算调用/速率/子代理;查询式零常驻税。
  #     MOD_DIR 副本已由上文 e-modules/*.sh glob 带走,此处只装 PATH 入口)
  if [ -f "$EMOD_SRC/heartbeat.sh" ]; then
    cp "$EMOD_SRC/heartbeat.sh" "$HOME/.local/bin/heartbeat" 2>/dev/null || { mkdir -p "$HOME/.local/bin"; cp "$EMOD_SRC/heartbeat.sh" "$HOME/.local/bin/heartbeat"; }
    chmod +x "$HOME/.local/bin/heartbeat"
    echo -e "${BLUE}  - heartbeat → ~/.local/bin/heartbeat(实时心跳: 读审计流算调用/速率/子代理)${NC}"
    case ":$PATH:" in
      *":$HOME/.local/bin:"*) ;;
      *) echo -e "${YELLOW}    ⚠ ~/.local/bin 不在 PATH,手动: export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}" ;;
    esac
  fi

  # ⑤ B-Ⅰ 环境画像(specs/B-environment.md Phase1)
  if [ -f "$SCRIPT_DIR/b-modules/env-profile.sh" ]; then
    cp "$SCRIPT_DIR/b-modules/env-profile.sh" "$MOD_DIR/" && chmod +x "$MOD_DIR/env-profile.sh"
    "$MOD_DIR/env-profile.sh" 2>/dev/null && echo -e "${GREEN}  ✓ 环境画像已生成(env-profile.md)${NC}" || true
  fi

  # ⑥ C-Ⅰ 自我画像(specs/C-embodiment.md)
  if [ -f "$SCRIPT_DIR/c-modules/self-portrait.sh" ]; then
    cp "$SCRIPT_DIR/c-modules/self-portrait.sh" "$MOD_DIR/" && chmod +x "$MOD_DIR/self-portrait.sh"
    "$MOD_DIR/self-portrait.sh" 2>/dev/null && echo -e "${GREEN}  ✓ 自我画像已生成(self-portrait.json)${NC}" || true
  fi

  # ⑦ D-preset-skills 部署(仓库→用户目录)
  if [ -d "$SCRIPT_DIR/preset-skills" ]; then
    for d in "$SCRIPT_DIR/preset-skills"/*/; do
      name=$(basename "$d")
      [ -f "$d/SKILL.md" ] || continue
      # mineru-local 仅随 INSTALL_MINERU=1 部署(MinerU 段 ⑦ 已接线; 未选装时不得经此 glob 误装)
      [ "$name" = "mineru-local" ] && [ "${INSTALL_MINERU:-0}" != "1" ] && continue
      if [ -d "$CONFIG_DIR/skills/$name" ]; then
        echo -e "${BLUE}  - skill $name 已存在,跳过${NC}"
      else
        mkdir -p "$CONFIG_DIR/skills/$name"
        cp -r "$d"* "$CONFIG_DIR/skills/$name/"
        echo -e "${GREEN}  ✓ preset-skill 已部署: $name${NC}"
      fi
    done
  fi

  # ⑧ subagent 路由自检(装后验证 librarian 模型跟随主配置)
  if command -v opencode >/dev/null 2>&1; then
    ROUTE_MODEL=$(python3 -c "import json;c=json.load(open('$CONFIG_DIR/oh-my-openagent.json'));print(next(iter(c.get('agents',{}).values(),{}).get('model','zhipuai-coding-plan/glm-5.3')))" 2>/dev/null || echo zhipuai-coding-plan/glm-5.3)
    [ -z "$ROUTE_MODEL" ] && ROUTE_MODEL=zhipuai-coding-plan/glm-5.3
    ROUTE_OUT=$(timeout -s KILL 60 opencode run --model "$ROUTE_MODEL" '回答:OK' 2>/dev/null | grep -c OK || true)
    ROUTE_OK=$(( ${ROUTE_OUT:-0} ))
    if [ "$ROUTE_OK" -gt 0 ] 2>/dev/null; then
      echo -e "${GREEN}  ✓ subagent 路由自检通过${NC}"
    else
      echo -e "${YELLOW}  ⚠ 路由自检未确认,手动验证:${NC}"
      echo "      opencode run --model $ROUTE_MODEL '回答:OK'"
    fi
    # patch 标记核对(两副本;自检必须能发现 patch 失效)
    PATCH_MARK=$(node -e '
const fs=require("fs");
const files=[process.env.HOME+"/.config/opencode/node_modules/oh-my-openagent/dist/index.js",
             ...fs.readdirSync(process.env.HOME+"/.cache/opencode/packages").filter(d=>d.startsWith("oh-my-openagent@")).map(d=>process.env.HOME+"/.cache/opencode/packages/"+d+"/node_modules/oh-my-openagent/dist/index.js")].filter(f=>{try{return fs.existsSync(f)}catch{return false}});
let hit=0,total=0;
for(const f of files){total++;try{if(fs.readFileSync(f,"utf8").includes("Model resolved via system default"))hit++}catch{}}
console.log(hit+"/"+total)' 2>/dev/null || echo "0/0")
    echo -e "${BLUE}  - omo patch 标记: $PATCH_MARK 副本命中(运行时副本未命中时重跑本脚本补打)${NC}"
  fi

  echo -e "${GREEN}  ✓ 安全/能力增强完成${NC}"
  echo -e "${BLUE}    模块: $MOD_DIR (权限红线/审计/自检/合规)${NC}"
else
  echo -e "${YELLOW}  ⚠ 未找到 e-modules（源码仓库外运行?）——跳过增强模块${NC}"
fi

step_end 12 "安全与能力增强"

# ------------------------------------------------------------------
# 完成
# ------------------------------------------------------------------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  OpenCode 配置完成!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}下一步:${NC}"
echo ""
echo "  1. 如需 API 提供商，编辑 opencode.json 添加 provider 配置:"
echo "     ${EDITOR:-vi} $CONFIG_DIR/opencode.json"
echo "     e.g. {\"provider\":{\"anthropic\":{\"options\":{\"apiKey\":\"sk-...\"}}}}"
echo ""
echo "  2. 如使用 DeepSeek 等兼容 API，baseURL 填:"
echo '     "https://api.deepseek.com/anthropic"'
echo ""
echo "  3. 调整模型路由（可选）:"
echo "     ${EDITOR:-vi} $CONFIG_DIR/oh-my-openagent.json"
echo "     为 agent 添加 model 字段即可覆盖默认模型，例如:"
echo '     "oracle": {"model": "deepseek/deepseek-v4-flash"}'
echo ""
echo "  4. 运行 OpenCode:"
echo "     opencode"
echo ""
echo "  5. 查看已安装的 skills:"
echo '     ls ~/.config/opencode/skills/   # superpowers 为插件,内置 /brainstorming 等斜杠命令'
echo ""
echo -e "${BLUE}配置文件位置:${NC}"
echo "  OpenCode:     $CONFIG_DIR/opencode.json"
echo "  模型路由:     $CONFIG_DIR/oh-my-openagent.json"
echo "  Claude 配置:  $CLAUDE_DIR/settings.json"
if [ "${INSTALL_GSD:-0}" = "1" ]; then
  echo "  GSD 工作流:   /gsd-help(已选装)"
else
  echo "  GSD 工作流:   未安装(INSTALL_GSD=1 可选装)"
fi
if command -v mineru >/dev/null 2>&1; then
  echo "  MinerU 解析:  mineru 命令已就绪(首次运行自动从 modelscope 下载模型)"
elif [ "${INSTALL_MINERU:-0}" = "1" ]; then
  echo "  MinerU 解析:  未装成(安装失败或 pip 缺失),手动: python3 -m pip install \"mineru[core]\"(PEP 668 系统加 --break-system-packages)"
else
  echo "  MinerU 解析:  未安装(大量解析 INSTALL_MINERU=1 本地档; 轻量用 Flash MCP, 见 README)"
fi
# MinerU agent 侧接线在场复核(动态判定: skill 目录 + mcp 段键; 收尾清单禁止静态列举)
if [ "${INSTALL_MINERU:-0}" = "1" ]; then
  MINERU_WIRE=""
  [ -f "$CONFIG_DIR/skills/mineru-local/SKILL.md" ] && MINERU_WIRE="mineru-local skill"
  if grep -q '"mineru-flash"' "$CONFIG_DIR/opencode.json" 2>/dev/null; then
    MINERU_WIRE="${MINERU_WIRE:+$MINERU_WIRE + }Flash MCP"
  fi
  if [ -n "$MINERU_WIRE" ]; then
    echo "  MinerU 接线:  $MINERU_WIRE 已部署(agent 即刻可调用; 隐私文档用本地 CLI, 便捷任务用 Flash MCP)"
  else
    echo "  MinerU 接线:  未部署(重跑 INSTALL_MINERU=1 ./setup-opencode.sh 可补)"
  fi
fi
# 选装汇总行: 按实际在场判定(装机选中≠装成——pip 失败链会静默跳过 MinerU/SkillOpt)
EXTRAS_SUM=""
[ "${INSTALL_GSD:-0}" = "1" ] && EXTRAS_SUM="GSD"
command -v mineru >/dev/null 2>&1 && EXTRAS_SUM="${EXTRAS_SUM:+$EXTRAS_SUM }MinerU"
if command -v mem0 >/dev/null 2>&1 || command -v skillopt-sleep >/dev/null 2>&1; then
  command -v mem0 >/dev/null 2>&1 && EXTRAS_SUM="${EXTRAS_SUM:+$EXTRAS_SUM }mem0"
  command -v skillopt-sleep >/dev/null 2>&1 && EXTRAS_SUM="${EXTRAS_SUM:+$EXTRAS_SUM }SkillOpt"
fi
[ -f "$CONFIG_DIR/plugins/sp-router.ts" ] && EXTRAS_SUM="${EXTRAS_SUM:+$EXTRAS_SUM }superpowers路由"
# DCP 存在"选中但 AGPL 门拒绝"中间态,以实际注册结果为准(与其安装段同一判据)
if grep -q 'opencode-dcp' "$CONFIG_DIR/opencode.json" 2>/dev/null; then
  EXTRAS_SUM="${EXTRAS_SUM:+$EXTRAS_SUM }DCP"
fi
if [ -n "$EXTRAS_SUM" ]; then
  echo "  已装组件(选装): ${EXTRAS_SUM}"
else
  echo "  已装组件(选装): 无(交互菜单或 INSTALL_*/SUPERPOWERS_ROUTER=1 可启用)"
fi
echo "  CodeGraph:    项目目录运行 codegraph init 生成索引"
echo ""
if grep -qi microsoft /proc/version 2>/dev/null; then
  echo -e "${YELLOW}⚠ WSL 注意事项:${NC}"
  echo "  Bun 路径已写入 ~/.bashrc，新终端自动生效"
  echo "  如果输入 'opencode' 仍报错 'node: not found'，请执行:"
  echo "    source ~/.bashrc"
  echo "  或重启终端"
fi

# 状态清单收尾写入(动态升级 P0): 以上所有步骤的在场事实落账,
# P1 --upgrade 以此还原选装上下文(不再依赖用户记得环境变量)
write_state_file

# P1 升级报告: diff 新旧状态清单(.prev 由 upgrade_restore_context 备份),
# 本次新装/仍缺失一目了然;考古路径无 .prev,不打报告
if [ "${UPGRADE_MODE:-0}" = "1" ] && [ -f "$CONFIG_DIR/.setup-state.json.prev" ]; then
  python3 -c "
import json
old=json.load(open('$CONFIG_DIR/.setup-state.json.prev')).get('components',{})
new=json.load(open('$CONFIG_DIR/.setup-state.json')).get('components',{})
gained=[k for k,v in new.items() if v and not old.get(k)]
lost=[k for k,v in old.items() if v and not new.get(k)]
print('升级完成: 本次新装:', '、'.join(gained) or '无', '| 仍缺失:', '、'.join(lost) or '无')" 2>/dev/null
fi
