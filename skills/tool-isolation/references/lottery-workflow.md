# Style Lottery — 风格抽奖生成器（自迭代版）

> 何时读：用户要求"一次性生成 N 套不同风格的文件/图标/设计让我挑"、"再生成几个备选"、多轮迭代挑选场景时。
>
> **本版的强制流程**：每次进入 lottery 都自检目录（保留/缺失 vs 目标数），缺则自动补足；同时把缺失样本视为负面投票、写入 `lottery-history.md`，作为后续 subagent 的"禁区"。不要等用户主动说"再生成"。
>
> 本文档原为 `styles-skill/references/lottery-workflow.md`，归档到 tool-isolation 后，路径约定改为 `.tool/<test-name>/design/`（与 .tool 隔离规范保持一致，所有产物落进隔离区）。

## 触发条件

当以下任一情况触发（AI 自动触发，不需要等用户开口）：

- 用户表达："生成 N 套不同风格的 …"、"来几个方案让我选"、"再生成一个/几个"
- 同一任务第二次及以上被调用，且输出目录中已有之前生成的文件
- AI 进入此任务时自动盘点目录，发现保留数 < 目标数
- 用户删除了某些文件（保留数下降，触发补差）

## 核心目标

用 subagent 并行产出多种风格的候选文件，让用户通过"删除不满意、保留满意"的方式投票。AI 根据保留下来的文件推断用户偏好，继续生成更符合口味的新方案。

## 输出约定

- **所有生成物放在 `.tool/<test-name>/design/` 目录下**（若用户未指定路径）。`.tool/` 由 `tool-isolation` 主文档管理，遵循隔离规范。
- 每个 subagent 负责一种独立风格，产出一个自包含文件（HTML/SVG/PNG/视频脚本/图片 prompt 等）。
- 文件名必须体现风格，例如 `icons_flat_illustration.html`。
- 单文件外层 HTML/SCSS/JS/CSS 不需要 npm 依赖时不必建 package.json；如需构建工具链，按 `tool-isolation` 的"npm 工具流程"补充。

## 调用流程（每次都走完整闭环）

> **核心：每次进入 lottery 都强制走「盘点 → 补足 → 归档负面样例 → 推断偏好 → 派 subagent」五步闭环。
> 不是用户主动再说"再生成"才走后续流程 —— 是 AI 每次都主动审一遍。**

### Step 1. 盘点当前目录

读取 `.tool/<test-name>/design/` 目录全部文件，对每个文件做**保留/缺失**判定：

| 文件状态 | 含义 |
|---|---|
| 当前在目录里 | **正面投票**（用户喜欢） |
| 在 `.trash/` 目录里 | **负面投票**（用户看了不满意，已归档删除） |
| 名字出现在 `lottery-history.md` 但目录里完全没有 | 历史上产出过、被彻底删除 |
| 当前目录无文件 | 首次调用，跳到 Step 4 |

`.trash/` 目录约定：

- `.tool/<test-name>/design/.trash/<style>-<timestamp>.html`
- **AI 不要主动删** —— 由用户删除文件后**人工**或**watcher 钩子**移动到此处
- 如果没有 `.trash/`，把所有"产出过但不在目录"的也视作负面投票样本

### Step 2. 计算「补差量」

```
目标数 N（首次默认 4，后续默认保留峰值）
  = max(当前保留数, 上次目标数)
补差量 = N - 当前保留数
```

| 情况 | 行为 |
|---|---|
| 保留数 < 目标数 | 补差量 > 0，必须补足 |
| 保留数 ≥ 目标数 | 补差量 = 0，记录"已饱和"；继续走 Step 3 推断偏好，**不主动补** |
| 目录空 | 首次生成 N 个，跳到 Step 4 |

> **关键：「不足」是默认触发条件** —— 不会出现"以为已经够了"停止迭代的情况。

### Step 3. 推断偏好 + 归档负面样例

**正面**（在目录里）：
- 命名规律、色板、复杂度、情绪、材质、构图、设计语言

**负面**（在 `.trash/` 或历史删除）：
- **必须显式记录到 `lottery-history.md`，供后续 subagent 避开**

`lottery-history.md` 模板：

