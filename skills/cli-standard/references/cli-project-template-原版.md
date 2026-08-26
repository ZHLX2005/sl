---
name: cli-project-template-reference
description: Reference — 原 cli-project-template skill 归档版本。企业级交互式 CLI 完整规范：扩展规范、引导规范、事务安全设计、文档规范、测试规范、失败场景记录。已被 cli-standard 合并。
metadata:
  type: reference
  original_name: cli-project-template
  archived_at: 2026-08-05
  merged_into: cli-standard
---

# cli-project-template（原版归档）

Go CLI 项目标准模板：企业级交互式 CLI 的完整规范，包括项目结构、代码模式、扩展流程和引导规范。

> **适用范围**: 需要在终端进行多步骤、多场景交互的 Go CLI 工具
> **设计原则**: 交互引导优先，CLI 参数兜底，事务安全，视觉统一

---

## 技术栈

| 库 | 版本 | 用途 |
|---|---|---|
| `github.com/spf13/cobra` | v1.10.2 | CLI 命令框架 |
| `github.com/AlecAivazis/survey/v2` | v2.3.7 | 交互式提示/选择 |
| `github.com/fatih/color` | v1.18.0 | 终端颜色输出 |

---

## 项目结构

```
project/
├── main.go                          # 入口，调用 cmd.Execute()
├── go.mod
├── CLAUDE.md                        # 项目说明（含特殊功能要求）
├── cmd/
│   ├── root.go                      # 根命令 + 交互式选择器
│   ├── feat1.go                     # 子命令：场景1
│   ├── feat2.go                     # 子命令：场景2
│   ├── abort.go                     # 子命令：中止操作（事务安全）
│   └── conflict.go                  # 子命令：冲突处理
├── internal/
│   ├── color/
│   │   └── color.go                 # 颜色包装器
│   ├── ui/
│   │   └── ui.go                    # 交互式提示 + 样式输出
│   └── git/                         # 业务逻辑（可选）
│       └── git.go                   # Git 操作包装器
├── docs/                            # 中文文档
│   ├── 场景1用法.md
│   ├── 场景2用法.md
│   └── 场景题原理.md
└── tests/                           # 场景级测试（可选）
    └── feat1_test.go
```

---

## 核心代码模式

### 1. internal/color/color.go — 颜色包装器

```go
package color

import "github.com/fatih/color"

func Cyan(format string, a ...interface{}) string {
    return color.CyanString(format, a...)
}

func Green(format string, a ...interface{}) string {
    return color.GreenString(format, a...)
}

func Yellow(format string, a ...interface{}) string {
    return color.YellowString(format, a...)
}

func Red(format string, a ...interface{}) string {
    return color.RedString(format, a...)
}

func Bold(format string, a ...interface{}) string {
    return color.New(color.Bold).Sprintf(format, a...)
}
```

### 2. internal/ui/ui.go — 交互式 UI

```go
package ui

import (
    "fmt"
    "github.com/AlecAivazis/survey/v2"
    "project/internal/color"
)

func Info(format string, a ...interface{}) {
    fmt.Println(color.Cyan("[INFO] ") + fmt.Sprintf(format, a...))
}

func Success(format string, a ...interface{}) {
    fmt.Println(color.Green("[SUCCESS] ") + fmt.Sprintf(format, a...))
}

func Warn(format string, a ...interface{}) {
    fmt.Println(color.Yellow("[WARN] ") + fmt.Sprintf(format, a...))
}

func Error(format string, a ...interface{}) {
    fmt.Println(color.Red("[ERROR] ") + fmt.Sprintf(format, a...))
}

// 输入字符串
func PromptString(msg string, defaultVal string) (string, error) {
    var answer string
    prompt := &survey.Input{Message: msg, Default: defaultVal}
    err := survey.AskOne(prompt, &answer)
    return answer, err
}

// Yes/No 确认
func PromptConfirm(msg string, defaultVal bool) (bool, error) {
    var answer bool
    prompt := &survey.Confirm{Message: msg, Default: defaultVal}
    err := survey.AskOne(prompt, &answer)
    return answer, err
}

// 单选列表
func PromptSelect(msg string, options []string, defaultVal string) (string, error) {
    var answer string
    prompt := &survey.Select{Message: msg, Options: options, Default: defaultVal}
    err := survey.AskOne(prompt, &answer)
    return answer, err
}

// 带帮助描述的选择
func PromptSelectWithHelp(msg string, options []string, helpTexts []string, defaultVal string) (string, error) {
    formattedOptions := make([]string, len(options))
    for i, opt := range options {
        formattedOptions[i] = fmt.Sprintf("%s - %s", opt, helpTexts[i])
    }
    return PromptSelect(msg, formattedOptions, defaultVal)
}

// 多选列表
func PromptMultiSelect(msg string, options []string, defaultVals []string) ([]int, error) {
    var selectedIndices []int
    prompt := &survey.MultiSelect{
        Message: msg,
        Options: options,
    }
    if len(defaultVals) > 0 {
        prompt.Default = defaultVals
    }
    err := survey.AskOne(prompt, &selectedIndices)
    return selectedIndices, err
}
```

