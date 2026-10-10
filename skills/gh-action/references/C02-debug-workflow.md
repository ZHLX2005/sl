# C02-debug-workflow — Actions 环境远程复现诊断（debug workflow 模板）

> 来自原 `gh-ci` skill（其前身为 `gh-ci-remote-debug`）。在 GitHub Actions 环境中复现和诊断 CI/CD 问题：用 gh CLI 触发 debug workflow，Monitor 追踪状态变化，拉取环境日志。

## 何时读取

本地无法复现、容器启动崩溃、需要 Actions 环境完整日志时加载本 ref。用户说"debug CI / 容器在 CI 里起不来 / 要 Actions 环境的日志"。常规排障命令（不建 debug workflow）走 [[B01-gh-troubleshoot]]；Monitor 用法与三铁律见 [[C01-monitor-build]]（监控链上一段）。

## Core Pattern

### 1. 创建 Debug Workflow

```yaml
name: Debug Deploy
on:
  workflow_dispatch:

jobs:
  debug:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # === 根据项目调整：构建依赖 ===
      - name: Setup pnpm
        uses: pnpm/action-setup@v4
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm run build

      # === Docker 构建和启动 ===
      - run: docker compose build

      # ⚠️ 必须设置 timeout 避免资源浪费
      - name: Docker Compose up
        timeout-minutes: 8
        run: docker compose up --abort-on-container-exit

      - name: Show logs on failure
        if: failure()
        run: docker compose logs --tail=100
```

### 2. 触发和监控

```bash
# 触发 workflow
gh workflow run Debug\ Deploy

# 监控状态（⚠️ 关键）
Monitor: gh run view <run_id>
```

### 3. Monitor 正确用法

**绝对规则：Monitor 完成后必须验证状态**（三铁律见 [[C01-monitor-build]]）

```
Monitor 返回 completed
  → gh run view <run_id> 验证
  → in_progress: 继续等待或重新 Monitor
  → completed/success/failure: 安全读取日志
```

### 4. 获取日志

```bash
# 查看失败日志
gh run view --job=<job_id> --log-failed

# 查看完整日志
gh run view --job=<job_id> --log
```

## Common Mistakes

### 错误 1：Monitor 误判（⚠️ 极其严重）

**错误流程：**
```
Monitor completed → 直接读取 gh run view → 数据过时/不存在
```

**正确流程：**
```
Monitor completed → gh run view <run_id> 验证状态 → 获取日志
```

### 错误 2：忘记设置 timeout

```yaml
- name: Docker Compose up
  timeout-minutes: 8  # ⚠️ 必须设置
  run: docker compose up --abort-on-container-exit
```

## Key Principles

- **Monitor/Loop 是用户特权**：不能主动取消（铁律 2，见 [[C01-monitor-build]]）
- **验证优于假设**：workflow 状态以 gh run view 为准
- **永远不要假设** Monitor 返回 = 任务完成

## 错误案例

### 错误：Monitor 完成后未验证状态即读取日志

**错误流程：**
```
Monitor completed → 直接 gh run view --log → 数据不存在或过时
```

**正确流程：**
```
Monitor completed → gh run view <run_id> 验证状态 → 根据状态决定操作
```

### 错误：主动取消 Monitor/Loop

**致命错误：**
```
Monitor 正在追踪状态 → 主动调用 TaskStop 取消 → 丢失监控能力
```

**后果：** 后续 Monitor 工具可能无法正常工作，或返回不准确的状态。

**正确做法：**
- 等待 Monitor 自然结束或状态变化通知
- 如果需要停止，让用户明确知道这是他们的特权
- 永远不要主动取消 Monitor/Loop 工具

## 相关引用

- 主页面索引:[[../SKILL]]
- 监控 SOP 与三铁律（监控链上一段）:[[C01-monitor-build]]
- 排障命令全集:[[B01-gh-troubleshoot]]