```markdown
# Lottery History — <test-name>

## 偏好（来自保留样本）
- 色板：<palette>
- 复杂度：<simple / moderate / rich>
- 情绪：<mood>
- 共同特征：<特征 1>、<特征 2>、…

## 反面（来自 .trash/ 删除样本）
- <style-1>：<一句话描述为什么差>（删除于 <timestamp>）
- <style-2>：<一句话描述为什么差>（删除于 <timestamp>）

## 迭代记录
- v1：生成 N 个 → 用户删 X 个
- v2：基于偏好补 Y 个 → …
```

### Step 4. 派发 subagent

**派发数量**：

| 情况 | 派发数 |
|---|---|
| 首次（目录空） | N（默认 4） |
| 补差（保留数 < 目标数） | 补差量 |
| 已饱和 | **不派发**，但可在 SUMMARY 里输出 "当前 N 个样本已饱和，请用户先评估并删除不喜欢的" |
| 出现明确瓶颈（负面样本已收敛到 2-3 类相同失败模式） | 按「瓶颈探索」模式派 1-2 个，刻意跨风格族突围 |

**并行 subagent 提示词模板**：

```
Create a file at `<path>` (under .tool/<test-name>/design/) in the style of <style_name>.
Purpose: <purpose>.
Quantity: <quantity>.
Unifying constraints: <color palette / dimensions / tone / format>.
Preferred (from kept samples): <palette>, <complexity>, <mood>.
Avoid (from .trash/ samples): <forbidden-style-1>, <forbidden-style-2>.
Output: single self-contained file, no external assets.
Write the file using the Write tool; do not paste the content back to chat.
```

**子 agent 拆分原则**：

| 维度 | 规则 |
|---|---|
| 风格族 | 每个 agent 必须属于不同的视觉族（neumorphism / flat / illustration / 3D / editorial / monochrome …） |
| 与负面样本距离 | 越靠近负面样本越危险；越跨族越安全 |
| 正面样本兼容 | 必须遵守 `lottery-history.md` 的偏好约束 |

### Step 5. 更新 history + 汇总

- 在 `lottery-history.md` 追加本次迭代的派发数 / 目标数 / 实际保留数
- 用 3-5 行 SUMMARY 输出当前状态：

```
[Lottery v3] .tool/<test-name>/design/
保留 4 / 目标 4 (饱和)
偏好：暖色调 + editorial 留白 + serif 标题
负面：渐变彩色（已归档 .trash/）、emoji-icon
本次未生成；建议：删除不喜欢的以触发自动补充
```

---

## 第一份（v0）走法

> 当 `design/` 空且无 `lottery-history.md`，按首次生成走：

1. **捕获需求**

   - 目标文件类型（图标、页面、组件、海报、视频、图片…）
   - 每个文件内包含的元素数量
   - 需要同时产出几种风格（默认 4）
   - 统一的约束（色板、尺寸、主题、格式、语言等）

2. **并行调用 subagent**（每个 agent 一种截然不同的风格）

   提示词只传递：
   - 目标文件路径（在 `.tool/<test-name>/design/<file>`）
   - 风格名称与定义
   - 产出目标与数量
   - 统一约束
   - 输出格式要求
   - "写文件即可，不要把内容贴回聊天"

   不预设 SVG/HTML/PNG/视频/图片等具体格式；由当前任务类型决定。

3. **初始化 `lottery-history.md`**（偏好留空、反面留空、迭代记录 v0）

4. **汇总结果**（列出文件 / 风格 / 路径，不贴代码）

## 第 N+1 份走法（每次进入 lottery 都自动跑 Step 1-5）

触发条件（任一即可）：
- 用户复述「再生成几个」/「再换风格」/「想看更多」
- 用户删除了某些文件（目录现存数 < 目标数）
- AI 主动重新打开这个测试时（每次任务启动都自检一次）

⚠️ **关键：AI 不要等用户开口**。每次 lottery 入口都自检 Step 1-2，缺则补。

## 一致性强约束

无论首次还是后续，每次生成时都必须向 subagent 强调：

- 同一批产出必须使用统一的设计语言（色板、比例、情绪、材质等）。
- 新方案在核心视觉语言上要尽量与保留方案兼容。
- 不允许每个文件各自为政、风格割裂。

## 与 tool-isolation 主规范的衔接

