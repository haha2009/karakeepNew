# 会话收尾检查清单

> 每次会话结束前,逐项检查。不通过项修复后再提交。

## 环境
- [ ] 标准启动路径可用(`init.sh --verify-only`通过)
- [ ] 无未记录的依赖变更

## 进度已更新
- [ ] claude-progress.md 已更新(当前状态/已完成/进行中/下一步)
- [ ] feature_list.json 状态与实际一致

## 功能清单真实
- [ ] feature_list.json 中标记为 passing 的功能确实通过了 verification command
- [ ] 无未记录的半成品

## 代码质量
- [ ] 所有测试通过
- [ ] Lint 无报错
- [ ] 无硬编码密钥或敏感信息

## 提交就绪
- [ ] 所有已完成的变更已提交 git
- [ ] commit message 说明了做了什么和为什么
- [ ] 下个会话可以直接运行 init.sh 接手

## 下一步明确
- [ ] claude-progress.md "下一步"部分有清晰的后续行动
- [ ] 如有阻塞,已记录原因和绕过方案
