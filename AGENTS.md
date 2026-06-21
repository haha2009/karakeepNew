# Karakeep

一站式信息收藏与管理平台。Monorepo (Turborepo + pnpm)。单用户服务（产品经理 + AI 开发者）。

---

## Agent 守则（所有 Agent 必须遵守）

### 核心理念

**你只做两件事：提需求 + 验收，其余 Agent 干。**

### 第一原则：先读后写

- 编辑文件前必须先读取。
- 用 file-picker / code-searcher / read_files 获取上下文。
- 修改导出符号后，必须更新所有引用。

### 第二原则：质量优先

- 优先正确性。每次改动后 spawn code-reviewer-deepseek-flash。
- typecheck 是底线——不通过不提交。

### 第三原则：最小改动

- 只改用户要求的内容，不顺手优化未涉及的部分。

### 第四原则：不擅自动线上

- 严禁擅自推送到线上。必须用户明确同意并主动触发。

---

## 提交前清理（不可跳过）

每次 commit 前必须先清理工作区。

### 清理流程

1. bash scripts/clean-workspace.sh --dry-run  — 预览
2. bash scripts/clean-workspace.sh --force     — 执行
3. pnpm preflight                              — typecheck+lint+format
4. git add -A                                  — 暂存
5. git commit -m "..."                         — 提交

### 清理范围

- 备份文件: *.bak, *.bak2, *.backup, *.new, *.working, *.template
- 临时文档: ACCEPTANCE_*.md, FINAL_*.md, TASK_*.md, *_CHECKLIST.md 等
- 临时 JSON: *-todos*.json, mark-*.json, complete-*.json 等
- 一次性 .sh: 白名单 start-dev.sh, do-build.sh, karakeep-linux.sh
- 异常目录: 单引号或空格开头

### 安全规则（永不删除）

1. Git 跟踪的文件
2. 白名单中的文件
3. 受管目录中的正规产物 (.codestable/, scripts/, docs/, docker/)
4. .gitignore 排除的目录

---

## Commit 前检查清单

1. bash scripts/clean-workspace.sh --check （工作区干净）
2. pnpm preflight （typecheck+lint+format 通过）
3. code-reviewer-deepseek-flash （代码审查）
4. git add -A && git commit -m "..."

---

## 核心命令

pnpm typecheck        — 类型检查
pnpm preflight        — 一站式检查
bash scripts/clean-workspace.sh --dry-run  — 预览清理
bash scripts/clean-workspace.sh --force     — 执行清理
