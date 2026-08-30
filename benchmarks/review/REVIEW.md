# Code Review — opencode-setup 8 文件只读评审

- 日期: 2026-08-30 · 评审人: opencode (glm-5.3)
- 范围: `e-modules/gen-permissions.sh`, `e-modules/audit-init.sh`, `e-modules/security-check.sh`, `a-modules/webmap`, `b-modules/opencode-env/.opencode/plugin.js`, `d-modules/opstate`, `c-modules/self-portrait.sh`, `setup-opencode.sh`(重点 L790-880)
- 维度: **Bug**(shell 陷阱/边界) | **安全**(注入/密钥) | **健壮性**(降级)
- 复现环境: /tmp/opencode 沙箱;标注 `[已验证]` 的条目均在沙箱实际复现(含前一轮 T1-T3),其余为代码走查 `[走查]`
- 事故披露: 验证 gen-permissions 零参行为时,`bash e-modules/gen-permissions.sh`(无参)按预期触发自覆写 bug 损伤了仓库文件,已立即 `git checkout --` 还原,当前工作树干净(见 G-1,该事故本身即 bug 的实锤)

## 结论速览

**REQUEST_CHANGES** — 3 项 HIGH 集中在"安全模块自身的部署与生效路径"上:主脚本以相对路径调用会**静默跳过全部安全模块**(U-1);gen-permissions 参数解析可**自毁脚本**(G-1,已实测);webmap 的注入扫描控制 **fail-open**(W-1,已实测)。安全工具链的核心控制点不可靠,需修复后复审。

| 文件 | CRITICAL | HIGH | MEDIUM | LOW |
|---|---|---|---|---|
| gen-permissions.sh | 0 | 1 | 1 | 1 |
| audit-init.sh | 0 | 1 | 3 | 4 |
| security-check.sh | 0 | 0 | 3 | 5 |
| webmap | 0 | 2 | 2 | 3 |
| plugin.js | 0 | 0 | 2 | 3 |
| opstate | 0 | 0 | 4 | 4 |
| self-portrait.sh | 0 | 0 | 2 | 4 |
| setup-opencode.sh | 0 | 3 | 5 | 6 |
| **合计** | **0** | **7** | **22** | **30** |

---

## 1. e-modules/gen-permissions.sh

### G-1 · HIGH · Bug [已验证·T2 族] · L13-14 参数解析
`OUT="${@: -1}"` 的边界行为:
- **零参数**: bash 对 `$@` 的负偏移把 `$0` 计入,`"${@: -1}"` 展开为 **`$0`(脚本自身路径)** → `cat > "$OUT"` 用交互版模板**覆写脚本自身**,退出码 0(实测:`OUT=./gen-permissions.sh` 后脚本变为 41 行 JSON 残骸;本次评审即以此误伤仓库文件后还原)。
- **单个空参数** `""`: `OUT=""` → `cat > ""` 重定向报错,set -e 以 1 退出(实测 `one-empty OUT=[]`)。
- 用法注释标明 `[输出路径]` 可选,裸跑即触雷;setup 主流程带显式路径(L818)不受影响,但部署到 `$MOD_DIR` 后用户/agent 裸调用即毁模块。
**修复**: 显式解析参数,如 `OUT=""; for a in "$@"; do [ "$a" = --headless ] && HEADLESS=1 || OUT="$a"; done; [ -n "$OUT" ] || OUT=/dev/stdout`。

### G-2 · MEDIUM · Bug · L13-14 参数顺序耦合
`gen-permissions.sh <路径> --headless` 时"最后参数获胜":OUT 变为 `--headless`→`/dev/stdout`,路径参数被静默丢弃。修复:同 G-1 的位置参数/开关分离解析。

### G-3 · LOW · 安全 · L22-29 无头版 deny 名单可绕过
`curl*|*sh` 类 glob 挡不住 `curl -o f && bash f`、`python -c "$(curl …)"`、`source <(curl …)`;`"*": "allow"` 兜底放行其余一切。属设计折衷,建议在文档标注残余风险,或补充 `*sh *`/`source <*` 模式。

## 2. e-modules/audit-init.sh

