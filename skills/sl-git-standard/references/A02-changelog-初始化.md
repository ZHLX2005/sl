---
name: changelog-初始化
description: Reference — sl-git-standard 的 CHANGELOG.md 初始化 SOP：硬性要求（每个 git 标准仓库必须有）、Keep a Changelog 格式、基线写法、回填规则、与 A/B/D/F 协作点、常见错误。
---
# Changelog 初始化 — 标准仓库必须有 CHANGELOG.md

> 主 SKILL.md 的「A 序列」（A01 .gitignore + A02 changelog）是两条「标准声明」硬性要求；本文档是 changelog 写文件**之前**的格式规范与写文件**之后**的维护规则。

## 硬性要求

凡经过 `sl-git-standard` 标准初始化的仓库（含已标准化的存量仓库），**根目录必须有 `CHANGELOG.md`**，否则视为 git 标准未达标。

与 A 序列（.gitignore）、B 序列（git.remote）同等级别——三条腿：忽略隔离 + 远程清单 + 变更日志。

## 问题背景

没有 CHANGELOG.md 的常见代价：

- 接手人不知道仓库当前有什么、有过什么
- marketplace 插件类仓库的"技能集"变更没有对外可读档
- 跨人 / 跨机器同步时，增量信息只藏在 git log 里（且经常不可读：消息粒度杂的仓库尤其）

## 格式规范（Keep a Changelog）

### 必要结构

```markdown
# Changelog

本项目的所有显著变更都记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/spec/v2.0.0.html)。

## [Unreleased]

## [X.Y.Z] - YYYY-MM-DD

### Added
- ...

### Changed
- ...

[Unreleased]: <compare_url>
[X.Y.Z]: <tag_url_or_commit_url>
```

### 段落分类

只允许以下 6 类（Keep a Changelog 1.1+）：

- `### Added` — 新功能
- `### Changed` — 既有功能变更
- `### Deprecated` — 即将移除
- `### Removed` — 已移除
- `### Fixed` — 修复
- `### Security` — 安全修复

按需留类，不写空段。

### 版本号

- 优先从 `marketplace.json` / `package.json` / `VERSION` / `__version__.py` 等现有版本源取
- 都没有 → 用首次初始化日期当 `0.1.0` 基线
- 日期格式：必须 `YYYY-MM-DD`（ISO 8601），与 Keep a Changelog 一致

### 比较链接

- `[Unreleased]` 指向「最近已发版 commit...HEAD」：`https://<host>/<owner>/<repo>/compare/<last_tag_or_baseline>...HEAD`
- 每个发版段指向 tag：`https://<host>/<owner>/<repo>/releases/tag/v<X.Y.Z>`
- 没有 tag 时，基线条目指向初始化时的 commit：`https://<host>/<owner>/<repo>/commit/<sha>`

## 初始化 SOP

### 步骤 1：定版本号

```bash
# 顺序尝试以下来源
cat .claude-plugin/marketplace.json | grep -i version
cat package.json | grep '"version"'
cat VERSION 2>/dev/null
```

都没有 → 写 `0.1.0`，日期写初始化当天。

### 步骤 2：扫描基线

```bash
# 顶层目录列表（理解仓库结构）
ls -la

# 现有技能数（marketplace 仓库）
ls skills/ | wc -l
ls skills/

# 现有 hooks
ls hooks/

# 现有文档
ls docs/
```

不深挖代码，只列可见的"骨架条目"——文件级 / 目录级粒度。

### 步骤 3：决定是否回填

**默认不回填**。仅在历史 commit 消息规整（含 conventional commits / feat:/fix:/chore: 前缀，且能按时间窗口归类为 6 类段落）时才做按月 / 按版本窗口的回填。

历史 commit 消息混乱（"fix"、"1"、"update"、"嘎嘎嘎"、空描述）→ 不回填，只写当前基线。理由：回填噪音 = 假信息，比没回填更糟。

### 步骤 4：写文件

文件位置：仓库根 `CHANGELOG.md`，与 `README.md` 同级。

模板见上方「格式规范」。

### 步骤 5：提交

CHANGELOG.md **必须入库**——与 B 序列 `www/git.remote` 同原则（仓库内容随仓库走，换机器 / 同事 clone 后才有标准基线）。

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): 初始化 CHANGELOG 基线 v0.1.0"
```

### 步骤 6（可选）：补一次发版 tag

如已定下基线版本，发一个轻量 tag 方便后续 `[Unreleased]` compare 链接稳定：

```bash
git tag v0.1.0
git push origin v0.1.0   # 仓库要求才推；本地存档也可以
```

## 与其他序列的协作

- **A01（.gitignore）**：`CHANGELOG.md` 不入 .gitignore。它是仓库内容，不是工具产物。
- **B01（git.remote）**：CHANGELOG.md 不影响 `www/git.remote` 清单；但若 release 触发 sync，注意 CHANGELOG 里的链接 base 与清单同源（`origin` URL）。
- **D01（commit snapshot）**：浅克隆存档到 `.claude/repo/project/` 时，CHANGELOG.md 已在 commit 里，无需特殊处理。
- **F01 / F02（迁移）**：迁移到 GitHub 后，把 CHANGELOG.md 里的所有 `https://` 链接 host 改一次（gitee.com → github.com 或反过来）。grep 一遍旧 host 即可。

## 常见错误

| # | 错误做法 | 后果 | 正确做法 |
|---|---|---|---|
| 1 | 把 `CHANGELOG.md` 加进 `.gitignore` | 团队 / 同事 clone 后文件丢失，标准形同虚设 | 永远不忽略，CHANGELOG 是仓库内容 |
| 2 | 写 `## [0.1.0]` 没日期 | 失去时间维度，无法判断新鲜度 | 必须 `## [0.1.0] - YYYY-MM-DD` |
| 3 | 逐条回填噪音 commit（"1"、"嘎嘎嘎"） | 假信息 = 比没回填更糟 | 默认不写历史，只写基线 |
| 4 | 没有 `[Unreleased]` 段 | 后续变更无处落 | 永远留空段占位 |
| 5 | 6 段分类混用 / 自创新分类 | 不可机器解析、不可对比 | 只用 6 类，写满就换段 |
| 6 | 日期写成 `2026/10/18` 或 `18/10/2026` | 区域歧义、不可解析 | `YYYY-MM-DD` |
| 7 | compare 链接写绝对路径 `compare/main...HEAD` | 默认分支改名就坏 | 用 commit SHA 作左端 |
| 8 | 半年才补一次 CHANGELOG | Unreleased 段越积越多，无法稳定 release | 每次合并到 main 前补一段 |

## 验收清单

- [ ] 根目录存在 `CHANGELOG.md`
- [ ] 顶部 `# Changelog` 标题
- [ ] 有 `## [Unreleased]` 段（可空但必须存在）
- [ ] 有 `## [X.Y.Z] - YYYY-MM-DD` 至少一个发版段
- [ ] 日期格式 `YYYY-MM-DD`
- [ ] 段内只用 6 类（Added / Changed / Deprecated / Removed / Fixed / Security）
- [ ] 底部有 link reference 表格（`[Unreleased]` + 每个发版段）
- [ ] `git status` 干净时（无 `.claude/repo/`、`.tool/` 污染），CHANGELOG.md 已入库
- [ ] 不在 `.gitignore` 中
