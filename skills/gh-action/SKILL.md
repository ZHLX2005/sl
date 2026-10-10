---
name: gh-action
description: Use when a GitHub Actions CI/CD workflow needs to be authored, debugged, monitored, or extended — covers battle-tested deploy templates (GHCR push + SSH deploy; self-contained docker save + SCP + docker load; Flutter Web → nginx on 82端口), the npm auto-publish pattern (`fuck-npm.yml`, push to main + provenance), an Android release-signing CI template, a build-monitoring SOP (Monitor until success/failure, 三铁律, 失败分类重试), a debug workflow template for reproducing failures inside the Actions environment, a gh CLI troubleshooting runbook, gh repo/secret setup SOP, and a fork squash-release PR SOP. Triggers: "GitHub Actions 失败 / 卡住 / 401", "监控流水线 / monitor CI build / gh 监控 / 看下 CI 状态 / 构建为什么挂了 / CI 失败了看看", "debug CI / 容器在 CI 里起不来 / 要 Actions 环境的日志", "deploy.yml / 发布到 GHCR / SSH 部署", "publish to npm / npm publishing / fuck-npm.yml", "GitHub Actions 写工作流", "服务器到 GHCR 网络慢 / 不依赖 registry / docker save + scp", "APK 签名 SHA 每次变 / 指纹漂移 / 覆盖安装失败 / INSTALL_FAILED_UPDATE_INCOMPATIBLE / CI 里配 keystore / release 签名", "Flutter web 部署 / flutter build web docker / nginx 部署 flutter / gh secret set SSH_KEY / deploy web 到服务器端口", "压缩领先 commit 再发版 / squash 后推到 upstream 然后 PR / open PR against upstream / fork 发版".
---

# gh-action

GitHub Actions CI/CD 通用 skill 仓库。**主页面仅做 ref 映射**,详细内容按需加载。

## 序列总览（先读这里）

| 代号 | 类别 | 成员 |
|---|---|---|
| **A** | 具体语言/场景的 workflow 模板 | A01 GHCR 部署 / A02 无 registry 部署 / A03 npm 发布 / A04 Android 签名 / A05 Flutter Web 部署 |
| **B** | 通用 gh CLI 操作（不绑定语言场景，主动调 gh 查信息/排障/配置/发版） | B01 gh-troubleshoot / B02 gh-setup / B04 upstream-release |
| **C** | CI 监控与远程调试（观测在跑的构建、失败后进 Actions 环境复现；C01→C02 是同一条链的两段） | C01 monitor-build / C02 debug-workflow |

| ref | 标题 | 简介 | 相对路径 |
|---|---|---|---|
| A01 | deploy-template | deploy.yml 通用模板(本地构建 → GHCR 推送 → SSH 部署)。含 4 个 GHCR 认证坑 + 慢网络 fallback 写法。 | [[references/A01-deploy-template]] |
| B01 | gh-troubleshoot | CI 失败时 gh CLI 排障命令:抓 raw log、卡住 run 取消、GHCR 401 诊断、服务器侧检查、一键诊断脚本。 | [[references/B01-gh-troubleshoot]] |
| B02 | gh-setup | **主动配置 SOP**:gh 建仓库(默认公开、执行前告知)、`gh secret set` 直接设 secret(SSH_KEY 走 stdin+LF 校验、NPM_TOKEN Automation 类型)、PAT 主动使用与防泄露三规矩、主动用 gh 查仓库/run/release 信息。A 序列模板都默认环境已配好,配环境走这个。 | [[references/B02-gh-setup]] |
| A03 | npm-publish | `fuck-npm.yml` 通用模板(push to main → 自动打 tag + npm publish --provenance)。含 NPM_TOKEN 自动化配置、幂等性两层检查、`--provenance` 公开仓库自动签名。**信仰命名**:npm 发布太折磨,所有 npm 自动发布工作流一律叫 `fuck-npm.yml`,后续工作流沿用。 | [[references/A03-npm-publish]] |
| A02 | deploy-template-no-registry | 自包含部署模板(本地构建 → `docker save` → SCP → 服务器 `docker load`)。**不依赖 GHCR / 任何 registry**,适合服务器到 GHCR 网络慢/不通、单服务部署。末尾贴 `ve` 项目实战案例与 6 处差异。 | [[references/A02-deploy-template-no-registry]] |
| A04 | android-signing-ci | CI 里的 Android release 签名干净模板(keystore 生成 → base64 灌 secret → 重建 → 构建 → 验签)。专治 **APK 签名 SHA 每次构建漂移 / 覆盖安装失败**:两层根因是 secret 没配 + keystore 步骤排在 build 之后。 | [[references/A04-android-signing-ci]] |
| A05 | flutter-web-docker-deploy | Flutter Web → nginx 镜像全自动部署:`flutter build web` 产物拷进 `web_deploy/` context → save/scp/load → 服务器 82 端口。含 gh CLI 一条龙设 4 个 secret(SSH_KEY 走临时文件+LF 校验)、端到端自测 SOP、8 个实战坑。 | [[references/A05-flutter-web-docker-deploy]] |
| B04 | upstream-release | Fork squash 发版 SOP:领先 commit soft reset 压缩 → `push --force-with-lease` → `gh pr create` → `--squash --delete-branch` → pr view 总结。base 自动探测(main/master)、两层失败诊断表、`--web` 兜底。原 `gh-upstream-release` skill 并入。 | [[references/B04-upstream-release]] |
| C01 | monitor-build | 构建监控 SOP:Monitor 持续监控直到成功/失败,三铁律(验证优于假设 / Monitor 是用户特权 / 状态以 gh run view 为准),失败分类重试,上传超时实测判据实战案例。原 `gh-ci` skill 并入。 | [[references/C01-monitor-build]] |
| C02 | debug-workflow | Actions 环境远程复现诊断:debug workflow 模板(workflow_dispatch + docker compose up 带 timeout-minutes),触发监控、拉环境日志。本地无法复现/容器在 CI 起不来时用。原 `gh-ci` skill 并入。 | [[references/C02-debug-workflow]] |

## 选 ref 速查

- **多服务 + 网络好 + 想用 GHCR 缓存** → A01 `deploy-template`
- **单服务 + 网络差/不想管 registry token** → A02 `deploy-template-no-registry`
- **Flutter web 部署到自建服务器 / flutter build web + nginx docker** → A05 `flutter-web-docker-deploy`
- **写 npm 包发布** → A03 `npm-publish`
- **CI 里出 Android APK / 签名指纹漂移 / 装不上要卸载** → A04 `android-signing-ci`
- **CI 跑挂了 / 卡住 / 要用 gh CLI 查 run、log、release 等 GitHub 侧信息** → B01 `gh-troubleshoot`
- **仓库还没建 / secret 还没配 / token 要设进 CI / 提高积极性主动配环境** → B02 `gh-setup`
- **监控流水线 / 看下 CI 状态 / monitor CI build / 构建成功没** → C01 `monitor-build`
- **debug CI / 容器在 CI 里起不来 / 要 Actions 环境日志**（监控发现失败后要深挖复现） → C02 `debug-workflow`
- **fork squash 领先 commit 发版 / 推 upstream 开 PR** → B04 `upstream-release`

## 续号规则

- 新的语言/场景模板 → A 序列，A06 起递增
- 新的通用 gh CLI 操作（查信息、仓库管理、发版操作等，不绑定具体语言） → B 序列，B05 起递增
- 新的监控/调试类动作 → C 序列，C03 起递增