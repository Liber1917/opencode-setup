# AGENTS.md 工程守则(全部来自实测事故)

## 核心守则:汇报与事实一致(三犯同源)

**一切"完成/成功/已装"的判定与汇报,以实际在场为准(command -v / 文件存在 / 配置读取复核),不以命令退出码或"应该成功了"为准。**

事故存档(为什么有这条):

1. 2026-08 权限合并假成功: except 分支静默重置配置,无条件打 "✓ 已合并"(AI 评审 U-4 抓出)
2. 2026-08 opstate claim 假成功: sed 不匹配仍 exit 0 照打 "✓"(评审实测 t9 复现)
3. 2026-09 收尾清单撒谎: MinerU 因 pip 缺失跳过安装,收尾却列进 "已装组件"(oct 真机)

## 派生规则

- 装包/安装类: 结束后 `command -v <工具>` 复核;退出码非零但工具在场 = 成功(信号杀包装进程 ≠ 安装失败,oct 实测);在场才算数
- 收尾清单: 动态生成(逐项查在场),禁止静态字符串列举"应该装的"
- 写配置: try/except 救援后必须复核关键字段仍在,救援 ≠ 静默清空
- 长任务/外部信号环境: 判定用事实复核,进程退出码只是线索(set -e 会被信号误导)

## 机器执行层

- completion-gate.sh(出环硬门控): 宣称完成前跑 `completion-gate.sh check`——git 卫生/测试通过/声明-在场一致/明文密钥四通道独立复核,任一未过退出码 1。双控防完成时幻觉假成功(arXiv 2606.09863 实证 44-52%→3%),见 e-modules/。

## 其他项目约定(简短)

- MIT/免费立场: 不推荐付费,AGPL 选装必须双重知会 + 确认门
- 真实环境测试优先: Docker 干净容器测不出第三方源/内存/信号类问题;每个产品决策要有 benchmark 背书
- 中文输出,中英文空格排版

## Memory

This repo keeps persistent context in `docs/memory/`.
- At the start of a task, read `docs/memory/facts.md` (kept under ~50 lines).
- When you complete a milestone, make a decision, or hit a pitfall, append to `docs/memory/memory-log.jsonl`.
- Search past context with `grep -i "<term>" docs/memory/memory-log.jsonl`.
- Project context belongs in `docs/memory/`, not in your built-in or local memory system.

(契约原文来源: murillovp/persistent-memory, MIT;主题模板与反记忆清单来源: LuciferForge/claude-code-memory, MIT)

### 不要存进记忆的东西(代码能 tell 你的都不存)

- 代码规范/文件路径/git 历史/具体 bug 修复方案
- 只存: 用户偏好、纠错记录(错→改→因)、决策及原因、外部资源指针

### facts.md 上限 50 行,超限把最旧的搬入 memory-log.jsonl(type:"fact-archive")
