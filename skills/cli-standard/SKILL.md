---
name: cli-standard
description: 创建任何主题的标准 Go CLI 工具。当用户说"创建CLI"、"脚手架"、"go命令行工具"、"cobra项目"、"交互式CLI"、"渐进式引导CLI"、"标准 CLI 模板"时使用。基于 Cobra + survey/v2 + fatih/color 三件套，提供目录结构、双模式执行、交互式选择器、事务安全、场景级测试的完整规范。
metadata:
  type: skill
  version: 3.0.0
  tags: [go, cli, cobra, survey, color, scaffold, template, standard]
---

# cli-standard — 任何主题的标准 CLI 工具

> 基于 [2000-dev/git/gitlike](../../2000-dev/git/gitlike) 框架萃取 + 两个原 skill 合并：
> 合并自 `cli-project-template`（企业级交互式 CLI 完整规范）
> 合并自 `go-cli-framework`（基于 gitlike 框架的脚手架模板）
>
> **核心设计理念**：目录即架构、渐进式交互、颜色即信息、事务即安全。
>
> **适用范围**：需要在终端进行多步骤、多场景交互的 Go CLI 工具。
> **设计原则**：交互引导优先，CLI 参数兜底，事务安全，视觉统一。

---

## 何时加载哪个 ref

| ref | 何时读取 | 路径 |
| --- | --- | --- |
| [[cli-project-template-原版]] | 需要企业级规范细节（事务安全设计、扩展规范、文档规范、测试规范、失败场景记录）时 | references/cli-project-template-原版.md |
| [[go-cli-framework-原版]] | 需要 gitlike 框架萃取细节（渐进式 3 模式、终端文档输出、命令编写规范表）时 | references/go-cli-framework-原版.md |
| [[gitlike-真实案例]] | 需要看 9 个真实命令、4 个场景文档、场景级测试报告的实战参考时 | references/gitlike-真实案例.md |

---

## 技术栈（标准三件套）

| 库 | 版本 | 用途 |
|---|---|---|
| `github.com/spf13/cobra` | v1.10.2 | CLI 命令框架 |
| `github.com/AlecAivazis/survey/v2` | v2.3.7 | 交互式提示/选择 |
| `github.com/fatih/color` | v1.18.0 | 终端颜色输出 |

```bash
go get github.com/spf13/cobra
go get github.com/fatih/color
go get github.com/AlecAivazis/survey/v2
```

---

## 标准目录结构

```
mycli/
├── main.go                          ← 入口：仅调用 cmd.Execute()
├── go.mod / go.sum
├── CLAUDE.md                        ← 项目说明（含特殊功能要求）
├── cmd/                             ← 命令层（每个文件一个命令 + root）
│   ├── root.go                      ← 根命令 + 交互式选择器 + init() 注册子命令
│   ├── command1.go                  ← 场景/功能 1
│   ├── command2.go                  ← 场景/功能 2
│   ├── abort.go                     ← 场景：中止操作（事务安全）
│   └── conflict.go                  ← 场景：冲突处理
├── internal/
│   ├── color/color.go               ← fatih/color 封装（避免包级循环引用）
│   ├── ui/ui.go                     ← survey/v2 封装（统一交互入口）
│   └── <domain>/                    ← 领域操作层（git/api/docker/file...）
│       └── <domain>.go
├── docs/                            ← 中文文档（文件名使用中文）
│   ├── 场景1用法.md
│   ├── 场景2用法.md
│   └── 场景题原理.md
└── test/                            ← 测试（场景级 E2E 优先于单元测试）
    └── scenario/
        └── command1_test.go
```

---

## 渐进式交互 3 模式（核心设计）

每个命令支持三种调用模式，由 `interactive` 标志自动切换：

| 模式 | 调用方式 | 适用场景 |
|---|---|---|
| **A: 全交互** | `mycli` / `mycli command1` | 零参数启动，逐项提示 |
| **B: 混合** | `mycli command1 --flag1 val` | 部分参数传入，未传项继续交互 |
| **C: 全自动** | `mycli command1 --flag1 val --yes` | CI/CD / 脚本环境，跳过所有交互 |

