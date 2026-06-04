---
name: git-commit-clone
description: |
  在 git commit 时自动创建项目浅克隆快照到 .claude/repo/project/，同时支持手动管理。
  适用于存档项目历史版本、对比不同 commit 之间的快照、回滚参考分析。
  触发场景：
  - "每次 git commit 后保存快照"
  - "查看项目历史快照"
  - "管理快照保留数量"
  - "为快照创建索引"
type: workflow
---

# git-commit-clone — 提交即快照

## 核心功能

每次 `git commit` 后，通过 `post-commit` hook **自动**将当前项目浅克隆（`--depth=1`）到 `.claude/repo/project/`，形成可浏览的项目快照存档。

同时提供手动管理命令。

## 架构

```
git commit
    │
    ├─ [post-commit hook] ──→ clone-snapshot.sh/ps1
    │                              │
    │                              ├─ git clone --depth 1 file://$PROJECT .claude/repo/project/<date>-<hash>/
    │                              ├─ 写入 .snapshot-meta.json
    │                              └─ 更新 snapshots.json 索引
    │
    └─ [Claude Skill] 手动管理
           ├─ setup   — 安装 hook + 初始化
           ├─ run     — 手动触发快照
           ├─ list    — 查看快照列表
           ├─ show    — 查看某个快照详情
           ├─ prune   — 清理旧快照
           └─ index   — 为快照创建索引
```

## 目录结构

```
.claude/repo/project/
├── 2026-06-04-a1b2c3d/           # 快照目录（日期-短哈希）
│   ├── (项目文件全量浅克隆)
│   └── .snapshot-meta.json       # 快照元数据
├── 2026-06-04-e4f5g6h/
├── 2026-06-05-xyz7890/
├── snapshots.json                # 全局快照索引（机器可读）
└── snapshots.log                 # 快照日志（备选，当 jq 不可用时）
```

## 命令参考

### `setup` — 安装 hook + 初始化

安装 `post-commit` git hook，同时初始化 `.claude/repo/project/` 目录，配置 `.gitignore`。

```bash
# Linux
bash .claude/skills/git-commit-clone/reference/setup-hook.sh

# Windows
powershell -ExecutionPolicy Bypass -File .claude/skills/git-commit-clone/reference/setup-hook.ps1
```

> 初始化后，按 `git-repo-cleanup` 模式 B 将 `.claude/repo/` 配置到 `.gitignore`：
> ```gitignore
> .claude/repo/*
> !.claude/repo/_read/
> !.claude/repo/_read/**
> ```

### `run` — 手动触发快照

手动为当前工作目录创建一个快照（与 hook 自动执行的逻辑完全相同）。

```bash
bash .claude/skills/git-commit-clone/reference/clone-snapshot.sh
# 或 Windows:
powershell -ExecutionPolicy Bypass -File .claude/skills/git-commit-clone/reference/clone-snapshot.ps1
```

### `list` — 查看快照列表

列出所有快照，显示时间、commit hash、commit message。

```bash
# 查看目录树
ls -la .claude/repo/project/

# 查看索引（如果支持 jq）
jq '.' .claude/repo/project/snapshots.json 2>/dev/null \
  || cat .claude/repo/project/snapshots.log
```

### `show` — 查看某个快照

```bash
# 以最新快照为例
SNAP=$(ls -1d .claude/repo/project/*-* | sort | tail -1)
echo "=== Snapshot: $(basename $SNAP) ==="
cat "$SNAP/.snapshot-meta.json"
echo "---"
ls -la "$SNAP/"
```

### `prune` — 清理旧快照

保留最近 N 个快照，删除更早的。默认保留 10 个。

```bash
# 保留最近 10 个
bash .claude/skills/git-commit-clone/reference/prune-snapshots.sh

# 自定义保留数量（保留 5 个）
bash .claude/skills/git-commit-clone/reference/prune-snapshots.sh 5
```

### `index` — 为快照创建索引（集成 `index-repos`）

为每个快照生成 `PROJECT_INDEX.md` 和 `PROJECT_INDEX.json`，使快照可浏览。

> 复用 `index-repos` skill 的并行 subagent 机制。
> 处理对象：`.claude/repo/project/` 下的快照目录（排除 `_read` 等常规排除项）

## 与现有技能集成

| 技能 | 集成方式 |
|------|---------|
| **`git-repo-cleanup`** | `setup` 时按模式 B 配置 `.gitignore`，避免快照被主仓库跟踪 |
| **`index-repos`** | `index` 命令为每个快照创建 `PROJECT_INDEX.md`，实现可浏览的历史存档 |
| **`repo-gitlink`** | 快照元数据包含 `remote_url`，可追加到 `git.remote` |
| **`mmx-research-gitclone`** | 复用 `--depth 1` 浅克隆验证模式和错误处理 |

## 实现脚本路径

```
.claude/skills/git-commit-clone/
├── SKILL.md                          # 本文档
└── reference/
    ├── clone-snapshot.sh             # Linux: 创建快照
    ├── clone-snapshot.ps1            # Windows: 创建快照
    ├── setup-hook.sh                 # Linux: 安装 hook
    ├── setup-hook.ps1                # Windows: 安装 hook
    └── prune-snapshots.sh            # 清理旧快照
```

## 错误处理

| 症状 | 原因 | 解决 |
|------|------|------|
| hook 不执行 | hook 可执行权限缺失 | `chmod +x .git/hooks/post-commit` |
| hook 不执行 | Windows git for bash 没有 sh | 使用 `setup-hook.ps1` 安装 |
| 快照目录为空 | `file://` 克隆失败 | 检查 `.gitignore` 是否排除自身 |
| 快照太多占用空间 | 保留数量默认 10 个 | 使用 `prune` 命令减少 |
| `jq` 命令未找到 | 未安装 jq | 回退到 `snapshots.log` 文本日志 |
| 快照跳过 | 同一 commit 已存在快照 | 这是预期的幂等行为 |

## 验证清单

- [ ] `setup` 后 `.git/hooks/post-commit` 存在且有执行权限
- [ ] 执行 `git commit` 后 `.claude/repo/project/` 自动生成快照
- [ ] `run` 命令手动创建快照成功
- [ ] `list` 能看到所有快照
- [ ] `prune` 正确保留最近 N 个
- [ ] `.snapshot-meta.json` 内容完整
- [ ] `.gitignore` 排除了 `.claude/repo/` 下的克隆内容（主仓库干净）
