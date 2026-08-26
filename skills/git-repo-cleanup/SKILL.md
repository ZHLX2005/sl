---
name: git-repo-cleanup
description: 清理git嵌套仓库，保持仓库隔离性，让 git add . 干净无污染。适用于 .claude/repo/ 或其他包含克隆仓库的目录。 当用户提到"清理git"、"处理嵌套仓库"、"git隔离"、"保持干净"、 "部分跟踪"、"白名单子目录"、"忽略但保留子目录"、"gitignore 否定规则"、"忽略 .tool/"、"工具目录不入库"时触发。
---
# git-repo-cleanup 工作流程

## 问题背景

`.claude/repo/` 等目录包含通过 git clone 下载的嵌套仓库。这些仓库会被 git 检测为：

- 修改 (modified content)
- 嵌套 gitlink (作为子模块被跟踪)

导致 `git status` 不干净，`git add .` 会污染暂存区。

常见需求有两个层次：

- **完全忽略**：整个目录不跟踪
- **部分跟踪**：忽略目录下的克隆仓库，但跟踪一个"阅读笔记"子目录（如 `.claude/repo/_read/`）

## 标准声明结构（默认，整块写入）

**这是唯一默认写法。任何模式下都写入下面整块规则，一行不删：**

```gitignore
# Cloned repositories (nested git repos)
# 父目录必须用 /* 半透明模式，否则否定规则失效
.claude/repo/*
!.claude/repo/_read/
!.claude/repo/_read/**

!.claude/repo/_self/
!.claude/repo/_self/**

# Tool artifacts / scratch tools (本地工具产物，不入库)
.tool/
```

**三条硬规则**：

1. **整块写入，即使 `_read/`、`_self/`、`.tool/` 目前不存在。** 规则是前瞻性的——现在写入，目录以后创建时笔记自动入库、工具产物自动被忽略。不存在≠不写。
2. 白名单目录还不存在时，整块结构的行为与"完全忽略"完全一致（克隆仓库照样被忽略），零副作用。
3. 禁止用裸 `.claude/repo/` 或 `.claude/repo` 代替本结构（原因见高频错误案例表第 1、2 行）。

---

## 模式 A：默认处理（写入标准结构）

适用场景：`.claude/repo/` 下全是克隆仓库，没有（或还没创建）笔记目录。

### 1. 检查当前状态

```bash
# 查看哪些嵌套仓库被跟踪
git ls-files --stage .claude/repo/

# 查看 git status
git status
```

### 2. 添加到 .gitignore

写入上面的**标准声明结构整块**（`repo/*` + `_read`/`_self` 白名单 + `.tool/`）。

> ⚠️ 不要因为 `_read/`、`_self/`、`.tool/` 不存在就退化为裸 `.claude/repo/`——白名单为空时行为相同，但目录将来创建时标准结构自动生效，裸写法要返工。

### 3. 从 git 跟踪中移除

**如果是被跟踪的 gitlink (子模块)**：

```bash
git rm --cached -r .claude/repo/
```

**如果只是嵌套仓库（未被跟踪但有 modified content）**：

```bash
# 只需确保 .gitignore 生效
# 无需其他操作
```

### 4. 验证结果

```bash
# 确认暂存区干净
git status

# 提交更改
git add .gitignore
git commit -m "chore: ignore .claude/repo/ cloned repos, whitelist _read/_self, ignore .tool/"
```

**完成标准**：

- `git status` 显示 `nothing to commit, working tree clean`
- `git add .` 不会暂存 `.claude/repo/` 下的任何文件

---

## 模式 B：部分跟踪子目录（白名单）

适用场景：`.claude/repo/` 下保存了多个克隆仓库用于参考，其中 `_read/`、`_self/` 子目录是阅读笔记或摘要，希望纳入版本控制。

### 1. .gitignore 正确表达

**标准声明结构已经覆盖本模式，无需额外规则。** 若之前写的是裸 `.claude/repo/`，替换为标准结构整块。

**三行的作用**（每个白名单目录都是三行一组）：

