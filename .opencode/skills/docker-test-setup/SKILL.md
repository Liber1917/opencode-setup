---
name: docker-test-setup
description: 用 Docker 容器矩阵测试 setup-opencode.sh（干净环境全流程 / deb822 / 断网 / 幂等）。修改 setup-opencode.sh 后必须跑本 skill 的测试矩阵。
---

# Docker 测试 setup-opencode.sh

## 何时使用

修改了 `setup-opencode.sh` 后、提交前。脚本会改系统配置、装大量软件,绝不能在真实环境直接跑——Docker 容器是唯一安全的回归方式。

## 测试矩阵

```bash
cd opencode-setup
docker pull ubuntu:22.04 ubuntu:24.04

# 1. 全流程(22.04 传统 sources.list): 必须退出码 0, 11 步全完成
docker run --rm -v "$PWD/setup-opencode.sh:/setup.sh" ubuntu:22.04 bash /setup.sh

# 2. deb822(24.04 ubuntu.sources 格式): 必须退出码 0
docker run --rm -v "$PWD/setup-opencode.sh:/setup.sh" ubuntu:24.04 bash /setup.sh

# 3. 断网降级: 不崩溃, 优雅失败 + 计时汇总
docker run --rm --network none -v "$PWD/setup-opencode.sh:/setup.sh" ubuntu:22.04 bash /setup.sh

# 4. 幂等: 同一容器跑两次, 第二次也退出码 0
docker run --name setup-test -v "$PWD/setup-opencode.sh:/setup.sh" ubuntu:22.04 bash /setup.sh
docker start -ai setup-test
docker rm setup-test
```

完整跑一次约 10-15 分钟(下载 node/bun/opencode 等),建议用 `timeout 900` 包裹。

## 断言清单

跑完后检查(容器内或日志):

1. **退出码 0**(全流程/幂等);断网场景允许非 0 但必须有汇总表
2. **汇总表 11 步齐全**(计时功能):`=== 各环节耗时 ===` 出现 11 行
3. **codegraph 注册为绝对路径**:
   ```bash
   node -e 'const c=JSON.parse(require("fs").readFileSync("/root/.config/opencode/opencode.json")); console.log(JSON.stringify(c.mcp.codegraph))'
   # 期望: {"type":"local","command":["/usr/bin/codegraph","serve","--mcp"],"enabled":true}
   ```
4. **opencode.json 无 anthropic provider**:`grep -c anthropic` = 0
5. **node/bun 实际可用**:`node --version`、`bun --version` 有输出
6. 关键产物存在:`/usr/local/bin/node`、`~/.bun/bin/bun`、`/usr/local/bin/opencode`

## 排障经验(血泪史)

### set -e 陷阱(最容易踩)

`set -e` 下,**命令替换内的失败命令会让脚本直接退出**,即使结果被 if 条件使用:

```bash
# ✗ BUG: codegraph 不存在时 command -v 返回非零 → 赋值语句退出码非零 → set -e 退出
CG_BIN="$(command -v codegraph 2>/dev/null)"

# ✗ BUG: 任一镜像 curl 超时(28) → 整个测速循环崩溃
S="$(curl -fsSL --max-time 10 ... 2>/dev/null)"

# ✓ 修复: 管道/命令末尾加 || true
CG_BIN="$(command -v codegraph 2>/dev/null || true)"
S="$(curl ... 2>/dev/null || true)"
```

排查法:脚本退出码 127 = command not found;28 = curl 超时;1 = set -e 普通失败。日志里"横幅后无任何输出直接跳汇总"= 该步骤第一行命令替换炸了。

### SUDO 空展开

```bash
SUDO=""   # root 环境
# ✗ BUG: 空展开后变成执行 `-E` 命令 → 127
curl -fsSL URL | $SUDO -E bash -
# ✓ 修复
curl -fsSL URL | ${SUDO:+$SUDO -E }bash -
```

`$SUDO` 开头的命令空展开没问题(如 `$SUDO apt-get` → `apt-get`),但选项开头的会炸。

### 干净镜像缺命令

ubuntu 容器无 curl/sudo/unzip。脚本已自动处理:早期 apt 安装 curl、无 curl 跳过 apt 测速、SUDO 自动判定。若新增依赖命令,记得加缺失检测。

### 验证技巧

- 隔离环境变量:`HOME=/tmp/fake SKIP_APT_MIRROR=1 bash setup-opencode.sh`(真实系统上安全跑)
- 快速复现某一步:提取步骤代码段到单独脚本 + 隔离 HOME 执行
- 模拟 npm 卡死:`timeout 5 npm i -g --registry=http://10.255.255.1:1/ pkg`