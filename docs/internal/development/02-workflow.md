# 开发工作流

## Superpowers 工作流

本项目严格遵循 Superpowers 方法论：

```
Brainstorm → Plan → Execute → Review → Finish
```

### 1. Brainstorm (设计先行)
- 新功能必须先设计，后编码
- 评估约束、探索替代方案、识别边缘情况
- 输出：设计决策文档

### 2. Plan (拆分任务)
- 将功能拆分为可独立执行的小任务
- 每个任务有明确的验收标准
- 输出：任务列表 (TaskCreate)

### 3. Execute (TDD 优先)
- 一次只做一个任务
- 优先测试驱动开发
- `pnpm typecheck` 类型验证
- `pnpm test` 测试通过

### 4. Review (代码审查)
- 每次任务完成后自我审查
- 关注正确性、可维护性、安全性
- 避免过度抽象

### 5. Finish (分支清理)
- 验证所有测试通过
- 清理控制台日志和调试代码
- Commit / PR

## 提交流程

```bash
git checkout -b feat/your-feature
# ... 开发 ...
git add <files>
git commit -m "feat: description"
```

Commit 格式：`type: description`

| type | 用途 |
|------|------|
| feat | 新功能 |
| fix | 修复 |
| refactor | 重构 |
| docs | 文档 |
| test | 测试 |
| chore | 杂项 |

## 代码质量门禁

每次提交前务必运行：

```bash
pnpm typecheck   # 类型检查 (无 --noEmit 错误)
pnpm lint:fix    # Lint 修复
pnpm test        # 测试通过
pnpm format:fix  # 格式化
```

## 分支策略

- `main` — 稳定分支，随时可部署
- `feat/*` — 功能分支，完成后 squash merge 到 main
- `fix/*` — 修复分支

## 数据库变更

1. 修改 `packages/db/schema.ts`
2. `pnpm db:generate --name <变更描述>`
3. 检查生成的 migration SQL
4. `pnpm db:migrate` 验证

## 子 Agent 使用

- 复杂代码分析和搜索用 `Explore` 类型 Subagent
- 独立模块用 Subagent 隔离上下文
- 避免在主上下文做深度代码搜索
