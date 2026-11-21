---
name: A10-ts-action-pipeline
description: server-cli-web TS 版的 action 类型链路——TS 类 + @action 装饰器 + zod 单一契约，经 gen-actions / gen-api-client 生成 action 清单与前端 typed client；讲清 z.input 与 z.output、出参「实现即契约」、跨语言 output 视图、生成物新鲜度对账，以及从 JS 老写法增量迁移的边界。
---

# A10 · TS 类型链路：装饰器 action + zod 契约 + 代码生成 + typed client

> 归属主文档 [[server-cli-web-scaffold]]。新项目立 action、加 action、改契约时读这篇；存量 JS 项目按第六节迁移，分层原理另见 [[A00-design-and-verify]]。
>
> **语言口径**：`src/**`、`bin/**`、`tests/**` 与新写的工具脚本一律 TS（`.ts` / `.tsx` / `.mts`）。
> 生成器脚本在 nx-kv 现状是 `.mjs`，那是既成事实；**新项目写成 `.mts` 用 tsx 直跑**，
> 且脚本只做文件读写，不承载业务逻辑。不新增无类型 JS。

## 这一篇解决什么

「action 到底写在哪」「为什么不能手写前端请求函数」「类型凭什么不用写两遍」
「改了契约忘了重新生成会怎样」「老项目怎么一步步换过来」。

一句话：**契约只声明一次（zod），四个入口（CLI / HTTP / 前端 / 跨语言）都从它派生。**

## 一、三段式声明：schema + 装饰器 + 类

一条 action 由三部分组成，缺一不可：

```ts
// src/modules/repo/actions/add.ts
import { z } from 'zod';
import { action, ActionBase, type ActionInput } from '../../../runtime/index.js';

export const AddRepoInput = z.object({
  path: z.string().min(1),
  name: z.string().optional(),
  depth: z.number().int().min(1).default(1),
});

@action({
  id: 'repo.add',                    // 全局唯一：模块.动作
  cli: ['repo', 'add'],              // → xxx repo add <path>
  http: ['POST', '/api/repos'],      // → POST /api/repos
  summary: '登记一个仓库',            // 进 help 与面板
  input: AddRepoInput,               // CLI 与 HTTP 共用的唯一契约
})
export class AddRepoAction extends ActionBase<typeof AddRepoInput> {
  async run(ctx: ActionInput<this['_input']>) {
    return this.ctx.repo.add(ctx.input);   // 返回即契约，见第三节
  }
}
```

| 部分 | 作用 | 唯一性 |
| --- | --- | --- |
| `AddRepoInput`（zod） | 参数形状 + 运行时校验 + 类型来源 | **全局唯一**；CLI 与 HTTP 都解析它 |
| `@action({...})` | 把这条 action 暴露到哪些面（CLI 路径 / HTTP 路由 / help 文案） | 每条 action 一份 |
| `ActionBase` 子类 | 实现（调 service） | 每条 action 一个文件 |

**为什么用类而不是对象字面量**：类能带泛型实参（`ActionBase<typeof AddRepoInput>`），
入参类型因此可以从类上「反推」出来——前端只 import 这个类，就能拿到 `z.input<…>`。
对象字面量没有这个类型锚点，只能再写一份 `Input` 类型，那就是第二份声明。

## 二、生成链：两个脚本、三类产物

```bash
pnpm gen          # = gen-actions + gen-api-client（test 链里也会跑）
```

| 脚本 | 扫描什么 | 产出 | 谁消费 |
| --- | --- | --- | --- |
| `scripts/gen-actions.mjs` | `src/modules/*/actions/*.ts` 里所有继承 `ActionBase` 的类 | `actions/_manifest.generated.ts` | 模块装配（静态 import） |
| `scripts/gen-api-client.mjs` | 运行时 registry 里**带 zod fields** 的 action | `web/frontend/api/client.generated.ts` + `cli-tree.json` | 前端 / 文档 / 面板 |
| `scripts/gen-dart-client.mjs`（可选） | 声明了 `output` 的跨语言 action | `contract/dart/**` | 外部语言客户端 |

**为什么是「生成」而不是「运行时扫目录」**（三条实测理由，改设计前先看）：

1. 运行时扫描要动态 `import` 每个文件，而注册表是**同步**建好的；动态 import 是异步的 →
   只能上顶层 await，把 CLI / HTTP / server 三条链全变成异步初始化。
2. 生成物有**新鲜度对账测试**：改了声明忘了生成，`pnpm test` 当场红；运行时扫描没有这个可钉的边界。
3. 生成物是静态 import，`tsc` 与打包器都能看见；运行时扫描对类型检查不可见。

**生成器不写时间戳噪声**：内容没变就不落盘（`writeIfChanged`）。否则每次 `pnpm test`
都刷新二十来个文件的 mtime，编辑器重扫、tsc 增量缓存失效、IDE 顺手把隔壁 Dart 包 pub 一遍。

