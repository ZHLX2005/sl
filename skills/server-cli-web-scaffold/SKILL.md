---
name: server-cli-web-scaffold
description: TypeScript 本地工具脚手架：zod 契约经代码生成产出 CLI、HTTP 与前端 typed client，前后端分离；存储可选 JSON 前期或 SQLite。Use when 建带面板的 CLI、起 cli+web 项目、补 Web 面板、skill install。
version: 2.0.1
metadata:
  author: zhlx <zhlx@localhost>
  tags:
    - scaffold
    - typescript
    - storage
    - codegen
    - cli
---

# server-cli-web 脚手架（TS 版）

给"本机工具类项目"的标准骨架：**serve 驱动 CLI 与 Web，CLI 与 API 同源，skill 驱动 agent**。
当前版本按 `nx-kv` 与 `nx-sk` 两套真实落地收敛。两条口径先钉死：

1. **语言一律 TypeScript**：不写 JS 写法（不上 `.js` 源码、不用无类型的对象字面量 action）。
   存量 JS 项目按 [[A10-ts-action-pipeline]] 第六节增量迁移。
2. **存储是两档选择，不是新旧代差**：前期用 JSON 单文件（简单、可手工修、零依赖）；
   数据量 / 并发 / 关系查询上来后升级 SQLite（迁移、事务、乐观并发）。两档都用 TS 实现，
   判档与升级信号见 [[A05-state-storage]]。

本骨架已在多个真实项目上完整落地并持续验证——宁可照抄规范，不要即兴发挥。
各 ref 的案例取自这些真实落地（**引用具体实现时以那一篇 ref 的说法为准**）。

> 写规范时若引用某个实现的路径/命令，**先确认那是该实现真实存在的**——
> 把 A 项目的路径写到 B 项目的案例里，读者照着去找不到，规范就失去可信度。

## Purpose

把「一个本机工具」拆成三个互不粘连的部分：**后端 action 层**（TS 类 + zod 契约）、
**前端壳**（独立 `src/web/frontend`，只消费生成的 typed client）、**数据层**（TS 存储层：
前期 JSON、后期 SQLite，**对上层保持同一个仓储接口**）。
目标是：加一个功能只改一处声明，CLI / HTTP / 面板 / agent 四个入口同时得到，且类型在编译期就对齐。

## Prerequisites

- Node ≥ 20（JSON 档足够）；**选 SQLite 档时 Node ≥ 22**（需要 `node:sqlite`）。
- pnpm、TypeScript 5.x、zod；无网络依赖、无 API key，`pnpm test` 全本地跑。
- 目标目录可写；`~/.<主题名>/` 用于放 `store.json` 或 `<名>.db` 与备份。

## 什么时候用

- 要从零建一个"既有命令行、又有浏览器面板"的本机工具
- 已有 CLI，要补一个 Web 面板，且**不是**重写一遍业务逻辑
- 要做一个 `npx xxx` 可分发的工具，且希望 agent 能自己学会用它

不适用：纯 Web 应用、纯 CLI 脚本、需要多用户/远程部署的服务。

## 核心不变量（整个骨架的地基）

这三条决定了所有后续设计。**先理解，再动手。**

### 1. 一条 action 声明，四端同时得到（TS + zod + 代码生成）

不要在 CLI 写一份命令表、在 API 再写一份路由表、在前端手抄一份请求函数——那是三份会分叉的清单。
新项目的 action 是**一个 TS 类 + 一个 zod schema**，用装饰器声明 CLI 路径与 HTTP 路由：

```ts
// src/modules/repo/actions/add.ts
@action({
  id: 'repo.add',
  cli: ['repo', 'add'],          // → xxx repo add <path>
  http: ['POST', '/api/repos'],  // → POST /api/repos
  summary: '登记一个仓库',
  input: AddRepoInput,           // zod schema：CLI 与 HTTP 共用的唯一契约
})
export class AddRepoAction extends ActionBase<typeof AddRepoInput> {
  async run(ctx: ActionInput<this['_input']>) { return this.ctx.repo.add(ctx.input); }
}
```

三个生成物由脚本产出、并被测试钉住新鲜度：

