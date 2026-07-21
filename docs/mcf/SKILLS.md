# 技能参考手册

> mattpocock 工程技能完整清单。inject.sh 自动安装到 `~/.claude/skills/`。

## 四条铁律对应

| 铁律 | 技能 | 何时用 |
|---|---|---|
| 1 先澄清 | `/grill-me` 或 `/grill-with-docs` | 非平凡任务开始前 |
| 2 共享语言 | `/domain-modeling` | 构建/更新 CONTEXT.md |
| 3 测试驱动 | `/tdd` | 实现功能或修 bug |
| 4 设计关怀 | `/to-spec` + `/improve-codebase-architecture` | 编码前设计 + 定期清理 |

## 用户调用技能

| 技能 | 用途 |
|---|---|
| `/ask-matt` | 推荐用哪个技能/流程(路由器) |
| `/grill-me` | 需求澄清面试(非代码场景) |
| `/grill-with-docs` | 需求澄清 + 构建领域模型 + 更新 CONTEXT.md/ADR |
| `/triage` | Issue 状态机流转(分类→确认→分配) |
| `/to-spec` | 对话转 spec,发布到 issue tracker |
| `/to-tickets` | 计划拆票(声明阻塞边) |
| `/implement` | 按 spec/ticket 构建,驱动 `/tdd` + `/code-review` |
| `/wayfinder` | 规划超大工作,拆 investigation tickets |
| `/setup-matt-pocock-skills` | 配置 issue tracker、标签、文档布局(每个项目跑一次) |
| `/teach` | 跨多会话教学新技能 |
| `/writing-great-skills` | 技能写作参考 |

## 模型自动调用技能

| 技能 | 用途 |
|---|---|
| `/tdd` | 红绿重构循环 |
| `/code-review` | 双轴审查(标准 + Spec) |
| `/diagnosing-bugs` | 系统化调试(复现→最小化→假设→修复) |
| `/domain-modeling` | 构建领域模型,更新 CONTEXT.md |
| `/codebase-design` | 深度模块设计(多功能+小接口) |
| `/prototype` | 一次性原型验证设计 |
| `/research` | 深度研究,输出引用 Markdown |
| `/resolving-merge-conflicts` | 按意图解决合并冲突 |
| `/handoff` | 上下文交接文档 |
| `/improve-codebase-architecture` | 扫描泥球 + 清理建议 |