### 3. cmd/root.go — 根命令 + 交互式选择

```go
package cmd

import (
    "os"
    "project/internal/color"
    "project/internal/ui"
    "github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
    Use:   "appname",
    Short: "应用描述",
    Long: color.Cyan("AppName - 应用描述\n\n") +
        color.Yellow("subcommand1: ") + "子命令1说明\n" +
        color.Yellow("subcommand2: ") + "子命令2说明\n",
}

func Execute() {
    // 无参数时显示交互式选择菜单
    if len(os.Args) == 1 {
        runInteractive()
        return
    }
    if err := rootCmd.Execute(); err != nil {
        ui.Error("执行失败: %v", err)
    }
}

func runInteractive() {
    commands := []string{"subcommand1", "subcommand2"}
    descriptions := []string{"子命令1说明", "子命令2说明"}

    selected, err := ui.PromptSelectWithHelp("选择操作:", commands, descriptions, commands[0])
    if err != nil {
        ui.Error("选择失败: %v", err)
        return
    }
    // 转换为完整命令并执行
    fullCmd := selected
    os.Args = []string{os.Args[0], fullCmd}
    rootCmd.Execute()
}

func init() {
    rootCmd.AddCommand(subCmd1)
    rootCmd.AddCommand(subCmd2)
}
```

### 4. cmd/subcommand.go — 子命令模式

```go
package cmd

import (
    "project/internal/color"
    "project/internal/ui"
    "github.com/spf13/cobra"
)

var (
    flagBranch string
    flagYes    bool
)

var subCmd1 = &cobra.Command{
    Use:   "subcommand1",
    Short: "简短说明",
    Long: color.Bold("子命令1\n\n") +
        color.Cyan("工作流程:\n") +
        "  1. 步骤一\n" +
        "  2. 步骤二\n" +
        "  3. 步骤三\n",
    RunE: runSubCmd1,
}

func init() {
    subCmd1.Flags().StringVar(&flagBranch, "branch", "", "目标分支名")
    subCmd1.Flags().BoolVar(&flagYes, "yes", false, "跳过确认")
}

func runSubCmd1(cmd *cobra.Command, args []string) error {
    ui.Info("开始执行...")

    // Flag 为空时降级到交互式提示
    if flagBranch == "" {
        var err error
        flagBranch, err = ui.PromptString("请输入目标分支名:", "")
        if err != nil {
            return err
        }
    }

    if !flagYes {
        confirm, err := ui.PromptConfirm("确认继续?", true)
        if err != nil || !confirm {
            return nil
        }
    }

    ui.Success("完成!")
    return nil
}
```

### 5. main.go — 入口

```go
package main

import "project/cmd"

func main() {
    cmd.Execute()
}
```

---

## 关键设计模式

### 双模式执行

- **直接 CLI**: `appname subcommand --flag value` → 直接执行
- **交互模式**: `appname` (无参数) → 显示选择菜单 → 执行选定命令

### Flag 降级到交互式提示

```go
if flagValue == "" {
    flagValue, err = ui.PromptString("请输入值:", "")
}
```

### 步骤式执行 + 视觉反馈

```go
ui.Info("步骤 1/3: 执行操作")
// do something
ui.Success("✓ 步骤 1 完成")
```

---

## 扩展规范（如何正确加新命令）

### 新增命令的标准流程

```
1. 在 cmd/ 下创建 <功能名>.go
2. 定义 cobra.Command 和 flag 变量
3. 实现 RunE 函数
4. 在 cmd/root.go 的 init() 中注册 rootCmd.AddCommand()
5. 更新 root.go 的 help Long 描述字符串
6. 更新 root.go 的 runInteractive() 中的 commands/descriptions 切片
7. 将业务逻辑函数放到 internal/<模块>/
8. 在 docs/ 下创建对应的中文文档
9. 编译测试（go build ./...）
10. 创建场景级测试
```

