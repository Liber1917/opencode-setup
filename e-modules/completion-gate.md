---
description: 出环硬门控——宣称完成前独立复核(git 卫生/测试/声明在场/明文密钥)
---

<goal>
出环验证(evidence-gated completion): 你即将宣称任务完成。完成时幻觉调研(arXiv 2606.09863)实测: 推理环内自评的假成功率 44-52%,双控(环内自评 + 环外机器脚本复核)压到 3%。现在由独立于你推理环的脚本复核你的完成声明,按退出码阻断/放行。这是 AGENTS.md 在场守则(一切"完成/已装"以实际在场为准)的机器执行层。
</goal>

<process>
1. 运行门控(在当前项目目录;不带 --message/--message-file,让门控从会话 DB 读你真实的最后一条 assistant 消息):

   bash ~/.config/opencode/opencode-setup-modules/completion-gate.sh check "$PWD"

2. 退出码 0 → 四通道复核通过,方可宣称完成。
3. 退出码 1 → 输出中每条 [✗] 行是一个未过项: 逐项修复(commit/跑过测试/纠正不在场的声明/清除密钥),再重跑本命令,直到退出码 0。退出码 1 时宣称完成 = 违反 AGENTS.md 在场守则。
4. 人工收尾只想看报告不阻断: 把 check 换成 report(恒退出 0)。
5. 不得绕过: 不改门控脚本、不伪造 --message 注入、不跳过未过项直接宣称完成。
</process>

<coverage>
声明-在场复核的名词映射为硬编码小批(opencode/mineru/skillopt/mem0/rtk/codegraph/bun/node + *.sh/*.json 等文件名模式),映射外不覆盖——门控输出会如实说明覆盖范围。
</coverage>
