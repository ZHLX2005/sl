# A06-rust-npm-cli — Rust CLI 通过 npm 分发（npx 直启）

> **加载时机**：要发布一个 Rust 编译的 CLI 工具，让用户 `npx <pkg>` 一键使用、无需安装 Rust 工具链时读本 ref。纯 JS/TS 包发布走 [[A03-npm-publish]]；本 ref 在其上叠加"二进制怎么进包、怎么跟 JS 一起发"这一层。

## 适用场景

- Rust 编译的单文件 CLI，想给不装 Rust 的用户一键运行（`npx <pkg>` / `npm i -g <pkg>`）
- 工具平台受限（如 Windows-only 的系统能力：WASAPI / 注册表 / Win32 API），希望 npm 侧直接拒绝不匹配平台
- 想要一条 `push → 编译 → 冒烟 → 发 npm` 的全自动链路

## 不适用场景

- 纯 JS/TS 包（无二进制）→ [[A03-npm-publish]]
- 需要分发动态库 / cdylib 给其他程序链接（这是 FFI 分发，不是 CLI 分发）
- 用户群都在同一内网、能直接拿到二进制 → 直接发 GitHub Release 即可，npm 这层是多余的

---

## 形态选择：单包内嵌 vs 主包+平台子包

| 形态                              | 结构                                                                 | 何时用                                                                                               |
| --------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| **单包内嵌**（本 ref 默认） | 一个 npm 包，二进制放 `binaries/<platform>-<arch>/` 随包发布       | 平台数 ≤ 2、二进制体积可接受（< 10 MB）。发布链路只有一条，最简                                     |
| **主包 + 平台子包**         | 主包 JS-only，每个平台一个子包，主包用 `optionalDependencies` 拉取 | 平台多（win/mac/linux × x64/arm64）、或想控制主包体积。代价：每个子包一条发布链路，版本同步成本翻倍 |

**建议从单包起步**。二进制变大或多平台了再拆子包，拆的成本远低于一开始就维护错。

---

## 仓库布局（单包形态）

```
<repo-root>/
├── Cargo.toml                 # Rust crate；[[bin]] name 与 npm bin 名保持一致
├── src/
├── package.json               # npm 包：bin + files + os/cpu
├── bin/<bin-name>.js          # JS 入口：解析二进制路径 → spawn
├── lib/platform.js            # 二进制路径解析（fallback 链）
├── binaries/<platform>-<arch>/  # 随包分发的二进制（CI 会覆盖更新）
│   └── <bin-name><.exe>
└── .github/workflows/
    ├── build.yml              # 编译 → 冒烟 → 提交二进制回仓库 → (tag 时) Release
    └── publish.yml            # workflow_run 触发 → 幂等检查 → npm publish
```

---

## 三大件

### 1. JS 入口 + 路径解析

`bin/<bin-name>.js`——只做一件事：找到二进制，透传参数，退出码透传：

```js
#!/usr/bin/env node
'use strict';
const { spawn } = require('child_process');
const { getBinaryPath } = require('../lib/platform');

let binary;
try { binary = getBinaryPath(); } catch (err) {
  console.error(err.message); process.exit(1);
}

const child = spawn(binary, process.argv.slice(2), { stdio: 'inherit' });
child.on('error', (err) => { console.error(err.message); process.exit(1); });
child.on('exit', (code, signal) => {
  if (signal) process.kill(process.pid, signal);
  else process.exit(code || 0);
});
```

`lib/platform.js` 的 fallback 链（顺序即优先级）：

1. **环境变量**（如 `<PKG>_BINARY`）——调试与自定义构建覆盖，必须最先
2. **随包的 `binaries/<platform>-<arch>/`**——npm install 用户的主路径
3. **`target/release/`**——仓库内开发者的 cargo 产物
4. 都没有 → 报错，错误信息里写清三条出路（装包 / cargo build / 设环境变量）

`process.platform` + `process.arch` 拼 key，Windows 记得补 `.exe` 后缀。

### 2. package.json 关键字段

```jsonc
{
  "name": "<pkg-name>",
  "bin": { "<bin-name>": "./bin/<bin-name>.js" },
  "files": ["bin/", "lib/", "binaries/", "README.md"],  // files 白名单控制包体积
  "os": ["win32"],        // 平台限定：npm 在不匹配平台直接拒绝安装，用户得到明确报错
  "cpu": ["x64"],
  "engines": { "node": ">=18.0.0" },
  "repository": { "type": "git", "url": "https://github.com/<owner>/<repo>.git" }  // --provenance 必需
}
```

- `os`/`cpu` 不是摆设：配了之后 macOS 用户 `npm i` 会得到清晰的 unsupported platform 提示，而不是装上后运行时炸
- crate 版本号与 npm `version` **保持一致**（手工同步；两条版本线漂移是维护噩梦）

### 3. workflow：build（编译 + 提交二进制回仓库）

