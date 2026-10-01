# B03 · 项目化启动 + 注册分组：xxx 的特殊化处理方案

> 归属主文档 [[server-cli-web-scaffold]]。这是 B 序列的**特殊化处理方案**——
> 不是「重量级调试」，而是把 A 序列规范（A00 / A01 / A05 / A07）落到一个具象参考实现上的**设计模式速查**。
>
> 参考实现：`xxx`（参考实现项目）。**先读 A 序列对应 ref 才能看懂**：
> 启动方式对应 [[A01-bootstrap-serve-first]]、注册分组对应 [[A00-design-and-verify]]（第三节 ctx 契约、第七节 CRUD 完备性）、cwd 作用域对应 [[A05-state-storage]] + [[A07-extension-loop]]。
>
> 本 ref 的存在意义：当你看 A 序列的抽象规范不知道「具体长什么样」，或者要判断「我的项目化设计对不对」，来这里对照——但**不要把这里的细节当成硬规范照抄**。

## 一、什么时候读这个

- 在 [[A00]] / [[A01]] 之后，想看一个**已经跑稳的真实项目**的对应实现
- 调试新接进来的项目化设计（actions / cwd / HTTP 路由）是否符合 A 序列规范
- 在自己项目里复现「session 没挂、scope 没串」一类问题，想知道 xxx 怎么处理

不适用：首次建项目（先按 A 序列的创建流程 7 阶段走）；正式规范的「**为什么**」（那是 A 序列的事）；本地排错（走 [[B01-browser-debugging]]）。

## 二、项目化启动方式

### 1. 单一可执行入口

`package.json#bin` 指向唯一入口 `bin/<name>.mjs`，**只做一件事：把 argv 转给 `src/runtime/cli.js`**：

```js
import { runCli } from '../src/runtime/cli.js';
runCli(process.argv.slice(2)).catch((err) => { ... });
```

注释明确写「为什么唯一入口：多入口 = 多份参数解析 = 迟早不一致」——
所有命令分发集中在 `cli.js` 一处，help / routes / bootstrap 不会漏掉任一侧。

### 2. 启动脚本分层

| 脚本 | 用途 |
|---|---|
| `pnpm dev` | `node scripts/dev.mjs`（Vite + Node 双进程并行） |
| `pnpm dev:vite` | 仅前端：`vite --host 127.0.0.1` |
| `pnpm dev:serve` | 仅后端：`node bin/<name>.mjs serve --no-open` |
| `pnpm build` | `vite build && node scripts/link-local.mjs --auto` |
| `pnpm start` | 构建 + `<name> serve`（生产态共用同一入口） |
| `pnpm link:local` / `unlink:local` | 本地软链到全局 `<name>` |
| `pnpm test` | lint + build + smoke + node:test 单元测试 |

**关键设计**：`server.js` 对构建工具零感知——只服务 `public/`，所以 dev 与 prod 走**同一入口**，不会出现「dev 能跑、打包后白屏」。

### 3. 启动期装载自检

`cmdServe` 在启动 server 之前：

```js
await import('./registry.js');   // 触发 MODULES 装载 + 重复命令检查
await import('./api.js');         // 触发 ROUTES 表编译
```

任何两个模块声明同名 CLI 命令或同名 HTTP 路由都会**启动瞬间抛错**，而不是等用户敲到那条命令时才发现。

启动成功后再把自己登记进 `recents`（「最近目录」列表），失败不阻塞启动。

### 4. cwd 作用域如何随启动自动获得

- `src/core/paths.js#cwdScope()` 默认从 `process.cwd()` 取 scope key，跨平台归一化（Windows 大小写折叠）
- `src/core/als.js` 用 `AsyncLocalStorage` 隔离 scope——独立文件，避免被前端 bundle 触碰
- Web 面板侧通过 `x-xxx-scope` HTTP 头激活 scope，路由分发被 `scopeStorage.run()` 包裹，**业务代码零改动**就能读到激活目录

> A 序列规范见 [[A05-state-storage]] 第「按 cwd 隔离而不是平铺」一节。

## 三、注册分组的设计模式

### 1. 模块（域）即注册单元

每个功能域都是 `src/modules/<name>/` 三件套：

```
modules/doc/        index.js          ← action 声明（CLI + HTTP 同源）
                    service.js       ← 业务实现
                    view.jsx         ← 面板视图（懒加载）
                    zg.js            ← 召回引擎集成（可选）
```

`index.js` 导出一个 `Module` 对象：`{ id, title, order, resource?, view, actions[] }`。
`order` 字段就是分组在面板 tab 上的排序键，**模块顺序由此确定，无需修改壳代码**。

