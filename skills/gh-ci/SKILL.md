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

### 2026-09-29 gh-ci 操作教训

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 看到 `Build Android APK` conclusion=failure 就判定"构建挂了" | 误判为代码问题，实际 APK 构建全绿，只有最后一步分发上传失败 | 先 `gh run view <id>` 看 JOBS 步骤级状态：定位到**具体哪一步**红，再读那一步日志 |
| 把上传失败当成 workflow 逻辑 bug | 差点去改 curl/校验代码，而根因是链路速度 | 读取 `Upload response` 原文：`i/o timeout` = 网络层；`code!=0` = 业务层 |
| **用下载方向速度外推上传方向** | **结论完全反了**：据下行 426KB/s 判定"上传必然超时、无解"，实测上传 22.5s 成功 | 判定上传问题时**必须实测上传**；下行速度与上行无关，不可外推 |
| 单点采样就下"必然失败"的定论 | 写出"差一倍多、无解"的错误结论，差点劝退一次可成功的操作 | 先做一次**真实操作**（哪怕小样本）再定论；多采样只能说明稳定，不能说明方向 |

**根因模式（上传超时）——判据**：

- 日志特征：`r.ParseMultipartForm failed: read tcp ...: i/o timeout`，且重试恰好 ~61s 后返回（服务端 60s 读超时写死）
- **超时的是上行（server 接收），判据必须用实测的上传速度**：`文件大小 / 60s > 实测上传速度` 才成立
  - 反例（09-29 踩的坑）：实测下行 426KB/s 就写"57.7MB 需 135s ⇒ 无解"，但上行实测 22.5s —— 方向搞错，结论作废
- 与"服务端故障"的区分：本机能连上（`connect=` 极短、http_code=200）说明服务活着；此时直接测一次上传即可定论
- 正确处理：**先用同一路径实测一次真实上传**（用可用的小文件或直接传目标文件到临时 key）。
  上传通 ⇒ 本机直传补发即可（`gh run download <run> -n <artifact>` 后 `curl -F "file=@..."`）；
  上传也超时 ⇒ 才是链路/服务端真问题，这时才考虑改服务端读超时或分片
- 直传补发时**别覆盖线上 key 做实验**：先传到 `fr_probe_test` 之类临时 key 验证，确认通了再传 `fr_latest_apk`
- 升级信号：同一失败从 09-22 偶发 → 09-27、09-29 连续 ⇒ 要求改分片/resumable 上传或换分发通道，而非继续重试

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
