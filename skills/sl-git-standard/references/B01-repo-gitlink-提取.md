---
name: repo-gitlink-提取
description: Reference — sl-git-standard 的清单↔磁盘一致性场景完整 SOP：get_git_remotes.py 的 check/extract/sync 三子命令、工作流、退出码、验收标准、常见错误。行为以 scripts/get_git_remotes.py 真实实现为准。
---

# Repo Gitlink 提取与一致性 — git.remote 清单 ↔ .claude/repo 磁盘

## Overview

`scripts/get_git_remotes.py` 维护两个状态的**一致性**：

- **清单（应然）**：`<root>/www/git.remote`，每行一个 remote URL
- **磁盘（实然）**：`<root>/repo/` 下的一级克隆目录

跨平台单文件 Python（Windows/Linux/Mac），取代旧 ps1/sh 双份脚本。旧版只会单向提取；现在 `check` 出 diff、`sync` 双向收敛。

## 调用方式

### Step 0 — 解释器预检（先于一切，禁止跳过）

三个候选解释器名都可能是坑（均为实机踩坑）：

| 候选 | 坑 |
| --- | --- |
| `py` | Git Bash 里可能不在 PATH（cmd 里有也没用）→ `command not found`，exit 127 |
| `python3` | WindowsApps stub 静默退出码 49；只有 Store 装了真 Python 时才可用 |
| 裸 `python` | 可能是 Python 2（conda 老 env）→ `SyntaxError: Non-ASCII character '\xe2' ... no encoding declared`；脚本全程 f-string，**py2 永远解析不了** |

预检一条命令，通过才继续；按顺序取第一个通过的候选：

```bash
<interp> -c "import sys; assert sys.version_info >= (3, 8)"
# 顺序：py -3  →  python3  →  uv run python  →  python（仅预检通过时）
```

### 子命令

```
<interp> scripts/get_git_remotes.py [check|extract|sync] [-f] [--prune] [--update] [--depth N] [--root <path>]
```

| 子命令 | 方向 | 行为 |
| --- | --- | --- |
| `check`（默认） | 只读 | diff 预览：`+clone` / `-prune` / `!conflict`，**不做任何修改**。exit 0 一致 / 1 有漂移 / 2 错误 |
| `extract` | 磁盘 → 清单 | 扫描克隆仓库的 origin，append + 自动去重；`-f` 重置文件 |
| `sync` | 双向 | 先 extract 回填清单 → 克隆清单里有、磁盘没有的（`--depth N` 浅克隆）→ `--update` 对已有克隆 `pull --ff-only` → `--prune` 删除清单里没有的目录 |

其他开关：`--root <path>` 显式指定 `.claude` 根（默认 cd 到项目根自动识别）。

> ⚠️ **不要 `./get_git_remotes.py` 直接执行**——脚本**故意不带 shebang**：Windows 上 py launcher 会把 `#!/usr/bin/env python3` 解析到 WindowsApps 的 python3 stub，静默退出码 49（实机踩坑，脚本头部有注释）。解释器选择一律走 Step 0。

## 一致性规则（脚本强制）

1. **同一 URL 谓词管读写两侧**（`git@` / `https://` / `http://` / `file://`）。origin 是裸本地路径（如 `C:/...` 或 `/home/...`）的克隆视为**机器本地资产**：extract 不写入清单（`LocalPath` 计数）、check/sync 不比对不 prune 不 update——换机器后 `sync --prune` 永不误删它。
2. **宿主项目自身永不入清单**：脚本探测 `root.parent` 的 origin（如 jv 的 `git@github.com:ZHLX2005/jv.git`），extract 跳过、sync 永不把宿主克隆进自己的 `.claude/repo/`。check 输出的 `Host repo (excluded)` 行即此。
3. **`_`/`.` 开头目录是元目录**（`_read`/`_self` 等）：不算参考仓库，`SkippedDirs` 计数。
4. **同名不同源 = conflict**：manifest 想要 `X.git` 但磁盘 `X/` 的 origin 对不上时，sync 不克隆不覆盖，报 `!conflict` 并 exit 2。消解靠手工：删掉该目录重跑 sync，或 `git remote set-url origin <manifest URL>`。
5. **退出码契约**：0 = 一致/成功；1 = check 发现漂移；2 = 错误（含 conflict）。CI 里可 `check` 当门禁。顶层兜底任何未捕获异常为 exit 2，不让崩溃伪装成"漂移"。

## 标准工作流

```
日常巡检        check                     → exit 0 什么都不用做
新克隆参考仓库   git clone ... .claude/repo/foo && check → 会看到 foo stale（未入清单）
                                          → sync 或 extract 回填清单
换机器/同事接手  check → sync              → 清单里的仓库自动克隆齐
清单瘦身        编辑 git.remote 删行 → sync --prune  → 磁盘目录被清（先看 check 预览！）
更新全部克隆     sync --update             → pull --ff-only，有本地分叉的仓库跳过并告警
清单入库        extract 后 commit .claude/www/git.remote → 换机器/同事接手 sync 有输入
```

