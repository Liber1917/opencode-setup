#!/usr/bin/env bash
# opencode-setup · E-Ⅲ 合规文档生成器
# 依据: spec E-3 Ⅲ 证据披露 — 按地区生成合规说明 + provider 数据流向清单
# 用法: gen-compliance.sh [--region cn|eu|auto] [--provider 名称...]
set -euo pipefail
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
OUT_DIR="${OPENCODE_COMPLIANCE_DIR:-$CONFIG_DIR/compliance}"
REGION="auto"
while [ $# -gt 0 ]; do
  case "$1" in
    --region) REGION="$2"; shift 2;;
    *) break;;
  esac
done

# ── 地区检测(auto) ──────────────────────────
detect_region() {
  # 语言/时区启发式;可被 --region 覆盖
  local lang="${LANG:-}"
  case "$lang" in
    zh_CN*|zh_SG*) echo cn;;
    *) echo eu;;  # 默认欧盟(最严格)兜底,宁严勿松
  esac
}
[ "$REGION" = "auto" ] && REGION=$(detect_region)

# ── provider 数据流向清单 ────────────────────
PROVIDERS=""
if [ -f "$CONFIG_DIR/opencode.json" ]; then
  PROVIDERS=$(python3 -c "
import json
c=json.load(open('$CONFIG_DIR/opencode.json'))
provs=c.get('provider',{})
# 含模型路由里的 provider(oh-my-openagent)
import os
omo={}
omo_path=os.path.expanduser('~/.config/opencode/oh-my-openagent.json')
if os.path.exists(omo_path):
    try: omo=json.load(open(omo_path)).get('agents',{})
    except: pass
allp=set(provs.keys())|{v.get('model','').split('/')[0] for v in omo.values() if isinstance(v,dict)}
print(', '.join(sorted(allp)) or '未检测到')
" 2>/dev/null || echo "未知")
fi
[ -n "${1:-}" ] && PROVIDERS="$*"

# ── 生成 ────────────────────────────────────
mkdir -p "$OUT_DIR"
DOC="$OUT_DIR/COMPLIANCE.md"
TODAY=$(date '+%Y-%m-%d')

{
cat << EOF
# Agent 环境合规说明 (COMPLIANCE.md)

> 生成: $TODAY · 地区: $REGION · 由 opencode-setup 合规模块生成
> 本文档供自查与披露,不构成法律意见;重大合规事项请咨询专业人士。

## 一、数据流向清单

- 已配置 provider: ${PROVIDERS:-无}
- **出境判定**: 上述 provider 的 API 请求将离开本机发送至其服务端。
  境内用户请确认 provider 是否有境内合规接入点(如智谱/通义/百度等国内服务)。
- **本地保留**: 会话数据存于本机(~/.config/opencode, ~/.local/share/opencode,
  ~/.local/share/opencode-audit)。审计日志默认保留 30 天(可配置)。
- **离线模式**: offline 未开时,自动更新/会话分享/web UI 代理存在外联。

## 二、${REGION} 地区合规要点

EOF

case "$REGION" in
  cn)
cat << 'EOF'
### 中国境内
依据《生成式人工智能服务管理暂行办法》(2023-08-15 施行)及 GB/T 45654-2025《网络安全技术 生成式人工智能服务安全基本要求》:

1. **面向境内公众提供服务** → 需**安全评估**;具舆论属性/社会动员能力 → 需**算法备案**。
   个人开发者的本地工具场景通常不构成"面向公众服务",但使用场景扩张时需重新评估。
2. **深度合成内容标识**: 由 AI 生成、可能被误认为自然人的文本/图片等,建议添加标识。
3. **数据合规**: 训练/输入数据需有合法来源;涉及个人信息需取得同意。
4. **不得非法留存可识别身份的输入/使用记录**: 审计日志请启用脱敏,并按需缩短保留期。
   - 本项目已内置: 审计 hook 脱敏(密钥打码)+ 默认 30 天轮转清理 → 建议保留。
5. **联网外联**: 如使用境外 provider,注意数据出境合规(个人信息保护法)要求。

### 建议动作
- [ ] 确认是否构成"面向境内公众"场景,评估是否需要安全评估/备案
- [ ] 开启审计脱敏 + 30 天保留(已内置,确认未关闭)
- [ ] 评估数据出境: 境内 provider(智谱/通义/百度) vs 境外(Anthropic/OpenAI)
EOF
    ;;
  eu)
cat << 'EOF'
### 欧盟 (EU)
依据 EU AI Act(2026-08-02 起执法)与 GDPR:

1. **透明度义务 (Art. 50)**: 与 AI 系统交互时,应告知用户其在与 AI 交互。
   - AGENT-CARD.md 已生成,可作自助披露模板;面向第三方部署时需完整履行。
2. **GPAI 义务 (已生效)**: 若本环境中的模型属"通用目的 AI",运营者需满足
   文档/版权/训练数据透明度等义务(视角色而定)。
3. **数据最小化 (GDPR Art. 5(1)(c))**: 只处理完成任务所必需的数据。
   - 建议: 审计保留期 30 天已符合最小化原则;勿无故延长。
4. **数据出境**: 向非欧盟 provider 传输个人数据需 GDPR 第五章机制(标准合同条款等)。

### 建议动作
- [ ] 确认你在 EU AI Act 下的角色(提供者/部署者/用户),对应义务不同
- [ ] 面向他人/组织提供使用 → 确保 Art.50 透明披露(AGENT-CARD 基础上补充)
- [ ] 涉及个人数据处理 → 检查数据出境合法性(境内 EU 节点或 SCC)
EOF
    ;;
esac

cat << EOF

## 三、自检对照
- [ ] 本文档已随环境更新(建议每次 setup 重跑后刷新)
- [ ] AGENT-CARD.md 存在: \$(test -f "$CONFIG_DIR/AGENT-CARD.md" && echo "✓" || echo "✗ 缺失")
- [ ] 审计日志脱敏确认: \$(grep -q REDACT "$CONFIG_DIR/../.local/share/opencode-audit/audit.jsonl" 2>/dev/null && echo "✓" || echo "— 尚无日志")
EOF
} > "$DOC"

echo "✓ 合规文档生成 → $DOC (地区: $REGION, provider: ${PROVIDERS:-无})" >&2
