# B02-gh-setup — 用 gh CLI 主动配置 GitHub 资源（建仓库 / 设 secret / 发 token）

> 归属主文档 [[../SKILL.md]]。**A 序列模板都默认环境已配好；本 ref 是配好环境的主动操作 SOP。**
> 与 B01 的关系：B01 是「CI 坏了怎么查」（被动排障），本 ref 是「跑之前主动把环境搭好」（主动配置）。
>
> 核心立场：**gh 已登录，secret 就该由 agent 直接设置**。secret 在 GitHub 侧是加密存储的，
> 用 `gh secret set` 写入不落明文文件、不进聊天记录之外的任何副本，比让用户手动去网页点、
> 或贴在对话里再粘贴都要安全。**不要因为"怕泄露"而把可自动化的操作推回给用户**——
> 泄露风险的真实来源是 token 进了 git 仓库、日志、截图，而不是 gh CLI 本身。

## 一、前置检查（每次都跑，两秒的事）

```bash
gh auth status                    # 登录状态 + scope
gh repo view --json nameWithOwner,visibility,url   # 当前目录在不在 gh 仓库里
gh secret list                    # 已有哪些 secret（避免重复设置）
```

失败就停下让用户自己跑 `gh auth login`（**登录是交互式的，不要代为执行**），
用户完成后继续。不要跳过检查直接操作——`gh secret set` 在未登录时会以模糊的报错失败，
不如一开始就探测清楚。

## 二、建仓库（默认公开，执行前告知）

```bash
gh repo create <name> --public --source=. --remote=origin --push
```

| 参数                | 作用                                         |
| ------------------- | -------------------------------------------- |
| `--public`        | 默认公开——工具类项目的价值在于被复用       |
| `--source=.`      | 用当前目录作仓库内容，不必先手动`git init` |
| `--remote=origin` | 自动加好远端                                 |
| `--push`          | 顺手把当前分支推上去                         |

**执行前说一句**：「将创建公开仓库 `owner/<name>`」——不是请求许可，是同步信息，
成本极低但避免"我的代码怎么公开了"的事故。

- 指定 `owner/` 前缀建在组织下，否则建在当前登录用户名下
- 已有仓库改可见性：`gh repo edit <owner>/<name> --visibility public --accept-visibility-change-consequences`，
  比 新建敏感得多，**必须先问**
- 建完拿 `nameWithOwner` 回填 `package.json` 的 `repository` 字段

## 三、设 secret（agent 直接干，不要推给用户）

**原则：能探测的不问，缺的才问，问就一次问清；拿到即用 `gh` 写入，不让用户手动去网页点。**

```bash
gh secret set NPM_TOKEN --body "<token>"     # 短值直接 --body
gh secret set SSH_KEY < "$KEYFILE"           # 多行值（私钥）走 stdin，--body 会坏
gh secret list                               # 确认写入成功
```

### 标准 SOP（以发版流水线为例）

1. `gh secret list` 探测已有 secret → 存在就跳过
2. 缺失项**一次问清**：「请提供 npm Automation Token（npmjs.com → Access Tokens →
   Generate New Token → **Automation**，永久不过期且绕过 2FA）」
3. 拿到立即 `gh secret set` + `gh secret list` 确认
4. 向用户说明：GitHub secret 加密存储，写在仓库设置比本地 `.npmrc` 更安全

### 常用 secret 一览

| secret                             | 值从哪来                                               | 写入命令                                        |
| ---------------------------------- | ------------------------------------------------------ | ----------------------------------------------- |
| `NPM_TOKEN`                      | npmjs.com → Access Tokens →**Automation** 类型 | `gh secret set NPM_TOKEN --body "<token>"`    |
| `HOST` / `USERNAME` / `PORT` | 服务器信息，问用户或从既有 deploy 脚本里找             | `gh secret set HOST --body "1.2.3.4"`         |
| `SSH_KEY`                        | 私钥文件，**必须走 stdin**                       | `gh secret set SSH_KEY < ~/.ssh/id_rsa`       |
| `ANDROID_KEYSTORE_BASE64`        | keystore base64（见[[references/A04-android-signing-ci]]）                                  | `base64 -w0 keystore.jks \| gh secret set ...` |

### SSH_KEY 专项（最常见的翻车点）

