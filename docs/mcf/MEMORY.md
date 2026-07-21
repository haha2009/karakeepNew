# Memory 使用规范

> 你不需要 Agent 记住所有事。你需要 Agent 进入这个项目时，**自动知道这个项目发生过什么**。

---

## 三层记忆，按场景选

| 层 | 放哪 | 谁读 | 适合 | 状态 |
|---|---|---|---|---|
| **项目记忆** | `.memory/` (随 git) | 任何 Agent | 项目特有、跨会话需要 | ✅ MCF 默认 |
| **个人记忆** | `~/.claude/projects/<hash>/memory/` | Claude Code | 个人偏好、跨项目 | 已内置，MCF 不管 |
| **跨工具记忆** | Second Brain / Hermes Memory | 多工具统一 | 你有多个工具 + 愿意部署 | 可选升级 |

---

## 项目记忆（MCF 默认）

任何 Agent 进入项目都看 `.memory/`。零依赖，零安装，纯 markdown。

```
.memory/
├── README.md               ← 这个文件说明 .memory/ 是什么
├── decisions.md            ← 关键决策记录
├── context.md              ← 项目持续状态
└── 2026-07-15-add-login.md ← 阶段性工作记录（日期前缀）
```

### 使用规则

1. **写决策不写细节**：`decisions.md` 里只记"为什么这样选"，不是"怎么实现"
2. **持续状态进 `context.md`**：项目当前进行到哪、待办什么、卡在哪
3. **阶段性工作用日期前缀**：`YYYY-MM-DD-<name>.md`，自然时间排序，便于检索
4. **小步快跑**：每次 Agent 做完一件值得记的事，写一条到 .memory/，不要憋一周总结
5. **AGENTS.md 是规矩，.memory/ 是日记**——规矩不写在 .memory/，日记不进 AGENTS.md

### Agent 怎么读

项目根目录的 `AGENTS.md` 写明：

> 打开 `.memory/context.md` 了解项目当前状态。
> 修改前检查 `.memory/decisions.md` 是否已有相关决策。

这样 Claude Code、Codex、Cursor 任何工具进入项目都自动加载项目记忆。

---

## 个人记忆（Claude Code 自带）

存在 `~/.claude/projects/<hash>/memory/`，每次新会话自动加载前 200 行。

适合：
- 你的个人偏好（不是项目规则）
- 跨项目还成立的习惯
- 临时约定，不适合写进 AGENTS.md

**流转路径**：Prompt 重复提醒 2 次 → 记入个人 Memory → 第 3 次会话还在用 → 提炼进 AGENTS.md（或全局 `~/.claude/CLAUDE.md`），从 Memory 删除。

---

## 跨工具记忆（可选升级）

如果你用多个工具（Claude + Codex + Cursor 等），想要个人级统一记忆，可以接入：

**Second Brain**（[rahilp/second-brain-cloudflare](https://github.com/rahilp/second-brain-cloudflare)）
- 部署到 Cloudflare 免费层，自托管
- 通过 MCP 暴露 `remember` / `recall` 工具给所有支持的客户端
- 跨工具统一，但**独立于单个项目**

> [!WARNING]
> Second Brain 是个人级服务，不替代 `.memory/` 项目记忆。两者并存：项目记忆随 git，个人记忆随你。

---

## 注意

- 项目记忆随 git 提交——**敏感信息不要写**（密钥、密码、个人信息）
- 个人记忆换电脑不会自动同步——重要的提级到全局 CLAUDE.md 或 AGENTS.md
- 不要把 Memory 当 git log——git log 是机器读的，memory 是 Agent 读的，作用不同
