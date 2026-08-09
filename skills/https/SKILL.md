---
name: https
description: Use when deploying a static site with Docker + Nginx + Let's Encrypt wildcard cert (DNS-01), authoring the docker-compose/nginx config, signing certs with acme.sh, writing deploy/rollback scripts, or troubleshooting the typical pitfalls (HTTP-01 stuck behind ICP firewall, 403 on port 80, certificate chain errors, deploy leaving old chunks, nginx not picking up renewed cert). Triggers: "nginx + let's encrypt 通配符", "docker compose 部署静态站", "acme.sh DNS-01", "deploy.sh 脚本模板", "证书 403 备案拦截", "网站白屏 chunk 残留".
---

# https

Docker Compose + Nginx + Let's Encrypt 通配符证书(基于 DNS-01)通用 skill 仓库。**主页面仅做 ref 映射与流程骨架**,详细内容按需加载。

## 选 ref 速查

| ref | 标题 | 何时读取 | 相对路径 |
|---|---|---|---|
| ref1 | skeleton-config | 搭骨架 / 改域名 / 改 nginx / 改 docker-compose / 改敏感信息规范 | [[references/skeleton-config]] |
| ref2 | cert-issuance | 签发证书 / 选 DNS 插件 / 自动续期 / DNS-01 vs HTTP-01 选型 | [[references/cert-issuance]] |
| ref3 | deploy-scripts | 写 deploy.sh / 写 rollback.sh / 验收每次发版 | [[references/deploy-scripts]] |
| ref4 | pitfall-library | 出问题查 / 速查命令 / HTTP-01 vs DNS-01 决策树 / 备案合规分支 | [[references/pitfall-library]] |

## 整套 Skill 流程总览

整条链路分**一次性准备(A~D)** 和**可重复执行(E~F)**。每个 ref 承担哪段见下面映射:

```
【一次性准备】
 A. 前置勘察      系统 / DNS 托管商 / 端口可达性 / 是否可备案        → ref2 §11 决策树 + ref4 备案分支
        │
 B. 骨架搭建      目录 + docker-compose + nginx 配置              → ref1
        │              (此时先不启用 HTTPS 443,等证书到位)
        ▼
 C. 证书签发      DNS API 凭证 → acme.sh → staging → 正式 → install-cert → ref2
        │
 D. HTTPS 上线    启用 443 + 80 跳转 → nginx -t → up -d → 验收      → ref1 + ref3 验收清单
        │
【可重复执行】
        ▼
 E. 发版 CD       构建产物 → deploy.sh → 版本快照 → rsync → reload  → ref3
        │
 F. 长期运维      crontab 自动续期(含 reload 钩子)→ 排坑          → ref2 §6.4 + ref4
```

各阶段产出物与验收点:

| 阶段        | 关键动作                          | 产出物                       | 验收标准                                  |
| ----------- | --------------------------------- | ---------------------------- | ----------------------------------------- |
| **A 勘察**  | 查 OS、查 NS、查端口、查备案可行性 | 一份技术选型结论             | 明确知道用哪种 challenge 和哪个 DNS 插件 |
| **B 骨架**  | 建目录、写编排与站点配置          | 目录树 + 两个配置文件        | `docker compose config` 无报错            |
| **C 证书**  | 建 RAM/API 凭证、签发、安装       | `certs/` 下 fullchain + key  | `acme.sh --list` 有记录且到期日正确       |
| **D 上线**  | 启用 TLS、跳转、启动容器          | 可访问的 HTTPS 站点          | 外网 HTTPS 返回 200,HTTP 返回 301         |
| **E 发版**  | 执行 `deploy.sh`                  | `releases/` 版本快照         | 冒烟返回 200 且资源 hash 已更新           |
| **F 运维**  | crontab + 定期验收                | 自动续期链路                 | `--cron --force` 演练成功并触发 reload    |

## 为什么强烈推荐 DNS-01 作为默认方案

它只需服务器**出站**访问 DNS 商 API,全程不需要外网连入你的机器。不受 80/443 端口封锁、防火墙、CDN、以及中国大陆 ICP 备案拦截的影响,而且是**唯一能签发通配符证书**的方式。HTTP-01 依赖外网入站访问 80 端口,链路更长更脆弱。决策细节见 [[pitfall-library]] §11 决策树。