| 生成物 | 脚本 | 谁消费 |
| --- | --- | --- |
| `actions/_manifest.generated.ts`（模块内 action 清单） | `scripts/gen-actions.mjs` | 模块装配（静态 import，可类型检查、可打包） |
| `src/web/frontend/api/client.generated.ts`（typed client） | `scripts/gen-api-client.mjs` | 前端；入参/出参类型从 action 类推导，**不手写第二份类型** |
| `contract/contract.json` + Dart client（可选） | `scripts/gen-actions` / `gen:dart` | 跨语言端；跨语言 action 额外声明 `output` 视图 |

**"Web 上能做的，CLI 都必须能做，agent 也都能调"** 由结构保证，不靠人记。
细节（装饰器元数据为什么要挂函数、`z.input` 与 `z.output` 怎么分、出参为什么默认没有 schema）
见 [[A10-ts-action-pipeline]]。

### 2. 依赖只能向下，前后端彻底分离

```
后端（Node，可被 CLI 与 server 复用）
core/       零业务语义基础设施（paths / errors / db / 原子写）
modules/    功能域：index.ts(声明) + service.ts(业务) + actions/*.ts，**不含任何视图**
runtime/    装配层：action 表 → CLI 命令表 + HTTP 路由表，不写业务
shared/     前后端共用的纯类型与纯函数（无 node: 依赖）

前端（浏览器，Vite 独立构建）
web/frontend/   React 壳：pages/ 一页一个目录、app/ 路由与壳、api/client.generated.ts
                **只 import shared/ 与生成的 client；禁止 import modules/ 与 runtime/**
```

三条边界必须用 lint 钉住（只写文档三次提交后就失效）：

1. `modules/**` 不得互相 import（枚举式禁列，新增模块必须手动补列——漏补是静默的）。
2. `web/frontend/**` 不得 import `modules/**`、`runtime/**`、任何 `node:` 内置模块。
3. 视图不再放在 `modules/<域>/view.jsx`：面板页面在 `web/frontend/pages/<页>/`，
   后端只通过 HTTP/typed client 与之交互。

为什么这条值得单独一条不变量：视图混在模块里时，"改个后端字段"会顺手改前端，
两个构建产物（Node 包与浏览器包）的边界就消失了——最终表现为 Vite 把 `node:` 打进浏览器包，
或者前端直接读到后端内部对象。**彻底分离后，前端只有一个入口：生成的 client。**

### 3. 失败抛异常，业务结果返回 `{ status }`

判定标准是**「调用方要不要处理它」**：

| 情形                               | 表达                                                             | 例子                               |
| ---------------------------------- | ---------------------------------------------------------------- | ---------------------------------- |
| 失败：调用方无从处理，只能中断上报 | `throw`                                                        | 参数非法、目标不存在、外部命令挂掉 |
| 业务结果：调用方要拿它做决策       | `return { status: 'ok' \| 'skipped' \| 'conflict' \| 'blocked' }` | 冲突等待用户选侧、幂等跳过         |

冲突**不是错误**——界面要拿它弹窗让用户决策，所以不能抛。这个边界想不清楚，
上层就只能靠字符串匹配猜，agent 也没法可靠分支。

详细展开见 [[A00-design-and-verify]]；TS 侧的异常与 zod 校验分工见 [[A10-ts-action-pipeline]]。

## Instructions：创建流程（7 阶段）

按顺序做，每阶段做完能跑再进下一阶段。**不要一次性铺完再调**。

| 阶段                        | 做什么                                                                                | 详读 |
| --------------------------- | ------------------------------------------------------------------------------------- | ---- |
| 1. 定骨架                   | TS 工程（tsconfig node/web 双份）、`bin/` 唯一入口、`core/` 三件套（paths / errors / db） | [[A01-bootstrap-serve-first]]     |
| 2. 起 serve                 | `xxx serve` 能起一个只服务静态页的空壳面板                                          | [[A01-bootstrap-serve-first]]     |
| 3. 立 action 机制           | `ActionBase` + `@action` 装饰器 + registry + 生成器（gen-actions / gen-api-client）  | [[A10-ts-action-pipeline]] |
| 4. 写第一个功能域           | 一个真实 `modules/<域>`：service + actions，端到端跑通 CLI + HTTP + 前端页面         | [[A02-web-panel]] · [[A03-cli-surface]] · [[A11-frontend-split]] |
| 5. 接状态                   | **先选档**：前期 JSON（`~/<主题名>/store.json`，TS 类 + 原子写 + rev），数据/并发上来再升 SQLite（`<名>.db`：驱动 + 迁移 + 事务 + 乐观并发）；两档共用同一仓储接口 | [[A05-state-storage]]     |
| 6. 上发布                   | GitHub Actions，tag 幂等 + npm provenance                                             | [[A06-release-actions]]     |
| 7. 接 agent（贯穿所有阶段） | 阶段 1 起 SKILL.md + references/00-思想文档.md 同时落地；每加一个功能域同步补场景 ref | [[A04-assert-skill]]     |

