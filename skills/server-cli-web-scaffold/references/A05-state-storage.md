---
name: A05-state-storage
description: server-cli-web 的状态存储两档选择（都用 TypeScript 实现）——前期 JSON 单文件（类型化 StoreState、原子写、mtime 失效、rev 乐观并发、零依赖）；数据量/并发/关系查询上来后升级 SQLite（node:sqlite 唯一引用点、user_version 迁移、每步一事务、VACUUM INTO、meta.rev）；两档共用同一仓储接口。
---

# A05 · 状态存储：JSON 与 SQLite 两档

> 归属主文档 [[server-cli-web-scaffold]]。定存储、接持久化、做升级时读这篇。

**先把一句话钉死：JSON 与 SQLite 是两档技术选择，不是新旧代差。**
前期项目用 JSON 是合理的（简单、零依赖、能手工修）；数据与并发需求上来后升 SQLite。
**两档都必须用 TypeScript 实现**——不写 JS，结构靠类型而不是靠约定。

## 一、先选档

| 维度 | JSON 档（前期） | SQLite 档（升级后） |
| --- | --- | --- |
| 适用 | 起步项目、几百到几千条记录、单写者为主 | 关系查询、多写者、历史/审计、数据超过几 MB |
| 依赖 | 零（`node:fs`） | `node:sqlite`（Node ≥ 22，仍 experimental） |
| 写入 | 全量序列化 + 原子写（tmp + rename） | 单语句 / `tx()` 事务 |
| 并发 | 原子写 + `rev` 乐观并发（检测得到、需重试） | WAL + `BEGIN IMMEDIATE` + `meta.rev` |
| 查询 | 全量载入内存，自己 filter | SQL、索引、join |
| 结构演进 | `normalize()` 补默认值（向前兼容） | `PRAGMA user_version` 迁移链 |
| 调试 | 文本可读、可手工改 | 需要 sqlite 客户端 |
| 成本 | 低 | 中（迁移、备份、PRAGMA） |

**升级信号（出现任意两条就该升）**：

1. 单文件接近几 MB，或每次启动读全量明显变慢。
2. 需要按多个条件筛选 / 排序 / 聚合，代码里到处 `filter`。
3. 有两个以上进程频繁写，`rev` 冲突（`BLOCKED`）成为常态。
4. 需要历史记录、审计、按时间回溯，或跨表一致性。

**没出现这些信号就不要提前上 SQLite**：迁移链、备份、PRAGMA 都是真实维护成本，
在几百条记录的项目里是过度工程。

## 二、放哪（两档一致）

```
~/.<主题名>/
  store.json          JSON 档：单一数据文件
  <名>.db             SQLite 档：主库
  backups/            SQLite 升级前的 VACUUM INTO 备份
```

一级目录、以主题名命名（`~/.xxx/`）的理由：用户能一眼找到、能手工备份、能删了重来。

```ts
// core/paths.ts —— 路径的唯一定义处
export const APP_NAME = '<主题名>';
export const APP_DIR = join(homedir(), `.${APP_NAME}`);
export const STORE_PATH = join(APP_DIR, 'store.json');
export const DB_PATH = join(APP_DIR, `${APP_NAME}.db`);

// 环境变量覆盖不是可选项：没有它，测试会写脏用户真实数据
export const storePath = (): string => process.env.<NAME>_STORE || STORE_PATH;
export const dbPath = (): string => process.env.<NAME>_DB || DB_PATH;
```

启动横幅把生效路径打出来：`存储: ~/.xxx/store.json` 或 `数据库: ~/.xxx/xxx.db`。

## 三、JSON 档（TypeScript）

### 3.1 状态形状与默认值

```ts
// core/store/types.ts
export interface Settings {
  theme: 'light' | 'dark';
  defaultTarget: string;
}

// Item 是项目自己的实体类型（如 Repo / Task）；这里只示范存放方式。
export interface Item { id: string }

export interface StoreState {
  version: number;
  rev: number;                 // 乐观并发计数，每次写入 +1
  settings: Settings;
  records: Item[];            // 业务集合，形状由项目定；这里用 records 代指
}

export const emptyState = (): StoreState => ({
  version: 1,
  rev: 0,
  settings: { theme: 'light', defaultTarget: '' },
  records: [],
});

// normalize 是向前兼容的兜底：老文件缺新字段时补默认值
export function normalize(raw: unknown): StoreState {
  const base = emptyState();
  if (!raw || typeof raw !== 'object') return base;
  const data = raw as Partial<StoreState>;
  return {
    ...base,
    ...data,
    version: data.version ?? base.version,
    rev: data.rev ?? 0,
    settings: { ...base.settings, ...(data.settings ?? {}) },
    records: Array.isArray(data.records) ? data.records! : [],
  };
}
```

