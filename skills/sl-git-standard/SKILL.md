---
name: sl-git-standard
description: Git 仓库心智扁平化标准——.claude/repo 嵌套克隆仓库的 .gitignore 控制（隔离/白名单/部分跟踪）+ git.remote 清单与 .claude/repo 克隆的一致性维护（check diff 预览 / extract 提取 / sync 双向收敛，跨平台 Python 脚本）。当用户提到"清理git"、"处理嵌套仓库"、"git隔离"、"保持干净"、"部分跟踪"、"白名单子目录"、"忽略但保留子目录"、"gitignore 否定规则"、"忽略 .tool/"、"工具目录不入库"、"提取 remote"、"git.remote"、"repo 参考列表"、"团队同步仓库列表"、"收集 git 链接"、"check 仓库一致性"、"sync 参考仓库"、"克隆清单里的仓库"、"prune 旧仓库"时触发。也用于创建新项目时的 git 标准初始化。
---
# sl-git-standard — Git 仓库心智扁平化标准

一个 skill 管两件配套的事：**不让克隆仓库污染宿主仓库**（.gitignore 控制），以及**把 `.claude/repo/` 参考仓库与 `www/git.remote` 清单对齐**（check 预览差异 / extract 提取 / sync 双向收敛）。两者共同服务一个目标——`.claude/repo/` 作为参考仓库区被"扁平化"：宿主 git status 永远干净，参考仓库的来源与状态随时可追溯、可重建。

## 核心原则

1. **标准声明结构整块写入，任何模式下不删行。** 规则是前瞻性的——`_read/`、`_self/`、`.tool/` 现在不存在也整块写入；空目录零副作用，目录将来创建时规则自动生效。不存在 ≠ 不写。
2. **父目录必须半透明。** `.claude/repo/*`（带 `/*`）而非 `.claude/repo/`——父目录被整体排除时，否定规则 `!` 完全失效。这是 git 的硬规则，也是本 skill 最高频的错误来源。
3. **真实代码是唯一真相。** `scripts/get_git_remotes.py` 是提取与一致性能力的唯一实现（跨平台单文件）；文档描述与脚本行为冲突时，以脚本为准并回改文档。
4. **清单与磁盘同源同滤。** `git.remote` 清单与磁盘克隆使用同一个 URL 谓词（git@/https/http/file://）；裸本地路径 origin 的克隆是机器本地资产，不入清单、不被 prune。宿主项目自身的 origin 永不入清单——sync 永不把宿主克隆进自己的 `.claude/repo/`。
5. **先 check 后 sync。** check 是只读 diff 预览（exit 0 一致 / 1 漂移 / 2 错误），sync 是收敛动作；删除性操作（`--prune`）必须先看 check 预览。
6. **提取产物必须被忽略。** `.claude/www/` 是脚本运行产物，不属宿主仓库内容——标准结构已内置忽略，禁止把 `git.remote` 提交进宿主仓库。

## 标准声明结构（.gitignore 默认整块）

```gitignore
# ============================================================
# Cloned repositories (nested git repos) — sl-git-standard
# 父目录必须用 /* 半透明模式，否则否定规则失效
# ============================================================
.claude/repo/*

!.claude/repo/_self/
!.claude/repo/_self/**

# git remote 提取脚本的运行产物（sl-git-standard）
.claude/www/

# Tool artifacts / scratch tools (本地工具产物，不入库)
.tool/
```

三条硬规则：

1. **整块写入，即使 `_read/`、`_self/`、`.tool/` 目前不存在**（原则 1）。
2. 白名单目录不存在时，整块行为与"完全忽略"完全一致，零副作用。
3. 禁止用裸 `.claude/repo/` 或 `.claude/repo` 代替本结构——见 [[gitignore-控制]] 高频错误表第 1、2 行。

## 场景路由（ref-map）

| 场景                                                         | 信号                                                                         | 何时读取                                                              | 路径                            |
| ------------------------------------------------------------ | ---------------------------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------- |
| ★**.gitignore 控制**（隔离/白名单/部分跟踪/工具目录） | "清理git"、"git add . 有污染"、"_read 要入库"、"忽略 .tool/"                 | 任何需要写或排查 .gitignore 规则时                                    | references/gitignore-控制.md    |
| ★**提取/一致性维护**（check/extract/sync）            | "提取 remote"、"git.remote"、"check 一致性"、"sync 参考仓库"、"prune 旧仓库" | 需要生成/刷新`.claude/www/git.remote`、克隆清单仓库或对齐磁盘状态时 | references/repo-gitlink-提取.md |
| 新项目 git 标准初始化                                        | 新仓库首次配置 .gitignore                                                    | 复用上面两个 ref，先读第一个                                          | 同上（组合场景）                |

## 文件索引

| 文档章节                                         | 对应文件                            |
| ------------------------------------------------ | ----------------------------------- |
| 提取脚本（唯一实现，跨平台，check/extract/sync） | `scripts/get_git_remotes.py`      |
| .gitignore 场景全部 SOP/验证/错误表              | `references/gitignore-控制.md`    |
| 提取场景 SOP/验收标准                            | `references/repo-gitlink-提取.md` |

## 与其他 skill 的协作

- `git-commit-clone`：快照元数据包含 `remote_url`，可追加到 `git.remote`（见 [[repo-gitlink-提取]]）。
- `project-index-reader` / `intent-capture-discuss`：消费 `.claude/repo/` 下的克隆仓库——本 skill 保证它们不污染宿主 git。