| 场景 | 路径 | 说明 |
|---|---|---|
| 纯静态 HTML / SVG / 图片 prompt | `.tool/<test-name>/design/<file>` | 无需 package.json，直接写文件 |
| 需要构建工具（esbuild / vite / sass） | `.tool/<test-name>/{src,dist,package.json}` + `design/<file>` | 按 `tool-isolation` 的 npm 工具流程建独立 `package.json`，`design/` 放产物 |
| 需要后端 / mock 数据 | `.tool/<test-name>/scripts/<file>.py` | 按 `tool-isolation` 的 Python 工具流程走 `uv venv` + `uv run python3` |
| 需要 CSS 预处理 | 嵌入 HTML 内 `<style>`，或 `.tool/<test-name>/design/<file>.css` | 不引入额外构建 |

> 关键：**路径统一以 `.tool/` 开头**，与项目代码、Git、Flutter 工程完全隔离。

## 自检脚本（建议）

`.tool/<test-name>/scripts/lottery-status.py` 一行命令即可查：

```bash
uv run python3 -c "
import os, sys
d = '.tool/<test-name>/design'
kept = [f for f in os.listdir(d) if not f.startswith('.')] if os.path.isdir(d) else []
trash = [f for f in os.listdir(d + '/.trash') if not f.startswith('.')] if os.path.isdir(d + '/.trash') else []
N = 4
gap = N - len(kept)
print(f'保留: {len(kept)}/{N}  缺失: {gap}  负面归档: {len(trash)}')
print('kept   :', sorted(kept))
print('trashed:', sorted(trash))
sys.exit(0 if gap == 0 else 1)
"
```

- exit 0 = 饱和，可以休息
- exit 1 = 缺，必须补足（让脚本自己决定是否触发 lottery）

## 错误案例

| 错误操作                         | 实际后果                           | 正确做法                         |
| -------------------------------- | ---------------------------------- | -------------------------------- |
| 后续调用时重新询问"你要什么风格" | 打断用户投票流程，显得没有记忆     | 直接检查保留文件并推断偏好       |
| 生成新方案时不考虑已删除的文件   | 可能再次产出用户讨厌的风格         | 删除记录即负面反馈，应主动规避，写入 `lottery-history.md` |
| 让 subagent 把代码/内容贴回聊天  | 上下文爆炸，用户无法直观比较       | 要求 agent 只写文件并确认路径    |
| 不检查目录就生成，导致风格重复   | 用户看到与保留方案雷同的新方案     | 列出目录内容，优先生成差异化风格 |
| 忽略设计语言一致性约束           | 同一批产出像来自不同项目           | 每次提示词都加入统一约束要求     |
| 把产物直接写到 `design/` 或项目根  | 污染项目目录，绕过 .tool 隔离       | 一律写到 `.tool/<test-name>/design/` |
| **AI 等用户说"再生成"才迭代**     | 多轮迭代靠用户记忆提醒，体感差     | **每次 lottery 入口都强制走 Step 1-5 自检闭环** |
| **删了文件但 AI 没记录**          | 下次又产出被删过的同款             | 删除立刻归档 `.trash/` + 更新 `lottery-history.md` |
| **补差量已饱和但 AI 仍继续派发**  | 目录臃肿，用户疲劳                 | 补差=0 时显式说明"已饱和"，暂停派发，等用户动作 |

## 提示词模板（仅供参考，非强制格式）

> 以下只是面向"图标"场景的示例，用于展示如何向 subagent 传递关键信息。实际任务可能是海报、视频脚本、图片 prompt 等，格式和约束会随之变化。

### 首次生成单个 agent 的提示词示例

```
Create a file at `<path>` (under .tool/<test-name>/design/) in the style of <style_name>.
Purpose: <purpose>.
Quantity: <quantity>.
Unifying constraints: <color palette / dimensions / tone / format>.
Output: single self-contained file, no external assets.
Write the file using the Write tool; do not paste the content back to chat.
```

### 后续生成提示词示例（基于偏好）

```
The user has kept: <list_of_files>.
Inferred preferences: <palette>, <complexity>, <mood>.
Generate a NEW style at `<path>` that is different from kept styles but compatible with the inferred preferences.
Respect the unifying constraints identified from kept files.
```