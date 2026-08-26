---
name: gitlike-真实案例
description: Reference — 2000-dev/git/gitlike 真实项目案例。9 个 git 工作流命令、4 个场景级测试、3 类冲突处理文档，完整演示 cli-standard 标准骨架在企业级项目中的落地方式。
metadata:
  type: reference
  source_project: 2000-dev/git/gitlike
  language: Go
  framework: Cobra + survey/v2 + fatih/color
  commands_count: 9
  archived_at: 2026-08-05
---

# gitlike — cli-standard 真实案例

> 本文档是 [[cli-standard]] 标准骨架在企业级项目中的完整落地参考。
> 来源：`2000-dev/git/gitlike/`（企业级 Git 工作流辅助工具）

## 项目定位

| 维度 | 说明 |
|---|---|
| 工具名 | `gitlike` |
| 主题 | Git 工作流（migrate / cherry-pick / cleanup / conflict / abort...） |
| 包名 | `gitlike` |
| 入口 | `main.go` → `cmd.Execute()` |
| 根命令 | `gitlike`（无参数 → 交互式选择 9 个命令） |

## 目录落地

```
gitlike/
├── main.go
├── go.mod / go.sum
├── CLAUDE.md                          ← 项目说明（含 8 条特殊功能要求）
├── cmd/                               ← 9 个命令 + root
│   ├── root.go                        ← 根命令 + 9 个命令的交互式选择器
│   ├── abort.go                       ← 中止 merge/rebase/cherry-pick/revert/am
│   ├── cherry_pick.go                 ← Cherry-pick 其他分支的 commit
│   ├── cleanup.go                     ← 清理历史（ghost rewrite）
│   ├── conflict.go                    ← 批量解决 git 冲突
│   ├── extract_commits.go             ← 提取 commits 到 feat-xxx
│   ├── force_push.go                  ← 强制推送到远程并建立映射
│   ├── migrate.go                     ← 迁移工作区到 feat 分支
│   ├── migrate_with_memory.go         ← 带记忆的分支迁移
│   └── prfeat.go                      ← 创建 workerea-xxx + feat-xxx
├── internal/
│   ├── color/color.go
│   ├── ui/ui.go
│   └── git/git.go                     ← 所有 git 命令的 os/exec 包装器
├── docs/                              ← 中文文档
│   ├── 案例1.md
│   ├── 提取commits到feat分支.md
│   ├── 中止操作.md
│   ├── 冲突处理.md
│   ├── 冲突处理测试.md
│   ├── 冲突处理测试报告.md
│   ├── 合并冲突本质.md
│   ├── 清理历史.md
│   ├── 交互式选择器使用指南.md
│   ├── extract-commits测试报告.md
│   └── superpowers/
└── test/
    ├── hello/                         ← 场景测试用的 hello 项目
    └── scenario/                      ← 场景级 E2E 测试
        ├── abort_test.go
        ├── cleanup_helper_test.go
        ├── cleanup_history_test.go
        └── extract_commits_test.go
```

**与 cli-standard 主文档的对照**：

| cli-standard 规范 | gitlike 落地 |
|---|---|
| `<domain>/` 业务域 | `internal/git/git.go`（os/exec 包装器） |
| 每个命令一个文件 | 9 个命令各占 `cmd/<name>.go` |
| 中文文档 | `docs/场景名.md`（9 个） |
| 场景级测试 | `test/scenario/*_test.go`（4 个） |

---

## 9 个命令清单

