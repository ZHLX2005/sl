***

name: b02-go-ctx-register

description: Go 插件化装配范式 —— 泛型注册中心 + init 自注册 + blank import 按需触发 + 工厂双模式（原型 New / 单例 Get）+ ctx 传值统一工厂签名。核心是用一个收敛的注册中心取代散落的 new，用 context 承载创建所需的类型化配置，让工厂签名永远不变。涉及 “Go 注册中心怎么写 / init 自注册 / blank import 触发注册 / 工厂原型与单例双模式 / ctx 传值统一工厂签名 / 同名重复注册静默覆盖 / 插件包反向 import 循环依赖” 时读取。

***

# b02 Go 注册中心 + init 自注册 + ctx 传值统一工厂签名

> 语言 / 框架特定的功能工程化意向（Go，仅依赖标准库 `context` + `sync`）。
> 不引入任何 DI 框架 —— “容器”的角色由 **注册中心 + init 自注册 + blank import** 三件套承担。

## 一、模式意向

**场景**：同一族可替换实现有 N 个分支（N 种连接器 / 处理器 / 驱动 / 模型 / 工具），各分支**构造参数不完全相同**，且要求 “加一个实现 = 加一个包 + 一行注册”，调用方零改动。

**要达到的效果**：

1. **接口与实现分离**：core 包只放 interface / Option，永不 import 任何实现包；
2. **注册中心收敛创建入口**：`name → 工厂` 的全局映射表，业务侧只经注册中心取实例，不再散落 `new`；
3. **init 自注册 + blank import 按需触发**：实现包在 `init()` 里登记自己；入口用 `_ "pkg"` 决定编译进哪些实现 —— 不 import 就不加载；
4. **双模式语义**：工厂同时提供 `New`（原型：每次新建）与 `Get`（单例：同配置复用），调用方按实例特征选择；
5. **ctx 传值统一签名**：把所有创建配置放进 `context`，工厂签名收敛为 `func(ctx) (T, error)`，新增配置字段不改变任何签名。

模式角色对应：

| 角色 | 承担 |
| --- | --- |
| core 接口包 | 只声明 interface / Option，零实现依赖 |
| 注册中心 | 泛型 `Registry[T]`，`name → T`（T 通常是工厂函数类型）的线程安全映射 |
| 组件包 | 一个实现一个包，`init()` 里 `Register(name, factory)` |
| 入口 cmd | blank import 全部组件包，触发注册 |
| 装配 / 解析层 | 读配置 → `Registry.Get(name)` → 工厂 → 实例 → 组装 |

## 二、目录骨架

```
core/       # 接口层：抽象契约（interface + Option 模式），不依赖任何实现
registry/   # 注册中心：name -> factory 的全局映射表（泛型 + sync.Map）
xxx/        # 组件包：每种实现一个包，init() 自注册
cmd/        # 入口：_ blank import 触发所有 init() 注册
parsing/    # 装配：从 Registry 取 factory 创建实例并组装
```

## 三、注册中心核心：泛型 Registry[T]

接口与实现分离成两个包：**接口在 `core/registry`，实现在 `x/registry`**，实现包只依赖接口。

```go
// core/registry/registry.go —— 契约，零实现依赖
package registry

type Registry[T any] interface {
    Register(name string, v T) error
    Unregister(name string)
    IsRegistered(name string) bool
    Get(name string) (T, bool)
    GetAll() map[string]T
}
```

```go
// x/registry/registry.go —— sync.Map 实现，线程安全
package registry

import (
    "fmt"
    "sync"
)

type registry[T any] struct{ m sync.Map }

func New[T any]() Registry[T] { return &registry[T]{} }

// Register 重复 key 直接报错（fail-fast），禁止后注册静默覆盖先注册
func (r *registry[T]) Register(name string, v T) error {
    if name == "" {
        return fmt.Errorf("registry: empty name")
    }
    if _, loaded := r.m.LoadOrStore(name, v); loaded {
        return fmt.Errorf("registry: %q already registered", name)
    }
    return nil
}

func (r *registry[T]) Get(name string) (t T, ok bool) {
    v, ok := r.m.Load(name)
    if !ok {
        var zero T
        return zero, false
    }
    t, ok = v.(T)
    return
}

func (r *registry[T]) IsRegistered(name string) bool {
    _, ok := r.m.Load(name)
    return ok
}

func (r *registry[T]) Unregister(name string) { r.m.Delete(name) }

func (r *registry[T]) GetAll() map[string]T {
    out := make(map[string]T)
    r.m.Range(func(k, v any) bool {
        out[k.(string)] = v.(T)
        return true
    })
    return out
}
```

