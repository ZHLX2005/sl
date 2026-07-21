---
name: boot-work-flow
description: 当用户说 "boot work-flow"、"初始化 work-flow"、"为这个仓库创建 work-flow skill"、"创建 <仓库名>-work-flow" 时触发。这是一个元skill：自动检测 git 仓库名 → 在项目本地创建 <repo>-work-flow skill → 仅写入项目启动方法和启动信息作为最小骨架 → 标注后续通过 /key_board_3 添加 references 增强。
---

# boot-work-flow — 工作流 Skill 引导器（元 skill）

## 职责

本 skill **只负责创建 `<repo>-work-flow` skill 的初始骨架**，不做完整工作流内容提取。

- 完整工作流沉淀交给 `/key_board_3` 通过 references 增量增强
- 本 skill 输出的是最小可运行骨架 + 后续增强入口

## 前置依赖

| Skill | 用途 | 必须性 |
|-------|------|--------|
| `skill-creator` / `writing-skills` | skill 写法规范 | 必须存在，否则终止 |
| `key_board_3` | 后续增强（添加 ref） | 必须存在，否则无法承诺增强链路 |

**前置缺失处理**：若 `skill-creator` 或 `key_board_3` 不可见，立即通知用户并终止流程，不得继续。

## 触发场景

用户输入包含以下任一：

- "boot work-flow"
- "初始化 work-flow skill"
- "为这个项目创建 work-flow"
- "创建 `<仓库名>`-work-flow"
- 在新克隆的仓库中调用 `/boot-work-flow`

## 核心原则

1. **自动检测仓库名** — 通过 `git remote -v` 提取 owner/repo，禁止让用户手填
2. **项目本地放置** — 创建在 `<项目根>/.claude/skills/<repo>-work-flow/`，而非用户全局目录
3. **最小骨架** — 初始只包含：项目简介、启动命令、关键端口/路径、技术栈。**不抽取工作流细节**
4. **明确增强入口** — SKILL.md 末尾必须标注 "调用 `/key_board_3` 添加 references 增强"
5. **幂等** — 已存在 `<repo>-work-flow` 时，提示用户选择「覆盖」或「跳过」，禁止直接覆盖

## 执行流程（必须按序）

### Step 1: 检测仓库名

```bash
cd <项目根>
git remote -v
```

提取格式：`git@github.com:<owner>/<repo>.git` 或 `https://github.com/<owner>/<repo>.git`

→ `<repo-name>` 取最后一段（去除 `.git`）。

**特殊处理**：

| 场景 | 处理 |
|------|------|
| 无 git remote | 退化为使用 `basename $(pwd)` 并提示用户确认 |
| 多个 remote（origin + orgin 拼写错误等） | 取第一个有效 remote |
| Monorepo 子目录 | 使用 `git rev-parse --show-toplevel` 获取项目根，再取 repo 名 |

### Step 2: 确认目标目录

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
TARGET_DIR="$PROJECT_ROOT/.claude/skills/<repo-name>-work-flow/"
```

**冲突处理**：若 `TARGET_DIR` 已存在，调用 AskUserQuestion 让用户选择：

- 「覆盖」（先备份原文件到 `.bak`）
- 「跳过」（终止本次 boot）

### Step 3: 创建目录

```bash
mkdir -p "$TARGET_DIR"
```

### Step 4: 探测启动信息（最小集）

自动扫描以下信息填充骨架（**不深入抽取工作流**）：

| 信息项 | 探测方式 |
|--------|----------|
| 项目简介 | 读取 README.md 首段（≤200 字） |
| 启动命令 | 扫描 `Makefile` / `package.json` 的 scripts / `go run` / `docker-compose.yml` |
| 技术栈 | 读取 `go.mod` / `package.json` / `Cargo.toml` / `pyproject.toml` 顶层 |
| 关键端口 | 扫描 `.env.example` / `config.yaml` / 代码中的 `:8080` 等字面量 |
| 目录结构 | `tree -L 2` 或 `ls` 顶层目录 |

**探测失败的字段**：写 `待补充`，禁止编造。

### Step 5: 写入 SKILL.md

模板（严格遵守）：

```yaml
---
name: <repo-name>-work-flow
description: <repo-name> 项目本地工作流 skill（骨架）。详细工作流、命令清单、最佳实践通过 /key_board_3 增量增强。
---

# <repo-name>-work-flow

## 项目简介

<Step 4 探测到的简介>

## 技术栈

<探测到的技术栈>

## 启动方法

```bash
<探测到的启动命令>
```

## 关键端口/路径

<端口与路径清单>

## 目录结构概览

```
<tree -L 2 输出>
```

---

## ⚠️ 骨架状态

本 skill 仅为最小启动骨架。**详细工作流、增强指南、references 尚未沉淀。**

### 后续增强路径

调用以下命令之一沉淀工作流：

- `/key_board_3 添加 ref` — 把工作流拆分为 references 下的专项文档
- 手动编辑本 skill 添加章节

### 增强候选清单

- [ ] 完整命令清单（build / test / lint / deploy）
- [ ] 架构图与模块边界
- [ ] 常见坑点与排错指南
- [ ] CI/CD 流程
- [ ] 开发规范与代码风格
- [ ] 故障排查 SOP
```

### Step 6: 通知用户

输出：

```
✅ <repo-name>-work-flow 骨架已创建：<TARGET_DIR>/SKILL.md

⚠️ 当前仅含最小启动信息。
下一步：调用 /key_board_3 添加 references 沉淀完整工作流。
```

## 易错与坑点

| 错误 | 根因 | 预防 |
|------|------|------|
| 让用户手填仓库名 | 跳过 `git remote -v` 自动检测 | Step 1 强制先执行 git 检测 |
| 创建到用户全局 `~/.claude/skills/` | 混淆元 skill 与项目本地 skill 边界 | Step 2 强制使用 `git rev-parse --show-toplevel` |
| 在骨架里写完整工作流 | 违反 "最小骨架 + 增量增强" 契约 | Step 5 模板固定，章节硬编码 |
| 探测失败时编造内容 | 偷懒 | 强制写「待补充」 |
| 已存在 skill 时直接覆盖 | 破坏幂等性 | Step 2 冲突检测 + AskUserQuestion |
| 增强入口只写一次 | 用户找不到 | Step 5 末尾固定出现"调用 /key_board_3"提示 |

## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 用 `basename $(pwd)` 代替 git remote | 用户在子目录运行 skill 时 repo 名错误 | 必须用 `git remote -v` |
| 把骨架写到 `~/.claude/skills/` | 跨项目污染，所有项目共用同一个 work-flow | 必须用 `git rev-parse --show-toplevel` |
| 骨架里塞满命令清单 | 与 `/key_board_3` 职责重叠，骨架膨胀 | 骨架只含启动信息，其余留空待补 |
| 忘记写增强入口 | 用户不知道下一步该做什么 | 末尾固定出现 `/key_board_3` 提示 |

## 成功标准检查清单

- [ ] 通过 `git remote -v` 检测到仓库名（未让用户手填）
- [ ] skill 创建在 `<项目根>/.claude/skills/<repo-name>-work-flow/`
- [ ] SKILL.md 含 YAML frontmatter 且 `name=<repo-name>-work-flow`
- [ ] 骨架仅含：项目简介、技术栈、启动命令、端口/路径、目录结构
- [ ] 末尾明确标注 "调用 `/key_board_3` 添加 references 增强"
- [ ] 探测失败的字段写「待补充」而非编造
- [ ] 已存在 skill 时先询问用户，不直接覆盖
- [ ] 输出末尾提示用户调用 `/key_board_3` 进入增强流程
