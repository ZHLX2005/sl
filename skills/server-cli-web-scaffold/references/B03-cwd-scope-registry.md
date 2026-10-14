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

### 4. 顶部「最近目录」切换器的前端 UI/UX

后端（scope 头 + ALS）解决了「请求能落到激活目录」，但用户要在面板上**看得见、切得动、收得回、删得掉**——
右上角那个目录切换下拉有一套容易漏的交互与 CSS。老形态用原生 `<details>` 也能跑，
成熟形态已演进成**受控下拉**，差异与踩坑都在下面。

**结构（header 右侧）**

- 只读 `<div className="meta">`：显示当前作用域路径的**末段名**（hover title 给全路径）；
- 受控下拉 `<div className="recents-wrap">`：触发按钮常驻 header（末段名 + 计数 + caret），`open` 为真时才挂菜单；
- 菜单每行 = 主按钮（末段名 + 完整路径 + 激活 `✓`）+ **hover 才显形**的 `×` 删除；
- 菜单底部 = 「＋ 添加目录」入口。

**为什么用受控 `<div>` 而不是原生 `<details>`**

`<details>` 的展开态是 **DOM 原生属性**，不是 React state。于是：

- 「点外部收回」只能去改 `ref.current.open = false` 直写 DOM——两套真相，React 侧不知道菜单关了；
- 行内要再放一个删除按钮时，`summary` / `ul` 的结构很别扭（`summary` 只该有一个）；
- 一行里要放**两个动作**（切换 + 删除）时，`<details>` 的表达力明显不够。

换成 `useState(open)` + `wrapRef` 后，开合只有一处真相，闭合逻辑一处收口。
（老项目的 `<details>` 不是错，只是**加了删除按钮之后**就不够用了。）

**CSS 三个可复用点**

| 需求 | 做法 | 为什么 |
|---|---|---|
| 行内操作按钮只在 hover 时显形 | 按钮 `position: absolute; right: 6px; top: 50%; transform: translateY(-50%); opacity: 0`；父行 `:hover` 时 `opacity: 1` | 常显会让每行右侧糊成一团噪音；用**绝对定位**而不是 `visibility` 占位，避免显隐时行宽抖动 |
| 主按钮给操作按钮留位 | 主按钮 `padding-right: 32px` | 否则长路径的文字会压到 `×` 底下，hover 时字与按钮叠在一起 |
| 菜单悬挂、不撑开 header | 菜单 `position: absolute; right: 0; top: calc(100% + 6px)`；父 `position: relative` | header 是 `position: sticky`，菜单若进文档流会把 header 顶高、把主体整块挤下去 |

两个配套的细节：

- 删除按钮的**危险色只给 `:hover`**（`background: var(--bad); color: #fff`），行本身的 hover 保持 `--soft`。
  用户一眼能看出「这一下是破坏性的」，而不是和普通行 hover 长得一样。
- 底部「＋ 添加目录」用 `border-top` 与列表分隔 + 斜体弱化——它是**另一个语义**（新增），不是列表项。

**交互铁律（高频漏点）**

| 要求 | 做法 |
|---|---|
| 点页面别处收起 | 监听 **`mousedown`**（或 `pointerdown`），不是 `click`，划 `wrapRef` 边界 |
| 点触发按钮别「关了又开」 | 同上——`click` 阶段会**先**冒泡到触发按钮的 `onClick`（`setOpen(true)`），把刚关掉的又打开；`mousedown` 早于 `click` 触发，天然避开 |
| Esc 收起 | 同一处 `keydown` 监听 `Escape` |
| 选中目录即收起 | 项 `onClick` 里先 `setOpen(false)` 再 `switchScope(...)` |
| 删除不误触切换 | `×` 的 `onClick` 里 **`e.stopPropagation()`**——否则冒泡到行内主按钮，删完还顺手把目录切走了 |
| 当前态可见 | activeScope 命中项加 `.active` + `✓`；再点一次 = 切回服务进程目录（`switchScope(null)`） |
| 自动跟随最新触发 | `useEffect` 依赖 `[top?.scope, activeScope?.scope]`：顶部 ≠ 激活时 `switchScope(top)`。用户点选、或**另一终端在新 cwd 起 serve** 后窗口聚焦刷新 bootstrap，两条来源都盖住 |
| 只显示末段 | 按钮渲染 basename，完整路径放 `title` |
| 添加目录走项目自己的弹窗 | `useDialog`（单输入框）+ `useGuard`/`useToast`。**不要用 `window.prompt`**：原生弹窗样式突兀、无法 toast 校验失败，且 `window.alert` 报错与项目其余提示不是一个视觉体系 |