**为什么用 `sync.Map` 而不是普通 `map`**：注册发生在各实现包的 `init()` 里，Go 的包初始化在同一 goroutine 内串行，但运行时可能有并发读 + 测试期并发注册/注销；`sync.Map` 免锁直接可用，避免给全局 map 外加 `sync.RWMutex` 的样板。

**为什么 `Register` 返回 error 而不是 panic**：注册由 `init()` 调用，panic 会让**整个进程启动失败且栈里看不到是哪个包**；返回 error 让调用方（init 或测试）决定如何处理，错误信息里带上 key。

### 包级单例暴露（每类组件一个文件）

```go
// x/registry/connector.go
package registry

import "example.com/project/core/connector"

// 工厂函数类型：类型安全，注册时传错函数签名会编译失败
type NewConnector func(opts ...connector.Option) connector.Connector

type connectorRegistry struct{ registry[NewConnector] }

// 包级单例：直接 var 初始化（Registry 本身并发安全，无需 sync.Once）
var connectorReg reg.Registry[NewConnector] = new(connectorRegistry)

func ConnectorRegistry() reg.Registry[NewConnector] { return connectorReg }
```

**要点**：注册中心是**包级变量**，不是某个 Factory struct 的字段 —— 这样谁也注册、谁都能查，Factory 只提供便捷方法，不独占注册表。

## 四、init 自注册与 blank import 按需触发

```go
// xxx/direct/connector.go —— 组件包只依赖 registry 接口
package direct

import "example.com/project/x/registry"

func init() {
    // init 里只做注册，不做网络/文件 IO
    if err := registry.ConnectorRegistry().Register("direct", NewConnector); err != nil {
        panic(err) // 启动期失败，早爆好过静默缺失
    }
}

func NewConnector(opts ...connector.Option) connector.Connector { /* ... */ }
```

```go
// cmd/app/register.go —— 唯一的触发点，集中放 blank import
package main

import (
    _ "example.com/project/xxx/direct"   // 触发 direct 的 init()
    _ "example.com/project/xxx/forward"
    _ "example.com/project/xxx/tcp"
    _ "example.com/project/xxx/auto"
)
```

运行时装配（配置驱动）：

```go
ln := registry.ListenerRegistry().Get(cfg.Listener.Type)   // name -> factory
l, _ := ln(listenOpts...)
l.Init(metadata.NewMetadata(cfg.Listener.Metadata))
```

**要点**：

- **只有 `init()` 里注册、且入口用 `_` import**，才能做到 “编译进哪个实现由 import 决定，不 import 不加载” —— 这是插件化的开关；
- `_ "pkg"` 的 blank import 集中放在一个 `register.go`，不要散落到业务代码里；
- `init()` 只做注册；任何可能失败/昂贵的初始化（建连接、读文件）都延后到工厂闭包里，避免 “import 即副作用”。

## 五、工厂双模式：原型 `New` 与单例 `Get`

**同一族工厂必须同时提供两种创建语义**，因为 “强制全局单例” 和 “每次都新建” 各有死穴：

| 方法 | 模式 | 行为 | 适用 |
| --- | --- | --- | --- |
| `New(ctx, name)` | **原型** | 每次调用创建新实例 | 需要独立实例、含状态、配置多变的组件 |
| `Get(ctx, name)` | **单例** | 同配置只创建一次，后续复用 | 创建成本高、无状态、配置固定的组件 |

**为什么两种都要**：若组件强制全局单例，初始化参数就被写死 —— 调用方 A 要 `/path-a`、调用方 B 要 `/path-b`，单例无法满足；反之若高成本组件（连接池、HTTP 客户端）每次新建，则重复初始化浪费。所以由调用方按实例特征选。

```go
// xxx/factory.go
package component

import (
    "context"
    "fmt"
    "sync"

    "example.com/project/x/registry"
)

type ComponentFactory func(ctx context.Context) (Component, error)

var compReg = registry.New[ComponentFactory]()

func init() {
    compReg.Register("typeA", NewTypeA) // 注册集中在 factory.go
    compReg.Register("typeB", NewTypeB)
}

func Registry() registry.Registry[ComponentFactory] { return compReg }

type Factory struct {
    singletons sync.Map // singletonKey -> Component
}

var (
    instance *Factory
    once     sync.Once
)

// 有状态的工厂对象用 sync.Once 懒加载
func GetFactory() *Factory {
    once.Do(func() { instance = &Factory{} })
    return instance
}

// New 原型模式：每次调用创建新实例
func (f *Factory) New(ctx context.Context, name string) (Component, error) {
    fn, ok := compReg.Get(name)
    if !ok {
        return nil, fmt.Errorf("component %q not registered", name)
    }
    return fn(ctx)
}

// Get 单例模式：同配置只创建一次，后续复用
func (f *Factory) Get(ctx context.Context, name string, cfgKey string) (Component, error) {
    key := name + "|" + cfgKey
    if v, ok := f.singletons.Load(key); ok {
        return v.(Component), nil
    }
    inst, err := f.New(ctx, name)
    if err != nil {
        return nil, err
    }
    actual, _ := f.singletons.LoadOrStore(key, inst)
    return actual.(Component), nil
}
```