### 实现模式

```go
func runCommand(cmd *cobra.Command, args []string) error {
    // 1. 先尝试从 flag 取值
    param := cmdFlag1
    interactive := param == ""  // 关键模式判断

    // 2. 仅当没传参数时才进入交互
    if interactive {
        param, err = ui.PromptString("请输入:", "")
        if err != nil { return err }
        if param == "" { return fmt.Errorf("xxx 不能为空") }
    }

    // 3. 确认环节也分模式
    if !cmdFlag2 && interactive {
        confirm, _ := ui.PromptConfirm("确认执行?", true)
        if !confirm { return nil }
    }

    // 4. 分步骤执行（带进度提示）
    ui.Info("步骤 1/N: 执行中...")
    // domain.DoSomething()
    ui.Success("✓ 步骤 1 完成")
    return nil
}
```

### 双模式执行（无参数 → 交互式选择器）

```go
// cmd/root.go
func Execute() {
    if len(os.Args) == 1 {
        runInteractive()  // 无参数 → 显示命令选择菜单
        return
    }
    if err := rootCmd.Execute(); err != nil {
        ui.Error("执行失败: %v", err)
    }
}

func runInteractive() {
    commands := []string{"cmd1", "cmd2"}
    descriptions := []string{"描述1", "描述2"}

    selected, err := ui.PromptSelectWithHelp("选择操作:", commands, descriptions, commands[0])
    if err != nil { ui.Error("选择失败: %v", err); return }

    // 解析选择结果 → 重新组装 os.Args → 调 rootCmd
    for i := range commands {
        if selected == commands[i] || selected == commands[i]+" - "+descriptions[i] {
            os.Args = []string{os.Args[0], commands[i]}
            rootCmd.Execute()
            return
        }
    }
}
```

---

## 核心代码模式（5 块必写）

### 块 1：`internal/color/color.go` — 颜色封装

```go
package color

import "github.com/fatih/color"

func Cyan(format string, a ...interface{}) string   { return color.CyanString(format, a...) }
func Green(format string, a ...interface{}) string  { return color.GreenString(format, a...) }
func Yellow(format string, a ...interface{}) string { return color.YellowString(format, a...) }
func Red(format string, a ...interface{}) string    { return color.RedString(format, a...) }
func Bold(format string, a ...interface{}) string   { return color.New(color.Bold).Sprintf(format, a...) }
```

### 块 2：`internal/ui/ui.go` — 交互式 UI 封装

```go
package ui

import (
    "fmt"
    "github.com/AlecAivazis/survey/v2"
    "mycli/internal/color"
)

// ── 彩色日志 ──
func Info(format string, a ...interface{})    { fmt.Println(color.Cyan("[INFO] ") + fmt.Sprintf(format, a...)) }
func Success(format string, a ...interface{}) { fmt.Println(color.Green("[SUCCESS] ") + fmt.Sprintf(format, a...)) }
func Warn(format string, a ...interface{})    { fmt.Println(color.Yellow("[WARN] ") + fmt.Sprintf(format, a...)) }
func Error(format string, a ...interface{})   { fmt.Println(color.Red("[ERROR] ") + fmt.Sprintf(format, a...)) }

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

func PromptMultiSelect(msg string, options []string, defaultVals []string) ([]int, error) {
    var selectedIndices []int
    prompt := &survey.MultiSelect{Message: msg, Options: options}
    if len(defaultVals) > 0 { prompt.Default = defaultVals }
    err := survey.AskOne(prompt, &selectedIndices)
    return selectedIndices, err
}
```

### 块 3：`cmd/root.go` — 根命令 + 交互式选择器

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

