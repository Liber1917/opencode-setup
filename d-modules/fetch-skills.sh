#!/usr/bin/env bash
# D: 按需摘取上游单点 skill 指引(mece/prd-writing/skill-creator, spec D-2)
# 版权边界: 无 LICENSE 声明的仓库不自动集成(保持 MIT 干净), 打印手动指引
set -euo pipefail
echo "上游单点 skill 手动获取指引(spec D-2):"
echo "  mece-skill:    git clone https://github.com/uxderrick/mece-skill → 拷 SKILL.md"
echo "  prd-writing:   https://github.com/assimovt/productskills → skills/prd-writing/"
echo "  skill-creator: https://github.com/anthropics/skills → skills/skill-creator/(官方)"
echo "注: 无 LICENSE 声明的仓库不自动拷贝, 用户自担(版权边界)"
