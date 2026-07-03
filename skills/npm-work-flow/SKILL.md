---
name: npm-work-flow
description: Use when the user asks to "publish to npm", "automate npm release", "set up npm publishing CI/CD", "GitHub Actions for npm", "publish package on push", or wants to wire up a GitHub Actions workflow that publishes an npm package. Covers the standard push-to-main pattern (tag + idempotency check + npm publish --provenance), required secrets, prerequisites, and verification steps. Mirrors the proven nx-sx pattern.
version: 1.0.0
---

# npm 发布工作流（GitHub Actions 标准模式）

本 skill 把"GitHub Actions 自动发布 npm 包"沉淀成可复用模板。一次配置，长期生效。

## 适用场景

- 你有一个 npm 包（TypeScript / JavaScript），想实现"push 到 main → 自动发布到 npmjs"
- 你希望发布过程可追溯、自动打 git tag、对历史版本重放安全
- 你不想每次手动 `npm version` + `npm publish`

## 不适用场景

- 仅需要 PR/CI 校验（不发布）—— 用 `ci` 工作流，不要 publish
- 私有/自建 registry —— 需要改 `registry-url` 和 secret
- Monorepo 多个包 —— 需要 `paths` 过滤和 per-package 工作流

---

## 标准模板：`.github/workflows/npm-publish.yml`

```yaml
name: Publish to npm

on:
  push:
    branches: [main]

permissions:
  contents: write   # 写 tag 需要；不要省

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0              # 必须 0，tag 检测需要完整历史
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          registry-url: 'https://registry.npmjs.org'

      - name: Get version
        id: version
        run: |
          VERSION=$(node -p "require('./package.json').version")
          echo "version=$VERSION" >> $GITHUB_OUTPUT
          echo "tag=v$VERSION" >> $GITHUB_OUTPUT

      - name: Check if tag exists
        id: check_tag
        run: |
          if git rev-parse "${{ steps.version.outputs.tag }}" >/dev/null 2>&1; then
            echo "exists=true" >> $GITHUB_OUTPUT
          else
            echo "exists=false" >> $GITHUB_OUTPUT
          fi

      - name: Create and push tag
        if: steps.check_tag.outputs.exists == 'false'
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git tag -a "${{ steps.version.outputs.tag }}" -m "Release ${{ steps.version.outputs.tag }}"
          git push origin "${{ steps.version.outputs.tag }}"

      - name: Check if version exists on npm
        id: npm_check
        run: |
          if npm view <YOUR_PACKAGE_NAME>@${{ steps.version.outputs.version }} version >/dev/null 2>&1; then
            echo "published=true" >> $GITHUB_OUTPUT
          else
            echo "published=false" >> $GITHUB_OUTPUT
          fi
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}

      - name: Publish to npm
        if: steps.npm_check.outputs.published == 'false'
        run: npm publish --provenance --access public
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

**重要**：把 `<YOUR_PACKAGE_NAME>` 替换成 `package.json` 里的 `name`。注意 scoped 包要带 `@scope/`（如 `@joke-lx/jc`）。

---

## 前置条件清单

### 1. 仓库侧（一次性）

| 项目 | 操作 | 位置 |
|---|---|---|
| `NPM_TOKEN` secret | 在 npmjs.com → Access Tokens → Generate New Token（Automation 类型），粘到 GitHub repo → Settings → Secrets and variables → Actions | GitHub repo |
| `GITHUB_TOKEN` | 默认就有，无需配置 | GitHub |
| `contents: write` | 工作流顶部声明，需要写 tag | 工作流内 |

### 2. `package.json` 侧

```jsonc
{
  "name": "<YOUR_PACKAGE_NAME>",      // 发布目标名，必须和 workflow 里一致
  "version": "0.1.0",                  // 每次发布前手动 bump
  "repository": {                      // --provenance 必需
    "type": "git",
    "url": "https://github.com/<owner>/<repo>.git"
  },
  "files": ["dist"],                   // 发布哪些目录
  "main": "dist/index.js",
  // ...
}
```

**`repository` 字段不能省**，否则 `--provenance` 会失败。

### 3. npm 侧（一次性）

| 项目 | 说明 |
|---|---|
| Token 类型 | **Automation**，不是 Publish。Automation 永久不过期、可绕过 2FA |
| Token 权限 | Read and publish（不要勾 Admin） |
| 组织包 | scoped 包（`@xxx/yyy`）首次发布需要组织 owner 在 npmjs.com 确认，或运行 `npm access public` |

---

## 发布一个版本的标准流程

```bash
# 1. 在本地开发，确保 working tree 干净
git status

# 2. bump 版本（自动改 package.json + 打本地 tag）
npm version patch   # 0.1.0 → 0.1.1
# 或 minor / major / 1.2.3 指定版本

# 3. 提交 + 推送
git push
git push --tags     # tag 也可以不推，CI 会自动创建