### 扩展的核心原则

| 原则 | 说明 | 错误示例 |
|---|---|---|
| **单文件单命令** | 每个命令独立文件 | 把所有命令塞进 root.go |
| **RunE 返回 error** | 不用 os.Exit，保证 defer 执行 | 业务逻辑里直接 os.Exit |
| **cobra init 只注册 flag** | init 中只做 flag 绑定，不做业务 | init 中调用 git 操作 |
| **flag 降级到交互式** | flag 未传→交互式提示 | 直接报错说"缺少参数" |
| **确认/取消事务安全** | 取消时 return nil，不修改文件 | 取消了还执行了一半操作 |
| **步骤式 + 颜色输出** | 每步有 Info/Success/Error | 全用 fmt.Println |
| **中文文档同步** | docs/ 下的文档与命令一一对应 | 只写代码不写文档 |
| **场景级测试** | 创建临时目录做真实场景测试 | 只有单元测试无场景测试 |

### 事务安全设计

所有关键操作必须按以下模式设计：

```go
// 1. 先获取所有需要的信息
// 2. 显示操作摘要让用户确认
// 3. 用户否认 → return nil（干净退出）
// 4. 用户确认 → 才执行实际修改

// ❌ 错误：边获取信息边修改
if err := doSomething(); err != nil {
    return err
}
confirm, _ := ui.PromptConfirm("确定?", true)

// ✅ 正确：先收集，再确认，再执行
info := collectInfo()
confirm, _ := ui.PromptConfirm("确认执行?", false)
if !confirm {
    ui.Warn("操作已取消")
    return nil
}
execute(info)
```

---

## 引导规范（交互式引导的设计约定）

### 颜色语义约定

| 颜色 | 含义 | 使用场景 |
|---|---|---|
| `cyan` | 信息提示 | 步骤说明、状态信息 |
| `green` | 成功确认 | 操作完成、√ 通过 |
| `yellow` | 警告注意 | 未提交更改、潜在风险 |
| `red` | 错误/失败 | 操作失败、异常中止 |
| `Bold` | 标题/关键词 | 命令标题、操作摘要 |

### 输出规范

- **首次输出**: `ui.Info(color.Bold("命令标题"))` + 空行
- **步骤输出**: `ui.Info("步骤 1/N: 描述")` + `ui.Success("✓ 步骤 1 完成")`
- **确认摘要**: 用 `━━━` 分隔线包裹摘要区块
- **错误输出**: `fmt.Errorf("描述: %w", err)` 返回给 cobra

### 交互式流程设计规范

```
┌─ 用户触发 ─────────────────────────────┐
│  ui.Info("命令标题")                    │
│  fmt.Println()                          │
├─ 步骤 1: 检测当前状态 ────────────────┤
│  ui.Info("正在检测...")                 │
│  ui.Success("检测完成")                 │
│  fmt.Println()                          │
├─ 步骤 2: 用户输入 ────────────────────┤
│  flag 为空 → ui.PromptString(...)       │
│  flag 不存在 → ui.PromptSelect(...)     │
│  fmt.Println()                          │
├─ 步骤 3: 操作摘要 + 确认 ────────────┤
│  ui.Info("━━━ 操作摘要 ━━━")           │
│  ui.PromptConfirm("确认?", false)       │
│  !confirm → return nil                  │
├─ 步骤 4: 执行 ────────────────────────┤
│  for i, item := range items {           │
│    ui.Info("[%d/%d] 处理: %s", i, n, x)│
│    execute(item)                        │
│    ui.Success("  ✓ 完成")               │
│  }                                      │
├─ 步骤 5: 验证 + 完成 ────────────────┤
│  validate()                             │
│  ui.Success(color.Bold("全部完成!"))   │
└──────────────────────────────────────────┘
```

### 确认对话框规范

- **默认值**: `PromptConfirm` 默认 `false`（安全保守）
- **路径**: `git checkout -b backup-before-xxx` 之前必须确认
- **数据丢失风险**: 必须显示风险提示，不能自动跳过
- **冲突检测后**: 显示终端文档，阻止自动执行，让用户手动处理

---

## 扩展注意点（高频坑和预防）

### 易错点检查表