| 命令 | 文件 | 核心功能 | 关键 flag |
|---|---|---|---|
| `migrate-workspace` | `cmd/migrate.go` | 迁移工作区到 feat 分支 | `--source`, `--target`, `--yes` |
| `migrate-with-memory` | `cmd/migrate_with_memory.go` | 带记忆的分支迁移 | `--source`, `--target`, `--yes` |
| `force-push-branch` | `cmd/force_push.go` | 强制推送到远程并建立映射 | `--branch`, `--remote`, `--yes` |
| `cherry-pick-branch` | `cmd/cherry_pick.go` | Cherry-pick 其他分支的 commit | `--source`, `--target`, `--yes` |
| `abort` | `cmd/abort.go` | 中止正在进行的 git 操作 | `--operation`, `--yes`, `--discard`, `--stash` |
| `resolve-conflicts` / `conflict` | `cmd/conflict.go` | 批量解决 git 冲突 | `--strategy`, `--yes` |
| `prfeat` | `cmd/prfeat.go` | 创建 workerea-xxx + feat-xxx | `--name`, `--yes` |
| `extract-commits` | `cmd/extract_commits.go` | 提取 commits 到 feat-xxx | `--source`, `--target`, `--yes` |
| `cleanup-history` | `cmd/cleanup.go` | 幽灵镜像清理（ghost rewrite） | `--yes` |

每个命令都遵循 cli-standard 的标准结构：

```go
// cmd/abort.go 节选
var (
    abortOperation string // --operation
    abortYes       bool   // --yes
    abortDiscard   bool   // --discard
    abortStash     bool   // --stash
)

var abortCmd = &cobra.Command{
    Use:   "abort",
    Short: "中止正在进行的 git 操作（merge/rebase/cherry-pick/revert/am）",
    Long:  color.Bold("...") + "..." + color.Cyan("支持的操作:\n") + "..." + color.Yellow("命令行参数:\n") + "...",
    RunE:  runAbort,
}

func init() {
    abortCmd.Flags().StringVar(&abortOperation, "operation", "", "...")
    abortCmd.Flags().BoolVar(&abortYes, "yes", false, "...")
    abortCmd.Flags().BoolVar(&abortDiscard, "discard", false, "...")
    abortCmd.Flags().BoolVar(&abortStash, "stash", false, "...")
}
```

---

## 交互式选择器（9 命令版）

`cmd/root.go` 完整展示了 cli-standard 推荐的"无参数 → 交互式选择器"模式：

```go
// cmd/root.go
func runInteractive() {
    fmt.Println()
    ui.Info(color.Bold("欢迎使用 Gitlike - 企业级 Git 工作流辅助工具"))
    fmt.Println()

    commands := []string{
        "migrate-workspace", "migrate-with-memory", "force-push-branch",
        "cherry-pick-branch", "abort", "resolve-conflicts",
        "prfeat", "extract-commits", "cleanup-history",
    }
    descriptions := []string{ /* 9 条对应中文描述 */ }

    ui.Info("请选择要执行的命令:")
    selected, err := ui.PromptSelectWithHelp("选择命令:", commands, descriptions, commands[0])
    if err != nil { ui.Error("选择失败: %v", err); return }

    var fullCmd string
    for i, cmd := range commands {
        if cmd == selected || selected == commands[i]+" - "+descriptions[i] {
            fullCmd = cmd
            break
        }
    }
    // ... 重新组装 os.Args → 调 rootCmd.Execute()
}
```

**注意**：commands/descriptions 两个切片必须严格同步，cli-standard 已在"易错点检查表"中标注。

---

## 事务安全设计：abort 命令的典型模式

`cmd/abort.go` 是事务安全设计的最佳示范：

```go
func runAbort(cmd *cobra.Command, args []string) error {
    // 1. 自动检测当前 git 状态（无需 flag 即可运作）
    currentOp, hasConflict, err := git.DetectCurrentOperation()
    if err != nil {
        ui.Error("检测失败: %v", err)
        return err
    }

    // 2. flag 为空时降级到交互式提示
    if abortOperation == "" {
        abortOperation = currentOp
    }

    // 3. 有冲突 → 打印终端文档让用户手动操作（事务安全）
    if hasConflict {
        printAbortConflictDocument(abortOperation)
        return nil  // 干净退出，不执行任何修改
    }

    // 4. 无冲突 → 显示摘要 + 确认 → 才执行
    if !abortYes {
        confirm, _ := ui.PromptConfirm("确认中止?", false)
        if !confirm {
            ui.Warn("操作已取消")
            return nil
        }
    }

    // 5. 分步骤执行
    ui.Info("步骤 1/N: 备份当前状态")
    if abortStash {
        git.StashChanges()
        ui.Success("✓ 备份完成")
    }
    // ...
    ui.Success(color.Bold("中止完成!"))
    return nil
}
```

