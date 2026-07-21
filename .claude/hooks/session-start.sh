#!/usr/bin/env bash
# session-start.sh — SessionStart Hook
# 每次会话开始时重申框架核心规则（软提醒，不拦截）。
echo '{"systemMessage": "MCF 框架已生效: AGENTS.md 通用规则(多工具共享)+CLAUDE.md 项目专属+docs/按需详述。Skills:全局~/.claude/skills/,项目.claude/skills/。禁止npx skills add直写项目目录(Hook硬拦截)。开发前先读相关源码，改动后必须跑构建命令。危险git操作已被保护。"}'
exit 0
