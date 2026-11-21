---
name: A09-template-generator
description: 把已跑稳的 server-cli-web 项目沉淀为可重用模板（templates/<id>/）——template.json 选项 schema、hooks.mjs 三钩子契约、文本 vs 二进制分发、列表变量展开、目标目录防覆盖与 dry-run；以及生成后 logo 现算这类「不该由通用生成器认识」的产物怎么交给钩子。
---

# A09 · 模板生成器：项目 → 可重发模板包

> 归属主文档 [[server-cli-web-scaffold]]。项目跑稳、想用 `npx xxx create` 再开同类项目时读这篇。
> 方向与创建流程相反：创建流程是「模板 → 项目」，本篇是「项目 → 模板」。

## 一、模板长什么样

```
templates/<id>/
  template.json          静态声明：id / name / description / namePrefix / nextSteps / options
  hooks.mjs              可选：默认导出 { options?, beforeGenerate?, afterGenerate? }
  files/                 模板树本体（原样复制，文本走 {{var}} 替换）
    src/ …
    tools/logo-gen/…     钩子要用的脚本（比如现算 logo）
```

`template.json` 的选项类型只有四种：`letters` / `string` / `number` / `enum`。
每个选项可带 `label` / `hint` / `default` / `required` / `pattern` / `values`。

```json
{
  "id": "server-cli-web",
  "name": "server-cli-web TS 骨架",
  "namePrefix": "nx-",
  "options": [
    { "name": "letters", "type": "letters", "required": true,
      "hint": "1~5 位小写字母，决定项目名、数据目录、bin 名与 logo" },
    { "name": "prefix", "type": "string", "default": "nx-", "pattern": "^[a-z0-9_-]*$" },
    { "name": "scheme", "type": "enum", "default": "mars",
      "values": ["klein", "mars", "hermes", "tiffany", "red", "vandyke", "prussian"] }
  ]
}
```

`letters` 是这一族的约定：项目名 = `prefix + letters`，同时派生数据目录、`bin/<name>.mjs`、logo 字母。
`nextSteps` 里的 `{{name}}` 用最终项目名渲染，生成完直接打给用户照做。

## 二、生成器怎么工作（六条硬事实）

1. **流式：从模板目录直接读、直接写目标**，不做「整树读进内存再写」。
   理由：模板可能含二进制资产（图片、字体），读成 utf8 再写会损坏；模板再大也不吃内存。
2. **只有文本走 `{{var}}` 替换**：判据是扩展名白名单 + 内容无 NUL 字节。
   二进制按字节复制，生成器**不认识**「图片」这个概念。
3. **列表变量会展开路径**：`files/a_{{lang}}/…` 配 `vars.lang = ['ts','go']` 会铺出
   `a_ts/…` 与 `a_go/…` 两份，文本里 `{{lang}}` 分别替换为对应标量。
4. **跳过清单固定**：`.git` / `node_modules` / `.DS_Store` / `template.json` / `.log` / `.tmp` 不带过去。
5. **目标目录已存在且非空 → 直接拒绝**：生成器覆盖用户目录是不可逆事故，
   宁可在这一步烦人（`BLOCKED`，让用户换目录或先清空）。
6. **`dryRun` 与真实生成共用 `walkTemplate`**：预览看到的文件清单 = 实际会写出的清单，
   不允许两条遍历逻辑各自演化。

## 三、hooks.mjs：三钩子契约

```js
export default {
  async options(ctx) { … },                 // 解析期：补动态默认值 / 改 hint
  async beforeGenerate(vars, ctx) { … },    // 生成前：返回要 patch 的变量
  async afterGenerate(targetDir, vars) { … } // 生成后：产出二进制 / 跑格式化
};
```

三条都能 async、都可省略；没有 `hooks.mjs` 一切照旧。

| 钩子 | 典型用途 | 返回 |
| --- | --- | --- |
| `options(ctx)` | 探测空闲端口、列出本机可用配色——值域依赖**运行环境**，写死在 json 里必然过期 | `OptionSpec[]`（按 name 合并，同名以动态为准） |
| `beforeGenerate(vars, ctx)` | 用户清空了端口要求"随便给一个"；把安装期占位渲染成字面量 | `Partial<Vars>`（patch） |
| `afterGenerate(target, vars)` | logo 全套（svg/png/ico）、代码格式化、生成额外清单 | 任意（生成器不解释） |

钩子拿到的 `ctx` 是**工具箱**（`probePort` / `probePorts` / `cwd` …），
模板作者不必 import 生成器内部模块——那会把模板和生成器内部路径绑死。

## 四、为什么 logo 不预置在模板里

模板里预置二进制 logo = 每次生成都是同一张图，而"图与项目名对不上"正是踩过的坑
（两个仓库的图标来自不同批次，肉眼可见不一致）。

正确做法：`afterGenerate` 里调用模板自带的 `tools/logo-gen`，**每次现算**。
这样做同时守住一条架构边界：**通用生成器永远不认识「图片」**，二进制产物由模板钩子负责。

## 五、把现有项目反推成模板

| 步 | 动作 | 判据 |
| --- | --- | --- |
| 1 | 复制一份干净项目到 `templates/<id>/files/`（先删 `node_modules` / `dist` / 本机数据） | `files/` 里没有生成物与个人配置 |
| 2 | 把随项目变化的值抽成 `{{var}}`：项目名、端口、描述、配色 | `grep -rn "旧项目名"` 在 `files/` 里为 0 |
| 3 | 写 `template.json`：`letters` + `prefix` + 端口 + 版本，`nextSteps` 用 `{{name}}` | 用 CLI 与面板两条路都能解析出默认值 |
| 4 | 需要环境相关默认值 / 二进制产物时写 `hooks.mjs` | 无钩子时也能生成成功 |
| 5 | 跑一次 `--dry-run`，再真正生成到一个空目录，`pnpm install && pnpm test` 全绿 | 生成出来的项目与手写项目行为一致 |
| 6 | 故意把目标目录填成非空，确认被拒绝 | 不会静默覆盖 |

## 检查清单

- [ ] `template.json` 的 `id` 与目录名一致，`name` 是人类可读名
- [ ] `files/` 里没有 `node_modules` / `dist` / 本机数据库 / 个人路径
- [ ] 所有随项目变化的值都是 `{{var}}`，没有硬编码旧项目名
- [ ] 二进制资产走字节复制，没有经过字符串替换
- [ ] `hooks.mjs` 只做三件事之一，且没有 import 生成器内部模块
- [ ] dry-run 清单与实际生成清单一致
- [ ] 目标非空时被拒绝（不是覆盖）

## 坑

| 坑 | 后果 | 正确做法 |
| --- | --- | --- |
| 整树读进内存再写 | 二进制损坏、大模板吃内存 | 流式逐文件复制 |
| 对二进制做 `{{var}}` 替换 | 图片/字体被写坏且难察觉 | 扩展名白名单 + NUL 检测 |
| 模板里预置 logo | 每个项目图标都一样，与名字对不上 | `afterGenerate` 现算 |
| 生成器里写"如果是 png 就…" | 通用生成器耦合具体产物类型 | 交给模板钩子，生成器不认识图片 |
| 目标目录已存在就直接写 | 覆盖用户已有代码，不可逆 | 非空即拒绝（`BLOCKED`） |
| dry-run 另写一套遍历 | 预览与实际不一致，用户被骗 | 共用 `walkTemplate` |
| 模板导入生成器内部模块 | 生成器重构时所有模板一起坏 | 只用 `ctx` 工具箱 |