func init() {
    // rootCmd.AddCommand(cmd1Cmd)
    // rootCmd.AddCommand(cmd2Cmd)
}
```

### 块 4：`cmd/command1.go` — 一个完整命令的标准结构

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
    // ── 2. 交互式输入（仅当命令行未提供时） ──
    value := cmd1Flag1
    interactive := value == ""
    if interactive {
        v, err := ui.PromptString("请输入 xxx:", "")
        if err != nil { return err }
        if v == "" { return fmt.Errorf("xxx 不能为空") }
        value = v
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
    ui.Success(color.Bold("操作完成!"))
    return nil
}
```

### 块 5：`main.go` — 最简入口

```go
package main

import "mycli/cmd"

func main() {
    cmd.Execute()
}
```

---

## 关键设计原则

| 原则 | 说明 | 错误示例 |
|---|---|---|
| **单文件单命令** | 每个命令独立文件 | 把所有命令塞进 root.go |
| **RunE 返回 error** | 不用 os.Exit，保证 defer 执行 | 业务逻辑里直接 os.Exit |
| **init 只注册 flag** | init 中只做 flag 绑定，不做业务 | init 中调用 git 操作 |
| **flag 降级到交互** | flag 未传→交互式提示 | 直接报错说"缺少参数" |
| **确认/取消事务安全** | 取消时 return nil，不修改文件 | 取消了还执行了一半操作 |
| **分步 + 颜色输出** | 每步有 Info/Success/Error | 全用 fmt.Println |
| **中文文档同步** | docs/ 与命令一一对应 | 只写代码不写文档 |
| **场景级测试** | 临时目录做 E2E 测试 | 只有单元测试无场景测试 |

---

## 颜色语义约定

| 颜色 | 含义 | 使用场景 |
|---|---|---|
| `cyan` | 信息提示 | 步骤说明、状态信息 |
| `green` | 成功确认 | 操作完成、√ 通过 |
| `yellow` | 警告注意 | 未提交更改、潜在风险 |
| `red` | 错误/失败 | 操作失败、异常中止 |
| `Bold` | 标题/关键词 | 命令标题、操作摘要 |

---

## 事务安全设计（高风险命令必备）

```go
// ❌ 错误：边获取信息边修改
if err := doSomething(); err != nil {
    return err
}
confirm, _ := ui.PromptConfirm("确定?", true)

// ✅ 正确：先收集，再确认，再执行
info := collectInfo()
confirm, _ := ui.PromptConfirm("确认执行?", false)  // 高风险操作默认 false
if !confirm {
    ui.Warn("操作已取消")
    return nil  // 干净退出
}
execute(info)
```

**何时打终端文档让用户手动操作**：
- git 冲突中止
- 危险操作（force push、清理历史等）
- 需要用户确认外部工具输出

```go
func printDocument(title, body string) {
    boxWidth := 70
    border := strings.Repeat("━", boxWidth)
    fmt.Println(color.Cyan("┏" + border + "┓"))
    fmt.Println(color.Cyan("┃") + centerText("⚠ "+title, boxWidth) + color.Cyan("┃"))
    fmt.Println(color.Cyan("┃") + leftText("  "+body, boxWidth) + color.Cyan("┃"))
    fmt.Println(color.Cyan("┗" + border + "┛"))
}
```

---

## 新增命令的标准流程（10 步 checklist）

```
1. 在 cmd/ 下创建 <功能名>.go
2. 定义 cobra.Command 和包级 flag 变量
3. 实现 RunE 函数（注意 3 模式判断）
4. 在 cmd/root.go 的 init() 中注册 rootCmd.AddCommand()
5. 更新 root.go 的 Long 描述字符串
6. 更新 root.go 的 runInteractive() 的 commands/descriptions 切片
7. 将业务逻辑函数放到 internal/<domain>/
8. 在 docs/ 下创建对应的中文文档
9. 编译测试（go build ./...）
10. 创建场景级测试
```

---

## 易错点检查表