**项目跑稳之后**，如果想再开一个同类新项目（`npx xxx create` 形态），做一次「沉淀为模板」——把整个项目打包成 `templates/<id>/` 下的可重发包。与上面 7 阶段方向相反（项目骨架 → 模板包），单独规范见 [[A09-template-generator]]。

**阶段 3 是关键**：action 机制没立起来就写业务，后面每加一个功能都要改四处，
很快会退化成"两份清单"——那正是这个脚手架要避免的。

项目建起来之后，**每次加/改一个功能域**都是同一套动作的重复。
具体要碰哪几个文件、漏了哪一个会静默失效，见 [[A07-extension-loop]]。

## ref 路由表（按需加载）

ref 分两个序列：

- **A 序列（A00–A11）**：脚手架完整流程 + 项目整体规范——初始化按创建流程顺序执行，规范类（A00/A07/A08/A09/A10/A11）按场景随时读。A10/A11 是**TS 版新增的两条地基**（类型链路、前后端分离），新项目必读。
---
- **B 序列（B01–B06）**：**三类重操作**——B01/B02 是调试与开发环境优化的重量级操作（不接入创建流程），B03 是**特殊化处理方案**（具象参考实现的设计模式速查，先读对应 A 序列 ref 才能看懂）。B04/B05 是**扩展方案**而非重操作（B04=多 skill 编排、B05=多行 CLI 输入/heredoc）；B06 是**操作记录**（按日期追加，不进主文档）——放 B 组是按 key-board 当下 ref 编号习惯，frontmatter 已说明命名/定性差异。均按需加载，不接入创建流程。

