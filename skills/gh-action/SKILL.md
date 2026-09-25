---
name: gh-action
description: Use when a GitHub Actions CI/CD workflow needs to be authored, debugged, or extended — covers a battle-tested deploy.yml template (Docker build + GHCR push + SSH deploy), a self-contained deploy.yml template (Docker save + SCP + docker load, no registry dependency), a gh CLI troubleshooting runbook for diagnosing stuck/failed runs, the standard npm-publish.yml pattern for pushing npm packages to the registry on `push to main`, an Android release-signing template for CI (keystore → base64 secret → key.properties → verify) that fixes APK signature SHA drift, and a Flutter Web → nginx docker deploy template (flutter build web → web_deploy/ context → save/scp/load → 82端口) with gh secret setup and end-to-end self-test SOP. Triggers: "GitHub Actions 失败 / 卡住 / 401", "deploy.yml / 发布到 GHCR / SSH 部署", "publish to npm / npm publishing / npm-publish.yml", "GitHub Actions 写工作流", "服务器到 GHCR 网络慢 / 不依赖 registry / docker save + scp", "APK 签名 SHA 每次变 / 指纹漂移 / 覆盖安装失败 / INSTALL_FAILED_UPDATE_INCOMPATIBLE / CI 里配 keystore / release 签名", "Flutter web 部署 / flutter build web docker / nginx 部署 flutter / gh secret set SSH_KEY / deploy web 到服务器端口".
---

# gh-action

GitHub Actions CI/CD 通用 skill 仓库。**主页面仅做 ref 映射**,详细内容按需加载。

| ref | 标题 | 简介 | 相对路径 |
|---|---|---|---|
| ref1 | deploy-template | deploy.yml 通用模板(本地构建 → GHCR 推送 → SSH 部署)。含 4 个 GHCR 认证坑 + 慢网络 fallback 写法。 | [[references/deploy-template]] |
| ref2 | gh-troubleshoot | CI 失败时 gh CLI 排障命令:抓 raw log、卡住 run 取消、GHCR 401 诊断、服务器侧检查、一键诊断脚本。 | [[references/gh-troubleshoot]] |
| ref3 | npm-publish | `fuck-npm.yml` 通用模板(push to main → 自动打 tag + npm publish --provenance)。含 NPM_TOKEN 自动化配置、幂等性两层检查、`--provenance` 公开仓库自动签名。**信仰命名**:npm 发布太折磨,所有 npm 自动发布工作流一律叫 `fuck-npm.yml`,后续工作流沿用。 | [[references/npm-publish]] |
| ref4 | deploy-template-no-registry | 自包含部署模板(本地构建 → `docker save` → SCP → 服务器 `docker load`)。**不依赖 GHCR / 任何 registry**,适合服务器到 GHCR 网络慢/不通、单服务部署。末尾贴 `ve` 项目实战案例与 6 处差异。 | [[references/deploy-template-no-registry]] |
| ref5 | android-signing-ci | CI 里的 Android release 签名干净模板(keystore 生成 → base64 灌 secret → 重建 → 构建 → 验签)。专治 **APK 签名 SHA 每次构建漂移 / 覆盖安装失败**:两层根因是 secret 没配 + keystore 步骤排在 build 之后。 | [[references/android-signing-ci]] |
| ref6 | flutter-web-docker-deploy | Flutter Web → nginx 镜像全自动部署:`flutter build web` 产物拷进 `web_deploy/` context → save/scp/load → 服务器 82 端口。含 gh CLI 一条龙设 4 个 secret(SSH_KEY 走临时文件+LF 校验)、端到端自测 SOP、8 个实战坑。 | [[references/flutter-web-docker-deploy]] |

## 选 ref 速查

- **多服务 + 网络好 + 想用 GHCR 缓存** → ref1 `deploy-template`
- **单服务 + 网络差/不想管 registry token** → ref4 `deploy-template-no-registry`
- **Flutter web 部署到自建服务器 / flutter build web + nginx docker** → ref6 `flutter-web-docker-deploy`
- **写 npm 包发布** → ref3 `npm-publish`
- **CI 里出 Android APK / 签名指纹漂移 / 装不上要卸载** → ref5 `android-signing-ci`
- **CI 跑挂了 / 卡住** → ref2 `gh-troubleshoot`