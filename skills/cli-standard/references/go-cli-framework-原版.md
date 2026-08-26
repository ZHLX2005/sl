---
name: go-cli-framework-reference
description: Reference — 原 go-cli-framework skill 归档版本。基于 gitlike 框架萃取的 Go CLI 脚手架模板：渐进式 3 模式、终端文档输出、命令编写规范表。已被 cli-standard 合并。
metadata:
  type: reference
  original_name: go-cli-framework
  archived_at: 2026-08-05
  merged_into: cli-standard
---

# Go CLI 脚手架 — Cobra + survey/v2 + fatih/color（原版归档）

> 基于 [gitlike](../reference:2000-dev/git/gitlike) 框架萃取，一套可复用的 Go CLI 项目结构模板。
> **核心设计理念：** 目录即架构、渐进式交互、颜色即信息。

## 依赖栈

```bash
go get github.com/spf13/cobra          # CLI 框架
go get github.com/fatih/color           # 终端颜色
go get github.com/AlecAivazis/survey/v2 # 交互式提示
```

## 目录结构

```
mycli/
├── main.go                ← 入口：仅调用 cmd.Execute()
├── go.mod / go.sum
├── cmd/                   ← 命令层（每个文件一个命令 + root）
│   ├── root.go            ← 根命令 + 交互式选择器 + init() 注册子命令
│   ├── command1.go        ← 场景/功能 1
│   └── command2.go        ← 场景/功能 2
├── internal/
│   ├── color/color.go     ← fatih/color 封装（避免包级循环引用）
│   ├── ui/ui.go           ← survey/v2 封装（统一交互入口）
│   └── <domain>/          ← 领域操作层（如 git、api、docker、file 等）
├── docs/                  ← 中文文档（文件名使用中文）
└── test/                  ← 测试资源（场景级测试）
    └── scenario/          ← 场景测试
```

## 快速开始

### 1. 创建项目骨架

```bash
mkdir mycli && cd mycli
go mod init mycli

# 安装依赖
go get github.com/spf13/cobra
go get github.com/fatih/color
go get github.com/AlecAivazis/survey/v2

# 创建目录结构
mkdir -p cmd internal/color internal/ui internal/domain docs test/scenario
```

### 2. 写入基础文件

#### `main.go` — 最简入口

```go
package main

import "mycli/cmd"

func main() {
    cmd.Execute()
}
```

#### `internal/color/color.go` — 颜色封装

```go
package color

import "github.com/fatih/color"

func Cyan(format string, a ...interface{}) string   { return color.CyanString(format, a...) }
func Green(format string, a ...interface{}) string  { return color.GreenString(format, a...) }
func Yellow(format string, a ...interface{}) string { return color.YellowString(format, a...) }
func Red(format string, a ...interface{}) string    { return color.RedString(format, a...) }
func Bold(format string, a ...interface{}) string   { return color.New(color.Bold).Sprintf(format, a...) }
```

#### `internal/ui/ui.go` — 交互式 UI 封装

```go
package ui

import (
    "fmt"
    "github.com/AlecAivazis/survey/v2"
)

// ── 彩色日志 ──
func Info(format string, a ...interface{})    { fmt.Println(cyan("[INFO] ") + fmt.Sprintf(format, a...)) }
func Success(format string, a ...interface{}) { fmt.Println(green("[SUCCESS] ") + fmt.Sprintf(format, a...)) }
func Warn(format string, a ...interface{})    { fmt.Println(yellow("[WARN] ") + fmt.Sprintf(format, a...)) }
func Error(format string, a ...interface{})   { fmt.Println(red("[ERROR] ") + fmt.Sprintf(format, a...)) }

// ── 交互式提示 ──
func PromptString(msg, defaultVal string) (string, error) {
    var answer string
    err := survey.AskOne(&survey.Input{Message: msg, Default: defaultVal}, &answer)
    return answer, err
}

func PromptConfirm(msg string, defaultVal bool) (bool, error) {
    var answer bool
    err := survey.AskOne(&survey.Confirm{Message: msg, Default: defaultVal}, &answer)
    return answer, err
}

func PromptSelect(msg string, options []string, defaultVal string) (string, error) {
    var answer string
    err := survey.AskOne(&survey.Select{Message: msg, Options: options, Default: defaultVal}, &answer)
    return answer, err
}

// PromptSelectWithHelp 带帮助文本的选择器 — 最实用的函数
func PromptSelectWithHelp(msg string, options, helpTexts []string, defaultVal string) (string, error) {
    if len(options) != len(helpTexts) {
        return "", fmt.Errorf("options and helpTexts must have the same length")
    }
    formatted := make([]string, len(options))
    for i := range options {
        formatted[i] = options[i] + " - " + helpTexts[i]
    }
    return PromptSelect(msg, formatted, formatted[0])
}

// ── 颜色助手（避免与 color 包循环引用） ──
func cyan(s string) string   { return "\033[36m" + s + "\033[0m" }
func green(s string) string  { return "\033[32m" + s + "\033[0m" }
func yellow(s string) string { return "\033[33m" + s + "\033[0m" }
func red(s string) string    { return "\033[31m" + s + "\033[0m" }
```

