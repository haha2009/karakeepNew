# Karakeep

一站式信息收藏与管理平台。Monorepo (Turborepo + pnpm)。单用户服务（产品经理 + AI 开发者）。

## 工作流

### 核心理念

**你只做两件事：提需求 + 验收，其余 Agent 干。**

### 部署守则

**⚠️ 严禁擅自推送到线上。每次上线必须经过用户明确同意并主动触发。**

工作流：改代码 → typecheck → **等待用户指令** → 用户执行部署脚本

### 你 vs Agent

| 你 | Agent |
|----|-------|
| "加个 X 功能" | 拆任务 → 改代码 → typecheck → 等你指令上线 |
| "改个 Y" | 定位 → 改 → typecheck → 等你指令上线 |
| "线上有问题" | 查日志 → 修 → typecheck → 等你指令上线 |
| "回滚" | 提供回滚命令，等你执行 |

### 部署命令参考（仅用户可执行）

| 模式 | 命令 | 耗时 | 适用场景 |
|------|------|------|---------|
| 热修复 | `bash scripts/hotfix.sh workers\|cli\|all` | ~30s | 纯 JS 改动（worker/CLI 逻辑） |
| 本地构建 | `bash scripts/build-deploy.sh` | ~5-15min | schema 变更、依赖改、前端、Dockerfile |
| CI 构建 | `push main` → CI → `bash scripts/deploy.sh` | ~12min | 需 ghcr.io 镜像的场景 |

### 安全保证

- **typecheck 是底线**：不通过不部署
- **自动健康检查**：HTTP 非 200 自动提示回滚命令
- **备份旧文件**：热修前自动备份原文件
- **回滚随时**：`docker compose up -d --force-recreate web` 恢复镜像版本

## 快速入口

- **快速部署** → `bash scripts/hotfix.sh workers`
- **完整构建** → `bash scripts/build-deploy.sh`
- **旧版 CI** → `bash scripts/deploy.sh`
- **部署纪要** → [.claude/deployment.md](.claude/deployment.md)
- **架构文档** → [docs/internal/architecture/](docs/internal/architecture/)

## 核心命令

| 命令 | 用途 |
|------|------|
| `pnpm typecheck` | 类型检查 |
| `pnpm lint` | 代码规范 |
| `pnpm format:fix` | 自动格式化 |
| `bash scripts/hotfix.sh workers` | 热修 worker（最快部署路径） |
| `bash scripts/build-deploy.sh` | 本地 Docker 构建 + 部署 |
| `bash scripts/deploy.sh` | 旧版：ghcr pull → SCP → 部署 |