- `.claude/repo/*` — 忽略目录下所有内容（注意是 `/*` 而非 `/`）
- `!.claude/repo/_read/` — 重新包含 `_read` 目录本身
- `!.claude/repo/_read/**` — 重新包含 `_read` 下的所有文件（含嵌套）

### 2. 验证规则生效

```bash
# 应该命中否定规则（不被忽略）。
# 注意：目录在磁盘上不存在时，必须带尾斜杠强制目录语义，
# 否则 git 按文件解析，目录型否定规则 !..._read/ 不会匹配
git check-ignore -v .claude/repo/_read/
git check-ignore -v .claude/repo/_read/bbolt/README.md

# 应该被忽略
git check-ignore -v .claude/repo/agentscope
git check-ignore -v .claude/repo/agentscope/README.md
```

预期输出：

- `_read/`（带尾斜杠）和 `_read/` 下文件命中 `!.claude/repo/_read/**` 等否定规则
- 其他子目录命中 `.claude/repo/*` 规则

### 3. 确认 .claude/repo 父目录本身可被发现

```bash
git check-ignore -v .claude/repo
# 预期：无输出（父目录不能被忽略，否则否定规则无法生效）
```

### 4. 提交更改

```bash
git add .gitignore
git add .claude/repo/_read/
git commit -m "chore: track .claude/repo/_read/ reading notes, ignore cloned repos"
```

---

## 模式 C：工具目录（.tool/）

适用场景：项目根下有 `.tool/` 目录保存工具脚本、临时脚本、辅助生成器、本地工具产物（如 `miniagent.exe`、`dev_ctr_hello.exe` 等已编译产物、scratch 工具）。这些工具与项目代码无关、不应纳入版本控制。

> **与模式 A 的区别**：`.tool/` 是**工具产物**，不是嵌套 git 仓库。处理方式更简单——只需在 `.gitignore` 中排除，无需考虑子模块解链。
>
> **标准声明结构已包含 `.tool/` 规则**——即使项目还没有 `.tool/` 目录也已写入。本模式只需处理两类遗留情况：之前误提交过（需解链）、或需要 `.tool/` 内部白名单。

### 1. 添加到 .gitignore

标准结构已含基础规则：

```gitignore
# Tool artifacts / scratch tools (本地工具产物，不入库)
.tool/
```

如果 `.tool/` 下只有少量子目录希望跟踪（比如 `tools/scripts/`），可用白名单模式：

```gitignore
# 忽略所有工具目录内容，但保留脚本子目录
.tool/*
!.tool/scripts/
!.tool/scripts/**
```

### 2. 从 git 跟踪中移除（若已跟踪）

```bash
# 如果之前误提交过 .tool/ 下的文件
git rm --cached -r .tool/

# 仅当目录里只有已编译产物（无 .git）才需要保留工作区文件
```

### 3. 验证规则生效

```bash
# 应该被忽略
git check-ignore -v .tool/
git check-ignore -v .tool/some-tool.exe

# 应该不被忽略（白名单模式）
git check-ignore -v .tool/scripts/build.sh
```

### 4. 提交更改

```bash
git add .gitignore
git commit -m "chore: ignore .tool/ for local tool artifacts"
```

**完成标准**：

- `git check-ignore -v .tool/` 命中忽略规则
- `git status` 不再显示 `.tool/` 下的任何变更
- `git add .` 不会暂存 `.tool/` 内容

---

## ⚠️ 高频错误案例