### A-1 · HIGH · Bug/安全 [已验证·T3] · L63-64(hook.sh)printf 拼 JSON 不转义
`printf '{"…","session":"%s",…,"cmd":"%s"}\n' "$TS" "$TYPE" "$SESSION" "$TOOL" "$CMD"` —— sessionID/tool/命令串含 `"` 或 `\` 即产生**非法 JSONL**。实测 `cmd='git commit -m "fix && release"'` → `json.decoder.JSONDecodeError`。带引号的命令极常见,审计日志大面积不可解析,observe-only 审计链失效。**修复**: 用 python `json.dumps` 组装整行,或对四字段做 `${v//\\/\\\\}; ${v//\"/\\\"}` 转义。

### A-2 · MEDIUM · Bug [已验证] · L68 熔断器语义错误
第二次 `grep -E '"src":"(deny|reject)"'` 在 run-length 统计**之前**把 allow 行全部滤掉 → awk 的 D/X 分类永远为 D,统计的是"窗口内 deny 累计数"而非"连续 deny"。实测 5 次 deny 与 5 次 allow **交错**仍告警 `consecutive_denies: 5`,与 spec"单会话连续 deny ≥5"不符。另: `$SESSION` 未转义直接进 grep 模式(正则注入,sessionID 含 `.` 等会误配);`tail -8` 作用在过滤后(最近 8 条 deny 而非最近 8 条事件)。**修复**: 单条 awk 扫该 session 最近 N 条事件,统计**末尾连续** deny 长度。

### A-3 · MEDIUM · 健壮性 · L29-34 event 段整体覆写
`c["event"] = {四通道}` 直接替换 opencode.json 既有的全部 event hooks,无备份、无合并。用户已有 hook 配置会被静默清除。**修复**: `c.setdefault("event", {})` 后按键合并,写前留 `.bak`。

### A-4 · MEDIUM · 健壮性 · L82(GNU stat)+L10(readlink -f)
`stat -c%s`/`readlink -f` 均为 GNU 专属,macOS/BSD 下 `--rotate` 直接被 set -e 打死。**修复**: `SIZE=$(wc -c < "$LOG")` 或探测 `stat -f%z`;readlink 加 fallback。

### A-5 · LOW · 健壮性 · hook L49 `TYPE="$1"` 缺参时 set -u 崩溃,事件静默丢失(违反 observe-only 承诺)。修复: `TYPE="${1:-unknown}"`。
### A-6 · LOW · 健壮性 · alerts.jsonl 无轮转无上限,只清 `audit.jsonl*`。修复: 纳入 rotate()。
### A-7 · LOW · 安全 · 审计目录/日志默认 644/755,本机其他用户可读(脱敏后仍含命令轮廓)。修复: init 时 `chmod 700 "$AUDIT_DIR"` + `touch "$LOG" && chmod 600`。
### A-8 · LOW · Bug · L30-33 `f"{audit_dir}/hook.sh ask"` 路径含空格即断。修复: 走 argv 传参或文档约束。

## 3. e-modules/security-check.sh

### S-1 · MEDIUM · 安全 · L63-64 固定临时路径 /tmp/.es_danger
世界可写目录下的可预测文件名 + `>` 覆写,无 O_EXCL:预置符号链接即任意文件 clobber(CWE-377),以 root 跑 setup 时可打 /etc 下文件。**修复**: `tmp=$(mktemp)` + trap 清理。

### S-2 · MEDIUM · 健壮性 · L45-54 npm audit 判定 fail-open
空输出/超时被 `|| true` 吞掉后,只要不含 "error" 字样就落进 else 打印 **"✓ npm audit signatures 通过"** —— 无证据即通过。**修复**: 以 npm 退出码 + 非空输出为通过前提,否则输出"无法判定"。

### S-3 · MEDIUM · 健壮性 · L26 `stat -c%a` GNU-only
macOS 下 set -e 中途崩溃,自检半途而废(auth.json 权限检查不到)。修复: 同 A-4 可移植化。

### S-4 · LOW · 安全 · L17-21/39/71 `$CONFIG_DIR` 内插进 python 源码串(路径含 `'` 即语法错误,环境变量注入面)。audit-init 的 argv 传参是正确姿势,应统一。
### S-5 · LOW · 安全 · L20 明文 key 正则漏报: 不含 `.`(JWT)、<12 字符、`Authorization` 头等;启发式可接受,建议注释标注假阴性范围。
### S-6 · LOW · Bug · L48 `N=$(… | grep -ci …)` 与 U-3(T1)同族的脆弱写法,当前仅因分支前置匹配而幸免。
### S-7 · LOW · 健壮性 · L63 `timeout 30 grep … || true` 超时被截断的扫描按"干净"处理。修复: 区分 124 退出码。
### S-8 · LOW · 健壮性 · 退出码被调用方吞(setup L841 管道过 tail/sed 且无 pipefail,FAIL>0 不可见);L29/34 的 .gitignore/.env 检查在 CWD=$CONFIG_DIR 下执行(见 U-7),结果失真。

## 4. a-modules/webmap

### W-1 · HIGH · 安全 [已验证] · L26 scan_injection fail-open + rtk 硬依赖
`echo "$1" | rtk grep -qiE … && return 1 || return 0` —— rtk 缺失(127)或其 grep 出错时落入 `|| return 0` = **判定为干净**。实测无 rtk 时注入样文返回 0(clean)。S3 核心控制可静默失效,且把语义敏感的程序化匹配交给 rtk(输出压缩包装器,非字节等价 grep)。**修复**: `G=grep; command -v rtk >/dev/null && G="rtk grep"` 并令工具失败=拒绝(fail-closed)。

### W-2 · HIGH · 安全 · L55/L77 显式 name 未消毒 → 路径穿越
`name="${2:-…}"` 仅对**默认** slug 做了 sed 消毒,显式传入的 `$2` 原样进 `dest="$SKILLS_DIR/$name"` + `mkdir -p`:`webmap install x '../../.config/opencode/…'` 可在 skills 外任意落 SKILL.md(覆写 ~/.bashrc 等)。该工具定位为 agent 调用,提示注入即可驱使 agent 传恶意 name。**修复**: 对 `$2` 施加同一 `s/[^a-z0-9-]//g` 并校验非空。

### W-3 · MEDIUM · 安全 · L58 trusted 判定用子串+正则
`rtk grep -q "$domain" "$REG"`: `install com` 匹配任意含 "com" 的行 → trusted=yes;域名自身作为未转义正则。**修复**: `grep -qF "^$domain|"`。

### W-4 · MEDIUM · 安全 · L91 围栏逃逸
内容包在 ``` 围栏内,但原始 llms.txt 含 ``` 即突围,注入文本以正文身份进入 SKILL.md。**修复**: 四反引号围栏或剥离去界符。

### W-5 · LOW · Bug · L95/L101 installed.list 以空白分词,含空字段即错位(修 W-2 后收窄);末行无换行会被 read 循环丢弃。
### W-6 · LOW · 健壮性 · L22 无下载体积上限(仅 max-time);注释宣称"只碰 robots 协议区"但从未取 robots.txt,名实不符。
### W-7 · LOW · Bug · L74 严格解析仅验首行 `^#`,配合 W-3 的误判 trusted,防线偏薄。

## 5. b-modules/opencode-env/.opencode/plugin.js

### P-1 · MEDIUM · 安全 · L50-52 commit message 注入面
`git log -1 --oneline` 的提交主题(克隆仓库中攻击者可控)被注入到受信任的 env 块。**修复**: 只注 branch,或截断并显式标注"不可信数据"。

### P-2 · MEDIUM · Bug(文档/实现矛盾) · L9 vs L37/50/61
头注释声明"只读静态,不 spawn 命令(防 EDR)",实现却 `execFileSync('which'/'git')`。违反自家 spec 的合规口径。**修复**: 用 fs 遍历 PATH + `accessSync(X_OK)` 实现,或修订 spec。

### P-3 · LOW · Bug · L27-29 Failed 片段不缓存 → 每次 render 重试探(抖动);GitFragment 返回 null 时 state 永远 Pending,状态机失真。
### P-4 · LOW · Bug · L98 `unshift({...ref, type:'text', text})` 把源 part 的 tool/state 等杂字段克隆进伪 text part,opencode 收紧 schema 即碎。修复: 只 unshift `{type:'text', text}`。
### P-5 · LOW · 健壮性 · L37 `execFileSync('which')` 在极简容器可能无此二进制(应 fail-closed 却误报"未安装")。同 P-2 的 PATH 扫描方案可解。

## 6. d-modules/opstate

### O-1 · MEDIUM · Bug [已验证] · L89-90 claim/done 幂等假成功
对不存在 id 执行 `opstate claim t9 alice` → sed 未匹配仍 exit 0,输出 "✓ t9 → active(owner:alice)";done 同理(实测 STATE.md 未变,exit 0)。一个以"对账"为卖点的工具自身制造未感知漂移。**修复**: sed 前后 grep 校验行存在,否则报错退出。

### O-2 · MEDIUM · 健壮性 · L24 parse_tasks 依赖 rtk grep
rtk 缺失 → `|| true` 吞掉 → status 显示 0 任务、reconcile 空转,静默失效(与 W-1 同根)。**修复**: 普通 grep。

### O-3 · MEDIUM · 安全 · L73/81/89 sed 注入
`$1/$2`(id/owner)未转义进 sed 正则与替换串: `&`、`\`、`|`、`/` 可损坏 STATE.md 或改写他任务行。**修复**: 转义 `|[&/\` 或改用 awk/python 按精确 id 改写。

### O-4 · MEDIUM · Bug · L51 vs L24 双解析器语义分叉
python 路径要求行完整含 4 字段,手写 `## id | status: active`(无 owner/depends)对 python 不可见、对 shell 路径可见 → 同一文件两种 reconcile 结果。**修复**: 统一解析器(python 版兼容缺省字段)。

### O-5 · LOW · 健壮性 · L41-67 python3 存在但执行失败(文件不可读等)时被 set -e 击杀,不会回退 shell 路径(降级仅覆盖 python3 缺失)。修复: `python3 … || shell_fallback`。
### O-6 · LOW · Bug · L89 第二个 sed 分支在 pending-with-owner 行产生 `| |` 双竖线格式漂移。
### O-7 · LOW · 健壮性 · L85 `.bak` 清理在异常路径不执行,残留 STATE.md.bak。
### O-8 · LOW · Bug · L86 `[ "$DRIFT" = 0 ]` 字符串比较可用但与 `$((…))` 数值风格混用,易在重构中踩坑。

## 7. c-modules/self-portrait.sh

### C-1 · MEDIUM · 安全 · L39-50 shell 变量内插进 python 源码
`'''$MODELS'''` / `json.loads('''$AGENTS''')` 系拼接:模型名或 JSON 含 `'''` 或 `'` 即语法破坏乃至**任意 python 代码执行**;MODELS 来自 `opencode models`(注册表/网络数据,非全可信)。虽最终 `2>/dev/null || echo 生成失败` 兜底为优雅降级,但注入后果不可接受。**修复**: 数据走环境变量/argv,python 侧 `os.environ`/`sys.argv` 读取(仓库内 audit-init 的 argv 模式可抄)。

### C-2 · MEDIUM · 健壮性 · L12-18/21-26/28-37 裸 `except:` 吞一切(含 KeyboardInterrupt),错误无区分无日志。修复: `except Exception as e: print(…, file=sys.stderr)`。

### C-3 · LOW · Bug · L10 `opencode models | head -30` 的表头/ANSI 残留会混进 available_models。
### C-4 · LOW · 健壮性 · L51 最终 python 的真实报错被 `2>/dev/null` 全掩,"检查 python3"提示误导排障。
### C-5 · LOW · Bug · L20 `ls | wc -l` 数的是条目不是 skill 目录(散文件会虚增);security-check L61/72 同病。
### C-6 · LOW · 安全 · L50-52 先写后 chmod 600 存在世界可读窗口(内容按 spec 无密钥,影响小);失败路径 chmod 报错被 `|| true` 吞属正常降级。

## 8. setup-opencode.sh(重点 L790-880)

### U-1 · HIGH · Bug [已验证·沙箱模拟] · L807(+根源 L535) 相对路径致步骤 12 整体静默跳过
L535 `cd "$CONFIG_DIR"` 后,`[ -d "$(dirname "$0")/e-modules" ]` 在 `$0` 为相对路径(`./setup-opencode.sh`,仓库根直接跑的标准姿势)时相对 CONFIG_DIR 解析 → 恒为假 → **整个安全/能力增强步骤(权限红线/审计/自检/合规/画像/skills)全部跳过**,仅留一行黄色 ⚠"源码仓库外运行?"。沙箱同构模拟输出 `MODULES SKIPPED (bug)`。L847/853/859 同病。**修复**: 脚本顶部 `SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)`,后续一律 `$SCRIPT_DIR/…`。

### U-2 · HIGH · 安全 · L818 /tmp/.perm.json 固定可预测临时路径
`"$MOD_DIR/gen-permissions.sh" /tmp/.perm.json` 经 `cat > $OUT`(无 O_EXCL)写入世界可写目录:预置符号链接 → root 运行时任意文件覆写;写后读前被调包 → 任意 permission JSON 注入 opencode.json(如全量 allow);且**用后不清理**,残留待下次利用。**修复**: `PERM_TMP=$(mktemp)` + `trap 'rm -f "$PERM_TMP"' EXIT`。

### U-3 · MEDIUM · Bug [已验证·T1] · L875-878 路由自检 grep -c 双行
`ROUTE_OK=$(timeout 60 opencode run … | rtk grep -c "OK" || echo 0)` —— grep -c 零匹配时**先打印 "0" 再以退出码 1 触发 `|| echo 0`**,ROUTE_OK 变成两行 `"0\n0"`(实测),`[ "$ROUTE_OK" -gt 0 ]` 抛 "integer expression expected"(被 2>/dev/null 掩埋)→ 靠报错落进 warn 分支,结果碰巧正确、机制全坏;rtk 缺失(127)亦被同一 `||` 掩盖。**修复**: `ROUTE_OK=$(… | grep -c OK || true); ROUTE_OK=$((${ROUTE_OK:-0}))`,单值化后再比较。

### U-4 · MEDIUM · Bug · L818-832 权限合并的假成功回显
`echo "✓ 权限红线已合并"` 无条件执行:gen-permissions 失败(`&&` 短路跳过 merge)或 python 打印 `SKIP:` 时照样打 ✓,安装日志撒谎。**修复**: 捕获 merge 输出,按 `OK` 门控回显。

### U-5 · MEDIUM · 健壮性/安全 · L875-878 自检的模型调用与空参
每次安装真实烧一次模型调用(配额/费用/60s 延迟),应改 opt-in;内嵌 `python3 -c "…open('$CONFIG_DIR/…')"` 嵌套引号在路径含 `'` 时崩,model 取到空串时 `--model ""` 传**单个空参数**(T2 族),opencode 报错落 warn。**修复**: model 判空回退默认;自检加开关。

### U-6 · MEDIUM · 健壮性 · L838-841 模块失败静默 + 输出截断
audit-init 失败无任何回显(连 ⚠ 都没有);security-check 被 `| tail -3 | sed` 截断且管道无 pipefail、`|| true` 兜底,`FAIL>0 exit 1` 完全不可见。**修复**: `if ! cmd; then ⚠…; fi` 模式,至少透出汇总行与退出码。

### U-7 · MEDIUM · 健壮性 · L790-791 中途 source 用户 .bashrc
`. "$HOME/.bashrc" 2>/dev/null || true`:rc 文件含 `exit`(部分非交互守卫写法)会**当场杀死 setup**(静默,步骤 12 前);别名/函数/PATH 副作用不可控。L493 已自行 export PATH,此 source 收益仅"当前终端",风险不成比例。**修复**: 删除该 source,提示用户 `source ~/.bashrc` 即可。另 L535 起 CWD 恒为 CONFIG_DIR,security-check 的 .gitignore/.env 检查(S-8)与 `dirname $0` 判定(U-1)均受此影响。

### U-8 · MEDIUM · 健壮性 · L818-827 与 audit-init 的配置写入非原子
两个 python 写手都是 `open(p,'w')` 原地覆写 opencode.json:中途崩溃留下截断 JSON,无备份无 tmp+rename。**修复**: 写临时文件 + `os.replace`,保留 `.bak`。

### U-9 · LOW · Bug · L37 计时汇总 `seq 1 11` 但实有 12 步(step_end 12 永不出现在汇总表)。
### U-10 · LOW · 健壮性 · L87-89 存量配置时 `read -r overwrite`:管道安装(`curl|bash`)会读到脚本自身后续行或 EOF(set -e 死/自噬)。加 `[ -t 0 ]` 守卫并默认 n。
### U-11 · LOW · Bug · L922 `$GSD_DIR` 从未赋值(输出空);L901 `$EDITOR` 可能为空。
### U-12 · LOW · 安全 · L339/342/460 `curl | bash` 装 nodesource/bun:与自家权限红线 `curl*|*sh: deny` 双标,无校验和。至少文档明示供应链取舍。
### U-13 · LOW · 健壮性 · L617 omo 补丁 anchor 未命中时仅 ⚠ 降级(正确),但 `node` 此处才被依赖,此前仅在"缺失安装"分支保证,极端路径下可能未装即用。

---

## 系统性模式(跨文件)

1. **rtk 被用作程序化 grep**(setup L878、webmap L26/51/58/74、opstate L24/80):rtk 是面向 LLM 的输出压缩器,非字节等价 grep;缺失/变形即逻辑损坏,且多处 fail-open/静默(W-1、O-2、U-3)。建议:脚本内部一律用系统 grep,rtk 只留在交互展示层。
2. **安全控制 fail-open**:W-1(注入扫描)、S-2(npm audit)、A-5(hook 崩溃丢事件)——安全路径上工具失败应等价于"拒绝/未知",而非"通过"。
3. **GNU-only 假设**:`stat -c`、`readlink -f`(A-4、S-3)与"支持 Linux/macOS/WSL"的声明冲突。
4. **shell→python 源码内插**:S-4、C-1、U-5 vs 正面范例 audit-init L22(argv 传参)——应统一 argv/env 传参。
5. **固定 /tmp 路径 + 非原子写**:U-2、S-1、U-8,统一 mktemp + tmp/rename + trap 清理。
6. **假成功回显**:U-4(权限合并)、O-1(claim/done)、U-6(audit 静默)——运维日志必须与实际结果一致,这是审计型项目的基本要求。

## 验证记录(/tmp/opencode,关键命令与结果)

| # | 验证 | 命令(要点) | 结果 |
|---|---|---|---|
| T1 | grep -c 双行 | `out=$(printf 'hello\n' \| grep -c "OK" \|\| echo 0)` | `out=[0\n0]` 两行;`[ "$out" -gt 0 ]` 报整数表达式错 |
| T2 | 1 空参/零参 | `OUT="${@: -1}"` 三态测试(t2b.sh) | 零参 → `OUT=$0`(自覆写,bash -x 追踪实锤);1 空参 → `OUT=""`(cat 重定向失败);3 参 → 末参 ✓ |
| T3 | audit printf 引号 | 构造 `cmd='git commit -m "fix && release"'` 喂 printf 模板 | 产出非法 JSON,`JSONDecodeError` |
| V1 | 熔断器语义 | 同 session 交错喂 5×allow+5×deny 给 hook.sh | 触发 `consecutive_denies:5` 告警(非连续仍告警) |
| V2 | webmap fail-open | 无 rtk 环境跑 scan_injection 同构逻辑 | 返回 0 = "clean" |
| V3 | opstate 假成功 | `opstate claim t9 alice`/`done t9`(t9 不存在) | 均 "✓" + exit 0,STATE.md 未变 |
| V4 | setup 相对路径 | 沙箱同构模拟(cd 后测 `[ -d ./e-modules ]`) | `MODULES SKIPPED (bug)` |
| V5 | .bashrc return/exit | source 含 `return` 的 rc | `return` 安全(降级该 finding 至 MEDIUM,exit 风险仍在) |

## 最终裁定

### REQUEST_CHANGES

**TOP 3(修复优先级)**:
1. **U-1** setup-opencode.sh:807+535 —— 相对路径调用导致安全模块全家静默跳过。旗舰功能在最常见调用方式下不生效,且日志仅有易被忽略的一行 ⚠。修复成本一行(SCRIPT_DIR),收益最大。
2. **G-1** gen-permissions.sh:13 —— `"${@: -1}"` 零参自覆写(实测毁档、exit 0)/空参崩溃;叠加 U-2 的 /tmp/.perm.json 固定路径写入,同一写路径兼具自毁与符号链接攻击面。
3. **W-1+W-2** webmap:26/55 —— S3 注入扫描 fail-open(实测)+ 显式 name 路径穿越:两个安全护栏在边界条件下同时失效,而 webmap 的威胁模型恰恰是"不可信第三方内容"。

次级必改(复审前):A-1(审计 JSONL 损坏,T3)、U-3(T1)、U-4(假成功)、A-2(熔断语义)。