**新增字段一律给默认值**，这样 `version` 很少需要真的用上。

### 3.2 原子写：永远不要直接覆写

进程在写到一半被杀（Ctrl+C、断电、OOM），直接覆写会让数据文件永久损坏。

```ts
async function writeAtomic(p: string, data: StoreState): Promise<void> {
  await fsp.mkdir(dirname(p), { recursive: true });
  const tmp = `${p}.tmp`;
  await fsp.writeFile(tmp, JSON.stringify(data, null, 2), 'utf8');
  await fsp.rename(tmp, p);      // 同一文件系统上 rename 是原子的
}
```

`rename` 让"新内容完整落盘"与"替换旧文件"成为一个不可分割的动作：
用户要么看到旧数据，要么看到新数据，不会看到半截。

### 3.3 读：缓存 + mtime 失效

CLI 进程改了数据，正在运行的 Web 服务必须立刻看到。**按 mtime 失效**：

```ts
let cache: StoreState | null = null;
let cacheMtime = -1;

export async function loadStore(explicit?: string): Promise<StoreState> {
  const p = explicit ?? storePath();
  try {
    const st = await fsp.stat(p);
    if (cache && cacheMtime === st.mtimeMs) return cache;
    cache = normalize(JSON.parse(await fsp.readFile(p, 'utf8')));
    cacheMtime = st.mtimeMs;
    return cache;
  } catch {
    // 文件不存在或损坏：返回空结构（首启；也允许用户手工修好后自动恢复）
    cache = normalize(null);
    cacheMtime = -1;
    return cache;
  }
}
```

两个容易漏的点：

1. **自己写完要主动刷新 mtime**，否则下一次读取白跑一遍，甚至可能读到中间态。
2. **读失败降级返回空结构，而不是抛错**：文件损坏时用户还能打开界面去修，
   而不是面对一个"启动即崩"的工具。

### 3.4 写：深拷贝 + `rev` 乐观并发

```ts
export async function mutateStore<T>(
  fn: (s: StoreState) => T,
  explicit?: string,
): Promise<T> {
  const p = explicit ?? storePath();
  const cur = structuredClone(await loadStore(p));   // 深拷贝：抛错不落盘才成立
  const expectedRev = cur.rev;
  cur.rev = expectedRev + 1;
  const result = fn(cur);                             // fn 抛错 → 不写盘
  // 写前再读一次磁盘 rev：两个进程同时改时，后提交者必须失败
  const latest = await loadStore(p);
  if (latest.rev !== expectedRev) {
    throw new AppError('BLOCKED', '数据已被其他进程修改，请重试');
  }
  await writeAtomic(p, cur);
  cache = cur;
  cacheMtime = (await fsp.stat(p)).mtimeMs;
  return result;
}
```

- **深拷贝是必需的**：直接改缓存对象会让"抛错不落盘"失效，因为缓存里已经是脏数据。
- `BLOCKED` 是**业务结果**（调用方可重试 / 提示用户），不是崩溃。
- JSON 档的并发是"检测得到、但不排队"：冲突多了就是升级信号。

> **现状提醒**：模板里的 `JsonStore`（`templates/server-cli-web/files/src/core/store.ts`）
> 已有原子写与 mtime 失效，但**还没有 `rev`**。新项目按本节补上；
> 单进程使用可以暂时不补，但只要 `serve` 与 CLI 同时写，就必须有 `rev`。

### 3.5 仓储接口（两档共用）

```ts
// core/store/repo.ts —— service 只认这个接口，不认具体实现
export interface StoreRepo {
  load(): Promise<StoreState>;
  mutate<T>(fn: (s: StoreState) => T): Promise<T>;
}
```

JSON 实现与 SQLite 实现都满足它；service 层不 import `node:fs` 或 `node:sqlite`。

## 四、SQLite 档

### 4.1 驱动：全项目唯一引用点

`node:sqlite` 仍是 experimental，API 改过（`DatabaseSync` → `Database`、`undefined` 绑定行为变化）。
**只在 `core/db/driver.ts` 里 import 它**，升级 Node 时只改这一个文件。