| ref | 何时读取                                                                                                                                                                                                                                                             |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [[A00-design-and-verify]]    | **立 action 机制时必读**（存量 JS 写法）——第三节 ctx 契约、第七节 CRUD 完备性、lint + 测试钉依赖图。**新项目先读 [[A10-ts-action-pipeline]]**，A00 里"对象字面量 + flags"的写法仅用于阅读老项目 |
| [[A01-bootstrap-serve-first]]    | 定工程骨架时；`serve` 到底该驱动什么、dev/prod 两种模式怎么分                                                                                                                                                                                                      |
| [[A02-web-panel]]    | **写 / 改面板与视图时必读**——面板视觉规范（单色 / 状态标签 / 立体感边界、行 28px · 按钮 32px · 字号 12px）、弹窗 / 复制 / 错误边界；**视图落点已改到 `web/frontend/pages/`，见 [[A11-frontend-split]]** |
| [[A03-cli-surface]]    | 定 CLI 对外契约时：`serve` / `skill install` / `skill get` 参数、`--json` 格式、三段拼接输出                                                                                                                                                                 |
| [[A04-assert-skill]]    | **初始化时必读**——`SKILL.md` + `references/00-思想文档.md` 的最小骨架、为什么要"先 skill 后代码"、**`assets/` 与项目文档的分工**、触发词自检 4 条、错误案例                                                                                                                              |
| [[A05-state-storage]]    | **定存储时必读（两档选择）**——JSON 档（TS 类型 + 原子写 + mtime 失效 + rev 乐观并发、零依赖）与 SQLite 档（`node:sqlite` 唯一引用点、`user_version` 迁移链、每步一事务、`VACUUM INTO` 备份、`meta.rev`）；含「何时从 JSON 升 SQLite」的判据、`store.json` 只导入一次、连接级 PRAGMA 陷阱 |
| [[A06-release-actions]]    | **配发版流水线 / 首次建包发布 / 发版排错时**：Trusted Publishing（OIDC 零 token）为主线；含首次建包 bootstrap、`gh repo create`、幂等 + tag、`gh run watch --exit-status`、staged 兜底 |
| [[A07-extension-loop]]    | **每次新增/修改一个功能域时必读**——闭环落点表、三处**没有任何断言**的静默失效点、以及怎么验证闸门本身真的会触发 |
| [[A08-framework-runtime]]    | **dev 模式 / 日常跑项目时必读**——vite + serve 两个进程、`pnpm run dev`、Node 18+ IPv6 / `--host 127.0.0.1`、跨平台 spawn 坑 |
| [[A09-template-generator]]    | **把项目沉淀为可重用模板时必读**——`template.json` schema、`hooks.mjs` 三钩子、文本 vs 二进制分发、防穿越三道闸、dry-run 与生成共用 `walkTemplate` |
| [[A10-ts-action-pipeline]]    | **新项目立 action / 加 action / 改契约时必读**——TS 类 + `@action` 装饰器 + zod 单一契约、`gen-actions` 与 `gen-api-client` 的产物与新鲜度测试、typed client 的类型从哪来、`z.input` vs `z.output`、出参"实现即契约"与跨语言 `output` 视图 |
| [[A11-frontend-split]]    | **动前端 / 加页面 / 排查"node 模块进了浏览器包"时必读**——`src/web/frontend` 独立壳、pages 目录约定、前端只能 import shared + generated client、三条 lint 边界、以及"前后端同源"到底同源在哪（契约，不是代码） |
| [[B01-browser-debugging]]    | **重量级排查，不接入创建流程**——当 Web 端问题反复出现、curl 正常但页面不对、或需要验证前后端连通性时才升级到这里：browser-harness 连 CDP 端点的 SOP（截图 / fetch 验证 / 注入 JS 模拟点击并观察按钮有效性 / 现象→层定位表）                                 |
| [[B02-link-local-shim]]    | **重量级环境操作，不接入创建流程**——要让全局 `xxx` 命令实时指向本仓库（改码即生效）时：为什么覆盖式 shim 而非 npm link / volta install、RECEIPT 备份清单与重装保护、兜底落点与 PATH 写入的防御性细节、`--auto` 模式（CI 安全）、unlink 还原与真实事故时间线                                 |
| [[B03-cwd-scope-registry]]    | **特殊化处理方案，不接入创建流程**——以真实落地项目为具象参考，看 A 序列规范在真实项目里「长什么样」：单一入口 + dev/prod 同入口、注册分组 + 一源三派生 + 装载期断言、cwd 作用域 + ALS + **跨项目面板（含最近目录下拉的交互与 CSS：受控下拉 / 点击外部收回 / 行内 hover 删按钮）**、视图注册表驱动壳；**先读对应 A 序列 ref 才能看懂**（对照表见 ref 第六节）                                                                              |
| [[B04-multi-skill]]    | **skill 子命令扩展方案**——`skill install [name]\|--group <name>\|--to <dir>\|--force`、`skill list` 输出形态、`groups.json` schema 与降级策略（缺失/损坏时目录扫描兜底）、默认 install 与主 skill 同名约定；面向**给已有项目加多种 skill**时的扩展口径（不是创建决策，命名/定性差异见 ref 自身 frontmatter）                                                                                                                                         |
| [[B05-multi-line-cli-input]]    | **多行 CLI 输入的 heredoc 处理方案**——多行参数跨 exec 边界被切的平台根因（实测 argv 9→5）、`-` 占位从 stdin 读的实现要点、AI 写 heredoc 的四种实测错误（定界符引号 / flag 位置 / EOF 缩进 / 漏 `-`）、spawnSync 隔离测试技巧 |
| [[B06-操作记录]]    | 查历史教训 / 追某条规范为什么变成现在这样时；每条记录带 `YYYY-MM-DD｜触发时机`，超过 12 个月未复核的按 [[M01-质检]] 判龄 |

## 验收清单

零知识开工前对照，交付前逐条确认：

