# A06 · 发版：GitHub Actions + Trusted Publishing（零 token）

> 归属主文档 [[server-cli-web-scaffold]]。读它当你要**首次建包发布 / 配发布流水线 / 发版排错**时。
>
> 目标：push 到 main 就自动发版，**不依赖开发者本机环境、不持有任何长期令牌**。
> 配好之后，发版 = 改 `package.json` 的 version + push。

## 零、先懂 npm 的三条发布通道（2026 政策现状）

npm 已限制「绕过 2FA 的令牌」做直接发布（典型报错 `E_STAGE_REQUIRED`），
老的 Automation Token 直发路线正在退场。现在实际只剩三条通道：

| 通道 | 机制 | 适用 | 结论 |
| --- | --- | --- | --- |
| **Trusted Publishing（OIDC）** | CI 用 GitHub OIDC 换发布权，零令牌 | 包**已存在**且已配信任关系 | **首选**：全自动、无秘密、provenance 自动签名 |
| 粒度令牌 + staged | 令牌只能把版本传到暂存区，人工 2FA 批准后上线 | 有令牌但 npm 限制直发 | 兜底；发版会变成「批一次才发一次」 |
| 本地登录直发 | 本机 `npm login`（2FA）后 `npm publish` | 人 | **仅用于首次建包与应急** |

**鸡生蛋问题**：Trusted Publisher 只能给「已存在的包」配置 →
**新包首发必须走一次本地登录**（下面的 bootstrap），之后全部版本交给 CI。

## 一、首次建包 SOP（本地登录 bootstrap，一次性）

### Step 1 · 确保远端仓库存在（不存在就建，默认公开）

```bash
gh auth status
```

失败就停下，让用户自己跑（**登录是交互式的，不要代为执行**）：

```
需要先安装并登录 GitHub CLI：
  gh auth login
完成后告诉我，我继续配置发布流水线。
```

登录正常后看一眼是否已关联远端：

```bash
git remote -v
gh repo view --json nameWithOwner,visibility,url    # 已在仓库目录里才有输出
```

没有远端就直接建（一条命令搞定关联与首次推送）：

```bash
gh repo create <包名> --public --source=. --remote=origin --push
```

| 参数 | 作用 |
| --- | --- |
| `--public` | **本骨架的默认**——这类工具的价值在于被复用，公开才能被 `npx` 到 |
| `--source=.` | 用当前目录作为仓库内容 |
| `--remote=origin` | 自动加好远端 |
| `--push` | 顺手推上去 |

**执行前先告知用户**：创建的是**公开**仓库。已有仓库改可见性要
`gh repo edit ... --accept-visibility-change-consequences`，**必须先问**。

拿到 `nameWithOwner` 写进 `package.json`（repository / homepage / bugs 三件套）。

### Step 2 · 确认包名可用

```bash
npm view <包名> version    # 有输出说明已被占用
```

被占用就让用户改名（或复用同名——旧包的历史版本会留在 npm 上，新项目从更高
版本号起发，例：旧线 0.1.x → 新项目直接 0.2.0 起）。

### Step 3 · 本地登录（交互式，agent 不要代跑）

```bash
npx npm@latest login     # npm 12：浏览器/OTP 流程
npx npm@latest whoami    # 确认登录身份
```

> Node 低于 22.22.2 时 npm 12 会打一行版本警告——**仅警告、不影响使用**；
> 干净起见用 Node ≥ 22.22.2 或 24。

### Step 4 · 首次发布

```bash
npm publish --access public          # 会要 OTP
```

若账号/组织策略**只允许暂存发布**（报 `E_STAGE_REQUIRED`）：

```bash
npx npm@latest stage publish --access public
npx npm@latest stage list              # 拿 stage-id
npx npm@latest stage approve <stage-id>   # 或网页 Staged 页点 Approve；reject 同理
```

### Step 5 · 验证并记档

```bash
npm view <包名> version      # 与 package.json 一致
git tag v<版本> && git push origin v<版本>   # 可选：首发也打 tag
```