三个实测坑：

1. **每次 import 都往 stderr 打 `ExperimentalWarning`**：污染冒烟测试文案断言。
   → `import './quiet.js'` **必须排在 `node:sqlite` 之前**（ESM 按声明顺序求值）。
2. **行对象是 null 原型**：`deepEqual` 失败。→ 出站一律 `{ ...row }`。
3. **`undefined` / `boolean` 不能绑定**：22.x 抛 `Provided value cannot be bound`。
   → 入站统一 `bindValue()`：`undefined → null`、`boolean → 0|1`、`Date → ms`、`bigint → number`。

**PRAGMA 是连接级设置**，每个连接都要设一次：

```ts
raw.exec(`
  PRAGMA journal_mode = WAL;
  PRAGMA foreign_keys = ON;       -- 默认 OFF，漏了 REFERENCES 全部不生效且不报错
  PRAGMA busy_timeout = 5000;     -- 抢写锁时等待，而不是立刻 SQLITE_BUSY
  PRAGMA synchronous = NORMAL;
`);
```

### 4.2 迁移链：`PRAGMA user_version` 驱动

```
core/db/
  version.ts            CURRENT_SCHEMA_VERSION
  migrations/index.ts   步骤表（每步声明 id / sql / apply）
  migrations/v1.sql …   DDL
  migrator.ts           planMigrationPath / migrate / backup
  bootstrap.ts          打开库 → 迁移 → 种子（升级只在这里发生）
```

四条硬规则：

1. **每步一个事务**：升级是"版本 N 已可用"的累加过程；一步失败停在上一可用版本，
   比整体回滚到 v1（数据在、但一列都读不出来）好排障。
2. **升级前 `VACUUM INTO` 备份**：WAL 下直接复制 `.db` 会拿到不一致快照；
   `VACUUM` 不能在事务里跑，所以备份是**升级事务之前**的独立动作。
3. **不给业务层懒升级的机会**：拿着旧 schema 干活的路径一条都不留。
4. **备份保留最近 N 份**：文件名用定宽时间戳，字典序即时间序。

### 4.3 写：`tx()` + `meta.rev`

```ts
export function tx<T>(db: DbApi, fn: () => T): T {
  db.exec('BEGIN IMMEDIATE');          // 立刻拿写锁，避免读到旧值再写
  try { const r = fn(); db.exec('COMMIT'); return r; }
  catch (e) { try { db.exec('ROLLBACK'); } catch {} throw e; }
}
```

```ts
const rev = Number(db.scalar(`SELECT value FROM meta WHERE key = 'rev'`) ?? 0);
tx(db, () => {
  const cur = Number(db.scalar(`SELECT value FROM meta WHERE key = 'rev'`));
  if (cur !== rev) throw new AppError('BLOCKED', '数据已被其他进程修改，请重试');
  db.run(`UPDATE meta SET value = ? WHERE key = 'rev'`, cur + 1);
  // …业务写入…
});
```

- 事务里不要再开事务；一个业务动作一个事务。
- 前端遇到 `BLOCKED` 应刷新后重试，不要静默重放。

### 4.4 从 JSON 档升级：只导入一次

```ts
if (!db.scalar(`SELECT 1 FROM meta WHERE key = 'json_imported'`) && existsSync(STORE_PATH)) {
  const legacy = normalize(JSON.parse(readFileSync(STORE_PATH, 'utf8')));
  tx(db, () => {
    // 按表插入；settings 逐键写入；rev 取 legacy.rev
    db.run(`INSERT INTO meta(key, value) VALUES('json_imported', '1')`);
  });
  renameSync(STORE_PATH, STORE_PATH + '.imported');   // 留证，不再读
}
```

- **只导入一次**：`meta.json_imported` 做幂等键；导入后改名，避免下次启动重复导入
  （否则用户删掉的数据会"复活"）。
- 升级期可以保留 `StoreRepo` 的 JSON 实现做回滚；切到 SQLite 实现是**换一个工厂**，
  service 代码不动。
- 稳定后删掉 JSON 读写代码与 mtime 缓存——**留着就是第二套真相**。

## 五、settings 的唯一归属

```
modules/settings/service.ts     ← 唯一读写入口（getSettings / updateSettings）
modules/settings/actions.ts     ← setting get / set
web/frontend/pages/settings/    ← 设置页
```