**可复用钩子（多下拉时抽进 `components/ui.jsx`）**

只有一个下拉时，把这段 effect 内联在组件里就够（`xxx` 就是内联的）。
一旦出现第二个下拉（更多面板入口），就该抽成钩子——否则每个组件都要重复一遍「mousedown + Esc + 边界判定」：

```js
// 点击「元素外部」或按 Esc 时触发回调。用 pointerdown 而非 click：mouseup 前就触发，点别处立即收起。
export function useClickOutside(ref, onOutside, { enabled = true } = {}) {
  useEffect(() => {
    if (!enabled) return;
    const onPointer = (e) => { const el = ref.current; if (el && !el.contains(e.target)) onOutside(e); };
    const onKey = (e) => { if (e.key === 'Escape') onOutside(e); };
    document.addEventListener('pointerdown', onPointer);
    document.addEventListener('keydown', onKey);
    return () => { document.removeEventListener('pointerdown', onPointer); document.removeEventListener('keydown', onKey); };
  }, [ref, onOutside, enabled]);
}
```

接线（App 壳，受控形态）：

```jsx
const [open, setOpen] = useState(false);
const wrapRef = useRef(null);
useClickOutside(wrapRef, () => setOpen(false), { enabled: open });
// 项：onClick={() => { setOpen(false); switchScope(active ? null : r); }}
// 删除：onClick={(e) => { e.stopPropagation(); guard(() => removeRecent(r)); }}
<div ref={wrapRef} className="recents-wrap">…</div>
```

> 切换器只改前端 `activeScope`；真正让后端落到该目录的是 `x-xxx-scope` 头 + ALS（见本节第 3 条）。
> 前端组件库与 ALS 分文件存放，别让 `als.js` 被打进前端 bundle。

> **删除的失败不要吞。** 切换是乐观的（本地状态先改），失败静默还能接受；
> 删除不同——失败后条目**看起来还在**，用户会以为没点中。让 `removeRecent` 把异常抛出来，
> 由调用方的 `guard` toast，与项目其余失败反馈一致。

### 5. hook 也按目录分文件

`paths.js#promptsFileFor(cwd)`：把 cwd 的归一化形式做 SHA1 前 12 位 → `${hash}.jsonl` 写到 `~/.xxx/prompts/`，文件名全 ASCII，规避 cwd 里的中文/空格。

### 6. 知识库按 workspace 目录命名

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
| 顶部 scope 切换器 + 点击外部收口 | `src/web/frontend/App.jsx`（单下拉时 effect 内联；多下拉时抽 `components/ui.jsx` 的 `useClickOutside`） |
| 面板视觉规范（单色 / 状态标签 / 立体感 / 密度双层） | `src/web/frontend/style.css`（`:root` 的 CSS 变量是唯一调色板来源） |
| 模块分组排序 | 各 `index.js` 的 `order` 字段 |

## 六、A 序列对照表

| 本 ref 章节 | 对应 A 序列规范 |
|---|---|
| 二 · 项目化启动方式 | [[A01-bootstrap-serve-first]]（dev/prod 同入口、serve 驱动） |
| 三 · 注册分组设计模式 | [[A00-design-and-verify]] 第 3 节（ctx 契约）/ 第 7 节（CRUD 完备性 / 三端一致性） |
| 四 · cwd 作用域 | [[A05-state-storage]]（按 cwd 隔离 + recents）/ [[A07-extension-loop]]（互依禁列） |
| 四 · 4 切换器 UI / CSS | [[A02-web-panel]]（面板视觉规范、点击外部收口、行 28px / 按钮 32px / 字号 12px 的密度双层） |
| 五 · 关键文件位置 | [[A01-bootstrap-serve-first]]（目录结构）+ [[A07-extension-loop]]（12 处闭环） |