## 二、npm 侧配置 GitHub Actions 信任关系（一次性，2FA）

**首选 CLI**（npm ≥ 12，需已登录）：

```bash
npx npm@latest trust github <包名> \
  --file npm-publish.yml \
  --repo <owner>/<repo> \
  --allow-publish -y
```

| 参数 | 说明 |
| --- | --- |
| `--file` | 工作流文件名，**必须与 `.github/workflows/` 下的名字一字不差**；改名后要重配（不匹配的失败表现只是 `ENEEDAUTH`，极难排查，见第六节） |
| `--repo` | `owner/repo` |
| `--allow-publish` | 允许**直接发布**（另有 `--allow-stage-publish` 对应暂存通道） |
| `--dry-run` | 预览不落盘 |

- 查看已配：`npm trust list <包名>`；撤销：`npm trust revoke <包名> --id=<id>`
- **网页备选**：npmjs.com → 包页 → Settings → Trusted Publisher → GitHub Actions，
  四项照抄 CLI 的语义（Organization / Repository / Workflow filename / Environment 留空）。
  **登录与 2FA 是交互式的——agent 不要代跑，把命令/路径给用户让他自己执行。**

## 三、工作流文件（Trusted Publishing 版）

`.github/workflows/npm-publish.yml`（文件名与 `npm trust` 的 `--file` 一致）：

```yaml
name: Publish to npm

on:
  push:
    branches: [main]

permissions:
  contents: write   # 打 tag 需要
  id-token: write   # Trusted Publishing / provenance 签名需要（OIDC）

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0                    # 必须 0：tag 检测要完整历史
          token: ${{ secrets.GITHUB_TOKEN }}

      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '24'                # npm@latest 要求 ≥22.22.2，不要用 20
          cache: 'pnpm'
          # 不要写 registry-url：它生成的 .npmrc 可能干扰 OIDC 通道

      - run: pnpm install --frozen-lockfile
      - run: pnpm run build
      - run: pnpm test                       # 发版前必须全绿

      - name: 读版本号
        id: pkg
        run: |
          echo "name=$(node -p "require('./package.json').name")" >> $GITHUB_OUTPUT
          echo "version=$(node -p "require('./package.json').version")" >> $GITHUB_OUTPUT
          echo "tag=v$(node -p "require('./package.json').version")" >> $GITHUB_OUTPUT

      - name: 已存在则跳过（幂等）
        id: check
        run: |
          if git rev-parse "${{ steps.pkg.outputs.tag }}" >/dev/null 2>&1; then
            echo "tag_exists=true" >> $GITHUB_OUTPUT
          else
            echo "tag_exists=false" >> $GITHUB_OUTPUT
          fi
          if npm view ${{ steps.pkg.outputs.name }}@${{ steps.pkg.outputs.version }} version >/dev/null 2>&1; then
            echo "published=true" >> $GITHUB_OUTPUT
          else
            echo "published=false" >> $GITHUB_OUTPUT
          fi

      - name: 打 tag
        if: steps.check.outputs.tag_exists == 'false'
        run: |
          git config user.name  "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git tag -a "${{ steps.pkg.outputs.tag }}" -m "Release ${{ steps.pkg.outputs.tag }}"
          git push origin "${{ steps.pkg.outputs.tag }}"

      - name: 升级 npm（Trusted Publishing 需 npm ≥ 11.5.1）
        run: npm install -g npm@latest

      - name: OIDC 预检（发布失败时先看这里）
        run: |
          echo "npm 版本: $(npm --version)"
          if [ -z "$ACTIONS_ID_TOKEN_REQUEST_URL" ]; then
            echo "::error::OIDC 环境缺失（检查 permissions: id-token: write）"
          else
            echo "OIDC 环境: 已注入"
            LEN=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=npm:registry.npmjs.org" | wc -c)
            if [ "$LEN" -gt 50 ]; then echo "ID token 获取: 成功"; else echo "::error::ID token 获取失败"; fi
          fi

      - name: 发布（OIDC，零 token）
        if: steps.check.outputs.published == 'false'
        run: npm publish --provenance --access public
```

