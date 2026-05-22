---
name: meta-lab-extention
description: |
  当用户要求"为XX语言创建lab规范skill"、"我要学Rust/Java/Go，生成对应的skill"、
  "创建一个学习项目的lab分层规范skill"、"按语言特性隔离lab并生成skill"时触发。
  此skill是"创建skill的skill"，用于为指定编程语言自动生成lab模块扩展规范skill。
---

从这两个skill当中获得skill的规范
/writing-skills 
/skill-creator

# Meta Lab Extention — 语言学习项目规范生成器

## 触发场景

- "我要学 Rust，给我建个 lab 规范的 skill"
- "为 Java 生成 lab 模块扩展 skill"
- "创建一个 Go 语言的学习项目规范 skill"
- "按语言特性隔离 lab，生成对应的 skill"
- "新建 XX 语言学习项目，需要 lab 分层规范"
- "帮我生成一个 xx 语言的 skill 来管理案例代码"

## 核心流程（必须按序执行）

### Step 1: 识别目标语言与工具链

从用户输入中提取：
- **目标语言**: Rust / Java / Go / Python / C++ / TypeScript 等
- **构建工具**: 该语言的主流包管理器/构建工具
  - Rust → Cargo (`Cargo.toml`)
  - Java → Maven (`pom.xml`) 或 Gradle (`build.gradle`)
  - Go → Go Modules (`go.mod`)
  - Python → uv (`pyproject.toml`)
  - C++ → CMake (`CMakeLists.txt`) 或 Meson
  - TypeScript → npm/pnpm (`package.json`)
- **lab 目录命名**: 默认 `lab/`，也可按语言缩写如 `py-lab/`、`rs-lab/`（多语言同仓库时）

### Step 2: 定义该语言的 Lab 分层规范

根据语言特性确定分层结构：

```
lab/
  {模块A}/           # 独立案例/知识点
    README.md        # 该模块的学习目标、运行方式
    源码文件         # 按语言惯例命名
    测试文件         # 单元测试/集成测试（如有）
  {模块B}/
    ...
```

各语言附加规范：
- **Rust**: 每个模块含 `Cargo.toml`（workspace member）或统一 workspace 管理；`src/main.rs` + `src/lib.rs`
- **Java**: 每个模块含 `src/main/java/` 和 `src/test/java/`；包名统一为 `lab.{模块}`
- **Go**: 每个模块是一个独立 package；`package {模块}`；测试文件 `_test.go`
- **Python**: 每个模块含 `__init__.py`；统一 `pyproject.toml` 管理依赖
- **C++**: 每个模块含独立的 `CMakeLists.txt` 或统一根目录 CMake 管理
- **TypeScript**: 每个模块含 `tsconfig.json` 或统一根配置；`index.ts` 为入口

### Step 3: 生成语言专属 Skill

在 `.claude/skills/{语言}-lab-extender/` 目录创建 `SKILL.md`。

生成的 skill **必须**包含：
1. YAML frontmatter（`name`、`description`）
2. 该语言的 lab 目录结构规范
3. 构建工具配置要求（如 `Cargo.toml` 如何注册 workspace member）
4. 扩展新模块的标准流程
5. 错误案例表格
6. 成功标准检查清单

### Step 4: 在项目根目录生成初始骨架（可选，如果用户要求）

如果用户明确说"新建项目"或"初始化项目"，则额外生成：
- 该语言的根构建配置文件（如 `Cargo.toml`、`pom.xml`、`go.mod`）
- `lab/` 目录
- 一个示例模块（如 `lab/hello_world/`）作为模板

### Step 5: 验证生成的 Skill

确认生成的 skill 文件满足：
- 目录正确: `.claude/skills/{语言}-lab-extender/SKILL.md`
- 包含 YAML frontmatter
- `description` 是触发描述，不是内容总结
- 包含至少 3 个错误案例
- 流程按序编号，可执行

## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 把生成的 skill 直接写在当前目录而非 `.claude/skills/` 下 | skill 无法被系统识别和触发 | 必须写入 `.claude/skills/{名称}/SKILL.md` |
| 生成 skill 时遗漏该语言的构建工具配置说明 | 用户后续扩展模块时不知道如何在 Cargo/Gradle 等中注册新模块 | 每个语言 skill 必须包含构建工具的模块注册方式 |
| 用同一套 Python 规范硬套到 Rust/Java 上 | 规范不适用，如要求 Rust 模块写 `__init__.py` | 根据语言特性定制规范，如 Rust 用 workspace member 而非 `__init__.py` |
| 生成的 skill `description` 写成内容总结而非触发条件 | skill 无法被正确匹配和触发 | `description` 必须写"当用户说XX时触发"形式的触发描述 |
| 忘记在生成的 skill 中包含错误案例 | 用户使用时频繁踩坑，重复犯错 | 每个生成的 skill 必须包含错误案例表格 |

## 成功标准检查清单

- [ ] 已识别目标语言和对应构建工具
- [ ] 已确定 lab 目录命名（`lab/` 或语言缩写形式）
- [ ] 已在 `.claude/skills/{语言}-lab-extender/` 创建 `SKILL.md`
- [ ] 生成的 skill 包含 YAML frontmatter（name + description）
- [ ] 生成的 skill 的 `description` 是触发描述
- [ ] 生成的 skill 包含该语言特有的模块结构规范
- [ ] 生成的 skill 包含构建工具的模块注册/依赖管理方式
- [ ] 生成的 skill 包含扩展新模块的标准流程（Step 1→N）
- [ ] 生成的 skill 包含错误案例表格（至少 3 条）
- [ ] 生成的 skill 包含成功标准检查清单
- [ ] 如用户要求初始化项目，已生成根构建配置和示例模块
