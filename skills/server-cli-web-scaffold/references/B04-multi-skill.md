---
name: multi-skill
description: 把项目里"skill install / list"从一个默认 skill 扩到"多个 skill 区别安装、可选 `--group` 一键装一组"。读这一篇做扩展：当项目的 `skill install` 需要支持 `skill install foo`、`skill list`、`skill install --group=bar`。创建新项目时（阶段 6 之后）与给项目加第二种 skill 时读。B 组里本 ref 是扩展方案而不是重操作 ref——frontmatter 已说明。
---

# B04-multi-skill — skill 子命令的扩展方案（多 skill / list / `--group`）

> **本 ref 是扩展方案，不是创建决策。** B 组原是重操作 ref（debug / shim / scope registry 等），本 ref 是项目级扩展规范——读它一次，按它的形态扩展 `skill install / list`，之后长期稳定。

## 加载时机

- 项目需要支持多个 skill 区别安装时（默认 + 配套 skill）
- 项目需要 `skill list` 时
- 给现有项目加第二种 skill 时

不运行时读。

## 验收标准（必须能跑通才算完成）

1. **`skill install foo`**：显式装某个 skill
2. **`skill install --group=foo`**：一键装一组（`foo` 是 `groups.json` 里的 key）
3. **`skill install`**（无参数）：装**默认 skill**（见下文"默认 install 的约定"）
4. **`skill list`**：列出所有可装的 skill + 当前默认安装哪个 + 当前哪些 group
5. 三个 install 形式都能跑通真链路测试（装到 `~/.claude/skills/` 或 `--to <dir>`）

## 默认 install 的约定（解决"装哪个"的歧义）

| 概念 | 命名 |
|---|---|
| 项目主 skill 名 | = `package.json` 的 `name` |
| 默认 `skill install` 装的 skill | = 主 skill 名 |
| `groups.json` 里的"默认 group" key | = 主 skill 名 |

**为什么这样约定**：用户开箱即用（`skill install` 不报错也不问装哪个）；与 `package.json.name` 同名让"哪个项目装哪个 skill"在源文件里能直接看出来。

**违反任一条**就是 BUG：用户跑 `skill install` 装错了、或者 `groups.json` 与 `package.json` 不一致。

## CLI 形状

```
xxx skill install [name]       [--to <dir>] [--force]
xxx skill install --group=<g>  [--to <dir>] [--force]
xxx skill get    [name] [ref]  [--to <dir>]
xxx skill get    --group=<g> [ref] [--to <dir>]
xxx skill groups
xxx skill list
```

- `install` 与 `list` 是**强制命令面**（与 `get` 平级），不要当 `get` 的"补充"
- `--group` 支持两种写法：`--group=<g>` 与 `--group <g>`（等价；缺值 / 空值 / 值以 `-` 开头一律报错，绝不回落默认）
- `--group` 与位置参数 `[name]` **互斥**——同时给报 `INVALID_INPUT`（二者等价，报错比猜意图友好）
- `--to` 是统一的安装目录参数（与 `get` 一致）
- `list` 不用 `--to`，永远只列**包内**（`assets/` 下）的 skill

## `groups.json` 形状

```json
{
  "version": 1,
  "$comment": "group 名 → skill 名列表的别名表。路径恒由 assets/<skills[i]>/ 推导——本文件只做聚合，不是第二条事实源。",
  "groups": {
    "<project-name>": {
      "skills": ["<project-name>"],
      "summary": "本项目主 skill（默认 install 装的就是这个）"
    },
    "<其他 group 名>": {
      "skills": ["<skill>", "<skill2>"],
      "summary": "一组配套 skill"
    }
  }
}
```

约定：

- 顶层 key = group 名（`--group=<key>` 引用）；default install 用 key = `package.json.name`
- `skills` 是数组：为将来"一组含多个 skill"留余地（`--group=foo` 时整批装）
- `summary` 一句话说明这组是干嘛的（给 `skill list` 的输出用）
- 不在 `groups.json` 里的 skill 仍能装（`skill install <name>` 显式），只是没有 group 一键装
- 同一 group 里重复的 skill 名去重（避免重复三态与重复计数）

## `skill list` 的输出

```
$ xxx skill list
可装的 skill:
  * xxx               （默认 install）
  * xxx-loop
可装的 group:
  * xxx
  * xxx-loop

$ xxx skill list --json
{"skills":["xxx","xxx-loop"],"defaultGroup":"xxx","groups":["xxx","xxx-loop"],"source":"manifest"}
```

- `（默认 install）` 标记：`groups.json` 里 key 与 `package.json.name` 相同的那一项；无匹配时不显示标记
- `source` 字段暴露数据来源：`manifest`（清单驱动）| `assets-dirs`（降级目录扫描）——降级路径唯一能被观测的地方

## 错误与降级