### 三条关键设计

1. **幂等**：tag 已存在、或该版本已发布，都跳过而不是报错。
   否则重复 push（rebase、重跑工作流）会失败，用户被迫手工处理。
2. **`fetch-depth: 0`**：浅克隆下 `git rev-parse <tag>` 查不到历史 tag，会重复打 tag。
3. **OIDC 预检步骤**：发布失败时，日志能一眼分清是「GitHub 侧链路」还是
   「npm 侧信任关系」问题——没有它只有一句 `ENEEDAUTH`，两头猜。

### 三个「不要」（都会静默破坏 OIDC 通道）

| 不要 | 后果 |
| --- | --- |
| 在发布步骤注入 `NODE_AUTH_TOKEN` | 走回令牌通道：轻则 401，重则 `E_STAGE_REQUIRED` |
| 让 `setup-node` 带 `registry-url` | 残留 `.npmrc` 干扰 OIDC（无令牌时显式报错） |
| 用 Node < 22.22.2 跑 `npm@latest` | `EBADENGINE` 直接装不上（CI 直接锁 24） |

### pnpm 版本要锁死

`package.json` 里写 `packageManager`，工作流不要再指定 version
（`pnpm/action-setup@v4` 自动读它）。另注意较新 pnpm 的 `ERR_PNPM_IGNORED_BUILDS`：
本地先跑通 `pnpm install && pnpm test` 再 push，第一次发版不带病。

## 四、push 之后：用 gh 盯住流水线

**发布不是 push 完就结束。** 流水线跑在远端，本地不盯就不知道结果——
而 npm 上的坏版本撤不回来（只能 `npm deprecate`）。

```bash
# 取刚触发的那一次 run（按 workflow 文件名过滤，避免抓到别的 run）
RUN=$(gh run list --workflow=npm-publish.yml --limit 1 \
        --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status          # 非 0 退出即失败，可当脚本判据
gh run view "$RUN" --log-failed            # 失败时只看失败步骤，不翻全文
```

### 全部跑通后确认三件事

```bash
gh run list --limit 1                  # 最近一次是成功
npm view <包名> version                 # npm 上确实有新版本
git ls-remote --tags origin | grep "v<版本>"   # tag 已推
```

### 可选：给 tag 建 GitHub Release

```bash
TAG="v$(node -p "require('./package.json').version")"
gh release create "$TAG" --title "$TAG" --generate-notes
```

## 五、日常发版流程（配好之后）

```bash
# 1. 改 package.json 的 version（tag 交给 CI 打）
# 2. 更新 CHANGELOG
# 3. push
git push
# 4. 盯住流水线
RUN=$(gh run list --workflow=npm-publish.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

**提醒用户**：这个流水线是 **push 到 main 即发布**。改 version 就等于「准备发版」。

## 六、排错对照表（本家族实操沉淀）

| 日志关键词 | 根因 | 处理 |
| --- | --- | --- |
| 发布步骤 `ENEEDAUTH`（OIDC 预检通过） | npm 侧没配信任关系；或 `--file`/`--repo` 与仓库实际不一致（**表现一样，极难分辨**） | `npm trust list <包名>` 核对；重新 `npm trust github ...`；配完 `gh run rerun <run-id> --failed` |
| `E_STAGE_REQUIRED`（403） | 用「只能暂存」的令牌跑直发 | 首选改走 Trusted Publishing；否则 `npm stage publish` + `stage approve <stage-id>` |
| `EBADENGINE`（装 npm@latest 时） | Node < 22.22.2 | CI/本地升到 Node 24 |
| `404 No match found for version` | 版本根本没发出去（staged 未批 / 发布步骤失败） | `npm stage list` 看暂存；`npm view` 确认；处理或重发 |
| 暂存里挂着旧版本 | 只 stage 没批 | `npm stage list` → `approve/reject <stage-id>`；不处理最终会过期 |
| `pnpm install` 非 0 | `ERR_PNPM_IGNORED_BUILDS` | 按「pnpm 版本要锁死」处理 |
| 日志显示「跳过」 | 幂等分支生效（tag/版本已存在），**不是失败** | 要重发必须改 version |
| force push 覆盖历史后旧 tag 还在 | `push --force` 不动 tag；旧 tag 指向被覆盖的提交 | 需要清理用 `gh api -X DELETE repos/<o>/<r>/git/refs/tags/<t>`；覆盖前可先把旧头存成**本地** tag 存档 |

## 七、CHANGELOG 约定

用 [Keep a Changelog](https://keepachangelog.com/) 的分类，中文正文即可：

```markdown
## [0.6.0] - 2026-09-16

