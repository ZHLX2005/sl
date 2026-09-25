# B02 · link-local shim：把全局命令指向本仓库（Windows 重操作）

> 归属主文档 [[server-cli-web-scaffold]]。这是一个**重量级环境操作**，**不接入创建流程**——
> 只在「改了代码想让全局 `xxx` 命令立刻生效」或「排查全局命令指向了哪份代码」时才读。
> 参考实现：`nx-rp`（v2，事故修复后的成熟版）与 `nx-sk`（移植 + devDir 收敛版）。
> 每一条都来自真实事故。

## 一、什么时候读这个

- 全局敲 `xxx` 跑的还是旧版，想让它**实时**指向本仓库（改码即生效，不用发版）
- 犹豫 `npm link` / `volta install` / 手写 shim 该选哪个
- 接手别人装过的 shim，要弄清「现在指向哪、怎么还原」
- 写项目自己的 `scripts/link-local.mjs`（本 ref 的 SOP 就是它的设计文档）

不适用：正式发版流程（走 [[A06-release-actions]]）；CI 里的安装（CI 根本不需要 shim）。

## 二、为什么是覆盖式 shim，而不是 npm link / volta install

| 路子 | 问题 |
| --- | --- |
| `npm link` | 在 **npm 全局 prefix** 下建 shim，而这个 prefix 未必在用户真实 PATH 上（volta 管的机器上尤其如此）——link 完 `xxx` 在用户终端里**仍然走旧包或 command not found**，且没人会注意到 |
| `volta install`（快照式） | `pnpm pack → volta install tarball`，装的是**快照**，改码后必须重跑；只在用户显式要求时作为备选模式 |
| **覆盖式 shim（默认）** | 找到用户敲 `xxx` 时**真实命中**的落点（PATH 顺序第一个含该命令变体的目录），把那里的启动器**备份后原地替换**成转发器。PATH 一字不动，已开着的终端立即生效；volta / npm / pnpm 管的文本 shim 一视同仁 |

覆盖式唯一的病根风险是「原件丢了」。曾发生过：早期版本覆盖不留备份，unlink 后
**全局命令静默消失**（nx-rp 审查实测事故）。结论不是「别覆盖」，而是「覆盖前必须逐字节备份」——
这就是 RECEIPT 清单的由来。

## 三、SOP：写一个 link-local.mjs

### 1. 探测现状（先看，后动）

不用 `where`/`which`——解析输出在不同 shell 下格式不一。**直接按 PATH 顺序找候选目录里
有没有 `xxx` 变体**（Windows 上 `.cmd` / `.exe` / `.bat` / 无扩展名），第一个命中目录就是
真实落点。无扩展名 / `.cmd` / `.ps1` / `.bat` 分别对应 Git Bash、cmd、PowerShell 三种调用方，
要全部覆盖；只有 `.exe` 的目录没法文本转发，报告后走兜底。

volta bin 定位后必须**校验特征**：目录里任一 `.cmd` 含 `volta run` 才算数——防止把用户 PATH 上
恰好叫 `Volta\bin` 的无关目录当成真的。

### 2. 覆盖（备份先行）

- 每个被改文件的原始内容**逐字节**存进 RECEIPT（`originals`），`null` = 原本不存在（unlink 时删除）
- 转发器内容带标记注释（如 `@REM xxx-local-shim -> <repo>`）：既是身份标识，也是 unlink 时
  「这文件还是不是我们的产物」的判据——别人改过的文件不能盲还原
- 重装保护（**v2 事故修复，必做**）：目标已是本工具转发器时，原件以**既有 v2 清单**为准，
  绝不把转发器内容当「原件」存进去——否则每重装一次原件就假一分，unlink 永远还原不回去
- 重装保护要**校验清单的 targetDir 与本次落点一致**才采信（用户换机器/换落点时旧清单是误导）
- 无扩展名文件写完要 `chmod 0o755`（Git Bash 需要 x 位）

### 3. RECEIPT 清单（unlink 的唯一依据）

```json
{
  "version": 2,
  "mode": "shim",
  "targetDir": "C:\\users\\me\\.local\\bin",
  "originals": { "C:\\...\\xxx": "原内容或 null", "C:\\...\\xxx.cmd": "..." },
  "pathEdit": null,
  "installedAt": "..."
}
```

**放哪**：`~/<工具名>/dev/install.json`——放工具自己的数据根目录下的 `dev/` 子目录，
**不要**为 dev shim 在用户空间另声明一个顶层目录（`~/xxx-dev/` 就是反例：用户视角多出一块
来路不明的顶层目录）。也**不要**走 `appHome()` 环境变量覆盖——清单记录的是**机器级** shim
状态，归属这台机器，不随 `NX_SK_HOME` 这类会话级覆盖漂移。

### 4. 兜底落点（PATH 上没有现成落点时才走）

优先级：**绝不写进包管理器自己的目录**（npm/volta/pnpm prefix——那里归包管理器管，更新时
可能被清掉）。

1. 用户 PATH 上**既有**的干净目录（不改注册表）：排在 volta bin 之前的、非 `%VAR%`、
   非系统受管（WindowsApps / WinGet / System32 / Program Files）
