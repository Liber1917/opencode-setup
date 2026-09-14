# Facts
<!-- Durable truths about this project. Keep under ~50 lines.
     Add new facts here, archive oldest to memory-log.jsonl when it grows. -->
<!-- 模板来源: murillovp/persistent-memory docs/memory/facts.md (MIT) -->
- 一切"完成/已装"判定以实际在场为准(command -v / 文件存在 / 配置读取复核),不以退出码或"应该成功了"为准
- 宣称完成前必跑 completion-gate.sh check(e-modules/,git 卫生/测试/声明-在场一致/密钥四通道)
- 输出中文,中英文之间加空格排版
- 本地记忆层粘合自 murillovp/persistent-memory + LuciferForge/claude-code-memory(均 MIT),mem0 三件套(CLI/MCP/collector 云端方案)已退役
- 只存代码 tell 不了的: 用户偏好、纠错记录(错→改→因)、决策及原因、外部资源指针
