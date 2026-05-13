---
name: cli-project-template
description: Go CLI 项目模板，基于 Cobra + survey/v2 + fatih/color，支持交互式选择和颜色输出
metadata:
  type: skill
  version: 1.0.0
  tags: [go, cli, cobra, survey, color]
---

# cli-project-template

Go CLI 项目标准模板：基于 gitlike 项目结构，适用于需要交互式引导的终端工具。

## 技术栈

| 库 | 版本 | 用途 |
|---|---|---|
| `github.com/spf13/cobra` | v1.10.2 | CLI 命令框架 |
| `github.com/AlecAivazis/survey/v2` | v2.3.7 | 交互式提示/选择 |
| `github.com/fatih/color` | v1.18.0 | 终端颜色输出 |

## 项目结构

```
project/
├── main.go              # 入口，调用 cmd.Execute()
├── go.mod
├── CLAUDE.md            # 项目说明
├── cmd/
│   ├── root.go          # 根命令 + 交互式选择器
│   ├── cmd1.go          # 子命令1
│   ├── cmd2.go          # 子命令2
│   └── ...
└── internal/
    ├── color/
    │   └── color.go     # 颜色包装器
    ├── ui/
    │   └── ui.go        # 交互式提示 + 样式输出
    └── git/             # 业务逻辑（可选）
        └── git.go
```

## go.mod 依赖

```go
module projectname

go 1.25.3

require (
    github.com/spf13/cobra v1.10.2
    github.com/AlecAivazis/survey/v2 v2.3.7
    github.com/fatih/color v1.18.0
)
```

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

## 创建新项目

```bash
# 1. 创建项目目录
mkdir -p new-cli-project/{cmd,internal/{color,ui,git}}
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
```