# 4. 观察 CI
# → GitHub repo → Actions → "Publish to npm" → 确认成功
```

`npm version` 的副作用：会创建本地 tag 并 commit 到 git。**CI 工作流会自己再创建一次 tag**，因为 tag 检测是幂等的（先查 git 上有没有，没有才创建）。

---

## 为什么这样设计（核心原则）

### 1. 触发器只用 `push` 到 main，不用 `workflow_dispatch`

- `workflow_dispatch` 让"发布"变成人工操作，容易忘记、容易错过
- `push` 到 main 让发布 = 推送 main，合二为一
- 配合 npm view 幂等检查，重复触发也安全

### 2. 幂等性：两层检查

| 检查 | 防什么 |
|---|---|
| `git rev-parse v$VERSION` | 防 tag 重复创建（重复 push 不会改写已有 tag） |
| `npm view <pkg>@<ver>` | 防重复发布到 npm（npm 自身拒绝，但提前跳过省一次 publish 错误） |

### 3. `--provenance` + 公开仓库

- npm `--provenance` 在 https://www.npmjs.com/package/<name> 显示 Sigstore 签名
- 公开仓库上 `setup-node@v4` 自动通过 OIDC 提供签名身份，**无需任何配置**
- 私有仓库需要 npmjs org 付费 + 额外 OIDC 配置

### 4. 不在 CI 里跑 build / test

**这个设计是有意权衡**：nx-sx 模式不跑校验步骤。理由：
- 发布频率低（每个版本一次），错误影响小
- `tsc / vitest` 在本地 PR 阶段已经跑过
- 简化工作流，减少维护成本

**如果你想加校验**（推荐生产项目）：在 `Checkout` 后、`Get version` 前插入：
```yaml
      - run: npm ci
      - run: npm run build
      - run: npm test
```
并在 build 失败时停止后续步骤（默认行为，`&&` 链式）。

### 5. 用 `package.json` 的 `name`，不硬编码

硬编码包名的坑：
- 改包名时容易忘改 workflow
- 多人维护时不同人改不同步

替代方案（更鲁棒）：
```yaml
      - name: Get package name
        id: pkgname
        run: echo "name=$(node -p "require('./package.json').name")" >> $GITHUB_OUTPUT
```
然后 `npm view ${{ steps.pkgname.outputs.name }}@${{ steps.version.outputs.version }}`。本 skill 默认硬编码以匹配 nx-sx 原版，但建议**新项目用动态方案**。

---

## 验证清单（第一次部署必跑）

1. **本地 lint**
   ```bash
   npx --yes actionlint .github/workflows/npm-publish.yml
   ```
   必须 `exit: 0`。IDE 报的 GitHub Actions 警告不一定准，actionlint 才是权威。

2. **推送后观察第一次 CI**
   - 仓库 → Actions → "Publish to npm"
   - 每个 step 的 `if:` 条件应该按预期命中
   - `Check if version exists on npm` 第一次必然输出 `published=false`
   - `Publish to npm` 成功 → 步骤显示 `published` 状态

3. **npmjs.com 确认**
   - 打开 https://www.npmjs.com/package/<your-package>
   - 应该看到刚发布的版本
   - 如果加了 `--provenance`，在版本页有 "Provenance" 徽章

4. **本地安装验证**
   ```bash
   mkdir /tmp/jc-test && cd /tmp/jc-test
   npm install -g <your-package>
   <your-bin> --help
   ```

---

## 错误案例（高频坑点）

| 错误操作 | 实际后果 | 正确做法 |
|---|---|---|
| 工作流里硬编码 `npm publish` 不带 `--provenance` | 发布没签名，npmjs 页面没有 provenance 徽章 | 始终加 `--provenance`（公开仓库无副作用） |
| `actions/checkout` 不带 `fetch-depth: 0` | tag 检测失败：`git rev-parse vX.Y.Z` 找不到 tag | 必须 `fetch-depth: 0` |
| `permissions` 没声明或声明 `read-only` | 推 tag 步骤报 403 | 顶部声明 `permissions: contents: write` |
| `package.json` 缺 `repository.url` 字段 | `--provenance` 失败，提示 "repository.url missing" | 补 `repository` 字段 |
| Token 用 "Publish" 类型而不是 "Automation" | 过期需要手动续签（Publish token 90 天），且 2FA 开启时会失败 | 用 Automation token，永久有效 |
| Scoped 包首次发布没 `npm access public` | 404 / 403 找不到包 | 首次发布前先 `npm access public` 或联系 org owner |
| CI 跑了但 `package.json` 是旧的 | 发布的版本和 main 不一致 | 在 `npm version` 之后再 `git push`，不要跳过 |
| push 工作流后 working tree 还有未提交改动 | 推 tag / publish 用的代码是上次 commit 的，新改动没生效 | 推送前 `git status` 确认 clean |

---

## 常见修改场景

### 加 build / test 校验

在 `Setup Node.js` 后插入：
```yaml
      - run: npm ci
      - run: npm run build
      - run: npm test
```
任意一步失败 → 后续 tag / publish 步骤都不会跑（默认 `&&` 行为）。

### 加 release-please 自动 changelog

把整个 publish job 替换成 `googleapis/release-please-action@v4`：
```yaml
      - uses: googleapis/release-please-action@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
```
release-please 会自动根据 Conventional Commits 生成 PR、改版本号、生成 CHANGELOG.md，然后触发你这里定义的发布。**用 release-please 时，删除本工作流的"Get version / Check tag / Create tag"步骤**，让它接管。

### 用 private registry（如 Verdaccio）

```yaml
      - uses: actions/setup-node@v4
        with:
          registry-url: 'https://npm.your-company.com'
          # 配套 secret 是 NPM_TOKEN，env var 是 NODE_AUTH_TOKEN
```
注意 token 名字可能不同（一些私有 registry 用 `AUTH_TOKEN`）。

### 跳过 `--provenance`（私有仓库）

私有仓库 `--provenance` 需要额外配置。直接去掉这个 flag：
```yaml
      - run: npm publish --access public
```

### 支持 prerelease tag（beta / rc）

在 `npm publish` 加 `--tag`：
```yaml
      - run: npm publish --provenance --access public --tag beta
```

---

## 与其它 skill 的关系

- **git-workflow** —— 提交规范、版本号语义化（semver）、Conventional Commits
- **skill-development** —— 本 skill 自身的元模板参考
- **key_board_2** —— 创建 skill 时的元流程

## 版本

- 1.0.0（2026-06-21）—— 从 `jc` 项目实战总结，模板来自 nx-sx