- [ ] `bin/<name>.mjs` 是唯一可执行入口，其余全是模块
- [ ] **TS 工程是双 tsconfig**（node / web 各一份），`pnpm typecheck` 两端都过；`pnpm test` 链里含 `gen`
- [ ] **action 是 TS 类 + zod**：`@action({id, cli, http, summary, input})`；`actions/_manifest.generated.ts` 由 `gen-actions` 产出、有新鲜度对账测试
- [ ] **前端 typed client 是生成物**：`web/frontend/api/client.generated.ts` 由 `gen-api-client` 产出；改了 action 契约但没重跑生成 → 测试红
- [ ] **前后端彻底分离**：`web/frontend/**` 不 import `modules/**` / `runtime/**` / `node:*`；页面在 `pages/<页>/`，后端模块目录里没有任何视图文件
- [ ] `pnpm start` 能一条命令起面板；`serve` 支持 `--port` 与 `--no-open`
- [ ] `serve` 端口被占时走 reuse/shift 两分支：占用者是自己的面板 → 复用并**开浏览器**；占用者是别人 → 换端口起自己的面板再开浏览器
- [ ] 跨项目统一的关闭开关 `NX_SERVE_NO_OPEN=1` 生效（`--no-open` 仍只管这一次）；bootstrap 响应带 `app.name`
- [ ] dev 模式的端口由 dev 脚本先解析：vite 代理目标与 serve 实际监听端口一致（端口用 `--port` 明确传给 serve）
- [ ] 面板：无 emoji、黑白灰、响应式、状态持久化、路径/标识可点击复制
- [ ] CLI：有 `skill install`（装到 `~/.claude/skills`）、`skill get`（输出 SKILL.md / references 给外部 agent，prefix → 文档 → install 状态三段拼接）、`assets/` 内有 skill、`--json` 输出纯 JSON
- [ ] 每个 Web 操作都有等价 CLI 命令，且有测试断言这条等价性
- [ ] 管理实体集合的模块声明了 `resource`，**CRUD 五操作齐备且两端都可调用**（见 [[A00-design-and-verify]] 第七节）
- [ ] 非集合模块（配置 / 动作集合 / 外部连接器 / 聚合）**没有**被硬套成 CRUD，但仍满足两端可达
- [ ] **存储档位已声明**：JSON（前期）或 SQLite（升级）；两档都是 TS 实现，上层走同一仓储接口
- [ ] **JSON 档**：`StoreState` 有 TS 接口、写入用「临时文件 + rename」原子写、按 mtime 失效缓存、`mutateStore` 深拷贝、有 `rev` 乐观并发
- [ ] **SQLite 档**：`node:sqlite` 只在 `core/db/driver.ts` 一处出现；`PRAGMA user_version` 驱动迁移、每步一个事务、升级前 `VACUUM INTO` 备份
- [ ] **SQLite 档写路径走事务 + 乐观并发**（`meta.rev` 不匹配抛 `BLOCKED`）；从 JSON 升级时 `store.json` 只导入一次并改名
- [ ] 存储路径 `~/<主题名>/<名>.db` 可用环境变量覆盖（否则测试写脏用户目录）
- [ ] 分层规则由 lint 强制，不是写在文档里的君子协定（三条边界都要有反向测试：临时写违例 → 退出码非 0）
- [ ] GitHub Actions 能在 push 后发版：首选 **Trusted Publishing**（OIDC 零 token；npm 侧用 `npm trust github --file <workflow> --repo <o/r> --allow-publish` 配一次；新包先按 [[A06-release-actions]] 第一节 bootstrap 首发）；缺配置时**把 npm 侧待办直给用户**而不是静默失败
- [ ] 远端仓库由 `gh repo create` 建好（默认公开，且**执行前已告知用户**）
- [ ] push 之后用 `gh run watch --exit-status` 确认流水线真的成功，不留"发出去了吗"的悬念

**每次新增 / 修改一个功能域时**，按 [[A07-extension-loop]] 第六节的闭环清单逐条过。
其中下面三处**没有任何断言会替你发现**，是最容易漏的：

- [ ] `src/index.ts` 已导出新 service
- [ ] `eslint.config.js` 互依禁列已加 `../<新模块>/*`（枚举式，漏补静默）
- [ ] `assets/<skill>/` 已补新场景（**文档→代码有断言，代码→文档没有**），且只写「怎么用」——
      「怎么改这个项目」属于项目仓库（`README.md`），不属于随包分发的手册

## Examples