存储上，JSON 档是 `state.settings`，SQLite 档是 `settings(key, value)` 表或 `meta` 的 JSON 列；
关键是**唯一入口**。数组型设置项在读取时统一归一化。

分层例外：其他模块可以单向只读 `settings/service.ts`，
lint 的枚举式禁列里**故意不列 settings**——这就是"唯一例外"的可执行写法。

## 六、测试怎么不碰真实数据

- 每档都用临时目录：`<NAME>_STORE=<tmp>/store.json` / `<NAME>_DB=<tmp>/t.db`；
  SQLite 的 `afterEach` **先 `db.close()` 再删目录**（Windows 上连接开着删库会 `EBUSY`）。
- JSON 档测试：原子写（写一半被杀不损坏）、mtime 失效、`rev` 冲突抛 `BLOCKED`。
- SQLite 档测试：从 v1 fixture 跑到当前版本、每步表结构、`VACUUM INTO` 备份可独立打开、
  两连接并发第二个拿到 `BLOCKED`。
- 升级测试：JSON fixture → 导入 SQLite → 数据条数与 `rev` 一致 → 再跑一次不重复导入。

## 检查清单

- [ ] 档位已声明（JSON 前期 / SQLite 升级），不是"默认上 SQLite"也不是"永远 JSON"
- [ ] 存储层是 TS：有 `StoreState` 接口与 `StoreRepo` 接口，没有 JS / `any` 逃逸
- [ ] 路径唯一在 `core/paths.ts`，两档都能用环境变量覆盖
- [ ] JSON 档：原子写（tmp + rename）、mtime 失效、`structuredClone`、`rev` 冲突抛 `BLOCKED`
- [ ] SQLite 档：`node:sqlite` 只在 `driver.ts`；每个连接设 PRAGMA；`user_version` 迁移；每步一事务；`VACUUM INTO` 备份
- [ ] SQLite 档写路径全走 `tx()`，`meta.rev` 冲突抛 `BLOCKED`（exit 0）
- [ ] 从 JSON 升级只导入一次并改名留证
- [ ] service 层只依赖 `StoreRepo`，不直接 import `node:fs` / `node:sqlite`

## 坑

| 坑 | 后果 | 正确做法 |
| --- | --- | --- |
| 把 JSON 当"落后方案"，起步就上 SQLite | 迁移链、备份、PRAGMA 压过收益 | 先 JSON，出现升级信号再换（判档表见第一节） |
| 用 JS 写存储层 | 结构靠约定，字段改名静默漏 | `StoreState` + `StoreRepo` 全 TS |
| JSON 直接覆写文件 | 中断即数据损坏 | 临时文件 + `rename` |
| 没有环境变量覆盖 | 测试写脏用户真实数据，且不易察觉 | `storePath()` / `dbPath()`，测试指向临时目录 |
| 深拷贝缺失 | 抛错后缓存里已是脏数据，"不落盘"名存实亡 | `mutateStore` 用 `structuredClone` |
| 自己写完不刷新 mtime | 下次读取白跑，可能读到中间态 | 写入后主动 `stat` 更新缓存 |
| 读失败直接抛错 | 数据文件损坏时工具启动即崩，用户无法自救 | JSON 档降级返回空结构 |
| JSON 档没有 `rev` | 两进程互相覆盖，lost-update | 载入记 rev，提交不匹配抛 `BLOCKED` |
| `node:sqlite` 散落多处 | 升级 Node 要改一圈 | 只留 `driver.ts` 一个引用点 |
| `import './quiet.js'` 放错顺序 | ExperimentalWarning 仍会打，冒烟断言随机红 | quiet 必须排第一 |
| 出站行直接返回 | null 原型让 `deepEqual` / 序列化出怪 | `{ ...row }` |
| 绑定 `undefined` / `boolean` | `Provided value cannot be bound` | `bindValue()` 归一 |
| 漏 `foreign_keys = ON` | 外键约束全部不生效，且不报错 | 每个连接设一次 PRAGMA |
| 升级前直接复制 `.db` | WAL 下拿到不一致快照 | `VACUUM INTO`（在事务之外） |
| 全程一个大事务迁移 | 一步失败回滚到 v1，数据在但读不出 | 每步一个事务 |
| 旧 `store.json` 每次启动都导入 | 用户删掉的数据"复活" | `json_imported` 幂等 + 改名 |
