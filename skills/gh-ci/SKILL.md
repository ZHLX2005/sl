---
name: gh-ci
description: GitHub Actions CI 一站式：监控构建直到成功或失败（自动重试）、CI 失败后远程复现与诊断（debug workflow、拉取 Actions 环境日志）。当用户说"监控流水线 / monitor CI build / gh 监控 / 构建为什么挂了 / CI 失败了看看 / debug CI / 看看 Actions 日志 / 容器在 CI 里起不来"，或要求持续跟踪 GitHub Actions 构建状态、在 Actions 环境中复现本地无法复现的问题时使用。即使只是"看下 CI 状态"也应用本 skill 的 Monitor 铁律。
---
# GH CI — GitHub Actions 监控与远程调试

监控 GitHub Actions 构建直到成功或失败；失败后在 Actions 环境中远程复现诊断。

## 触发条件

| 用户说 | 动作 | 加载 ref |
| --- | --- | --- |
| "监控流水线" / "monitor CI build" / "gh 监控" / "看下 CI 状态" | 监控构建直到完成，失败时分析/重试 | [[monitor-build]] |
| "CI 失败了看看为什么" / "debug CI" / "容器在 CI 里起不来" / "要 Actions 环境的日志" | 创建 debug workflow 远程复现诊断 | [[remote-debug]] |

> 先监控后发现需要深挖 → [[monitor-build]] 拿到失败日志后接 [[remote-debug]] 复现。两者是同一条链的两段。

## Monitor 三铁律（两个场景共同的核心，先读这里）

1. **验证优于假设**：Monitor 返回 `completed` ≠ 任务完成。必须 `gh run view <run_id>` 验证真实状态后再操作——Monitor 的完成通知只代表轮询停止，workflow 可能还在跑或数据尚未落盘。
2. **Monitor/Loop 是用户特权**：永远不主动调用 TaskStop 取消 Monitor。等它自然结束；要停，让用户来。
3. **状态以 `gh run view` 为准**：任何一步基于状态的决策（读日志 / 重试 / 通知成功）之前，先用 `gh run view` 确认状态，不基于 Monitor 返回值推断。

## 主流程（3 步）

1. **识别诉求**：监控在跑的构建 → [[monitor-build]]；本地无法复现的失败要远程诊断 → [[remote-debug]]
2. **加载 ref 执行**：按 ref 的 SOP 走（Monitor 配置、日志命令、重试策略都在 ref 里）
3. **收尾**：按 Monitor 铁律验证状态后才报告结论；失败时先分析原因再问用户是否重试（代码错误 → 修代码；环境卡死 → rerun）

## 场景路由（ref-map）

| 场景 | 信号 | 何时读取 | 路径 |
| --- | --- | --- | --- |
| 监控构建（状态检查 / Monitor 配置 / 日志技巧 / 重试策略） | "监控流水线 / CI 状态 / 构建成功没" | 触发监控类诉求时 | references/monitor-build.md |
| 远程调试（debug workflow 模板 / 触发监控 / 拉日志） | "debug CI / 容器起不来 / 要 Actions 日志" | 触发远程诊断类诉求时 | references/remote-debug.md |

## AI 生成代码 Top错误事项(不超过5)

| 错误 | 后果 | 预防 |
| --- | --- | --- |
| Monitor 返回 completed 直接读日志 | 数据过时/不存在，基于假象下结论 | 先 `gh run view` 验证状态（铁律 1） |
| 主动取消 Monitor/Loop | 丢失监控能力，后续状态通知不可靠 | 用户特权，永不主动 TaskStop（铁律 2） |
| 用 `sleep && gh run list` 轮询 | 烧上下文、慢、容易错过状态变化 | 用 Monitor 持续监控，状态变化自动通知 |
| debug workflow 不设 timeout | 容器卡死烧掉 Actions 配额 | `docker compose up` 必须带 `timeout-minutes` |
| 构建失败不分析直接 rerun | 代码错误重跑还是挂，浪费一轮 13 分钟 | 先看失败日志分类：代码错误→修代码，daemon 卡死→rerun |

## 错误案例记录

每次执行后在下方追加操作教训：

```markdown
### [日期] gh-ci 操作教训

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| ... | ... | ... |
```

## 成功标准检查清单

- [ ] 任何状态结论都有 `gh run view` 输出背书（不基于 Monitor 返回值）
- [ ] 未主动取消过 Monitor/Loop
- [ ] debug workflow 的 `docker compose up` 带 `timeout-minutes`
- [ ] 失败时先给出失败日志的关键行，再给重试建议
- [ ] 成功时通知用户产物位置（如 APK 下载信息）

## 与其他 skill 的协作

```
gh-ci        →  GitHub Actions 监控 + 远程调试
git-workflow →  提交规范 / 版本语义化（触发构建的前置）
```
