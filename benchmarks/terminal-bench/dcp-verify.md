# opencode-dcp 插件验证报告

- 日期: 2026-09-06
- 环境: 本机 (非容器), opencode 1.18.29 (/root/.bun/bin/opencode), 模型 zhipuai-coding-plan/glm-5.3
- 沙箱: HOME=/tmp/opencode/dcp-home (裸配置+auth 副本), 工作目录 /tmp/opencode/dcp-work{,-ctl}, 实验后已清理
- 数据来源: 沙箱 HOME 的 opencode.db (session/part 表逐条 JSON 解析), 非推断值

## 三问三答

| 问 | 答 | 关键证据 |
|----|----|---------|
| ① 装得上跑得通吗 | **能** | 官方 `opencode plugin @tarquinen/opencode-dcp@latest --global` 一次成功; echo 截获请求 tools 数组含 `compress` (11 工具之一) |
| ② 模型会自主 compress 吗 | **会 (自主触发档, 最优档)** | 单会话 9 轮任务内模型**自主调用 compress 4 次** (#1 R1 内 / #2 R6-7 / #3 R8 / #4 R9), 全程零人为提示; 第 5 次由 /dcp-compress 命令引导 |
| ③ 收益多少 | **末态上下文 -82%, 均值 -69%, 计费当量 -43%; 但未缓存 input +21% (缓存失效代价)** | 逐 fetch 上下文: 实验组峰值 39K→末段回落至 12.6K (锯齿), 对照组单调爬至 69.1K 无回落 |

## ① 安装与烟测

安装 (官方装法, npm 网络通, registry 走 npmmirror):

```
export HOME=/tmp/opencode/dcp-home
opencode plugin @tarquinen/opencode-dcp@latest --global
# → Installed @tarquinen/opencode-dcp@latest / Scope: global / Done
```

安装形态与受影响面 (全部在沙箱 HOME 内, 宿主 /root/.config 未动):

| 位置 | 内容 | 说明 |
|------|------|------|
| ~/.config/opencode/opencode.json | plugin 数组新增 `"@tarquinen/opencode-dcp@latest"` (1 行) | 唯一配置改动, 可逆 |
| ~/.cache/opencode/packages/@tarquinen/ | 包缓存 178MB (含依赖) | 运行时按 spec 解析, opencode 自管 |
| ~/.config/opencode/{package.json,package-lock.json,node_modules} | opencode plugin 命令生成的插件开发依赖 63MB | 副产物 |
| ~/.config/opencode/dcp.jsonc | 首次运行自动生成 (仅 $schema 行, 其余取默认) | DCP 自有配置, 与 opencode.json 分离 |

烟测 (echo 假 provider 截获法, 端口 8898 独立实例): 跑一条 "say hi", 截获的 anthropic 格式请求体 tools 数组:

```
['bash', 'compress', 'edit', 'glob', 'grep', 'read', 'skill', 'task', 'todowrite', 'webfetch', 'write']
```

`compress` 在列 → 插件加载成功且工具确实暴露给了模型。system prompt 中亦有 DCP 注入文本。

注意: 安装命令首次执行超时被杀 (2 分钟), 重跑约 3 分钟完成——大包下载, 一次性成本。

## ② 自主触发实验 (核心)

### 配置 (dcp.jsonc, 人为调低阈值以逼出 nudge)

```jsonc
"compress": {
  "minContextLimit": 8000,   // README 默认 50000
  "maxContextLimit": 16000,  // README 默认 100000
  "nudgeFrequency": 5,
  "nudgeForce": "soft"
}
```

调低理由: glm-5.3 上下文窗口大, 默认 50K/100K 在 8-12 轮内不可达。8K/16K 使 R1 (读 65KB 日志) 后即越过阈值。**此为实验加速, 生产默认值下结论外推需谨慎** (阈值越高触发越晚, 但机制相同)。

### 会话设计

单会话 ses_f8a62a78effeoFV8R4ELiAzr3h, 9 轮真实任务 (日志分析→统计→测试→修 bug→回归→双日志对比→写脚本→大输出压测→写总结), 每轮 `opencode run --auto --session <sid>` 接续, 真实工具输出 (read 65KB 日志/grep 80 条 ERROR/edit/测试)。

### compress 时间线 (db part 表逐条, role=assistant 即模型发起)

| # | 本地时间 | 所在轮 | 压缩规模 | 结果 |
|---|---------|--------|---------|------|
| 1 | 15:28:01 | R1 (读 app.log 后) | 5 messages | -29.3K removed, +581 summary |
| 2 | 15:32:08 | R6-7 (读 deploy.log 后) | 28 messages | -38.1K 累计/-7.9K 增量, +1.7K summary |
| 3 | 15:34:57 | R8 (80 条 ERROR 输出后) | 35 messages | -41K 累计/-2.9K 增量, +2.5K summary |
| 4 | 15:36:24 | R9 (写 SUMMARY 后) | 4 messages | 压缩最近任务段 |
| 5 | 15:37:01 | /dcp-compress 命令轮 | 4 messages (m0041-m0044) | 命令引导, 含完整结构化摘要 |

判定: **自主触发 (理想档)**。三次实测前科 (gsd-help 零次/skill 自发零次) 的"模型从不主动调用非必要工具"假设在 DCP 上**被证伪**。但必须如实归因: 模型自主调用发生在 DCP 自身向请求上下文注入 nudge 文本之后 (context-limit-nudge/turn-nudge, nudgeFrequency=5 即每 5 次 fetch 注入一次; R4 stdout 曾捕获到注入的 "Keep active context uncompressed / Compressed block context..." 提示文本, 为注入的直接证据)。即: **不是模型凭空想起 compress, 是插件持续推动 + 工具确实可用 + 阈值真实到达三者的合力**。这恰是 DCP 的设计机制, 不算人为干预, 但也不是"模型无私自觉"。

任务设计中"8 轮后无触发则加显式人为 nudge"一节: **跳过**——R1 即已自主触发, 无需人为推动。

### /dcp-compress 手动命令路径

`opencode run --command dcp-compress --session <sid>` 成功: 模型执行 range 模式压缩 (startId/endId/结构化摘要), 输出确认压缩生效。手动路径可用, 作为自主触发失效时的兜底。

## ③ 压缩收益实测 (同任务量对照组)

对照组: 同素材副本 + 同 9 条 prompt (路径替换), `--pure` (无任何插件), ses_f8a592c8affecjJdnbOVG2Pigp。

逐 fetch 上下文 (input + cacheRead, 取自 part 表 step-finish 的 tokens 字段):

| 指标 | 实验组 (DCP) | 对照组 (--pure) | 差异 |
|------|-------------|----------------|------|
| fetch 数 | 37 | 33 | — |
| 每 fetch 上下文峰值 | 39,219 | 69,102 | -43% |
| 每 fetch 上下文均值 | 15,696 | 50,167 | **-69%** |
| 末段上下文 (末 3 fetch) | ~12.6-13.2K | ~68.5-69.1K | **-82%** |
| 累计未缓存 input | 76,644 | 63,533 | **+21% (更贵)** |
| 累计 cacheRead | 504,128 | 1,592,000 | -68% |
| 计费当量 (input + cacheRead/10) | 127,056 | 222,733 | **-43%** |

曲线形态: 实验组呈**锯齿形** (涨至 ~38K → 压缩回落 ~10K → 再涨 → 再回落), 对照组**单调爬升无回落** (7K → 69K)。DCP 的核心价值在此: **上下文体积受控**, 长会话不会滚雪球, 峰值减半、末态 -82%, 直接延展会话寿命。

计费面两面性 (如实记录):
- 收益: 总处理 token 大降 (计费当量 -43%), 且上下文小 → 每请求更便宜, 幻觉面也小。
- 代价: 压缩改写历史 → 前缀缓存失效, 未缓存 input 累计 +21%; DCP 注入的 nudge/摘要文本本身也耗 token。**在高缓存命中、按 token 计费的场景, 短期账单可能反而略贵; 收益在长会话防膨胀与 cacheRead 减少上兑现**。

## AGPL 合规注记 (我们不默认装的理由)

DCP 为 **AGPL-3.0-or-later**。AGPL 的网络条款 (§13) 使"将其作为网络服务一部分提供"可能触发整体源码披露义务; opencode 插件与主进程同进程加载 (bun import), 属"合并工作"解释的灰色地带。组织合规策略通常将 AGPL 列为默认禁用、需法务逐案豁免的许可证。故: **实验/个人沙箱可用, 团队默认配置不装**; 若要引入需过合规评审, 并评估隔离边界 (如独立进程代理形态——作者的新项目 Sleev 即此路线)。

另注: DCP README 自述开发重心已转移至 Sleev (本地代理形态, 兼容 Claude Code/Codex/OpenCode), DCP 处于维护模式——选型时需考虑上游活跃度。

## 局限

1. 阈值 8K/16K 为实验加速值, 非默认; 默认 50K/100K 下触发会更晚, 但机制 (nudge→自主调用) 已被证实。
2. 单会话单模型 (glm-5.3) 单次运行; 模型行为有方差, 但 4 次自主触发跨 4 个不同轮次, 非孤例。
3. 对照组与实验组 fetch 数略异 (33 vs 37, 压缩轮多出的工具循环所致), 均值比较对此敏感度低, 结论不变。
4. 计费当量按 cacheRead=1/10 价估算, Zhipu 实际折扣价不同则数字等比变化, 方向不变。

## 清理记录

- 杀 echo 假服务 (端口 8898) 进程
- 删除 /tmp/opencode/dcp-home (含 db/dcp.jsonc/包缓存), /tmp/opencode/dcp-work, /tmp/opencode/dcp-work-ctl, /tmp/opencode/dcp-echo*, /tmp/opencode/dcp-pkg
- 宿主 /root/.config 与 /home/opencode-setup 除本报告外零改动; B 轮实验 (bg_dac0d8c7) 沙箱与 router-modules 未触碰