| 用户说 | 走哪条路 | 关键产物 |
| --- | --- | --- |
| 「给我做个本机 xxx 管理器，要能在浏览器里点」 | 阶段 1→5，先空壳 serve，再第一个功能域 | `bin/<name>.mjs`、`modules/<域>/actions/*.ts`、`pages/<页>/` |
| 「这个老项目（JS + store.json）迁移」 | [[A10-ts-action-pipeline]] 第六节的 5 步增量迁移 + [[A05-state-storage]] 的 JSON 档 | 源码转 TS，JSON 存储保留为前期档；需要关系查询再升 SQLite |
| 「面板要加一页」 | [[A11-frontend-split]] 第四节 | `routes/<页>.ts` + `pages/<页>/index.tsx`，不改全局登记 |
| 「CLI 要能装 skill 给 agent 用」 | [[A04-assert-skill]] + [[A03-cli-surface]] | `skill install` / `skill get`，`assets/<skill>/` |

## 错误案例

| 错误操作                                                             | 实际后果                                                                                                                 | 正确做法                                                          |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------- |
| 先写业务，后面再"补" action 机制                                     | 每加一个功能要改 4 处（flag 白名单 / help 文本 / switch / 渲染），很快退化成两份清单                                     | 阶段 3 先立机制，再写第一个功能域                                 |
| CLI 与 Web 各写一份命令/接口清单                                     | 必然分叉；面板上有按钮、CLI 里没命令，且没人发现                                                                         | 一条 action 同时声明`cli` 与 `http`                           |
| 分层只写在 README 里                                                 | 三次提交后失效，模块互相 import 成网                                                                                     | 写成 eslint`no-restricted-imports` + 一致性测试                 |
| 存储直接用默认路径                                                   | 测试写脏用户的真实数据目录                                                                                               | 存储路径支持环境变量覆盖，测试必须指向临时目录                    |
| 面板与 CLI 传参形态不同（CLI 用`--off`、面板传 `enabled:false`） | 同一语义两条调用路径，只测了一条 → 另一条静默失效                                                                       | 两条入口必须有**对照测试**断言走同一分支                    |
| 声明了`args:['ref']` 却没检查它与 `http` 的 `:ref` 同名        | 参数静默变成`undefined` 传进 service（无 body 的 DELETE 尤其容易中招）                                                 | 写完一条 action 就对照名字，见[[A00-design-and-verify]] 的 ctx 契约表                      |
| 用「目录名」的校验规则去卡文件路径                                   | 拒绝`.gitignore` 这类正常文件                                                                                          | 名称与路径分开校验；路径允许前导点                                |
| 直接把 node 侧代码 import 进前端                                     | Vite 把`node:` 内置模块打进浏览器包                                                                                    | 前端只 import `shared/` 与 `api/client.generated.ts`，三条边界用 lint 拦住（见 [[A11-frontend-split]]） |
| 改了 action 契约却没重跑生成                                         | `client.generated.ts` 与后端签名漂移；类型检查发现不了（生成物里是旧类型），运行时才 404/参数错                     | `pnpm test` 链里含 `gen` + 新鲜度对账测试；提交前必须 `pnpm gen` |
| 没有主键就谈"乐观并发"                                               | JSON 档整份覆盖：两个进程各自读旧值再写，后写的静默抹掉先写的（经典 lost-update）；SQLite 档无主键则连冲突都检测不到 | JSON 档也用 `rev` 计数（载入记 rev，提交不匹配抛 `BLOCKED`）；SQLite 档读 `meta.rev`，不匹配抛 `BLOCKED`（见 [[A05-state-storage]]） |
| 数据量还没上来就上 SQLite                                             | 前期项目被迫写迁移链、备份、PRAGMA，维护成本压过收益 | 先 JSON（几百条记录足够），出现「关系查询 / 多写者 / 历史审计」信号再升 SQLite（见 [[A05-state-storage]] 判档表） |
| 用 JS 写存储层                                                       | 结构靠约定不靠类型，字段改名全仓库静默漏 | 存储层一律 TS：`StoreState` 接口 + 仓储接口，JSON 与 SQLite 实现同一个接口 |
| 新模块忘补 eslint 的互依禁列                                         | **静默**：新模块变成「谁都可以依赖」，而那条禁列是逐模块枚举的，规则随模块数增加持续衰减                           | 把「加模块必补禁列」写进[[A07-extension-loop]] 的闭环表；禁列旁留注释说明漏补是静默的   |
| 读命令的 flag 照抄写命令的`default`                                | 参数层无条件注入默认值，「不传 = 全部」的分支**永远走不到**——不报错、不崩，只是永远返回半个结果                  | 写命令的 flag 可带`default`，读命令的过滤 flag 一律不带         |
| 加了命令但没写进`assets/<skill>/`                                  | **单向断言**只保证「文档提到的命令一定存在」，反方向不强制 → 漏写没有任何测试会红，而 agent 侧该命令等于不存在    | 更新`assets/` 是闭环的**必做项**，不是「有空再补」        |
| 把开发规范（加功能域要碰哪几处、lint 怎么改）写进`assets/<skill>/` | 这段知识随包发到用户机器上，而用户侧 agent 手上没有`src/`，永远用不上；真正需要它的仓库开发者在项目仓库里反倒找不到   | 判据是「**用户装完包，他的 agent 何时需要它**」，不是「它重不重要」；开发规范归位到项目`README.md`／本脚手架 skill（见 [[A04-assert-skill]]）        |
| lint 规则从没红过就当它没问题                                        | 规则写错（路径 glob 不匹配、files 没覆盖到`view.jsx`）不会报错，只会永远通过——**一个从没红过的规则等于不存在** | 加/改 lint 规则后做一次反向测试：临时写个违例文件，确认退出码非 0 |
| `serve` 端口被占就抛「请换一个端口」                                | 用户多半**自己已经开着一个**——既看不到它也拿不到地址，还要自己猜端口                     | 探测占用者：是自己就复用并**开浏览器**；是别人才换端口（见 [[A01-bootstrap-serve-first]]） |
| 关闭开关写成 `NX_<项目>_NO_OPEN`                                    | 一个变量关不掉全部项目，「全项目统一关闭」名存实亡                                          | 固定 `NX_SERVE_NO_OPEN`，所有项目同一个名字                   |