2. 实在没有才新建 `~/<工具名>/dev/` 并**防御性地**插到用户 PATH 最前面：
   - 读用户 PATH 用 `reg query`，失败再 PowerShell 复核；**查询失败必须中止**，
     绝不能把「读不到」当「PATH 为空」去写（那会清空用户 PATH）
   - 写后必须**回读校验**，不一致就中止并报告
   - 跳过 `%VAR%` 条目（`GetEnvironmentVariable` 三参重载读原文不展开；两参的旧 .NET 会展开）

### 5. unlink 还原

- 只信 RECEIPT；`originals[f] === null` → 删文件，有内容 → 原样写回（+x 位）
- 还原前校验文件仍带本工具 shim 标记，不带就跳过（文件被人改过，不能盲写）
- 当时的 `pathEdit` 要从用户 PATH 摘除（同样走读校验写）
- 清单不存在时给兜底扫描（默认 devDir 里找带标记的文件），并提示用户手查 PATH 残留

### 6. build 链路的 `--auto` 模式（CI 安全）

`build` 脚本挂 `link-local --auto`：**只覆盖现成落点**，没有就静默跳过——不新建目录、
不动 PATH、任何异常都不拖垮 build。这样 CI / 全新机器跑 `pnpm run build` 完全安全，
而日常开发 build 顺带保持 shim 新鲜。

```json
"build": "vite build && node scripts/link-local.mjs --auto",
"link:local": "node scripts/link-local.mjs",
"unlink:local": "node scripts/link-local.mjs --unlink"
```

默认**直接动手**（覆盖 + 备份足够安全，dry-run 反而挡路）；`--dry-run` 才只预览。

## 四、踩过的坑（全部真实发生）

| 坑 | 后果 | 正确做法 |
| --- | --- | --- |
| `npm link` 在 volta 机器上用 | shim 落在 npm prefix（不在真实 PATH），`xxx` 仍走 volta 旧包，没人注意到 | 探测 PATH 上的**真实落点**，原地覆盖 |
| 覆盖不留备份（v1） | unlink 后全局命令**静默消失** | 覆盖前逐字节存 RECEIPT；这就是「那次事故的根源是没备份，不是覆盖本身」 |
| 重装时把转发器当「原件」备份 | 每装一次原件假一分，unlink 永远还原不回 | 已是转发器 → 原件以既有 v2 清单为准；且校验 targetDir 一致才采信 |
| RECEIPT 放 `~/xxx-dev/` 顶层目录 | 用户空间多一块来路不明的顶层目录 | 收进 `~/<工具名>/dev/`；机器级状态，不走 appHome 覆盖 |
| 兜底目录写进包管理器 prefix | 包管理器更新时被清掉或冲突 | 只写用户 PATH 既有干净目录，或新建 `~/<工具名>/dev/` |
| 读用户 PATH 失败当「PATH 为空」 | 写回去**清空用户 PATH** | 查询失败必须中止；reg + PowerShell 双路 |
| 写 PATH 后不回读 | 写坏了不知道 | 回读校验，不一致即中止 |
| `spawn('npm', ..., { shell: true })` | Windows 上 npm.cmd 参数被 cmd.exe 重排/截断 | 直接 spawn node 二进制；PATH 操作用 `reg` / `powershell` 直调 |
| PowerShell `GetEnvironmentVariable` 三参重载在旧 .NET 不存在 | 脚本报「找不到方法」重载 | 优先 `reg query`；三参不可用时降级两参（接受 `%VAR%` 展开的差异，跳过含 `%` 的条目） |
| Git Bash 把 `/v` `/T` 当路径转换（→ `C:/Program Files/Git/v`） | `reg query HKCU\... /v Path` 报无效语法 | MSYS 下写 `//v`，或改走 PowerShell；详见 [[A08-framework-runtime]] 第五节 |
| unlink 盲还原被改过的文件 | 把用户后来的修改覆盖掉 | 还原前校验文件仍带 shim 标记；无标记跳过 |

## 五、案例时间线（两个参考实现）

- **nx-rp v1 → v2**：v1 覆盖不留备份 → unlink 后全局命令消失（审查实测发现）→ v2 引入
  RECEIPT（originals 逐字节备份）+ 重装保护（转发器原件以既有清单为准）+ v1 清单 legacy 清理
- **nx-sk 移植（2026-09-24）**：从 nx-rp 移植时**漏了重装保护**，装完后发现 shim 已存在但
  无清单（正是 v1 事故态）——补上重装保护后，当时只能以「转发器现内容」为原件（历史原件
  已不可考）；随后把 RECEIPT 从 `~/nx-sk-dev/` 收敛到 `~/nx-sk/dev/`，并清理了更早一次
  兜底安装留下的孤儿 shim（清理前先验证带 shim 标记 + 注册表确认 PATH 无残留条目）

**教训**：移植这类「安全机制」脚本时，逐条对照参考实现的**事故修复 diff**，不能只抄主流程——
主流程两版几乎一样，恰恰是防事故的部分最容易在移植中丢。