### Added
### Changed
### Fixed
### Removed
```

对**破坏性变更**要单独说清楚并给迁移方式（CLI 命令名变化 / `--json` 形状变化 /
HTTP 路径变化）——这些是 agent 与脚本直接依赖的契约。

## 八、踩过的坑

| 坑 | 后果 | 正确做法 |
| --- | --- | --- |
| 沿用「gh secret set NPM_TOKEN + `npm publish` 直发」旧方案 | npm 政策变更后直接 403 `E_STAGE_REQUIRED`，发版卡死 | 新项目一律 Trusted Publishing；令牌只留在 bootstrap/应急 |
| 把「staged + 人工批准」当终点 | 每次发版都要人点，失去 CI 自动化意义（用户会明确否决） | 信任关系配好后走 OIDC 直发，全自动 |
| 没意识到「信任关系只能配已存在的包」 | 新包配 `npm trust` 报包不存在，卡在鸡生蛋 | 首发走本地登录 bootstrap（第一节） |
| CI 用 Node 20 + `npm@latest` | npm 12 `EBADENGINE`，流水线红 | CI 锁 Node 24 |
| 发布步骤仍注入 `NODE_AUTH_TOKEN` | 覆盖 OIDC 通道，报的却是旧的令牌类错误 | Trusted Publishing 版工作流：不注入 token、不带 registry-url |
| 没有 OIDC 预检步骤 | 失败只剩 `ENEEDAUTH`，分不清 GitHub 侧还是 npm 侧 | 保留预检步骤（环境注入 + token 获取），失败先看它 |
| `--file` 与 workflow 文件名不一致 | 报错与「没配」完全相同（`ENEEDAUTH`），排查半天 | 改名时同步 `npm trust revoke` + 重配；预检通过仍 ENEEDAUTH 先查这个 |
| 一上来就问用户要 token | 用户被迫回答本可自动探测的问题 | 先探测；Trusted Publishing 方案下**根本不需要令牌** |
| 工作流不幂等 | 重跑必失败，被迫手工干预 | tag 存在 / 版本已发布 → 跳过 |
| `fetch-depth` 用默认（1） | 查不到历史 tag，重复打 tag 报错 | 显式 `fetch-depth: 0` |
| 发版前不跑测试 | 坏版本进了 npm，且不可撤销 | workflow 里 `pnpm test` 是前置步骤 |
| 忘记 `assets/` 在 `files` 里 | 内置 skill 没进包，`skill install` 找不到 | `package.json` 的 `files` 必须含 `assets/` |
| 没锁 pnpm 版本 | 本地能过、CI 因版本差异失败 | `packageManager` 锁死 |
| **push 完就不管流水线** | 坏版本进了 npm，撤不回来 | `gh run watch "$RUN" --exit-status` |
| 用 `gh run watch` 不带 run id | 可能盯到别的 run | 先 `gh run list --workflow=<file> --json databaseId` 取准 |
| force push 覆盖远端后当没事 | 旧 tag 悬空、旧产物仍指向被覆盖的提交 | 覆盖前把旧 head 存**本地** tag（`archive/*`）；远端旧 tag 按需清理 |
