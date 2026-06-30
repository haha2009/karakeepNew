# 开发工作流协议

> 原则：小步快跑，持续验证。commit 快，push 前严。

## 循环速度

```
本地迭代：  git add → git commit  (10秒，turbo cache 保护)
验证推送：  git push              (1-2分钟，完整 QC)
生产部署：  deploy.sh rebuild     (2分钟，含自动备份)
```

## Commit 前（秒级，绝不阻塞）

```
✅ 快：workspace clean 检查 + format:fix
✅ 什么都不需要等，改了 → 提交 → 继续写
```

## Push 前（做完整 QC）

```
✅ lint + typecheck + build
✅ turbo cache 会加速第二次及以后的检查
✅ 失败了修完再推，不要 --no-verify 跳过（除非紧急 hotfix）
```

## Turbo 缓存策略

Turbo 的 `lint/typecheck/build` 对未变更的包返回缓存命中。
- 只改 web 包：其他 26 个包秒出
- 改了 db 层：db + 依赖它的包（api, web）重新跑，其余缓存
- **第一次最慢，后面飞起** — 所以别怕跑 full suite

## 什么时候跑全量命令

| 场景 | 跑什么 | 频率 |
|------|--------|------|
| 每 commit | pre-commit (秒级) | N 次/天 |
| 每 push | pre-push (分钟级) | 几次/天 |
| 怀疑缓存陈旧 | `pnpm typecheck` | 几天一次 |
| CI/CD 后强制 | — | 每次 PR |

## Sherif / open-api

- 不在 commit 流程里
- 每周跑一次即可：`pnpm exec sherif` + `pnpm run --filter @karakeep/open-api check`
- open-api 变更单独 commit

## 构建优化提醒

- `pnpm install` 用 `--frozen-lockfile` (CI) 或不加 (本地，允许更新)
- 原生模块 (better-sqlite3, sharp) 首次安装需要编译，约 2-3 分钟
- `turbo run build --continue` 可并行构建多个包