### 组件模式选择指南

| 组件特征 | 推荐 | 原因 |
| --- | --- | --- |
| 创建成本高（连接池、HTTP 客户端） | 单例 `Get` | 避免重复初始化开销 |
| 需要不同配置参数 | 原型 `New` | 每个调用方独立配置 |
| 持有请求 / 会话状态 | 原型 `New` | 状态隔离，避免串扰 |
| 纯无状态、配置固定 | 单例 `Get` | 安全共享，减少 GC |

**单例缓存 key 必须包含全部配置参数**（如 `name|model|baseURL|dimensions`），否则不同配置会错误复用同一实例。**有状态对象（session / request context）禁止单例缓存**，必须每次 `New`。

## 六、ctx 传值：统一工厂签名

### 问题：构造参数不一致，签名无法统一

```go
// base 组件只需要 API 配置
NewBaseRunner(ctx, apiKey, modelName, baseURL)

// 另一个组件需要 API + 数据库配置
NewEventRunner(ctx, apiKey, dbCfg)
```

注册中心里存的是**固定类型的工厂函数**，无法同时兼容这些参数组合。若每个组件定义自己的工厂方法，就绕过了注册中心。

### 错误方案

| 方案 | 问题 |
| --- | --- |
| `func(args ...any)` | 丢失类型信息，调用方不知道该传什么 |
| 每个组件各自定义工厂方法 | 签名不统一，注册中心形同虚设 |
| 强制把参数塞进一个大 struct | 无关字段冗余，扩展时频繁改结构体 |

### 正确方案：配置经 context 传递，工厂签名收敛为 `func(ctx) (T, error)`

```go
// 1) 配置包（示例命名 ctxbiz）：每种配置独立 struct + Get/With 三件套
package ctxbiz

import "context"

// 配置的 ctx key 用「本类型的空 struct 实例」，Go 官方推荐，比 string 类型安全
type APIconfig struct {
    Model   string `json:"model" description:"模型名"`
    BaseURL string `json:"baseURL" description:"服务地址"`
    ApiKey  string `json:"apiKey" description:"密钥"`
}

func GetAPIconfig(ctx context.Context) (*APIconfig, bool) {
    cfg, ok := ctx.Value(APIconfig{}).(*APIconfig)
    return cfg, ok
}

func WithAPIconfig(ctx context.Context, cfg *APIconfig) context.Context {
    return context.WithValue(ctx, APIconfig{}, cfg)
}
```

```go
// 2) 统一工厂签名：所有组件同一签名，只依赖 ctx
type RunnerFactory func(ctx context.Context) (Runner, error)

func (f *Factory) New(ctx context.Context, name string) (Runner, error) {
    fn, ok := reg.Get(name)
    if !ok {
        return nil, fmt.Errorf("runner %q not registered", name)
    }
    return fn(ctx)
}
```

```go
// 3) init() 注册闭包：从 ctx 取配置，缺配置返回 error（禁止 panic）
func init() {
    // 通用组件：只需 APIconfig
    reg.Register("base", func(ctx context.Context) (Runner, error) {
        api, err := requireAPI(ctx)
        if err != nil {
            return nil, err
        }
        return buildRunner(ctx, api)
    })

    // 特殊组件：额外需要 DB 配置，按需组合
    reg.Register("event", func(ctx context.Context) (Runner, error) {
        api, err := requireAPI(ctx)
        if err != nil {
            return nil, err
        }
        var opts []Option
        if db, ok := ctxbiz.GetDBConfig(ctx); ok && db != nil {
            sqlTool, err := sqlFactory.New(ctx, "sql", db)
            if err != nil {
                return nil, fmt.Errorf("create sql tool: %w", err)
            }
            opts = append(opts, WithTool(sqlTool))
        }
        return buildRunner(ctx, api, opts...)
    })
}

// requireXxx 返回 error，缺配置不 panic
func requireAPI(ctx context.Context) (*ctxbiz.APIconfig, error) {
    cfg, ok := ctxbiz.GetAPIconfig(ctx)
    if !ok {
        return nil, fmt.Errorf("ctxbiz.APIconfig not found in context")
    }
    return cfg, nil
}
```

