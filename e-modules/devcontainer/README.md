# opencode-setup · C 档 devcontainer 说明

## 用途
在 Docker 容器内运行 opencode 的隔离环境模板 —— 适合不受信代码 / 多分支并行 / 依赖隔离 / 需要彻底隔离的高风险场景。

## 安全设计(对齐 spec E-2 C 档)
- **非 root**: `containerUser: vscode`(容器内最低权限,不跑 root)
- **权限最小化**: `--cap-drop=ALL` + `no-new-privileges`(容器内无法提权)
- **数据分离**: opencode 配置/历史挂独立 volume(`opencode-config` / `opencode-bashhistory`),宿主机目录不直接暴露
- **egress 白名单**: 需要更严格网络时可加 `--network none` 或自建代理网关;容器默认网络已比宿主机隔离一层
- **gh-proxy 镜像链**: postCreateCommand 走 ghfast.top 镜像拉 setup 脚本(国内友好)

## 使用
```bash
# 需要 devcontainer CLI
npm install -g @devcontainers/cli
cd 项目目录
devcontainer up --workspace-folder .
# 或 VS Code: Dev Containers: Reopen in Container
```

## 与 B 档(bwrap)的关系
| | B 档 bwrap | C 档 devcontainer |
|---|---|---|
| 隔离强度 | 进程级(共享内核) | 容器级(独立命名空间) |
| 开销 | ~2-3% CPU | ~5-10% + 镜像 |
| 适用 | 日常开发 | 不受信代码/多分支/数据库 |
| 默认 | 不装(选装) | 按需 |

## 注意
- 此模板是**起点**,生产使用请按项目补充: 依赖安装、端口、数据库等
- egress 白名单如果要严格化,需自建代理或用 `--network` 指定桥接网并配 iptables 规则(超出本模板范围,记入跟踪)