| 错误写法                                        | 实际后果                                                         | 正确做法                                              |
| ----------------------------------------------- | ---------------------------------------------------------------- | ----------------------------------------------------- |
| `.claude/repo` + `!.claude/repo/_read`      | 父目录被整体排除，否定规则**完全失效**，`_read` 仍被忽略 | 父级必须用`.claude/repo/*`（带 `*`）              |
| `.claude/repo/` + `!.claude/repo/_read/`    | 同上，`/` 结尾仍然排除父目录本身                               | 用`.claude/repo/*`                                  |
| 只有`!.claude/repo/_read/` 一行否定           | 只能恢复目录本身，目录里的文件仍被忽略                           | 必须再加`!.claude/repo/_read/**`                    |
| `repo/` 宽泛规则 + `.claude/repo/*`         | `repo/` 也会匹配 `.claude/repo` 作为目录                     | 删掉冗余的`repo/`，或改成 `repo/*` 并配合否定规则 |
| 否定规则写在忽略规则**之前**              | 后面的忽略规则仍生效，否定不触发                                 | 否定规则必须放在忽略规则**之后**                |
| 把`.tool/` 写成 `tool/`（少一个点）         | 可能误匹配其他非工具目录（如`toolchain/`、`tools/`）         | 必须带前导点`.tool/`，且 gitignore 区分大小写       |
| `.tool/` 规则加入后 `git status` 仍显示改动 | 之前已跟踪的文件没从索引移除                                     | 执行`git rm --cached -r .tool/` 后再提交            |
| "`_read/`、`_self/`、`.tool/` 还不存在，等存在了再加规则" | 目录创建时笔记不会自动入库、工具产物直接污染仓库，还得返工改 .gitignore | **不存在≠不写。** 标准结构整块写入，规则前瞻生效，空目录零副作用 |

### 根因速记

> **Git 的硬规则**：如果父目录被排除，否定规则 `!` 无法在它下面重新包含任何东西。
> 父目录必须"半透明"——自身不被忽略，但内部内容被忽略。这就是 `dir/*` 模式的本质。

---

## 常见问题排查

| 现象                                                                    | 原因                           | 解决                                              |
| ----------------------------------------------------------------------- | ------------------------------ | ------------------------------------------------- |
| `_read` 下的文件不出现在 `git status`                               | 父目录被整体排除               | 把`.claude/repo` 改成 `.claude/repo/*`        |
| `git check-ignore` 显示 `!.claude/repo/_read/**` 命中但文件仍不显示 | 父目录被排除，子文件无法浮上来 | 同上                                              |
| `git add .claude/repo/_read` 报错 `pathspec did not match`          | 父目录不存在或被规则屏蔽       | 检查`git check-ignore -v .claude/repo` 应无输出 |
| 部分子目录被跟踪了                                                      | 否定规则位置错误或缺`**`     | 重新检查三行顺序与内容                            |
| `git status` 看到 `modified content`                                | 嵌套仓库有改动                 | 已在 .gitignore 中，提交 .gitignore 即可          |
| `check-ignore .claude/repo/_read` 显示命中**忽略**规则而非否定规则 | 路径在磁盘上不存在，git 按文件解析，目录型否定 `!..._read/` 不匹配 | 用尾斜杠强制目录语义：`git check-ignore -v .claude/repo/_read/` |

---

## 验证清单

完成后必须满足（标准结构下的统一清单）：

**结构正确性**：

- [ ] `.gitignore` 中写入了**标准声明结构整块**（`repo/*` + `_read`/`_self` 白名单 + `.tool/`），未因目录不存在而省略
- [ ] `git check-ignore -v .claude/repo` 无输出（父目录半透明，否定规则才能生效）

**白名单生效**：

- [ ] `git check-ignore -v .claude/repo/_read/`（带尾斜杠）命中否定规则
- [ ] `git check-ignore -v .claude/repo/_self/`（带尾斜杠）命中否定规则
- [ ] `_read/` 已有文件时，`git status` 能看到其新文件

**忽略生效**：

- [ ] `git check-ignore -v .claude/repo/agentscope`（任一克隆目录）命中忽略规则
- [ ] `git check-ignore -v .tool/` 命中忽略规则
- [ ] `git status` 看不到克隆仓库与 `.tool/` 下的内容
- [ ] `git add .` 不会暂存任何克隆仓库内容

**解链（仅此前被跟踪过时）**：

- [ ] 若克隆仓库曾被跟踪，执行了 `git rm --cached -r .claude/repo/` 并提交
- [ ] 若 `.tool/` 曾被跟踪，执行了 `git rm --cached -r .tool/` 并提交