> 用 B03 的正确姿势：**先读完对应 A 序列 ref**，再回到这里看具象实现；不要跳过 A 序列直接照抄这里的细节。

## 七、错误案例（xxx 沉淀到本 ref 时识别出的潜在踩坑）

| 错误操作 | 实际后果 | 正确做法 |
|---|---|---|
| 跳过 A 序列直接照抄 B03 的具象设计 | 抽象层与具象层混在一起——读到「`x-xxx-scope` 头」时不知道这是 [[A05]]「按 cwd 隔离」的具象，还是某个项目的特定设计；改规范时漏改 xxx 一侧 | 把 A 序列当必读前置；B03 只当「具象形态速查」，不替代规范 |
| 把 B03 当成「扩展清单」去挂新模块 | 新模块通过 B03 就能加到 xxx 框架里，但 **server-cli-web 本身**并没把它当成骨架能力——下次别的项目复用又要重新设计 | 落在 [[A07-extension-loop]] 的 12 处闭环表里，而不是 B03 的子章节 |
| 把 xxx 的具体路径/文件名当成硬规范 | xxx 是参考实现；`paths.js#cwdScope` 的归一化规则、`store.json` 的 scopes 形状都是**这一类项目**的形态，但每个项目的 `APP_NAME` / `recents` 上限 / KB 目录命名规则都不同 | B03 只描述「这一类项目怎么解」；具体阈值/命名到项目仓库或 [[A05]] 决定 |
| 顶部目录下拉用原生 `<details>` 却不处理点击外部 | 点开「最近目录」后点页面别处菜单不收起，只能再点一次 summary——典型小 bug；选中目录后菜单也常停住不关 | 用第 4 节的收口方式（`mousedown`/`pointerdown` 外部 + Esc）：单下拉内联 effect 即可，多下拉抽 `useClickOutside`；并在选中项 onClick 里主动收起 |
| 给下拉加「删除」后仍留在 `<details>` 形态 | `<details>` 的展开态是 DOM 原生属性（`ref.current.open`），与 React state 两套真相；且 `summary` 结构塞不下「切换 + 删除」两个动作 | 换受控 `<div>` + `useState(open)`（见第 4 节）；`<details>` 只在没有行内附加动作时才够用 |
| 用 `click` 监听「点击外部」 | 与触发按钮自己的 `onClick` 同阶段冒泡：先关闭再被 `setOpen(true)` 抵消，表现为「点一下关了又弹开」 | 用 `mousedown` / `pointerdown`——早于 `click` 触发，天然避开 |
| 行内删除按钮不 `stopPropagation` | 点 `×` 冒泡到行内切换按钮，条目删掉的同时还把 scope 切走了 | `×` 的 `onClick` 里 `e.stopPropagation()` |
| 行内操作按钮常显 | 每行右侧糊成一团噪音，列表本体被抢焦点 | 绝对定位到右侧 + `opacity: 0`，父行 `:hover` 才 `opacity: 1`；主按钮 `padding-right` 留位防文字压字 |
| 菜单用 `position: static` 进文档流 | header 是 `sticky`，菜单把 header 顶高、主体整块下移 | 菜单绝对定位悬挂（`absolute; right: 0; top: calc(100% + 6px)`），父容器 `position: relative` |
| 添加/输入路径用 `window.prompt` | 原生弹窗样式与面板不是一个体系，且 `window.alert` 报错无法融入 toast | 走项目自己的 `useDialog` + `useGuard`/`useToast`（见第 4 节） |
| 删除失败被 `.catch(() => {})` 吞掉 | 条目看起来还在，用户以为没点中，反复点 | 删除不吞异常——`removeRecent` 抛出，调用方 `guard` toast（切换可以乐观静默，删除不行） |