```go
// 4) 调用方：先注入配置，再调工厂；签名永远不变
func Handle(ctx context.Context, apiKey, model, baseURL string) (string, error) {
    ctx = ctxbiz.WithAPIconfig(ctx, &ctxbiz.APIconfig{ApiKey: apiKey, Model: model, BaseURL: baseURL})
    runner, err := component.GetFactory().New(ctx, "base")
    if err != nil {
        return "", err
    }
    return runner.Run(ctx, input)
}
```

### 收益

| 维度 | 效果 |
| --- | --- |
| 类型安全 | 每种配置是强类型 struct，编译期检查 |
| 签名统一 | `func(ctx context.Context) (T, error)` 一种签名适配所有组件 |
| 按需扩展 | 新增配置类型只需加 struct + Get/With，不改任何工厂签名 |
| 按需组合 | 组件只取自己需要的配置（base 不碰 DBConfig） |
| 解耦 | 调用方与工厂通过 ctx 解耦，不依赖具体参数列表 |

## 七、ctx 配置类型的字段约束

每个 ctx 配置 struct 都必须满足：

| 约束 | 说明 | 违反后果 |
| --- | --- | --- |
| key 用**空 struct 实例** | `ctx.Value(MyType{})` 而非 `"myType"` | string key 无命名空间，跨包冲突、数据被覆盖 |
| `Get` 返回 `(*T, bool)` | 第二个返回值表示是否存在 | 调用方无法区分 “不存在” 与 “零值” |
| `With` 接收 `*T` 注入 | 统一传指针 | 值拷贝，大结构有性能问题且修改不共享 |
| struct 带 `json` tag | 序列化 / 配置加载字段名可控 | 日志、配置加载时字段名混乱 |
| struct 带 `description` tag | 描述字段用途 | 字段语义无法机器理解，模板 / 文档失真 |
| 命名 `Get<Type>` / `With<Type>` | 统一前缀 | IDE 补全失效、命名混乱 |

**新增一个 ctx 配置类型的骨架**（直接复制填字段）：

```go
package ctxbiz

import "context"

type <Name> struct {
    Field1 string `json:"field1" description:"说明"`
    Field2 int    `json:"field2" description:"说明"`
}

func Get<Name>(ctx context.Context) (*<Name>, bool) {
    v, ok := ctx.Value(<Name>{}).(*<Name>)
    return v, ok
}

func With<Name>(ctx context.Context, v *<Name>) context.Context {
    return context.WithValue(ctx, <Name>{}, v)
}
```

**批量新增多个配置类型时按依赖顺序**（而非字母序）：几乎所有组件都依赖的放最前 —— 例如 `APIconfig → DBConfig → EmbeddingConfig → ModelConfig → ToolConfig → TelemetryConfig`。

## 八、边界与变体

| 情况 | 处理 |
| --- | --- |
| ctx 里该放什么 | **只放创建组件所需的配置**；实例（连接、Loader、Client）严禁放进 ctx，实例一律经工厂获取 |
| 配置型 vs 实例型签名 | 不能混用。配置型：`GetXxx(ctx) (*Xxx, bool)` / `WithXxx(ctx, *Xxx) context.Context`；实例型不存在（实例从工厂取） |
| 组合工厂（graph / 编排层） | 只**组合**已有组件工厂，不自己管理底层组件的注册；如 `retriever.Get().New(ctx, name)` 后再组装 |
| 注册位置 | **集中注册**（`factory.go` 的 `init()`）或**每文件各自 `init()`** 二选一，不要混；集中注册可一眼看到全部 key |
| 不允许反向 import | `tool/` 不准 import `agent/`，`model/` 不准 import `tool/`…… 反向 = 循环依赖。底层包只依赖接口 / 标准库 / 第三方 SDK |
| 无状态字符串集合（如 prompts） | 不需要注册中心，保持单例工厂即可 —— 属于 “刻意不注册” |
| 想看全部已注册项 | 暴露 `GetAll()` / 启动日志打印 key 集合，供核对 |

## 九、错误案例

