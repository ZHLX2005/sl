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

```
py scripts/get_git_remotes.py [check|extract|sync] [-f] [--prune] [--update] [--depth N] [--root <path>]
python3 scripts/get_git_remotes.py ...        (Linux/Mac)
```

| 子命令 | 方向 | 行为 |
| --- | --- | --- |
| `check`（默认） | 只读 | diff 预览：`+clone` / `-prune` / `!conflict`，**不做任何修改**。exit 0 一致 / 1 有漂移 / 2 错误 |
| `extract` | 磁盘 → 清单 | 扫描克隆仓库的 origin，append + 自动去重；`-f` 重置文件 |
| `sync` | 双向 | 先 extract 回填清单 → 克隆清单里有、磁盘没有的（`--depth N` 浅克隆）→ `--update` 对已有克隆 `pull --ff-only` → `--prune` 删除清单里没有的目录 |

其他开关：`--root <path>` 显式指定 `.claude` 根（默认 cd 到项目根自动识别）。

> ⚠️ **必须显式给解释器**（`py` / `python3`），不要 `./get_git_remotes.py` 直接执行——脚本**故意不带 shebang**：Windows 上 py launcher 会把 `#!/usr/bin/env python3` 解析到 WindowsApps 的 python3 stub，静默退出码 49（实机踩坑，脚本头部有注释）。

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
```

**`--prune` 纪律**：先 `check` 看预览（`-prune` 行），确认没误伤再 `sync --prune`。prune 只删"shareable origin 且不在清单"的目录，本地路径资产的 clone 永不被动。

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
| 11 | git status 不被产物污染 | `.claude/www/` 已被标准结构忽略（见 [[gitignore-控制]]） |

## Common Mistakes

| Mistake | Prevention |
| --- | --- |
| 直接 `./get_git_remotes.py` 执行（无 shebang） | 显式 `py`（Win）/ `python3`（Unix）；Windows stub 静默 49 |
| `--prune` 前不看 check 预览 | prune 是删除性操作；先 `check` 审 `-prune` 行 |
| 手工往 manifest 写裸本地路径行（`C:/...`） | 会被读取侧拒收（静默不生效）；要写本地源用 `file:///` 形态 |
| 以为 sync 会覆盖 origin 对不上的同名目录 | 不会——conflict 阻塞 exit 2，需手工消解（见一致性规则 4） |
| 以为宿主项目会被自己 sync 进 repo/ | host origin 探测排除；不会（一致性规则 2） |
| 在错误目录执行导致写到 skill 锚点 | 看 `Root:` / `Manifest:` 输出行确认；项目级操作 cd 到项目根 |
| 把 `git.remote` 提交进宿主仓库 | `.claude/www/` 在标准声明结构里被忽略；别从 .gitignore 删这条 |
| 以为会产生重复行（旧版行为） | Python 版自动去重，重复执行幂等 |
| Hardcoded paths | 脚本内用 `Path(__file__)` / `Path.cwd()` 解析，勿改绝对路径 |
