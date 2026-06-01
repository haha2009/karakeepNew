# 测试规范

## 测试策略

### 分层

| 层级 | 工具 | 覆盖目标 | 覆盖率要求 |
|------|------|---------|-----------|
| Unit | Vitest | 纯函数、工具、hooks | > 80% |
| Integration | Vitest | tRPC routers、service 层 | > 60% |
| E2E | Playwright | 核心用户流程 | 关键路径 |

### 优先级

1. 核心逻辑: bookmark CRUD、搜索、爬虫结果处理
2. 业务规则: 规则引擎、标签分配、去重逻辑
3. 复杂计算: AI 结果解析、数据处理管道
4. UI 交互: 推荐使用 E2E 测试覆盖

## 测试规范

### Unit Test

- 每个纯函数都应测试
- 使用 `describe` + `it` 组织
- 测试文件放在被测文件同目录，命名 `*.test.ts`
- Mock 外部依赖 (DB、AI API、MeiliSearch)

```typescript
// 示例结构
describe('bookmarkService.create', () => {
  it('should create a bookmark with valid URL', async () => {});
  it('should reject duplicate URLs for same user', async () => {});
  it('should queue crawler job after creation', async () => {});
});
```

### Integration Test

- 使用内存 SQLite + Drizzle 测试数据库
- 测试 tRPC router 的输入输出
- 覆盖错误情况: 未授权、不存在的资源、重复数据
- 测试完整流程: 创建 → 爬取 → 推理

### E2E Test

- 使用 `@karakeep/e2e_tests` 包
- Playwright 模拟浏览器操作
- 核心流程: 注册 → 添加书签 → 查看 → 搜索 → 删除
- 需要搭建完整测试环境 (Chrome + MeiliSearch + Workers)

## 命名规范

- 文件: `*.test.ts` 或 `*.spec.ts`
- 描述: 清晰说明测试场景和期望行为
- Mock 变量: `mockBookmarkData`、`mockUserId`

## CI 要求

- PR 合并前必须通过 `pnpm test`
- 新增功能需包含对应的测试
- 修复 bug 需添加回归测试
- 覆盖率不能低于合并目标 (新增代码建议 > 80%)

## 当前状态

- Vitest 已配置
- 基础测试框架可用
- **缺乏** E2E 测试覆盖
- **缺乏** 主要 tRPC router 的集成测试
- **缺乏** Worker 逻辑的单元测试