**`--prune` 纪律**：先 `check` 看预览（`-prune` 行），确认没误伤再 `sync --prune`。prune 只删"shareable origin 且不在清单"的目录，本地路径资产的 clone 永不被动。

### 主动调用默认 SOP（同步 / 检查 / 补充例行巡检）

skill 被主动调用做仓库例行维护时按此顺序执行。"把本地 repo 提交进 `www/git.remote`" = 第 3 步 extract（磁盘 origin 回填清单，幂等 append + 去重）。

| 步 | 动作 | ask 门 | 说明 |
| --- | --- | --- | --- |
| 1 | Step 0 解释器预检 | 直接做 | 不过则按顺序换候选，禁止跳过 |
| 2 | `check` 只读 diff | 直接做 | exit 0 → 报告"一致"，结束 |
| 3 | stale（磁盘有、清单无）→ `extract` 回填清单 | 直接做 | 幂等安全动作；即"把本地 repo 提交进 git.remote" |
| 4 | missing（清单有、磁盘无）→ **询问用户是否 clone** | **必问** | 用户同意才 `sync [--depth N]`；不同意则只报告不动作 |
| 5 | `!conflict` → 报告 + 手工消解选项 | **必问** | 删目录重跑 sync，或 `git remote set-url origin <URL>` |
| 6 | `--prune` / `--update` | **必问** | 删除性/改动磁盘动作，巡检默认不附带执行 |
| 7 | commit `.claude/www/git.remote` 进宿主仓库 | 直接做 | 清单是仓库内容（主文档原则 6）；回填后随宿主提交，换机器/同事 clone 后 sync 才有输入 |

## Input/Output Convention

```
Input:  <root>/repo/<name>/.git          (一级子目录；_/. 开头为元目录)
Output: <root>/www/git.remote            (append 默认；-f 重置)
Format: 每行一个 URL：git@ / https:// / http:// / file://
统计:   extract → Added/Deduped/NoRemote/LocalPath/SkippedDirs
        sync    → Cloned/clone-failed/Updated/Pruned/Conflicts
```

## Acceptance Criteria

| # | Criterion | Test Method |
| - | --------- | ----------- |
| 1 | 输出文件生成于 `<root>/www/git.remote` | 落盘检查 |
| 2 | 每行一个合法 URL，无空行 | `cat` |
| 3 | append 重复执行幂等（自动去重） | 重跑 `Deduped` 递增，行数不变 |
| 4 | `-f` 重置文件 | 行数 == 仓库数 |
| 5 | check 一致 → 0 / 漂移 → 1 / 错误 → 2 | 造漂移后跑 check 看退出码 |
| 6 | sync 克隆缺失仓库（`--depth` 生效为浅克隆） | `Cloned` 计数 + 目录出现 |
| 7 | `--update` ff 拉更新，分叉仓库跳过不中断 | `Updated` 计数 + stderr 告警 |
| 8 | `--prune` 删清单外目录；本地路径资产不动 | check 预览 → prune → `git status` 干净 |
| 9 | 宿主自身 origin 永不入清单、永不被克隆 | check 的 `Host repo (excluded)` 行 |
| 10 | conflict 阻塞且 exit 2，不覆盖磁盘 | 同名不同源 fixture |
| 11 | 清单随宿主仓库提交 | `.claude/www/` 无忽略规则；`git add .claude/www/git.remote` 生效（见 [[A01-gitignore-控制]]） |

## Common Mistakes

| Mistake | Prevention |
| --- | --- |
| 直接 `./get_git_remotes.py` 执行（无 shebang） | 显式解释器 + Step 0 预检；Windows stub 静默 49 |
| 裸 `python` 直接跑（本机 conda 可能是 2.7） | 先跑 Step 0 预检；报 `Non-ASCII character ... no encoding declared` = 选错解释器 |
| 假设 `py` 一定在 PATH（Git Bash 实测 127） | 预检失败按 `py -3 → python3 → uv run python` 顺序换 |
| 巡检时静默 clone 清单缺失仓库 | missing 必须先问用户；clone 是外向动作，同意才执行 |
| `--prune` 前不看 check 预览 | prune 是删除性操作；先 `check` 审 `-prune` 行 |
| 手工往 manifest 写裸本地路径行（`C:/...`） | 会被读取侧拒收（静默不生效）；要写本地源用 `file:///` 形态 |
| 以为 sync 会覆盖 origin 对不上的同名目录 | 不会——conflict 阻塞 exit 2，需手工消解（见一致性规则 4） |
| 以为宿主项目会被自己 sync 进 repo/ | host origin 探测排除；不会（一致性规则 2） |
| 在错误目录执行导致写到 skill 锚点 | 看 `Root:` / `Manifest:` 输出行确认；项目级操作 cd 到项目根 |
| 忽略/漏提交 `.claude/www/`（清单不随仓库走） | 标准结构不忽略 www；extract 后把 `git.remote` commit 进宿主仓库，否则换机器/同事 clone 后 sync 无输入 |
| 以为会产生重复行（旧版行为） | Python 版自动去重，重复执行幂等 |
| Hardcoded paths | 脚本内用 `Path(__file__)` / `Path.cwd()` 解析，勿改绝对路径 |