#### `cmd/root.go` — 根命令 + 交互式选择器

```go
package cmd

import (
    "fmt"
    "os"
    "mycli/internal/color"
    "mycli/internal/ui"
    "github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
    Use:   "mycli",
    Short: "一句话描述",
    Long: color.Cyan("MyCLI - 一句话描述\n\n") +
        color.Yellow("command1: ") + "描述1\n" +
        color.Yellow("command2: ") + "描述2",
}

func Execute() {
    if len(os.Args) == 1 {
        runInteractive()
        return
    }
    if err := rootCmd.Execute(); err != nil {
        color.Red("错误: %v", err)
    }
}

func runInteractive() {
    fmt.Println()
    ui.Info(color.Bold("欢迎使用 MyCLI"))
    fmt.Println()

    commands := []string{"cmd1", "cmd2"}
    descriptions := []string{"描述1", "描述2"}

    ui.Info("请选择要执行的命令:")
    selected, err := ui.PromptSelectWithHelp("选择命令:", commands, descriptions, commands[0])
    if err != nil {
        ui.Error("选择失败: %v", err)
        return
    }

    // 解析选择结果
    for i := range commands {
        if selected == commands[i] || selected == commands[i]+" - "+descriptions[i] {
            fmt.Println()
            ui.Info("已选择: %s", color.Green(commands[i]))
            fmt.Println()
            os.Args = []string{os.Args[0], commands[i]}
            rootCmd.Execute()
            return
        }
    }
}

func init() {
    // rootCmd.AddCommand(cmd1Cmd)
    // rootCmd.AddCommand(cmd2Cmd)
}
```

### 3. 创建业务命令（模板）

#### `cmd/command1.go` — 一个完整命令的标准结构

```go
package cmd

import (
    "fmt"
    "mycli/internal/color"
    "mycli/internal/<domain>"
    "mycli/internal/ui"
    "github.com/spf13/cobra"
)

// ── 命令行参数（包级变量） ──
var (
    cmd1Flag1 string // --flag1
    cmd1Flag2 bool   // --yes
)

var cmd1Cmd = &cobra.Command{
    Use:   "command1",
    Short: "简短描述",
    Long: color.Bold("标题\n\n") +
        color.Cyan("工作流程:\n") +
        "  1. 第一步\n" +
        "  2. 第二步\n\n" +
        color.Yellow("命令行参数:\n") +
        "  --flag1 <val>    描述\n" +
        "  --yes            跳过确认",
    RunE: runCmd1,
}

func init() {
    cmd1Cmd.Flags().StringVar(&cmd1Flag1, "flag1", "", "描述")
    cmd1Cmd.Flags().BoolVar(&cmd1Flag2, "yes", false, "跳过确认")
}

func runCmd1(cmd *cobra.Command, args []string) error {
    ui.Info(color.Bold("标题"))
    fmt.Println()

    // ── 1. 前置条件检查 ──
    // ...

    // ── 2. 交互式输入（仅当命令行未提供参数时） ──
    value := cmd1Flag1
    interactive := value == ""
    if interactive {
        value, err := ui.PromptString("请输入 xxx:", "")
        if err != nil { return err }
        if value == "" { return fmt.Errorf("xxx 不能为空") }
    }

    // ── 3. 显示摘要 → 确认 ──
    if !cmd1Flag2 && interactive {
        confirm, _ := ui.PromptConfirm("确认执行?", true)
        if !confirm {
            ui.Warn("操作已取消")
            return nil
        }
    }
    fmt.Println()

    // ── 4. 分步骤执行（带进度提示） ──
    ui.Info("步骤 1/N: 执行中...")
    // domain.DoSomething()
    ui.Success("✓ 步骤 1 完成")
    fmt.Println()

    // ── 5. 验证结果 ──
    ui.Info("验证中...")
    // ...

    // ── 6. 完成 ──
    ui.Success(color.Bold("操作完成!"))
    return nil
}
```

## 渐进式交互模式（核心设计）

这是 gitlike 框架**最丝滑的设计**。每个命令支持三种调用模式：

### 模式 A: 全交互式（零参数启动）

```bash
mycli                      # → 显示命令选择器 → 选择功能 → 逐项输入
mycli command1             # → 直接进入该命令的交互式流程
```