| 错误操作 | 实际后果 | 正确做法 |
| --- | --- | --- |
| 在 `Get()` 的 `sync.Once` 里注册 | 延迟到第一次调用才注册，违背 init 自注册语义 | 包级 `var` + `init()` 注册 |
| 用普通 import 而非 `_` | 引入未使用的包 → 编译错误 | blank import `_ "pkg"` |
| Registry 用普通 `map` | 并发注册数据竞争 | `sync.Map` 或外加 `sync.RWMutex` |
| 注册中心放在 Factory struct 内 | 单例与注册表耦合，无法独立访问 | 注册中心是包级变量，Factory 只提供便捷方法 |
| `init()` 里做网络 / 文件 IO | 包导入即执行副作用，测试崩溃、可能 panic | `init()` 只注册，复杂初始化延后到工厂闭包 |
| `Register` 用 `Store`（直接覆盖） | 同名静默覆盖，先注册的功能整体失效且无报错 | `LoadOrStore` + 重复即返回 error |
| 泛型解析 / 配置缺失时静默降级 | 问题推迟到业务数据进来才爆 | fail-fast：解析不出 / 缺配置直接返回 error 或启动失败 |
| 强制全局单例 | 不同调用方需要不同配置时冲突 | 提供 `New()` 原型模式，按需创建 |
| 高成本组件每次新建 | 重复创建连接池，性能浪费 | 提供 `Get()` 单例缓存，key 含全部配置参数 |
| 有状态对象做单例缓存 | 多请求共享状态，数据混乱 | 有状态对象必须每次 `New()` |
| 用 `any` / `...any` 做工厂参数 | 丢失类型信息，调用方不知道传什么 | 用 ctx 传类型化配置 |
| ctx key 用 string（如 `"apiConfig"`） | 跨包冲突，值被覆盖或取错 | 用 struct 零值做 key（`APIconfig{}`） |
| `Get` 不返回 bool，直接类型断言 | 配置不存在时 panic | `v, ok := ctx.Value(MyType{}).(*MyType)` |
| 把实例（连接 / Client）塞进 ctx | 混淆配置与实例，生命周期失控 | 实例从工厂获取，ctx 只放配置 |
| 工厂闭包内 `panic("config not found")` | 生产环境崩溃 | `requireXxx` 返回 error |
| 改工厂签名时用 `sed` 批量改 | 函数体残留旧参数引用 / 孤立括号，语法错误 | 先 `grep -r` 扫全部调用点建 checklist，再手工精确改，**每改一处立即编译** |

## 十、可执行检测命令

```bash
# 1. 反向依赖（破坏分层）：底层包不准 import 上层包，预期无输出
grep -rn "example.com/project/tool" ./model/ --include="*.go"
grep -rn "example.com/project/agent" ./tool/ ./model/ --include="*.go"

# 2. 同名重复注册：统计每个名字的注册次数，应都为 1
grep -rhoP 'Register\("\w+"' . --include="*.go" | sort | uniq -c | awk '$1 > 1'

# 3. ctx key 用 string（应为 struct 零值）：预期无输出
grep -rn 'context\.WithValue(ctx, "' . --include="*.go"

# 4. init() 里的副作用：>10 行的 init 可疑
grep -rn -A 10 "^func init()" . --include="*.go" | grep -c "http\.\|os\.\|net\."

# 5. 工厂闭包里的 panic：预期无输出
grep -rn "panic(" . --include="*.go" | grep -i "factory\|register"

# 6. 文件过大（>300 行）：考虑按组件拆文件
find . -name "*.go" -exec wc -l {} \; | awk '$1 > 300 {print}' | sort -rn
```

## 十一、检查清单

- [ ] core 接口包不 import 任何实现包；实现包只 import 接口 / 标准库 / 第三方 SDK
- [ ] 注册中心是包级变量（不是某个 struct 的字段），泛型 `Registry[T]`，底层 `sync.Map`
- [ ] 每个组件包在 `init()` 里 `Register(name, factory)`；`init()` 内无网络 / 文件 IO
- [ ] 入口 `register.go` 用 `_ "pkg"` 集中 blank import 触发注册，业务代码里不散放
- [ ] 工厂同时提供 `New`（原型）与 `Get`（单例）；单例缓存 key 含全部配置参数；有状态对象只用 `New`
- [ ] 所有工厂签名收敛为 `func(ctx context.Context) (T, error)`，配置全部从 ctx 取
- [ ] 每种配置是独立 struct + `Get<Type>/With<Type>` 三件套；ctx key 用空 struct 实例
- [ ] `Get` 返回 `(*T, bool)`；字段带 `json` 与 `description` tag
- [ ] ctx 只放配置，不放实例；缺配置由 `requireXxx` 返回 error，无 panic
- [ ] 同名重复注册、泛型 / 配置不可解析一律 fail-fast，无静默覆盖与降级
- [ ] 无反向 import（底层包不依赖上层包），编译期无循环依赖
- [ ] 启动日志能打印 / 断言全部已注册 key 集合