_最后更新：2026-11-19_

## Limitations

- 只面向**单机单用户**工具；不做多租户、鉴权、远程部署（需要这些请换 server 框架）。
- **JSON 档没有事务与多写者保证**：只有原子写 + `rev` 乐观并发；两个以上写进程频繁冲突时该升 SQLite。
- SQLite 走 `node:sqlite`（Node ≥ 22 内置，仍标 experimental）：升级 Node 时先跑 `pnpm test:db`，
  驱动差异只在 `core/db/driver.ts` 一处需要适配。
- 代码生成覆盖的是「契约 → 客户端方法」，**不覆盖页面接线**：哪个按钮调哪个 action 仍需手写。
- 前端壳是 React + Vite，不提供 SSR；面板只在 `127.0.0.1` 本机使用。
- 本 skill 只管项目骨架与工程规范，不负责业务语义设计，也不做效果评测（评测走 SkillEvaluator）。

## Troubleshooting

| 症状 | 大概率原因 | 处置 |
| --- | --- | --- |
| `pnpm typecheck` 报「找不到 _manifest」 | 新模块只建了 `actions/*.ts`，没跑 `pnpm gen` | 跑 `pnpm gen`，并把生成物提交 |
| 前端调用 404 / 参数名对不上 | `client.generated.ts` 是旧的 | 重跑 `gen-api-client`；看 `cli-tree.json` 里该 action 的路由 |
| 启动即崩、报 `SQLITE_BUSY` | 多进程同时写、没设 `busy_timeout` | 连接级 PRAGMA 一次设好；写路径包 `tx()` |
| 升级后读不出旧数据 | 迁移没跑或 `user_version` 不对 | 看 `core/db/version.ts` 与 `migrations/index.ts` 的步骤表；升级前先 `VACUUM INTO` 备份 |
| 浏览器包体积异常、build 报 `node:` 无法解析 | 前端 import 了后端模块 | 按 [[A11-frontend-split]] 的边界排查，lint 反向测试确认规则生效 |

## 操作记录

已迁出主文档 → [[B06-操作记录]]。新增记录按 X01 操作记录模板写：`YYYY-MM-DD｜触发时机`，并带「失效条件 / 复核于」。
