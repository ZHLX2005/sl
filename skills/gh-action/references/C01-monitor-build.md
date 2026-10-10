# C01-monitor-build — 构建监控 SOP（Monitor 直到成功或失败）

> 来自原 `gh-ci` skill（其前身为 `gh-ci-monitor`）。监控在跑的构建、持续跟踪状态变化、失败后分类处理。

## 何时读取

用户说"监控流水线 / monitor CI build / gh 监控 / 看下 CI 状态 / 构建为什么挂了"时加载本 ref。拿到失败日志后需要进 Actions 环境复现深挖 → 接 [[C02-debug-workflow]]（监控链下一段）；只要 gh 排障命令全集（不监控）→ 接 [[B01-gh-troubleshoot]]。

## Monitor 三铁律（先读这里）

1. **验证优于假设**：Monitor 返回 `completed` ≠ 任务完成。必须 `gh run view <run_id>` 验证真实状态后再操作——Monitor 的完成通知只代表轮询停止，workflow 可能还在跑或数据尚未落盘。
2. **Monitor/Loop 是用户特权**：永远不主动调用 TaskStop 取消 Monitor。等它自然结束；要停，让用户来。
3. **状态以 `gh run view` 为准**：任何一步基于状态的决策（读日志 / 重试 / 通知成功）之前，先用 `gh run view` 确认状态，不基于 Monitor 返回值推断。

## 工作流程

### 1. 检查当前构建状态

先获取当前最新构建列表：

```bash
gh run list --limit 1
```

判断状态：

- `in_progress` → 构建进行中，开始监控
- `completed success` → 构建已成功，通知用户
- `completed failure` → 构建失败，询问是否重试

### 2. 启动 Monitor 监控

使用 Monitor 工具持续监控：

```
描述: GH CI build monitor
timeout_ms: 600000 (10分钟超时)
persistent: true
command: gh run list --limit 1
```

Monitor 返回 `completed` 状态时，**先按铁律 1 验证真实状态**，再继续。

### 3. 验证构建结果

```bash
gh run list --limit 1
gh run view <run_id> --log 2>&1 | grep -E "FAILURE|error" | head -5
```

- 成功 → 通知用户，提供产物下载信息
- 失败 → 分析错误原因，询问是否重试

### 4. 构建失败处理

```bash
# 重新触发构建
gh run rerun <run_id>

# 或创建新构建（对于 PR）
gh pr checkout <pr_number> && git push
```

## 关键经验

### Monitor 工具使用要点

1. **persistent:true** — 设置为持久模式，持续监控直到 TaskStop 或会话结束
2. **timeout_ms** — 最大监控时间，建议 600000ms（10分钟），正常构建约 13 分钟
3. **不要用 sleep 轮询** — Monitor 会自动在状态变化时通知，不要用 `sleep && gh run list` 轮询
4. **Monitor stream ended** — 这只是意味着轮询停止，不代表构建完成，需要再次检查 `gh run list`（铁律 1 的具体表现）

### 危险节点识别

通过 `gh run list` 发现之前失败的时间点，预判本次构建的风险窗口。

### 日志查看技巧

```bash
# 查看失败原因
gh run view <run_id> --log 2>&1 | grep -E "FAILURE|error" | head -10

# 查看 Gradle 构建详情
gh run view <run_id> --log 2>&1 | grep -B5 -A5 "Running Gradle"

# 查看所有注释/警告
gh run view <run_id>  # 显示 ANNOTATIONS
```

### 重试策略

- **代码错误** → 先修复代码再重试
- **超时不响应** → 可能是 gradle daemon 卡死，直接 rerun

## AI 生成代码 Top错误事项(不超过5)

| 错误 | 后果 | 预防 |
| --- | --- | --- |
| Monitor 返回 completed 直接读日志 | 数据过时/不存在，基于假象下结论 | 先 `gh run view` 验证状态（铁律 1） |
| 主动取消 Monitor/Loop | 丢失监控能力，后续状态通知不可靠 | 用户特权，永不主动 TaskStop（铁律 2） |
| 用 `sleep && gh run list` 轮询 | 烧上下文、慢、容易错过状态变化 | 用 Monitor 持续监控，状态变化自动通知 |
| debug workflow 不设 timeout | 容器卡死烧掉 Actions 配额 | `docker compose up` 必须带 `timeout-minutes`（模板见 [[C02-debug-workflow]]） |
| 构建失败不分析直接 rerun | 代码错误重跑还是挂，浪费一轮 13 分钟 | 先看失败日志分类：代码错误→修代码，daemon 卡死→rerun |

## 错误案例记录

每次执行后在下方追加操作教训：

```markdown
### [日期] 监控操作教训

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| ... | ... | ... |
```

### 2026-09-29 操作教训（来自原 gh-ci）

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

## 相关引用

- 主页面索引:[[../SKILL]]
- 失败后远程复现深挖（监控链下一段）:[[C02-debug-workflow]]
- gh CLI 排障命令全集:[[B01-gh-troubleshoot]]