## 三、类型从哪来（最容易写错的一节）

| 位置 | 用什么 | 为什么 |
| --- | --- | --- |
| handler 入参 | `ActionInput<this['_input']>`（= `z.output`） | `.default()` 已填好，handler 拿到的一定是完整形状 |
| 调用方入参（CLI / 前端） | `z.input` | 带 `.default()` 的字段在调用侧是**可选**的 |
| handler 出参 | **没有 schema**，方法签名即契约 | 同一信息只声明一次，杜绝"两份声明漂移" |
| 跨语言出参 | 额外声明 `output`（zod **视图**，只列要暴露的字段） | Dart 拿不到 TS 类型；`output.safeParse(真实返回)` 由测试对账 |

**别把 `z.input` 和 `z.output` 混用**：混了不会报类型错，只会在某个默认值没填时
把 `undefined` 传进 service——表现为"参数偶尔是空的"，最难查。

**出参为什么不给 schema**：给了就要维护两份（方法返回 + schema），而两份一定会漂。
跨语言场景是唯一例外，因为对方拿不到 TS 类型——这时 `output` 是**视图**（只列对端要的字段），
不是 service 的完整返回结构。

## 四、装饰器的三个实测坑

1. **元数据挂方法函数上（WeakMap），不要挂 `context.metadata`**：
   tsx（esbuild）编译时 `Symbol.metadata` 在 Node 里是 `undefined`，用 context 会**静默丢元数据**。
2. **装饰器不能改方法签名**（TC39 要求返回类型兼容），也给不了被标方法的参数推断——
   入参类型走基类泛型 + 幻影字段 `_input`，装饰器里 `value` 用 `any` 透传。
3. **`http: null` 是显式声明**：纯 CLI 命令必须写 `null`（不是省略），测试会断言"两种态都存在"。

## 五、新鲜度对账（生成物的唯一保障）

```bash
pnpm gen && git diff --exit-code -- 'src/modules/**/_manifest.generated.ts' \
  'src/web/frontend/api/client.generated.ts'
```

- `tests/unit/action-registry.test.mjs`：清单与磁盘上的类是否一一对应。
- `tests/unit/api-client.test.mjs`：`client.generated.ts` 是否与当前 registry 一致。
- 这两条测试的价值不在"正常时通过"，而在**改了契约却没重跑生成时必红**。

## 六、从存量项目（JS / 对象字面量 action）增量迁移

> 这一节只服务**迁移**：新项目不要照这里起手，直接用前三节的 TS 三段式。

| 步 | 动作 | 判据 |
| --- | --- | --- |
| 1 | 保留 legacy flags 通道（`serve` / `help` / `version` 这类平台命令） | 它们不是业务 action，不必先迁 |
| 2 | 新加的业务 action 一律走 zod 通道 | 老模块可以暂时不动 |
| 3 | `gen-api-client` 只生成 `Array.isArray(a.fields)` 的 action | 老前端 `client.js` 继续手写，互不干扰 |
| 4 | 迁完一个模块，删掉它的 `view.jsx` 与手写 client 函数 | 前端页面改调生成 client |
| 5 | legacy 通道只剩平台命令后，整体删除 | 删之前 `grep -rn "flags:" src/modules` 应为空 |

## 检查清单

- [ ] 新的 action 是「schema + 装饰器 + 类」三段式，schema 在 action 文件内，不再有独立 `schemas.ts`
- [ ] `@action` 的 `id` 全局唯一；纯 CLI 命令显式 `http: null`
- [ ] handler 入参写 `ActionInput<this['_input']>`，没有手写第二份 Input 类型
- [ ] 改完 action 跑了 `pnpm gen`，两个生成物已提交
- [ ] 跨语言 action 声明了 `output`，且测试用 `output.safeParse(真实返回)` 对账
- [ ] 新增 action 后 `cli-tree.json` 里能看到对应路由

## 坑

| 坑 | 后果 | 正确做法 |
| --- | --- | --- |
| 手写前端请求函数 + 手写入参类型 | 与后端 schema 漂移，类型检查发现不了 | 用 `client.generated.ts`，类型从 action 类反推 |
| 入参用 `z.input` 传给 handler | `.default()` 没填，service 收到 `undefined` | handler 用 `z.output`（`ActionInput<…>`） |
| 把元数据挂 `context.metadata` | esbuild 编译后静默丢失，action 不在清单里 | 挂方法函数（WeakMap） |
| 改了契约没重跑 `pnpm gen` | 前端调旧路由 / 旧参数，运行时才炸 | `pnpm test` 含 gen + 新鲜度对账 |
| 给每个 action 都写 `output` | 多一份要维护的声明，必然漂 | 只有跨语言 action 才声明 |
| 生成器每次都重写文件 | mtime 噪声、增量编译失效 | `writeIfChanged`，内容没变不落盘 |
