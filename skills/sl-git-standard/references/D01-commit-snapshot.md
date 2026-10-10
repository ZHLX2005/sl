---
name: D01-commit-snapshot
description: 为指定 commit 创建项目浅克隆快照到 .claude/repo/project/，跨平台 Python 实现。替代原 clone-snapshot.sh + clone-snapshot.ps1 + prune-snapshots.sh 三脚本。触发场景："为这个 commit 创建快照"、"快照当前项目状态"、"管理快照保留数量"、"为快照创建索引"。
---

# D01 — 提交快照（commit-snapshot）

为**指定 commit** 创建浅克隆（`--depth=1`）快照到 `.claude/repo/project/`。
脚本位置：`scripts/commit_snapshot.py`（与 `get_git_remotes.py` 同级，跨平台 Python）。

## 命令速查

| 命令 | 用途 |
|---|---|
| `py commit_snapshot.py` | 为当前 HEAD 创建快照（snapshot 是默认 subcommand） |
| `py commit_snapshot.py a1b2c3d` | 为指定 commit 创建快照 |
| `py commit_snapshot.py list` | 列出所有快照 |
| `py commit_snapshot.py show <name>` | 显示某个快照的元数据 |
| `py commit_snapshot.py prune --keep 5` | 保留最近 5 个，删其他 |
| `py commit_snapshot.py index` | 为每个快照生成 PROJECT_INDEX |

> Linux/Mac 替换 `py` 为 `python3`。

## 调用约定（无 shebang）

**不要期望脚本有 shebang 行。** Windows 上 `#!/usr/bin/env python3` 会被 py launcher
解析为 WindowsApps python3 stub（退出码 49）。**始终用显式解释器**：

```bash
py  commit_snapshot.py ...    # Windows
python3 commit_snapshot.py ... # Linux/Mac
```

## 目录结构

```
.claude/repo/project/
├── 2026-10-10-a1b2c3d/
│   ├── (项目文件全量浅克隆)
│   ├── .snapshot-meta.json
│   ├── PROJECT_INDEX.md
│   └── PROJECT_INDEX.json
├── 2026-10-09-e4f5g6h/
├── snapshots.json                # 全局机器可读索引
```

## 快照命名规则

`<YYYY-MM-DD>-<7 位短哈希>`，例如 `2026-10-10-a1b2c3d`。
按名字排序 ≈ 按时间排序（prune 因此从最旧开始删）。

## .snapshot-meta.json 字段

| 字段 | 含义 |
|---|---|
| `commit` | 完整 commit SHA |
| `short_hash` | 7 位短哈希 |
| `author` | 作者名 |
| `email` | 作者邮箱 |
| `timestamp` | commit 时间戳（秒） |
| `subject` | commit 标题 |
| `remote_url` | 仓库 origin URL（**可追加到 git.remote**） |
| `created_at` | 快照创建 ISO 时间 |

## 5 个 subcommand 详解

### snapshot（默认）

为指定 commit 创建浅克隆快照。

```bash
py commit_snapshot.py                      # HEAD
py commit_snapshot.py a1b2c3d              # 指定 commit
py commit_snapshot.py --root D:/proj/x     # 指定 .claude 根
```

幂等：同一 commit 的快照已存在则跳过。

### list

列出所有快照，按日期倒序。

```
Found 5 snapshot(s):
  2026-10-10-a1b2c3d  2026-10-10  feat(x): add Y
  2026-10-09-e4f5g6h  2026-10-09  fix(z): ...
  ...
```

### show

显示单个快照的完整元数据。

```bash
py commit_snapshot.py show 2026-10-10-a1b2c3d
```

### prune

保留最近 N 个，删其他。默认 N=10。

```bash
py commit_snapshot.py prune --keep 5
```

`rmtree_force` 兼容 Windows read-only `.git` 对象文件。

### index

为每个快照生成 `PROJECT_INDEX.md` + `PROJECT_INDEX.json`（轻量本地实现）。

```bash
py commit_snapshot.py index
```

## 根解析（与 get_git_remotes.py 一致）

1. `--root <path>` — 显式指定 `.claude` 根
2. `<cwd>/.claude` — 当前工作目录下有 `.claude/repo/`
3. skill-anchored `.claude` — skill 安装位置（兜底）

## 与 B 序列的联动（关键）

D01 的 `remote_url` 字段是 B 序列（`get_git_remotes.py`）的天然输入源：

```bash
# 1. 创建快照
py commit_snapshot.py
# 2. 把快照的 remote_url 提取到 git.remote
#    (遍历 .claude/repo/project/*/.snapshot-meta.json, 取 remote_url)
py ../get_git_remotes.py extract
```

这让"项目历史快照"和"参考仓库清单"自然衔接。

## 错误处理

| 症状 | 原因 | 解决 |
|---|---|---|
| `cannot resolve commit` | commit 不存在 / 未 fetch | 先 `git fetch` |
| `git clone FAILED` | 浅克隆失败（网络/权限） | 检查 remote URL；可能需要先 fetch |
| `snapshot already exists` | 同一 commit 已快照 | 幂等行为，忽略 |
| `Permission denied` (Windows prune) | `.git` 对象 read-only | `rmtree_force` 已处理，重试即可 |
| 索引文件损坏 | `snapshots.json` JSON 不合法 | 脚本兜底重建为空索引 |

## 验证清单

- [ ] `py commit_snapshot.py` 创建快照成功
- [ ] 快照目录含 `.snapshot-meta.json`
- [ ] `snapshots.json` 自动追加
- [ ] `py commit_snapshot.py list` 列出快照
- [ ] `py commit_snapshot.py show <name>` 输出元数据
- [ ] `py commit_snapshot.py prune --keep 1` 正确删除
- [ ] `py commit_snapshot.py index` 生成 `PROJECT_INDEX.md/.json`
- [ ] Windows + Linux 双平台通过

## 与其他 skill 的协作

- **A 序列**（`.gitignore` 控制）：D01 的产物应被 A 序列的 `.claude/repo/*` 规则自然忽略
- **B 序列**（`get_git_remotes.py`）：D01 的 `remote_url` 是 B 序列 `extract` 的输入源
- **F 序列**（跨平台迁移）：可同批调用，先迁移再快照
