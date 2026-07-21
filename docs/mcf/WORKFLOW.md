# 开发工作流

## 标准开发循环

```
1. 用户提需求
2. 读相关源码 + 读 AGENTS.md + 读 CLAUDE.md
3. 写简要计划 → 用户确认
4. 编码（一次改动，一个目的）
5. 验证（构建 + 测试 + 提交前清理）
6. 提交 → 用户验收
7. 有问题回到 4
```

## 提交前清理清单

每次提交前，按此顺序检查每一项：

### □ 调试残留

```
[X] 无 console.log / print / println
[X] 无 TODO / FIXME / HACK 标记
[X] 无 debugger / debug 语句
[X] 无被注释掉的旧代码（不要"留着备用"）
[X] 无临时文件（.tmp .bak scratch/ outputs/ *.log）
```

### □ 代码清理

```
[X] 删未使用的 import（你自己的改动造成的）
[X] 删未使用的变量/函数（你自己的改动造成的）
[X] 无重复代码
[X] 文件 ≤ 400 行
[X] 不改格式（不 prettier 没 prettier 过的文件）
```

### □ 验证

```
[X] 构建通过
[X] 测试通过
[X] lint 通过
[X] 改动最小——diff 每行都对应要求
```

### □ 提交信息

```
格式: <type>: <具体描述>
类型: feat / fix / refactor / docs / test / chore / perf
示例: "fix: 修复用户邮箱含大写字母时 user lookup 空指针"
"修 bug" → ❌ | "修了××情况下的××错误" → ✅
```

## 调试流程

1. 读完整错误消息和堆栈——不只看 ErrorType
2. 先复现——不能复现就不能验证修复
3. 一次改一个地方——改了三个 bug 消失你不知道哪个是真修了
4. 找根因，不加 workaround——null 突然出现就找出为什么 null。加个 null check 了事等于没修
5. 陷入僵局时——说出你试了什么、看到了什么、怀疑什么，不要随机尝试 20 次

## 提交规范

```
<type>: <简短描述>

可选：为什么（如果从描述看不出来）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

## 完成条件

1. 构建通过
2. 测试通过（新增代码有对应测试）
3. 无残留的调试语句
4. 无硬编码密钥
5. 依赖变更在 commit message 里说明了原因
6. 改动范围最小化
