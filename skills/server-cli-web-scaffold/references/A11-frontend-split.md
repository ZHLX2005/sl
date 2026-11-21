---
name: A11-frontend-split
description: server-cli-web 的前后端分离规范——src/web/frontend 作为独立 Vite 壳，页面按 routes/pages 目录发现、只消费生成的 typed client 与 shared 纯类型；三条 lint 边界（模块互依、前端不得 import 后端/node、视图不得留在 modules）；以及从旧 view.jsx 结构迁移的步骤与违规症状。
---

# A11 · 前后端彻底分离

> 归属主文档 [[server-cli-web-scaffold]]。动前端、加页面、排查"node 模块进了浏览器包"时读这篇。

## 这一篇解决什么

「视图放哪」「前端怎么拿数据」「为什么不能直接 import service」
「页面要不要在某个全局表里登记」「前后端同源到底同源在哪」。

## 一、目录：两条构建链，一个契约

```
后端（tsc 编成 Node 包）                前端（vite 编成浏览器包）
core/        基础设施                    web/frontend/
modules/     功能域（service + actions）   ├─ main.tsx / App.tsx         壳
runtime/     action → CLI / HTTP 装配      ├─ app/     路由、布局、导航
shared/      纯类型 + 纯函数（无 node:）    ├─ routes/<页>.ts            路由声明（唯一来源）
                                          ├─ pages/<页>/index.tsx      页面本体
                                          └─ api/
                                               ├─ client.ts            手写传输层
                                               └─ client.generated.ts  生成的方法（勿手改）
```

**shared/ 是唯一允许两边共用的目录**：只放类型、常量、纯函数（`zod` schema 可以，
`node:fs` / `process` / 任何后端 service 不行）。它不 import `core` / `modules` / `runtime`。

## 二、三条边界，全部用 lint 钉

| # | 规则 | 违反后的症状 | lint 写法 |
| --- | --- | --- | --- |
| 1 | `modules/**` 不得互相 import（`settings` 是唯一单向例外） | 模块成网，删一个模块带崩五个 | `no-restricted-imports` 的**枚举式**禁列：新增模块必须手动补列 |
| 2 | `web/frontend/**` 不得 import `modules/**`、`runtime/**`、`core/**`、`node:*` | Vite 把 `node:` 打进浏览器包，或前端读到后端内部对象 | `no-restricted-imports` 按路径前缀禁 |
| 3 | `modules/**` 不得出现视图文件（`view.jsx` / `*.tsx`） | 前后端边界消失，改后端顺手改 UI | `no-restricted-imports` + 目录检查脚本（`modules/**/*.tsx` 应为 0） |

**枚举式禁列是个提醒机制**：新模块必须手动加进别人的禁列，否则它就"谁都可以依赖"。
漏补是**静默**的——所以要在每条规则旁留注释说明这一点，并做一次反向测试
（临时写违例 → 跑 lint → 确认退出码非 0）。

## 三、前端怎么拿数据：生成 client + 手写传输层

```ts
// 页面里：只 import 生成物
import { repoAdd, repoList } from '../../api/client.generated.js';

const list = await repoList({ type: 'ref' });   // 入参/返回类型都来自 action 类
await repoAdd({ path, name });
```

半自动的边界（有意为之）：

| 自动（生成器） | 手写（人） |
| --- | --- |
| 每个 action 一个方法、方法名、入参/返回类型、路由模式、路径参数、query/body 分流 | 传输层 `api()`（错误信封、超时）、页面接线（哪个按钮调哪个方法） |

**为什么生成物不在浏览器里跑 zod**：schema 只以 `import type` 出现，运行时校验留在服务端
（`zod-bridge` 双端守同一份 schema）。省掉整个 zod 进浏览器包，代价是前端拿不到即时校验——
这是刻意的取舍。

**错误信封**固定两态，前端按 `code` 分支，不靠字符串匹配：

```ts
{ ok: true,  data: T }
{ ok: false, error: string, code?: string, details?: unknown }   // → 抛 ApiError，带 .code
```

## 四、页面注册：目录即声明

```ts
// frontend/app/pages.ts —— 唯一清单来自文件系统
const DECLARATIONS = import.meta.glob(['../routes/*.ts', '!../routes/contract.ts'], {
  eager: true, import: 'default',
});
```

- 新增页面 = 新建 `routes/<名>.ts`（声明 `nav` / `layout` / `order`）+ `pages/<名>/index.tsx`（本体）。
- **不需要**改任何全局文件（旧做法：后端 views 表 + 前端组件表 + 测试三方对账，漏一处页面就静默消失）。
- 路由 id = 文件名；`nav` 没写就不进导航（详情页、向导页天然隐藏）。
- `eager: true` 只 eager 路由声明，页面组件仍按需加载。

## 五、"前后端同源"到底同源在哪

同源的是**契约**，不是代码：

```
action 声明（zod + cli/http） ──┬── CLI 命令表
                               ├── HTTP 路由
                               ├── client.generated.ts（前端方法 + 类型）
                               └── contract.json / Dart client（跨语言）
```

前端**不共享**后端的 service、状态对象、数据库连接。这不是"同一个 monorepo 里的一个包"，
而是"同一份契约的两个消费者"。

## 六、从旧结构迁移（view.jsx 在 modules 里）

| 步 | 动作 | 验收 |
| --- | --- | --- |
| 1 | 盘点 `modules/*/view.*`，列出页面 → 模块的对应表 | 表里每个页面都有归属 |
| 2 | 在 `web/frontend/pages/<页>/` 重建页面，数据调用换成生成的 client | 页面能跑，且没有 import 后端 |
| 3 | 删除 `modules/*/view.*`，模块目录只留 service + actions | `modules/**/*.tsx` 为 0 |
| 4 | 加三条 lint 规则 + 反向测试 | 临时违例文件能让 lint 红 |
| 5 | 更新 `assets/<skill>/` 里"怎么用"的部分（不含开发规范） | agent 侧能看到新页面路径 |

**别一次迁完**：一页一迁，迁完跑 `pnpm build` 确认浏览器包没有 `node:` 依赖。

## 检查清单

- [ ] `src/web/frontend` 能独立 `vite build`，不依赖后端源码
- [ ] 页面只 import `shared/**` 与 `api/client.generated.ts`
- [ ] 新页面只加 `routes/<名>.ts` + `pages/<名>/index.tsx`，没改全局登记文件
- [ ] `modules/**` 下没有任何 `.tsx` / `view.*`
- [ ] 三条 lint 规则都有**反向测试**（违例必红）
- [ ] 错误处理按 `code` 分支，没有对 `error` 文案做字符串匹配

## 坑

| 坑 | 后果 | 正确做法 |
| --- | --- | --- |
| 页面直接 import 后端 service | Vite 打包失败或把 `node:` 带进浏览器 | 只走 `api/client.generated.ts` |
| 在 `modules/<域>/` 里建 `view.tsx` | 边界消失，前后端又粘一起 | 页面放 `pages/<页>/`，模块不放视图 |
| 页面在某个全局数组里手工登记 | 漏登记时页面静默不出现 | `import.meta.glob` 扫 `routes/*.ts` |
| 前端也 import zod 做校验 | 浏览器包多几百 KB | schema 只用 `import type`，运行时校验留服务端 |
| 把 `shared/` 当垃圾桶 | 往里放 node 依赖，前端立刻炸 | shared 只放纯类型与纯函数 |
| lint 规则只写不禁 | 规则写错也永远通过 | 加规则后做一次反向测试 |