| 问题 | 后果 | 预防 |
|---|---|---|
| `RunE` 中忘了 `return nil` | 自动输出 `Usage` 帮助 | cobra 命令最后必须显式 return |
| `os.Exit(1)` 前没清理 | 临时文件残留 | 用 `defer` 清理或只用 `return err` |
| `PromptConfirm` 默认 `true` | 用户容易误确认 | 高风��操作默认 `false` |
| 交互式界面改了但 CLI 参数没跟着改 | 非 TTY 环境跑不了 | 每个交互输入都对应一个 flag |
| 忘记在 `root.go` 注册 | 命令存在但不可用 | 编译通过不代表已注册 |
| `longDesc` 只写英文 | 中文环境看不懂 | 所有用户可见文本用中文 |
| 混用 `fmt.Println` 和 `ui.Info` | 颜色风格不统一 | 用户输出全部用 `ui.*` |
| 直接修改 `root.go` 的 `runInteractive()` | 两边不同步 | 合并时检查 commands/descriptions 切片 |

### 典型失败场景记录

#### 场景 A：命令存在但未注册

```
症状: go build 通过，但运行时 Error: unknown command "xxx"
根因: cmd/xxx.go 写好了，但 root.go 的 init() 没有 AddCommand
修复: rootCmd.AddCommand(xxxCmd)
预防: 写完命令后立刻改 root.go
```

#### 场景 B：交互式菜单不显示新命令

```
症状: appname --help 能看到，但 appname 交互式菜单没有
根因: runInteractive() 里的 commands/descriptions 切片没更新
修复: 同步修改两个切片
预防: 把注册和菜单更新写成 checklist 项
```

#### 场景 C：flag 降级到交互提示写成了硬依赖

```
症状: 非 TTY 环境（CI/CD）直接报错 interactive prompt is disabled
根因: flag 没有默认值，且没有提供直接 CLI 参数路径
修复: 所有交互提示都对应一个 CLI flag，且允许 CLI 直接传
预防: "每个交互输入都对应一个 flag" 原则
```

---

## 文档规范

### docs/ 目录约定

```
docs/
├── 场景1用法.md        # 每个命令对应一个中文文档
├── 场景2用法.md
└── 场景题原理.md        # 跨场景的原理说明（可选）
```

- 文档名：中文
- 内容结构：问题描述 → commit 拓扑图 → 原理分析 → 解决步骤 → 总结
- 文档中嵌入关键命令、Git 算法解释、示意图

---

## 测试规范

### 场景级测试模式

测试必须**创建真实 git 仓库**做端到端测试，而非 mock。

```go
func TestScenario(t *testing.T) {
    // 1. 创建临时目录
    tmpDir := t.TempDir()

    // 2. 初始化 git 仓库
    run(t, tmpDir, "git", "init")
    run(t, tmpDir, "git", "config", "user.email", "test@test.com")
    run(t, tmpDir, "git", "config", "user.name", "test")

    // 3. 创建测试数据（分支、冲突等）
    os.WriteFile(filepath.Join(tmpDir, "f.txt"), []byte("base"), 0644)
    run(t, tmpDir, "git", "add", ".")
    run(t, tmpDir, "git", "commit", "-m", "init")

    // 4. 执行被测命令
    cmd := exec.Command(goBinary, "run", ".", "subcommand", "--yes")
    cmd.Dir = tmpDir
    output, _ := cmd.CombinedOutput()

    // 5. 验证结果
    if !strings.Contains(string(output), "完成") {
        t.Fatal("预期完成但未找到")
    }
}
```

---

## 创建新项目

```bash
# 1. 创建项目目录
mkdir -p new-cli-project/{cmd,internal/{color,ui,git},docs}
cd new-cli-project

# 2. 初始化 Go 模块
go mod init new-cli-project

# 3. 添加依赖
go get github.com/spf13/cobra@v1.10.2
go get github.com/AlecAivazis/survey/v2@v2.3.7
go get github.com/fatih/color@v1.18.0

# 4. 按模板创建文件
# - main.go
# - cmd/root.go
# - cmd/subcommand.go
# - internal/color/color.go
# - internal/ui/ui.go

# 5. 验证编译
go build ./...
```

---

## 更新日志

| 版本 | 变更 |
|---|---|
| v1.0.0 | 初始模板：基本结构、双模式执行、交互式选择 |
| v2.0.0 | 新增扩展规范、引导规范、事务安全设计、文档规范、测试规范、失败场景记录 |
