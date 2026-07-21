---
name: key_board_2
description: 当用户要求"总结成skill"、"保存对话为skill"、"提取提示词"、"做成技能"时触发。这是元技能模板，用于指导创建其他技能，而非被创建的技能本身。
---
# Key Board — Skill 创建元模板

## 依赖 skill 声明与校验（最高优先级，先于一切）

> **区分两层依赖，别混淆：**
> - **元层依赖**：key_board_2 自己运行所需的前置 = `skill-creator` / `writing-skills`。
> - **产物层依赖**：用户在**待总结内容**里指名的 `/xxxskill`，是**被创建的新 skill** 的前置，
>   必须写进**新 skill 自己**的 SKILL.md（frontmatter + 顶部声明），而不是写给 key_board_2。

**默认前置 skill（元层）：`skill-creator` / `writing-skills`**

### 规则

1. **识别依赖**：只要用户在指令里指名调用某个 `/xxxskill`（例如 `/sc:reflect`、`/k6`、`/tool-isolation`），
   即视为**前置 skill**——判断它属于元层还是产物层：
   - 用来指导"如何创建"→ 元层依赖（key_board_2 先加载）。
   - 出现在"新 skill 要做的事"里 → 产物层依赖（写进新 skill）。
2. **显式声明**：动手前，先在回复顶部用一行显式列出全部依赖：
   ```
   依赖skill: skill-creator, writing-skills, <用户指名的其它 skill>
   ```
   多个依赖用逗号分隔。
3. **加载校验**：逐个确认每个依赖 skill 是否存在/可加载。
4. **加载失败 = 直接终止**：只要有**任意一个**依赖 skill 无法加载，
   **立即停止**，不再执行后续任何步骤，并明确提示用户：
   ```
   ⛔ 依赖 skill 无法加载：<skill名>
   已终止本次 skill 创建。请先安装/修复该依赖后重试。
   ```

> 只有全部依赖都成功声明并加载后，才进入下面的「触发条件 / 创建流程」。

### Worked Example：产物层依赖如何落到新 skill

用户说：
> "让 ai 使用 **/k6** 这个 skill 进行压测，按照 **/tool-isolation** 的方式创建目录，
> 并且生成报告，报告中需包含具体时间和项目状态的 commit hash，方便快速定位。"

正确处理：

1. 识别产物层依赖：`k6`、`tool-isolation`（都是新 skill 运行时的前置）。
2. 先校验这两个 skill 可加载；任一失败 → 立即终止并提示（见规则 4）。
3. 新 skill 的 SKILL.md 里**显式写出**：
   ```markdown
   ---
   name: k6-load-test-report
   description: <触发描述>
   ---
   # ...
   依赖skill: k6, tool-isolation
   > 如任一前置无法加载，立即终止并提示用户。
   ```
   报告产物要求（具体时间、项目 commit hash）作为新 skill 的输出规范写入其正文。

## 触发条件

当用户说以下内容时触发：

- "总结成 skill"
- "保存对话为 skill"
- "提取对话中的提示词"
- "把我的要求存成技能文件"
- "做成 skill"

## 核心原则

**key_board 是"创建 skill 的 skill"，不是要被修改的 skill。**

每次创建新 skill 时，必须：

1. 创建**独立目录** `.claude/skills/<新skill名称>/`
2. 在目录内创建 `SKILL.md`
3. 必须包含 YAML frontmatter

## 创建流程（必须按序执行）

### Step 0: 依赖校验（见顶部「依赖 skill 声明与校验」）

先显式声明 `依赖skill: ...` 并逐个加载校验；**任一依赖加载失败即终止并提示**，不进入 Step 1。

### Step 1: 调用 /sc:reflect 反思

**先调用 /sc:reflect 进行复盘**，整理：

- 成功案例和成功根因
- 错误案例和错误根因
- 坑点和预防方法

### Step 2: Capture Intent

基于反思结果，理解用户意图，回答：

- 这个 skill 要解决什么问题？
- 什么时候触发？
- 输出格式是什么？

### Step 3: 创建目录

```bash
mkdir -p .claude/skills/<skill名称>/
```

### Step 4: 编写 SKILL.md

必须包含：

```yaml
---
name: <skill名称>
description: <触发描述>
---

# Skill 标题
## 内容...
```

### Step 5: 写入内容

基于 /sc:reflect 反思结果，填充成功/失败案例和坑点警示。

## 易错和坑（高频错误）

| 错误                                  | 根因                          | 预防                         |
| ------------------------------------- | ----------------------------- | ---------------------------- |
| 缺少 YAML frontmatter                 | 跳过格式直接写内容            | 写之前先确认文件结构         |
| 在 key_board 目录内创建新 skill       | 混淆元模板职责                | 新 skill 必须在独立目录      |
| frontmatter 的 description 放错误内容 | 没理解 description 是触发描述 | description=触发条件，非总结 |
| 跳过 Capture Intent                   | 急于输出                      | 必须先回答三个问题再动手     |
| 直接修改 key_board 自身内容           | 把元模板当普通 skill          | key_board 是模板，不应被修改 |
| 依赖 skill 没声明就动手                | 忽视前置 skill                | 先显式写出 `依赖skill: ...`  |
| 依赖加载失败仍继续创建                | 没做加载校验                  | 任一依赖失败立即终止并提示   |

## 错误案例记录规范

每个 skill 必须包含错误案例：

```
## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| ... | ... | ... |
```

### 我的犯错记录

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 把 skill 创建在 `memory/skills/` 目录 | skill 无法被系统识别和触发，分散了记忆与技能的职责 | skill 必须放在 `.claude/skills/<skill名>/SKILL.md` |

**常见坑点类型：**

1. **格式错误** — frontmatter 缺失/错误
2. **目录错误** — 在错误位置创建文件
3. **理解偏差** — 误解用户意图或工具能力
4. **流程跳跃** — 跳过必要步骤

## 成功标准检查清单

- [ ] 顶部已显式声明 `依赖skill: ...`（含用户指名的 /xxxskill）
- [ ] 已逐个校验依赖可加载；任一失败则终止并提示
- [ ] 创建了独立目录 `.claude/skills/<新skill>/`
- [ ] SKILL.md 包含 YAML frontmatter
- [ ] name 和 description 字段完整
- [ ] description 是触发描述，不是内容总结
- [ ] 内容包含触发场景、核心逻辑
- [ ] 包含错误案例警示（高频坑点）
- [ ] 调用 /sc:reflect 进行复盘

## 调用 skill-creator

创建完 skill 后，可选调用 skill-creator 进行：

- 测试用例编写
- 量化评估
- 描述优化