**核心要点**：
- 检测 → 摘要 → 确认 → 执行（4 段式）
- 冲突场景**不执行任何修改**，只打印文档让用户手动操作
- 取消时 `return nil`，文件不被修改

---

## 终端文档输出（冲突处理时的标准模式）

`cmd/conflict.go` / `cmd/abort.go` 展示了"打印带边框的终端文档让用户手动操作"的模式：

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                       ⚠ 检测到 3 个文件冲突                            ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃  冲突文件:                                                          ┃
┃    1. src/main.go                                                   ┃
┃    2. src/utils.go                                                  ┃
┃    3. README.md                                                     ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃  请按以下步骤手动处理:                                                ┃
┃    1. 打开冲突文件，搜索 <<<<<<< HEAD 标记                          ┃
┃    2. 选择保留的代码段，删除标记                                     ┃
┃    3. git add <file>                                                ┃
┃    4. git commit 继续合并                                           ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**为什么用终端文档而不是直接执行**：
- 冲突解决是不可逆的"创作性"操作
- 用户必须看到全部上下文才能决策
- 自动 merge 策略可能在 50% 的情况下猜错

---

## 场景级测试（test/scenario/）

gitlike 把场景级测试当作主要测试手段：

| 测试文件 | 覆盖命令 | 关键模式 |
|---|---|---|
| `abort_test.go` | `abort` | 创建真实 git 仓库 → 制造 merge 冲突 → 验证 abort 行为 |
| `extract_commits_test.go` | `extract-commits` | 模拟多分支 + 多次提交 → 验证提取 + squash 合并 |
| `cleanup_history_test.go` | `cleanup-history` | 创建幽灵镜像 → 验证 ghost rewrite 行为 |
| `cleanup_helper_test.go` | `cleanup-history` 辅助 | 辅助函数单测 |

**典型场景测试结构**（取自 `abort_test.go` 思想）：

```go
func TestAbortWithMergeConflict(t *testing.T) {
    // 1. 创建临时目录 + 初始化 git 仓库
    tmpDir := t.TempDir()
    runGit(t, tmpDir, "init")
    runGit(t, tmpDir, "config", "user.email", "test@test.com")
    runGit(t, tmpDir, "config", "user.name", "test")

    // 2. 制造冲突场景
    os.WriteFile(filepath.Join(tmpDir, "f.txt"), []byte("base\n"), 0644)
    runGit(t, tmpDir, "add", ".")
    runGit(t, tmpDir, "commit", "-m", "init")

    runGit(t, tmpDir, "checkout", "-b", "feat")
    os.WriteFile(filepath.Join(tmpDir, "f.txt"), []byte("feat change\n"), 0644)
    runGit(t, tmpDir, "add", ".")
    runGit(t, tmpDir, "commit", "-m", "feat change")

    runGit(t, tmpDir, "checkout", "master")
    os.WriteFile(filepath.Join(tmpDir, "f.txt"), []byte("master change\n"), 0644)
    runGit(t, tmpDir, "add", ".")
    runGit(t, tmpDir, "commit", "-m", "master change")

    // 3. 制造 merge 冲突（预期会失败）
    runGit(t, tmpDir, "merge", "feat")  // 会留下 MERGE_HEAD + 冲突文件

    // 4. 执行被测命令
    cmd := exec.Command("go", "run", ".", "abort", "--operation", "merge", "--yes")
    cmd.Dir = tmpDir
    output, _ := cmd.CombinedOutput()

    // 5. 验证：MERGE_HEAD 已被清除
    if _, err := os.Stat(filepath.Join(tmpDir, ".git", "MERGE_HEAD")); !os.IsNotExist(err) {
        t.Fatalf("MERGE_HEAD 应该被清除但仍存在\n输出: %s", string(output))
    }
}
```