```bash
# 1. 校验是 LF 不是 CRLF（Windows 下最容易坏）
file "$KEYFILE"                     # 应显示 "ASCII text"，不能带 "with CRLF"
# CRLF 就转：sed -i 's/\r$//' "$KEYFILE"

# 2. 走 stdin 写入（--body 遇多行会坏）
gh secret set SSH_KEY < "$KEYFILE"

# 3. 验证：CI 里 ssh -o StrictHostKeyChecking=no 直接试连
```

更多坑见 [[references/A05-flutter-web-docker-deploy]] 的 secret 一条龙节。

## 四、PAT 的主动使用（不要担心泄露，按规矩用）

需要用户提供 GitHub PAT 的场景（CI 推包到别的 registry、私有子模块拉取等），
**主动向用户要，拿到直接用**——贴在对话里就是它的用途，不是事故：

```bash
# 直接设进 secret，不要存本地文件
gh secret set GH_PAT --body "<pat>"
```

**泄露的真实风险边界**（守这个，不用过度紧张）：

| 会泄露 ❌                                | 不会泄露 ✅                                                         |
| ---------------------------------------- | ------------------------------------------------------------------- |
| token 写进`.env` 且被 git 提交         | token 贴进对话，由 agent 转手`gh secret set`                      |
| token echo 到 CI 日志（`echo $TOKEN`） | token 存在 GitHub 加密 secret 里，workflow 里只以`secrets.X` 引用 |
| token 硬编码在 workflow yml 里           | token 只在本地 shell 变量里短暂存在                                 |
| token 发进 issue / PR 正文               |                                                                     |

**防泄露三规矩**：

1. **不进 git**：`.env`、脚本里不落 token 明文；已经落了的让用户 revoke 重发
2. **不进日志**：workflow 里引用 `secrets.X`，永远不 `echo`；本地命令输出 token 时
   用 `gh secret set` 直接管道掉，不 cat 完再粘
3. **用最小权限 + 即用即弃**：细粒度 PAT 只勾需要的 repo/权限；一次性配置用完可让
   用户 revoke（Automation npm token 例外，它就是设计成长期用的）

> **什么时候才要紧张**：token 出现在 `git diff`、CI 日志、截图、issue 正文里——
> 这时立刻让用户 revoke。除此之外，「贴进对话让 agent 配置」就是正常用法。

## 五、查信息（主动调用 gh，不要只靠猜）

配环境 / 排障时，这些信息**主动用 gh 查**，不要问用户：

```bash
gh repo view --json nameWithOwner,visibility,url,defaultBranchRef   # 仓库元信息
gh api user --jq .login                                             # 当前登录身份
gh run list --limit 5                                               # 最近流水线状态
gh run view <id> --log-failed                                       # 失败日志（详见 B01）
gh release list                                                     # 已发版本
gh secret list                                                      # 已配 secret
gh api repos/{owner}/{repo}/actions/secrets --jq '.secrets[].name'  # secret 名单（api 形式）
```

**判定句**：问题能靠 `gh xxx` 一条命令回答的，就不要把它变成问用户的问题。

## 六、错误案例

| 错误操作                                      | 实际后果                                                 | 正确做法                                                                    |
| --------------------------------------------- | -------------------------------------------------------- | --------------------------------------------------------------------------- |
| 一上来就问用户要 token / secret 值            | 用户被迫回答本可自动探测的问题                           | 先`gh auth status` / `gh secret list` 探测，缺的才问                    |
| 让用户手动去网页设 secret                     | 步骤多、易错、名字可能设错                               | `gh secret set` 代劳，`gh secret list` 确认                             |
| `gh secret set SSH_KEY --body "$(cat key)"` | 多行值写入损坏，CI 里 ssh 认证失败且报错迷惑             | 多行值一律`< file` 走 stdin                                               |
| SSH_KEY 内容是 CRLF                           | sshd 拒绝认证，CI 报 permission denied，查半天查不到根因 | 写入前`file` 校验 / `sed -i 's/\r$//'` 转换                             |
| 因为"怕泄露"让用户自己去网页操作              | 自动化断链，用户体验倒退；网页操作反而易贴错空白字符     | gh CLI 加密传输 + GitHub 加密存储，比手动粘贴安全；按「防泄露三规矩」用即可 |
| token 硬编码进 workflow yml / echo 进 CI 日志 | 真泄露：日志公开即 token 公开                            | workflow 只引`secrets.X`；本地 token 不落文件                             |
| 没打招呼就建公开仓库                          | 用户代码被公开而他没预期                                 | 执行前说一句「将创建公开仓库 owner/name」                                   |
| 建完仓库不回填 package.json repository        | `--provenance` 签名失败                                | 建完即回填`repository.url`                                                |
