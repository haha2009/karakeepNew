# LOOP.md — 工程循环状态

> 本文件由 MCF 框架管理。记录当前自动化循环的状态。
>
> 引用: ArchiveExplorer "Loop and Harness engineering" (2026-06-28)
> 引用: 0xCodez "14-step roadmap from prompter to loop designer" (2026-06-09)

## 当前循环
- 状态: idle
- 启动时间: (未启动)
- 循环类型: none

## 循环配置
- 最大轮次: 10
- Token 上限: 40000
- 温度阈值: <90 启动 / >=95 停止
- 重复检测窗口: 3 轮
- invariant: 始终 block "rm -rf .claude/"

## 循环架构

### Harness 层 (静态,跨运行不变)
1. `CLAUDE.md` — 项目形态,<300 行,周修剪
2. `settings.json` — 工具 allowlist + hook 注册
3. `hooks/` — PreToolUse + PostToolUse + Stop 三层策略
4. `agents/` — 独立 verifier subagent(独立上下文验证)
5. `skills/` — SKILL.md 渐进披露
6. `.mcp.json` — MCP 连接器声明
7. `MEMORY.md` + vault — 跨会话状态 + 项目典籍

### Loop 层 (每次运行执行)
1. 目标规格 — PROMPT.md / AGENTS.md,每轮重读
2. Plan → Act → Verify — 独立上下文验证
3. Sub-agent fan-out — 并行独立任务
4. 调度器 + 持久化 — cron/launchd 触发,状态序列化
5. 失败防护 — 三大失败模式检测

### 失败防护 (Loop Guards)
- **Ralph Wiggum 检测**: 检测重复迭代(同动作签名连续 3 轮)
- **Context Rot 保护**: 强制摘要压缩(超 10 轮 / 40K token / 5 轮低多样性)
- **Token Budget**: 单次循环硬上限 40K token

## 最近 5 轮记录
| 轮次 | 时间 | 温度前 | 温度后 | 合入数 |
|---|---|---|---|---|
| (无) | | | | |

## 新增功能 (v1.1)
- `schedule-loop.sh` — launchd/systemd/cron 调度器集成
- `loop-guard.sh` — Ralph Wiggum + Context Rot 防护库
- `audit-skill.sh` — 技能安装前注入审计
- `worktree-manager.sh` — 并行 sub-agent worktree 隔离
- `comprehension-debt.sh` — comprehension debt 追踪
- `.claude/agents/verifier.md` — 独立验证 subagent
- `.claude/hooks/post-edit.sh` — PostToolUse 策略底线
- `.mcp.json` — MCP 连接器基线配置

## Gulli 21 模式对齐 (v1.2)

| 模式 | 章节 | 实现库 | 状态 |
|------|------|--------|------|
| Prompt Chaining | Ch.1 | self-improve.sh 流水线 | ✅ |
| Routing | Ch.2 | orchestration.sh | ✅ |
| Parallelization | Ch.3 | orchestration.sh | ✅ |
| Reflection | Ch.4 | reflection.sh | ✅ |
| Tool Use | Ch.5 | Bash/Edit/Read + MCP | ✅ |
| Planning | Ch.6 | self-improve 阶段 | ✅ |
| Multi-Agent | Ch.7 | orchestration.sh | ✅ |
| Memory Management | Ch.8 | MEMORY.md + memory.sh | ✅ |
| Learning & Adaptation | Ch.9 | self-improve 循环 | ✅ |
| MCP | Ch.10 | mcp-manager.sh | ✅ |
| Goal Setting | Ch.11 | exploration.sh | ✅ |
| Exception Recovery | Ch.12 | recovery.sh | ✅ |
| Human-in-the-Loop | Ch.13 | human-loop.sh | ✅ |
| RAG | Ch.14 | rag.sh + rag_reasoning.py | ✅ |
| Inter-Agent Comm | Ch.15 | mcp-manager.sh | ✅ |
| Resource-Aware | Ch.16 | orchestration.sh | ✅ |
| Reasoning | Ch.17 | rag_reasoning.py | ✅ |
| Guardrails/Safety | Ch.18 | Hook + safety.sh | ✅ |
| Evaluation & Monitoring | Ch.19 | VCR + snapshot + telemetry | ✅ |
| Prioritization | Ch.20 | orchestration.sh | ✅ |
| Exploration | Ch.21 | exploration.sh | ✅ |