| 问题 | 后果 | 预防 |
|---|---|---|
| `RunE` 中忘了 `return nil` | 自动输出 `Usage` 帮助 | cobra 命令最后必须显式 return |
| `os.Exit(1)` 前没清理 | 临时文件残留 | 用 `defer` 清理或只用 `return err` |
| `PromptConfirm` 默认 `true` | 用户容易误确认 | 高风险操作默认 `false` |
| 交互式改了但 CLI 参数没跟着改 | 非 TTY 环境跑不了 | 每个交互输入都对应一个 flag |
| 忘记在 `root.go` 注册 | 命令存在但不可用 | 编译通过不代表已注册 |
| `Long` 只写英文 | 中文环境看不懂 | 所有用户可见文本用中文 |
| 混用 `fmt.Println` 和 `ui.Info` | 颜色风格不统一 | 用户输出全部用 `ui.*` |
| 直接修改 `runInteractive()` 没改注册 | 菜单/注册不同步 | 合并时检查两切片 |

---

## 场景级测试模式

测试必须创建真实仓库/真实环境做 E2E 测试，而非 mock：

```go
// test/scenario/command1_test.go
package scenario

import (
    "os/exec"
    "path/filepath"
    "strings"
    "testing"
)

func TestCommand1Basic(t *testing.T) {
    // 1. 创建临时目录 + 初始化仓库
    tmpDir := t.TempDir()
    run(t, tmpDir, "git", "init")
    run(t, tmpDir, "git", "config", "user.email", "test@test.com")
    run(t, tmpDir, "git", "config", "user.name", "test")
    os.WriteFile(filepath.Join(tmpDir, "f.txt"), []byte("base"), 0644)
    run(t, tmpDir, "git", "add", ".")
    run(t, tmpDir, "git", "commit", "-m", "init")

    // 2. 执行被测命令
    goBinary, _ := exec.LookPath("go")
    cmd := exec.Command(goBinary, "run", ".", "command1", "--flag1", "val", "--yes")
    cmd.Dir = tmpDir
    output, _ := cmd.CombinedOutput()

    // 3. 验证结果
    if !strings.Contains(string(output), "完成") {
        t.Fatalf("预期完成但未找到\n输出: %s", string(output))
    }
}
```

---

## 验证清单

- [ ] 项目有 `cmd/`, `internal/color/`, `internal/ui/`, `internal/<domain>/` 目录
- [ ] `internal/color/color.go` 包含 Cyan/Green/Yellow/Red/Bold
- [ ] `internal/ui/ui.go` 包含 Info/Success/Warn/Error + PromptString/PromptConfirm/PromptSelect/PromptSelectWithHelp
- [ ] `cmd/root.go` 在 `len(os.Args)==1` 时进入交互式选择器
- [ ] 每个业务命令支持 `--yes` 跳过确认
- [ ] 每个业务命令在无参数时进入交互模式
- [ ] 每个业务命令执行后验证结果
- [ ] 项目可编译通过 `go build ./...`
- [ ] 场景级测试覆盖每个业务命令

---

## 文件索引（主文档章节 → 真实案例代码）

| 文档章节 | 真实案例（gitlike） |
|---------|-------------------|
| 入口 | `2000-dev/git/gitlike/main.go` |
| 根命令 | `2000-dev/git/gitlike/cmd/root.go` |
| 颜色封装 | `2000-dev/git/gitlike/internal/color/color.go` |
| UI 封装 | `2000-dev/git/gitlike/internal/ui/ui.go` |
| 业务命令（9 个） | `2000-dev/git/gitlike/cmd/{cherry_pick,extract_commits,force_push,cleanup,migrate,abort,conflict,prfeat}.go` |
| 业务域 | `2000-dev/git/gitlike/internal/git/*.go` |
| 中文文档 | `2000-dev/git/gitlike/docs/场景名.md` |
| 场景测试 | `2000-dev/git/gitlike/test/scenario/` |

完整实战参见 [[gitlike-真实案例]]。

---

## 更新日志

| 版本 | 变更 |
|---|---|
| v1.0.0 | 初始模板：基本结构、双模式执行、交互式选择 |
| v2.0.0 | 新增扩展规范、引导规范、事务安全设计、文档规范、测试规范、失败场景记录 |
| v3.0.0 | 合并 cli-project-template + go-cli-framework，统一 3 模式渐进式交互，以 gitlike 真实案例为基准重写 |