### 2. 一条 action 同时声明 CLI + HTTP

```js
{
  id: 'doc.zg.query',
  cli:  ['zg', 'query'],            // CLI 路径
  http: ['POST', '/api/zg/query'],  // HTTP 路由
  args: [...],
  flags: { ... },                   // spec 共用
  run: (ctx, meta) => service.x(),
  render: (data, ctx) => '...',
}
```

### 3. 派生三张表 + 结构性保证

**CLI 命令表、HTTP 路由表、help 文本三者全部从 `ACTIONS` 派生**——
这是「Web 上每个操作都有等价 CLI 命令」得以成为**结构性保证**而非口头约定的根因。

| 派生消费方 | 派生物 |
|---|---|
| `cli.js` | `ALL_COMMANDS = [...BUILTINS, ...ACTIONS]`（最长前缀匹配） |
| `api.js` | `ROUTES = ACTIONS.filter(a => a.http).map(compileRoute)` |
| `builtins.js#cmdHelp` | 命令表用 `commandEntry(action)` 格式化 |
| `system/routes` action | 命令 ↔ 路由对照表，bootstrap 下发前端 |

### 4. 装载期断言（registry.js 末尾）

```js
for (const a of ACTIONS) {
  if (seenIds.has(a.id))   throw 'action id 重复';
  if (cli 重名)             throw 'CLI 命令重复';
  if (http 重名)            throw 'HTTP 路由重复';
  if (!paths.length && !a.http) throw 'Web 操作必须有 CLI 等价';
  if (a.streamBody && !a.http) throw '声明了流式却没有 HTTP 路由';
}
```

**方向性约定（刻意不对称）**：每条 action 都必须有 CLI；http 允许为 null（纯 CLI 命令），但**不允许声明 http 却没 cli**——这条把「Web 多于 CLI」从口头约定变成了结构铁律。

> 这条铁律的抽象形式见 [[A00-design-and-verify]] 第七节「CRUD 完备性」与「三端一致性」。

### 5. spec.js 是 CLI/HTTP 共用的强转器

同一份 `action.args` / `action.flags` 规格，被两路复用：

- CLI：`parseFlags(action, tokens)` 切出位置 + 命名参数
- HTTP：`compileRoute(action)` + `applySpec(action, raw)` 把路由占位符、query、body 拍平到 `raw`，再交给同一个 `coerce()` 强转

改一个 flag 的类型（比如 boolean→enum），CLI 解析和 HTTP 路由**自动同步**——不会出现两侧漂移。

> ctx 合并与强转的契约细节见 [[A00-design-and-verify]] 第三节。

### 6. 视图注册表（前端壳）

`src/web/frontend/registry.js`：

```js
export const VIEWS = [
  { id: 'doc',          component: lazy(() => import('../../modules/doc/view.jsx')) },
  { id: 'deps',         component: lazy(() => import('../../modules/deps/view.jsx')) },
  { id: 'hook-prompt',  component: lazy(() => import('../../modules/hook-prompt/view.jsx')) },
  // ...
];
```

App 的 tab 导航、hash 路由、懒加载**全部由这张表驱动**——
新增面板 = 写 `view.jsx` + 在这里登记一行。

## 四、不同目录启动如何获得项目级上下文

### 1. cwd 即 scope——单一作用域键

`paths.js#cwdScope()` 把 `process.cwd()` 归一化后当 store 的桶 key：

- Windows：`path.resolve().toLowerCase()`
- POSIX：`path.resolve()`

业务集合一律按 `cwdScope` 索引存放在 `~/.xxx/store.json`：

```json
{
  "version": 1,
  "settings": { "defaultPort": 7820, "openBrowser": true },
  "scopes": {
    "<cwdScope A>": { "docs": [...], "workflows": {...} },
    "<cwdScope B>": { "docs": [...], "workflows": {...} }
  },
  "recents": [ { "scope", "path", "lastUsedAt" }, ... ]
}
```

`recents` 是**全局跨 scope** 的列表（最多 20 条，最近在前），与各 scope 桶并存——A 序列规范的「按 cwd 隔离 + 共享 recents」的具体形态。

### 2. 同一面板，多个项目

`system.recents.touch`（纯 HTTP）和 `serve` 启动时都会调用 `touchRecent(cwd)`，recents 列表是面板顶部的「scope 切换」数据源：

- 在 A 目录 `xxx serve` → 端口被占时，**先探测**端口上的 `/api/health` 是否有 `cwdScope` 字段
- 是自己的面板 → 把 A 登记进 recents、打开浏览器；**一个面板管所有项目**，不需要每个项目开一个端口

### 3. Web 面板切换 scope