```yaml
name: build
on:
  push:
    branches: [main]
    paths: ['src/**', 'Cargo.toml', '.github/workflows/build.yml']
    tags: ['v*']
  pull_request:
    paths: ['src/**', 'Cargo.toml', '.github/workflows/build.yml']
  workflow_dispatch:

permissions:
  contents: write        # 提交二进制回仓库 + 打 tag 建 Release 都需要

jobs:
  build:
    runs-on: <runner>    # 按目标平台选，Windows 工具就 windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
        with: { workspaces: '. -> target' }

      - run: cargo build --release --locked

      # 三层冒烟，一层都不能省：
      #   --help/--version   二进制本体活着
      #   JS resolver        bin 查找链在 CI 环境也能走通（用环境变量指向新产物）
      - name: Smoke (binary)
        shell: bash
        run: |
          ./target/release/<bin-name> --help
          ./target/release/<bin-name> --version
      - name: Smoke (JS resolver)
        shell: bash
        run: |
          <PKG>_BINARY="$(pwd)/target/release/<bin-name>" node -e "
            const p = require('./lib/platform').getBinaryPath();
            const out = require('child_process').execSync('\"' + p + '\" --version', {encoding:'utf8'});
            if (!out.includes('<bin-name>')) throw new Error('not responsive');
          "

      # 关键步：二进制 commit 回仓库。publish 侧直接 checkout 这个 commit，
      # 不走 artifact 传递（原因见下"为什么这样设计"第 2 条）。
      - name: Commit binary back
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        shell: bash
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          mkdir -p binaries/<platform>-<arch>
          cp target/release/<bin-name>* binaries/<platform>-<arch>/
          git add binaries/
          if git diff --cached --quiet; then
            echo "binary unchanged"
          else
            git commit -m "chore(binary): update <bin-name>"
            git push
          fi

      - uses: actions/upload-artifact@v4
        with: { name: <artifact-name>, path: target/release/<bin-name>*, if-no-files-found: error }
```

tag 触发时追加一个 `release` job（`needs: build` + `if: startsWith(github.ref, 'refs/tags/v')`）：`actions/download-artifact@v4` 拉产物 → 统一改名带平台前缀（Release 资产是扁平的，多平台产物同名会互相覆盖，最终只剩最后一个）→ 重算 SHA256 → `softprops/action-gh-release@v2` 上传并写明各资产对应的平台。

### 4. workflow：publish（workflow_run 触发）

