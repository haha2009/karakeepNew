# 开发规范

## 项目规范

### 工作流

1. **设计先行**: 任何改动前理解目标和约束
2. **Plan 模式**: 非微小改动先出 plan，用户批准后执行
3. **TDD 优先**: 核心逻辑先写测试
4. **增量提交**: 每次完成独立功能点就 commit
5. **代码审查**: 提交前通读自己的 diff

### 分支管理

- `main` 分支保持可部署状态
- 功能分支: `feat/<简短描述>`
- 修复分支: `fix/<简短描述>`
- 使用 squash merge 保持线性历史

### Commit 规范

```
<type>: <简短描述>

<可选: 详细说明>
```

类型: feat / fix / refactor / docs / test / chore

### 代码质量门禁

```bash
# 提交前必须通过
pnpm typecheck    # 0 类型错误
pnpm lint:fix     # 0 lint 错误
pnpm test         # 所有测试通过
pnpm format:fix   # 格式正确
```

## 协作规范

### 沟通
- 问题描述清晰: 预期行为 vs 实际行为
- 遇到阻塞时记录当时的上下文和尝试过的方案
- 使用 `/compact` 管理上下文，避免 token 溢出

### 文档同步
- 功能变更同时更新相关文档
- API 变更同步更新 SDK 类型
- Schema 变更同步生成 migration

### 评审标准
1. 是否正确? (逻辑正确，处理了边界情况)
2. 是否安全? (输入验证、权限检查)
3. 是否可维护? (命名清晰，不过度抽象)
4. 是否高效? (SQL 查询合理，避免 N+1)

## 技术规范

### 数据库
- 不直接在代码中使用 SQL，全部通过 Drizzle API
- 涉及数据迁移时创建可逆的 migration
- 批量操作注意事务完整性

### API
- tRPC router 按资源拆分
- 所有 procedure 输入用 zod 验证
- 权限检查在每个 procedure 中显式进行
- 避免在 tRPC procedure 中直接操作文件系统

### Worker
- Worker 需要幂等设计 (可重复执行)
- 失败处理使用 Liteque 内置重试机制
- Worker 日志记录关键节点 (开始/完成/失败)
- 长时间 Worker 定期检查 cancellation signal

### 前端
- 使用 `useSuspenseQuery` 替代 `useQuery`
- 列表页使用 infinite scroll
- 表单使用 React Hook Form + zod 验证
- 图片使用 next/image 优化

## 安全规范

- 用户输入必须验证和转义
- 用户间数据严格隔离 (userId 绑定)
- API Key 只存 hash
- 不记录敏感信息到日志
