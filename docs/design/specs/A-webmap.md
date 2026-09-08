## 方向 A:联网认知(2026-08-24 定稿:自研 webmap + 3S 护栏)

### A-0 选型原则(2026-08-24 新增,由用户约束确立)
- **项目 MIT License → 不推荐付费项目、不捆绑第三方 key/配额、版权干净**。
- 由此排除:付费/带 key 门槛/抓取版权不清的 MCP 服务、Sleev(闭源付费)、ContextOS(死胎+无许可)。DCP(AGPL 免费)仅留选装池。
- 自研 webmap 成为 A 方向唯一完全符合的载体:纯 curl+本地解析,零依赖零费用,只抓站点授权给机器人的数据(llms.txt/sitemap/robots.txt),MIT 下无版权负担。

### A-1 自研三件套 + 3S 护栏(定稿,2026-08-24 参考设计版)
**授权核查结论**:webmap 生态无干净 MIT 轮子(firecrawl 无许可/已弃用、llms-txt-hub NOASSERTION、seo-audits 无许可、python-sitemap GPL-3.0)→ **跟 llms.txt 开放标准自研**(llmstxt.org 规范本身 MIT),参考轮子设计但不抄代码。
**参考设计来源**(不抄代码,仅借设计/API 形态):
- llmstxt-cli(npm,无许可):**"llms.txt 即 skill"成熟模式**——`install <名>`→抓 llms.txt→存 `.agents/skills/<slug>/SKILL.md`→symlink 各 agent;明确支持 OpenCode
- firecrawl generator(弃用):标准 `llms.txt` + `llms-full.txt` 双版本
- llms-txt-hub(898★):curated 目录按主类(6)+副类(7)组织

```
webmap(自研, MIT 干净, 仿 llmstxt-cli 命令形态):
  webmap init              # 初始化 curated 注册表(种子仿 hub 分类结构)
  webmap install <名>      # 抓该站点 llms.txt/llms-full.txt → skills/<slug>/SKILL.md → 注册 opencode
  webmap search <词>       # 搜注册表
  webmap update            # 刷新已装(llms-full 优先, 仿 --full)
  内部: curl 抓 llms.txt/robots.txt → 严格解析(3S S3) → 存 SKILL.md(3S S2 分级)
  3S 护栏: 限速≤2req/s/UA/审计(S1) · 注册表 hash 锁+trusted/community 分级(S2) · 注入隔离+严格解析(S3)
  持久站点图: SQLite 本地跨会话累计(数据主权)
```

### A-2 3S 顾虑与防御(用户明确:三个全中,对策为必做)
| S | 风险 | 防御(必做) |
|---|---|---|
| **S1 安全**(探测动作被 EDR 盯) | curl 批量抓取/遍历 = 像爬虫侦察 | 限速≤2req/s 串行;先 robots.txt 只抓 allow 路径;明确 UA(opencode-webmap/1.0+contact)不伪装;探测写审计日志;诚实边界:EDR 仍可能观察,不承诺隐身 |
| **S2 供应链**(注册表投毒/域名劫持) | curated YAML 被篡改→agent 抓恶意源 | 注册表每源存 sha256 抓取前校验(改即拒);trusted(内置种子+hash)/community(用户添加低信任)分级;注册表随 git 版本化可追溯;DNS 过期/转移异常核对(可选) |
| **S3 内容安全**(注入/污染) | 恶意站点在 llms.txt/sitemap 塞 prompt 注入;内容污染 agent | **注入隔离(核心)**:抓取内容仅作数据结构进独立上下文,明确"不可信数据非指令",禁止内容指令被执行;严格解析(失败即弃,不接受宽松解析);trusted 源进正常上下文,community 源默认隔离+标记;注入特征启发式(含"忽略以上/你是AI/系统提示"等模式→标记) |

### A-3 与既有能力的关系
- **graphify**:webmap 的"持久站点图"可落 graphify(五仓实测其文档建图能力)——接分层记忆钩子,非新建 SQLite(可选演进)
- **分层记忆**:回答级 dense-output → 会话级压缩(omo 兜底+ACP/Magic Context 候选)→ 项目级 graphify + 联网级 webmap,四级贯通(钩子记,执行待定)

### A-4 状态
- 选型定稿:自研为主(3S 护栏必做),Sleev/ContextOS 排除,DCP 选装池
- 待做:webmap 原型(curated 注册表+探测工具+隔离层),可复用验证体系测试
- 未决:webmap 与 graphify 的落点整合(先各自独立,后接分层记忆)