```yaml
name: Publish to npm
on:
  workflow_run:
    workflows: [build]
    types: [completed]
    branches: [main]

permissions:
  contents: write     # 打 tag
  id-token: write     # npm --provenance 的 OIDC 签名

jobs:
  publish:
    if: >-
      github.event.workflow_run.conclusion == 'success' &&
      github.event.workflow_run.head_branch == 'main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          # 必须显式 checkout 触发 run 的 sha——workflow_run 默认 checkout 的
          # 是当前 main HEAD，可能已经跑到触发 commit 之后
          ref: ${{ github.event.workflow_run.head_sha }}
      - uses: actions/setup-node@v4
        with: { node-version: '20', registry-url: 'https://registry.npmjs.org' }

      # 幂等两层（同 A03）：tag 已存在跳过；npm 已有该版本跳过
      - name: Get version
        run: |
          VERSION=$(node -p "require('./package.json').version")
          echo "version=$VERSION" >> $GITHUB_OUTPUT
          echo "tag=v$VERSION" >> $GITHUB_OUTPUT
      - name: Check tag / create
        # ... git rev-parse 探测，不存在则创建推送（同 A03）
      - name: Check npm version
        id: npm_check
        run: |
          if npm view "$(node -p "require('./package.json').name")@${{ steps.version.outputs.version }}" version >/dev/null 2>&1; then
            echo "published=true" >> $GITHUB_OUTPUT
          else
            echo "published=false" >> $GITHUB_OUTPUT
          fi
      - name: Publish
        if: steps.npm_check.outputs.published == 'false'
        run: npm publish --provenance --access public
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

---

## 为什么这样设计（核心判据）

### 1. 构建与发布必须顺序化，禁止并行

push 同时触发 build 和 publish 时，publish 读到的是**仓库里的旧二进制**——新二进制要等 build 跑完 commit 才存在。用 `workflow_run` 把 publish 挂在 build 完成之后，链路变成「编译 → 提交二进制 → 发布」，npm 上的包永远含最新二进制。

### 2. 二进制走 git 提交，不走 artifact 传递

跨 workflow 下载 artifact 需要 `run-id` + 对应权限，且 workflow_run 上下文默认查的是**自己的** run，漏传 `run-id` 就报 `Artifact not found`（高频坑）。二进制 commit 回仓库后，publish 侧普通 checkout 就能拿到——链路里少一个易碎环节。附带收益：`binaries/` 里永远有可运行的版本，源码 install 也能用。

### 3. CI 的 GITHUB_TOKEN 推送不触发下游 workflow

GitHub 为防递归，用默认 GITHUB_TOKEN push 不会触发任何 `on: push` workflow。所以「build 提交二进制 → publish 被自动带起」这条路天然不通，**必须**用 `workflow_run` 显式衔接。这不是缺陷，是设计依据。

### 4. 冒烟必须覆盖 JS resolver

二进制 `--help` 通过 ≠ 用户 `npx` 能跑。JS 侧的路径解析（fallback 链、`.exe` 后缀、平台 key 拼接）是独立的出错面，CI 里用环境变量指向刚编译的产物跑一遍才算闭环。

---

## 包名审查：发布前先探测

npm 对新包名有**相似度审查**：与现有知名包（规范化后）编辑距离过近直接 403，报错形如 `Package name too similar to existing package <x>`。这是抢注防护，无申诉快速通道。

**探测 SOP**（一次临时发布实测，唯一可靠办法）：

```bash
mkdir probe && cd probe
echo '{"name":"<candidate>","version":"0.0.1-probe","description":"probe","license":"MIT"}' > package.json
npm publish --registry https://registry.npmjs.org/ --access public
# 403 too similar → 换名
# + <candidate>@0.0.1-probe → 名字可用，立即撤回：
npm unpublish <candidate>@0.0.1-probe --force --registry https://registry.npmjs.org/
```

经验判据：

- 短名（4-5 字符）与知名包一两个字符之差几乎必被拦（如与 `rsvp`/`csso`/`svgo` 同族的四字母组合）
- 带连字符分散、或含义独特的名字通过率高
- scope 包（`@scope/name`）不受全局相似度审查约束，但子包名内那段仍受
- 撤回后 registry 可能残留 `0.0.0-stage` 占位版本（staged publishing 机制）——无害，`dist-tags.latest` 指向真实版本即可；占位符有时 unpublish 报成功也不消失，不必纠缠

---

## 错误案例

| 错误操作                                               | 实际后果                                                  | 正确做法                                                                  |
| ------------------------------------------------------ | --------------------------------------------------------- | ------------------------------------------------------------------------- |
| push 同时触发 build 和 publish                         | npm 上发出去的是仓库里的旧二进制                          | workflow_run 顺序化：publish 挂在 build 完成后                            |
| publish 侧用默认 checkout                              | 拿到的是 main HEAD，可能不含刚提交的二进制                | `ref: ${{ github.event.workflow_run.head_sha }}`                        |
| 跨 workflow 下载 artifact 不传 `run-id`              | `Artifact not found`（默认查自己的 run）                | 要么补 `run-id: ${{ github.event.workflow_run.id }}`，要么改走 git 提交 |
| 二进制 `--help` 冒烟通过就发布                       | 用户端 `npx` 因路径解析错误跑不起来                     | 补 JS resolver 冒烟层                                                     |
| `package.json` 漏 `os`/`cpu`                     | 不支持平台装上了，运行时报神秘错                          | 显式声明，让 npm 安装期就拒绝                                             |
| 漏 `repository.url`                                  | `--provenance` 报 EUSAGE                                | 补 repository 字段（同 A03）                                              |
| Cargo 与 npm 版本号分头改                              | 二进制 `--version` 与包版本对不上，排查浪费时间         | 两条线同步 bump；或 CI 加一致性校验                                       |
| CI 里 `cargo build` 不带 `--locked`                | Cargo.lock 未提交时 CI 随机解析新依赖，构建不可复现       | 提交 Cargo.lock + `--locked`                                            |
| publish 步骤只给 `NODE_AUTH_TOKEN` 但没跑 setup-node | ENEEDAUTH（该变量靠 setup-node 生成的 .npmrc 引用才生效） | setup-node + `registry-url`，或直接用 `NPM_TOKEN`                     |

---

## 验证清单（第一次上线必跑）

1. `npx --yes <pkg>@<version> --version` 在**目标平台**真实跑通（这是最终验收，其余都是辅助）
2. `npm pack --dry-run` 确认二进制在 tarball 里、包体积可接受
3. 在不支持平台上 `npm i` 应被拒绝且报错清晰
4. npmjs.com 版本页有 Provenance 徽章
5. 改一行 Rust 代码 push，观察完整链路：build 绿 → 二进制 commit 回来 → publish 绿 → npm 上新版本
6. 再 push 一次（版本没变）：publish 应幂等跳过

## 与其它 ref 的关系

- [[A03-npm-publish]]——publish workflow 的幂等/签名/secret 细节以它为准，本 ref 只讲二进制层怎么叠上去
- [[B02-gh-setup]]——`NPM_TOKEN` 与仓库/secret 的配置 SOP

## 版本

- 1.0.0（2026-10-13）—— 首版，从 Windows 音频录制 CLI 的实战发行链路抽象（单包形态 + workflow_run 顺序化 + 包名探测 SOP）
