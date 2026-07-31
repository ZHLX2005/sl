---
name: gh-action
description: Use when GitHub Actions CI/CD deploy workflow fails or needs to be authored — covers a battle-tested deploy.yml template (Docker build + GHCR push + SSH deploy) and a gh CLI troubleshooting runbook for diagnosing stuck/failed runs, capturing logs via the GitHub API, and inspecting server-side Docker state.
---

# gh-action

GitHub Actions CI/CD 通用 skill 仓库。**主页面仅做 ref 映射**,详细内容按需加载。

| ref | 标题 | 简介 | 相对路径 |
|---|---|---|---|
| ref1 | deploy-template | deploy.yml 通用模板(本地构建 → GHCR 推送 → SSH 部署)。含 4 个 GHCR 认证坑 + 慢网络 fallback 写法。 | [[references/deploy-template]] |
| ref2 | gh-troubleshoot | CI 失败时 gh CLI 排障命令:抓 raw log、卡住 run 取消、GHCR 401 诊断、服务器侧检查、一键诊断脚本。 | [[references/gh-troubleshoot]] |
