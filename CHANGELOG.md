# Changelog

All notable changes to MCF (My Claude Framework) will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [v4.6.0] - 2026-07-19

### Added
- Self-improvement loop (6 Phase): Mine → Analyze → Apply → Verify → Snapshot → Anti-pattern
- Update mechanism: `update.sh` + `.framework-version` tracking
- Hook bypass whitelist: `.claude/hook-bypass.json` user-configurable
- Hook performance timing: logs to `.memory/hook-timing.log` when >500ms

### Changed
- AGENTS.md slimmed to 36-line router (was 180+ lines)
- Skills list moved to `docs/SKILLS.md`
- Hook error messages upgraded to 3-element format (what + why + how to fix)

### Verified
- Hook protection: 21/21 tests pass
- E2E injection: 18/18 tests pass
- Self-improvement: full 6-phase loop executes
