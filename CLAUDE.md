@AGENTS.md
# CLAUDE.md — {{PROJECT_NAME}}

> 此文件仅补充项目专属配置。通用规则（Skills/PM 协作/编码标准）见 AGENTS.md。

---

## 项目信息

- **技术栈**：{{TECH_STACK}}
- **构建**：`{{BUILD_CMD}}`

---

## Hooks

> 本条规则 Agent **不能跳过**。CLAUDE.md 是软建议，Hooks 是硬拦截。

`.claude/settings.json` 预装 3 个 Hook 脚本（2 PreToolUse + 1 SessionStart）：

| 操作类型 | 拦截时机 | 拦截效果 |
|---|---|---|
| `npx/yarn/pnpm/bunx skills add` / `npx @anthropic-ai` | PreToolUse Bash | exit 2，阻止执行 |
| `git push --force` / `git reset --hard` / `git branch -D` | PreToolUse Bash | exit 2，阻止执行 |
| `rm -rf .claude/` / `rm -rf .agents/` | PreToolUse Bash | exit 2，阻止执行 |
| 删除/覆盖 `LOOP.md` / `STATE.md` / `gate.yaml` / `.env` / `CLAUDE.md` / `AGENTS.md` / `README.md` | PreToolUse Bash | exit 2，阻止执行 |

**Hook 覆盖边界**：仅 Bash 工具。Edit/Write 工具不受 Hook 拦截——关键文件保护靠 AI 遵守 AGENTS.md 规则。
---

## 设计质量

做 UI 相关改动必须按此顺序执行：

1. **读 [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md)**
2. **读 [docs/UIUX.md](docs/UIUX.md)**
3. **找 3 个已有页面或组件** — 理解项目 UI 风格
4. 编码

> 如有前端设计技能，装到 `~/.claude/skills/`。

---

## Memory

- **`.memory/`** — 项目共享记忆（随 git 提交），所有 Agent 可见
- **`~/.claude/projects/<hash>/memory/`** — 个人本地记忆（不提交）

详见 [docs/MEMORY.md](docs/MEMORY.md)。

---

## 完成后协议

1. 构建通过
2. 测试通过
3. 提交前清单全部打勾（见 [docs/WORKFLOW.md](docs/WORKFLOW.md)）
4. 无硬编码密钥/密码
5. 改动范围最小化