```js
// api.js#handleApi
const scopeHeader = req.headers['x-xxx-scope'];
if (typeof scopeHeader === 'string' && scopeHeader.trim()) {
  return scopeStorage.run({ scope: scopeHeader.trim(), dir: scopeHeader.trim() }, () => dispatch(...));
}
return dispatch(...);
```

业务代码全用 `cwdScope()` / `cwdDir()` 拿当前 scope —— 由于 `als.js` 是 `AsyncLocalStorage`，
整个请求 async 链上**自动落到激活目录**，零侵入。

### 4. hook 也按目录分文件

`paths.js#promptsFileFor(cwd)`：把 cwd 的归一化形式做 SHA1 前 12 位 → `${hash}.jsonl` 写到 `~/.xxx/prompts/`，文件名全 ASCII，规避 cwd 里的中文/空格。

### 5. 知识库按 workspace 目录命名

`paths.js#workspaceKbFor(cwd, docRootSetting)` 把 cwd 用 `serializePath` 折成 `[A-Za-z0-9_-]` 串作目录名：

```
<docRoot>/<workspace-key>/<doc-id>.md
<docRoot>/shared/                  ← 跨项目共享（--shared）
```

`doc.export` 把 store 里的登记态文档镜像为 KB 目录里的 markdown，再交给 zg 索引 →
语义召回结果天然按 workspace 分桶，`--no-shared` 控制是否并查共享库。

## 五、关键文件位置速查

| 关注点 | 文件 |
|---|---|
| 单一入口 | `bin/<name>.mjs` |
| CLI 运行器 + 命令匹配 | `src/runtime/cli.js`（`runCli` / `matchCommand`） |
| 模块聚合 + 装载期自检 | `src/runtime/registry.js` |
| 平台命令（serve/help/version/skill） | `src/runtime/builtins.js` |
| spec 强转（CLI/HTTP 共用） | `src/runtime/spec.js` |
| HTTP 路由编译 + scope 切换 | `src/runtime/api.js` |
| 静态服务（dev/prod 同源） | `src/runtime/server.js` |
| 路径常量 + cwd 作用域 | `src/core/paths.js` |
| AsyncLocalStorage 隔离层 | `src/core/als.js` |
| 状态读写（原子写 + mtime 失效缓存） | `src/core/store.js` |
| 模块三件套范本 | `src/modules/doc/index.js` |
| 视图注册表（前端壳） | `src/web/frontend/registry.js` |
| 模块分组排序 | 各 `index.js` 的 `order` 字段 |

## 六、A 序列对照表

| 本 ref 章节 | 对应 A 序列规范 |
|---|---|
| 二 · 项目化启动方式 | [[A01-bootstrap-serve-first]]（dev/prod 同入口、serve 驱动） |
| 三 · 注册分组设计模式 | [[A00-design-and-verify]] 第 3 节（ctx 契约）/ 第 7 节（CRUD 完备性 / 三端一致性） |
| 四 · cwd 作用域 | [[A05-state-storage]]（按 cwd 隔离 + recents）/ [[A07-extension-loop]]（互依禁列） |
| 五 · 关键文件位置 | [[A01-bootstrap-serve-first]]（目录结构）+ [[A07-extension-loop]]（12 处闭环） |

> 用 B03 的正确姿势：**先读完对应 A 序列 ref**，再回到这里看具象实现；不要跳过 A 序列直接照抄这里的细节。

## 七、错误案例（xxx 沉淀到本 ref 时识别出的潜在踩坑）

| 错误操作 | 实际后果 | 正确做法 |
|---|---|---|
| 跳过 A 序列直接照抄 B03 的具象设计 | 抽象层与具象层混在一起——读到「`x-xxx-scope` 头」时不知道这是 [[A05]]「按 cwd 隔离」的具象，还是某个项目的特定设计；改规范时漏改 xxx 一侧 | 把 A 序列当必读前置；B03 只当「具象形态速查」，不替代规范 |
| 把 B03 当成「扩展清单」去挂新模块 | 新模块通过 B03 就能加到 xxx 框架里，但 **server-cli-web 本身**并没把它当成骨架能力——下次别的项目复用又要重新设计 | 落在 [[A07-extension-loop]] 的 12 处闭环表里，而不是 B03 的子章节 |
| 把 xxx 的具体路径/文件名当成硬规范 | xxx 是参考实现；`paths.js#cwdScope` 的归一化规则、`store.json` 的 scopes 形状都是**这一类项目**的形态，但每个项目的 `APP_NAME` / `recents` 上限 / KB 目录命名规则都不同 | B03 只描述「这一类项目怎么解」；具体阈值/命名到项目仓库或 [[A05]] 决定 |