**核心原则**：测试必须创建**真实的 git 仓库**做端到端验证，不能 mock git 命令。

---

## 中文文档体系（docs/）

gitlike 把中文文档当作产品的"使用手册"来维护：

| 文档 | 主题 | 典型结构 |
|---|---|---|
| `案例1.md` | 端到端工作流示例 | 场景描述 → 步骤 → 效果 |
| `提取commits到feat分支.md` | 单个命令详解 | 问题 → 拓扑图 → 原理 → 解决步骤 |
| `中止操作.md` | 单个命令详解 | 4 种 git 操作的中止方法 |
| `冲突处理.md` | 冲突解决原理 | 合并冲突本质 → 处理流程 |
| `合并冲突本质.md` | 跨场景原理 | 3-way merge 算法解释 |
| `清理历史.md` | 单个命令详解 | ghost rewrite 算法 |
| `交互式选择器使用指南.md` | 入门文档 | 3 模式介绍 |
| `冲突处理测试.md` / `冲突处理测试报告.md` | 测试报告 | 资源清单 + 效果清单 |
| `extract-commits测试报告.md` | 测试报告 | 资源清单 + 效果清单 |

**文档与命令一一对应**：每个 `cmd/<name>.go` 都有一个 `docs/<name>.md`。

---

## 关键工程纪律（来自 CLAUDE.md）

`2000-dev/git/gitlike/CLAUDE.md` 提炼出的 8 条工程纪律：

```
1. 创建 cobra 项目
2. 交互式设计：按场景询问用户必须参数、可选参数，并支持命令行直接传入
3. 使用颜色库
4. 代码修改后必须完成编译测试：
   a. 生成测试相关资源（自己创建 hello 项目），优先场景级测试
   b. 执行
   c. 生成测试报告：使用了哪些资源、完成了哪些效果
5. 这是 git 项目，默认已安装 git
6. 基于企业工作的 git 场景
7. 必须先规划，再执行
8. 交互式流程设计：考虑 git 冲突时在终端显示文档让用户自己操作，保证中止的事务性
```

**特殊功能要求**：
- 生成文档存放到 `docs/`
- 文档名使用中文

---

## 复用本案例的步骤

要把本案例的模式套用到新主题 CLI（如 docker、api、file），按以下步骤：

```
1. 复制 gitlike 的目录结构（main.go / cmd/ / internal/{color,ui,domain}/ / docs/ / test/scenario/）
2. 把 internal/git/ 换成 internal/<你的领域>/
3. 在 cmd/ 下重新设计命令（参考 gitlike 的 9 个命令拆分思路）
4. 每个命令配一个 cmd/<name>.go + docs/<name>.md
5. 用 test/scenario/ 写场景级 E2E 测试
6. 在 CLAUDE.md 写清楚本项目的工程纪律
```

---

## 与 cli-standard 主文档的差异点

| 维度 | cli-standard 主文档 | gitlike 真实案例 |
|---|---|---|
| 规模 | 5 块必写代码模板 | 9 个真实命令 + 4 个测试 |
| 行业 | 通用 | 企业级 Git 工作流 |
| 错误处理 | 通用易错点 | git 特有的"冲突中止""force push"等高风险场景 |
| 文档 | 主文档自带 docs/ 规范示例 | 9 个真实中文文档 |
| 测试 | 通用场景测试模板 | 4 个真实 E2E 测试 |

**结论**：cli-standard 主文档提供"骨架"，本 ref 提供"血肉"。新主题 CLI 应先按主文档搭骨架，再参考本 ref 填血肉。