### 模式 B: 混合式（部分参数+部分交互）

```bash
mycli command1 --flag1 val # → 跳过该参数的输入，其他参数继续交互
```

### 模式 C: 全自动化（CI/脚本模式）

```bash
mycli command1 --flag1 val --yes  # → 跳过所有交互直接执行
```

### 实现模式

```go
func runCommand(cmd *cobra.Command, args []string) error {
    // 1. 先尝试从 flag 取值
    param := cmdFlag1
    interactive := param == ""  // 关键模式判断

    // 2. 仅当没传参数时才进入交互
    if interactive {
        param, _ = ui.PromptString("请输入:", "")
    }

    // 3. 确认环节也分模式
    if !cmdFlag2 && interactive {
        confirm, _ := ui.PromptConfirm("确认?", true)
        if !confirm { return nil }
    }
}
```

## 终端文档输出

当需要让用户手动操作（如 git 冲突中止、危险操作）时，打印带边框的终端文档：

```go
func printDocument() {
    boxWidth := 70
    border := strings.Repeat("━", boxWidth)

    fmt.Println(color.Cyan("┏" + border + "┓"))
    fmt.Println(color.Cyan("┃") + centerText("⚠ 标题", boxWidth) + color.Cyan("┃"))
    fmt.Println(color.Cyan("┃") + leftText("  内容", boxWidth) + color.Cyan("┃"))
    fmt.Println(color.Cyan("┗" + border + "┛"))
}

func centerText(text string, width int) string {
    if len(text) >= width { return text[:width] }
    left := (width - len(text)) / 2
    return strings.Repeat(" ", left) + text + strings.Repeat(" ", width-left-len(text))
}

func leftText(text string, width int) string {
    if len(text) >= width { return text[:width] }
    return text + strings.Repeat(" ", width-len(text))
}
```

## 场景测试模板

CLI 的测试应优先做**场景级测试**（E2E），而不是单元测试：

```go
// test/scenario/command1_test.go
package scenario

import (
    "os/exec"
    "testing"
)

func TestCommand1Basic(t *testing.T) {
    cmd := exec.Command("go", "run", ".", "command1", "--flag1", "val", "--yes")
    output, err := cmd.CombinedOutput()
    if err != nil {
        t.Fatalf("执行失败: %v\n输出: %s", err, string(output))
    }
    // 验证输出包含预期内容
    if !strings.Contains(string(output), "操作完成") {
        t.Errorf("未找到完成标记")
    }
}
```

## 命令编写规范

| 规范                      | 说明                                    | 强制 |
| ------------------------- | --------------------------------------- | ---- |
| **Use 短横线命名**  | `Use: "my-command"`                   | ✅   |
| **Short 一句话**    | `Short: "做什么"`                     | ✅   |
| **Long 含场景说明** | 用`color.Bold/Cyan/Yellow` 分块       | ✅   |
| **RunE**            | 用`RunE` 而非 `Run`（可返回 error） | ✅   |
| **--yes 统一**      | 每个业务命令都提供`--yes` 跳过确认    | ✅   |
| **包级 Flag 变量**  | `var cmd1Flag1 string`                | ✅   |
| **init 注册 Flag**  | `cmd.Flags().StringVar(&flag, ...)`   | ✅   |
| **分步骤日志**      | `步骤 1/N: 描述` + `✓ 步骤 1 完成` | ✅   |
| **操作摘要**        | 执行前显示摘要 + 确认                   | ✅   |
| **验证结果**        | 执行后验证状态                          | ✅   |

## References

| Ref | 路径 | 说明                                                  |
| --- | ---- | ----------------------------------------------------- |
| [[goframe-v2]]    | —   | 如果项目使用 GoFrame v2，优先使用 GoFrame 的 CLI 框架 |
| [[cli-project-template]]    | —   | 另一份 CLI 项目模板（基于 Cobra + survey/v2 + color） |

## 验证清单

- [ ] 项目有 `cmd/`, `internal/color/`, `internal/ui/`, `internal/<domain>/` 目录
- [ ] `internal/color/color.go` 包含 Cyan/Green/Yellow/Red/Bold
- [ ] `internal/ui/ui.go` 包含 Info/Success/Warn/Error + PromptString/PromptConfirm/PromptSelect/PromptSelectWithHelp
- [ ] `cmd/root.go` 在 `len(os.Args)==1` 时进入交互式选择器
- [ ] 每个业务命令支持 `--yes` 跳过确认
- [ ] 每个业务命令在无参数时进入交互模式
- [ ] 每个业务命令执行后验证结果
- [ ] 项目可编译通过 `go build ./...`