| 情形 | 行为 |
|---|---|
| `skill install --group=bogus` | 报 `INVALID_INPUT`，**给出可用 group 列表**——AI 能据此自纠 |
| `groups.json` 缺失或损坏 | **降级到目录扫描**（每个 `assets/<x>/SKILL.md` 视作一个 group），不崩；损坏时 stderr 一行警告 |
| `groups.json` schema 错（缺 `groups`、某 group 缺 `skills`、含非法 skill 名） | 报 `INVALID_INPUT`（**不静默**——schema 错是作者/打包事故，藏着只会让 debug 抓瞎） |
| `--group=<name>` 与 `[name]` 同时给 | 报 `INVALID_INPUT`——二者只能选其一 |
| 清单声明了不存在的 skill | 延迟到 install 时报「未找到内置 skill」（清单是声明，资产齐备与否是另一回事） |

**降级策略一句话**：`assets/` 是兜底事实源；`groups.json` 是**便捷**而非**必需**——它坏了用户也能用，只是没了 group 一键装。

## 实现要点（容易踩的坑）

- **默认 install 推导**：读 `process.cwd()/package.json` 的 `name` 与 `groups.json` 顶层 key 匹配；读失败 → `defaultGroup: null`（render 不显示标记，不崩）
- **render 分支判别必须显式**：`Array.isArray(r.skills) && Array.isArray(r.groups)` 同时满足才走 list 分支——单 skill 安装结果里也可能带 `skills` 数组，靠单字段嗅探会被巧合命中
- **helper 复用**：list 与 groups 子命令共用 `loadGroups()` / `availableGroups()` / `listAssetDirs()`，**不重复实现目录扫描**
- **dispatcher 派发集中一处**：`install → get → groups → list` 的 `sub ===` 派发全在同一个函数里；新增子命令插在末尾，不要拆出独立派发函数
- **安装返回形状**：单 skill 与历史逐字节兼容（仅多一个 `group` 字段），多 skill 才走 `{status, group, skills:[...]}` 聚合——判别用显式 `group` 字段，不做形状嗅探

## 测试要点

- 用 `spawnSync(process.execPath, ...)` + 自定义 `USERPROFILE/HOME` 指向临时目录做隔离（**绝不碰真实 `~/.claude/skills`**）
- 注：Windows 上若 node 经 Volta 安装，改 `USERPROFILE` 会让 Volta 报 `Could not determine LocalAppData`——所以子进程必须用 `process.execPath`（真实 node 二进制）而非 PATH 上的 shim
- 伪资产树用环境变量（如 `XXX_ASSETS_ROOT`）指向临时目录——**在调用时读取而非模块加载时**，否则测试 import 顺序决定行为
- 覆盖：三种 install 形式、list 的默认标记、降级路径（删 groups.json 仍可用）、schema 错误报错、幂等（二次安装 skipped）、部分冲突聚合

## 自检（做完扩展后跑一遍）

- [ ] `package.json` 的 `name` 与 `groups.json` 默认 group key 同名
- [ ] `package.json` 的 `files` 字段含 `"assets/"`
- [ ] `groups.json` 里每个 `skills[i]` 都对应一个真实存在的 `assets/<name>/SKILL.md`
- [ ] 跑 `skill list` 输出正确（含默认 install 标记）
- [ ] `skill install <name>` 与 `skill install`（无参数）装的是同一个 skill
- [ ] `skill install --group=<key>` 装该 group 内的全部 skill
- [ ] `skill install --group=bogus` 报 `INVALID_INPUT` + 列出可用 group
- [ ] 删除 `groups.json` 仍能用（降级路径）

## 与现有 ref 的关系

- [[A03-cli-surface]]：`serve` / `skill install` / `skill get` 的**对外契约**（参数、--json、三段拼接）——本 ref 是其上的扩展，遵循同套约定
- [[A04-assert-skill]]：`assets/` 与项目文档的分工——本 ref 是它的"多 skill 分组"具体落地，**`groups.json` 是用户侧 agent 的资料（放 `assets/` 内），扩展规范本身留在本 ref**
- [[A07-extension-loop]]：加新功能域要碰的 12 处 + 三处静默失效点——本 ref 是其中"skill 子命令扩展"那一处的具体内容

## 反模式

| ❌ 反模式 | 为什么坏 |
|---|---|
| `groups.json` 与 `package.json.name` 不同名 | `skill install`（无参数）装错 skill，违反默认 install 约定 |
| 默认 install 装 `groups.json` 里所有 skill | `groups.json` 的存在意义就废了——"批量"与"默认"两个概念混在一起 |
| `groups.json` 缺失就崩 | 旧版本没 `groups.json` 也能跑——降级到目录扫描是兼容性要求 |
| `groups.json` 里塞 `description` / `tags` 等冗余字段 | schema 越复杂，跨项目同步成本越高——保持最小结构 |
| `skill install` 报错且什么都不做 | 违反"开箱即用"——必须降级到目录扫描，不能让用户面对空错误 |
| `skill list` 没有 group 分组 | 用户看不到 `--group` 怎么用、也看不到默认装的是哪个 |
| `runList` 自己重新读一遍 `assets/` | 与 groups 子命令重复实现目录扫描，逻辑漂移 |
| 多 skill 安装结果靠 `skills.length` 判别 | 长度 1 的退化结果也带数组——必须用显式 `group` 字段判别 |
