---
name: pitfall-library
description: Use as a lookup when something breaks at any stage — 30 curated pitfalls (15 cert-class + 15 deploy-class), the cheat-sheet of one-liners (deploy/rollback/health/renew), and the HTTP-01 vs DNS-01 decision tree with mainland China ICP-blocking remediation paths. Load this ref during troubleshooting, when choosing between DNS-01 and HTTP-01, or when planning around mainland ICP firewall. Loaded from https/SKILL.md as ref4.
---

# pitfall-library — 坑位/速查/决策树

## 加载时机

- 任意阶段出问题时查(证书签发、发版、缓存)
- 第一次部署前选 DNS-01 vs HTTP-01
- 大陆节点服务器,需要规划绕过 ICP 备案拦截

## 1. 速查命令(放在手边)

```bash
cd /srv/web-docker

./deploy.sh ~/dist.zip                     # 发版
./rollback.sh                              # 列出可回滚版本
./rollback.sh 20260101-120000              # 回滚到指定版本
docker compose ps                          # 容器状态
docker compose logs -f --tail=50 nginx     # 实时日志
docker exec nginx nginx -t                 # 校验配置
docker exec nginx nginx -s reload          # 热重载
~/.acme.sh/acme.sh --list                  # 证书清单与到期日
~/.acme.sh/acme.sh --cron --force          # 强制续期演练
curl -s ifconfig.me                        # 查本机公网 IP
```

## 2. ⚠️ 坑位大全

### 2.1 证书类

| 坑                              | 现象                                                       | 原因 / 解法                                                                                                                                                   |
| ------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **死磕 HTTP-01**          | nginx 日志显示 200 且响应体 87 字节,LE 仍报 403           | 87 字节正是 keyAuthorization(43 + 1 + 43)的长度,说明服务端完全正确,403 由中间网关注入。大陆未备案域名的 80 端口会被云厂商网关拦截 →**改用 DNS-01** |
| 「本地 curl 200」误判           | 以为链路已通                                               | 本地 curl 走 loopback,绕过安全组与云网关,只能证明最内层。必须用外网视角验证,或用 letsdebug.net                                                             |
| 凭证变量为空                    | `Error adding TXT record`                                | 形如 `export Ali_Key="$ALI_KEY"` 引用了不存在的变量 → 空值调 API。先 `echo` 确认非空                                                                      |
| 凭证顺序颠倒                    | 同上                                                       | ID 填 Key 字段、Secret 填 Secret 字段,不要对调                                                                                                               |
| Secret 含特殊字符               | 签名失败                                                   | 必须双引号包裹;优先用 env 文件而非命令行                                                                                                                     |
| 权限未授予                      | `Forbidden.RAM` / `NoPermission`                       | 补授 DNS 读写权限                                                                                                                                             |
| 密钥来源 IP 白名单              | 权限正确但仍 `NoPermission`                             | 关闭该限制,或把服务器公网 IP 加入白名单                                                                                                                      |
| 服务器时间偏移                  | `SignatureDoesNotMatch`                                  | 偏差超过 15 分钟即失败。`sudo timedatectl set-ntp true`                                                                                                     |
| 旧 TXT 残留                     | `DomainRecordDuplicate` / `Incorrect TXT record found` | 删除 DNS 里所有 `_acme-challenge` 记录后重试                                                                                                                 |
| **失败次数打满**          | `too many failed authorizations`                         | LE 限制 5 次失败授权/小时/域名。修好后也需等待。**所有调试先用 `--staging`**                                                                          |
| 通配符不含裸域                  | 访问裸域报证书不匹配                                       | 两个 `-d` 都要写                                                                                                                                             |
| 用了 `cert.pem` 而非 fullchain | 部分客户端报证书链不完整                                   | 必须使用 `--fullchain-file` 的产物                                                                                                                           |
| 直接引用 acme.sh 内部路径       | 续期后 nginx 仍加载旧证书                                  | 必须 `--install-cert` 拷出到固定路径,acme.sh 只维护该目标文件                                                                                               |
| **忘记 `--reloadcmd`**  | 90 天后网站证书过期,但续期日志显示成功                    | `--install-cert` 时必须带 reload 钩子,并用 `--cron --force` 演练验证                                                                                     |
| 默认 CA 不是 LE                 | 签出来是 ZeroSSL 证书                                      | 先 `--set-default-ca --server letsencrypt`                                                                                                                   |
| `dig: command not found`      | 无法排查 DNS                                               | 装 `bind-utils`(RHEL 系)或 `dnsutils`(Debian 系),或用 DoH 接口 `curl` 查询                                                                          |

### 2.2 部署类

| 坑                                | 现象                                | 解法                                                                                   |
| --------------------------------- | ----------------------------------- | -------------------------------------------------------------------------------------- |
| **root 指向容器内默认目录** | 一直显示 Nginx 欢迎页               | `root /usr/share/nginx/html` 必须有宿主机 `./webroot` 挂载,否则永远是镜像自带内容 |
| 只 `cp` 不清旧文件               | 旧 chunk 残留、白屏、报错找不到模块 | 用 `rsync -a --delete`                                                                |
| `index.html` 被缓存             | 发版后用户仍看旧页面                | `location = /index.html` 加 `no-store`;静态资源靠 hash 长缓存                     |
| SPA 路由刷新 404                  | 直接访问子路径 404                  | `try_files $uri $uri/ /index.html;`                                                  |
| 改配置直接 reload                 | 配置写错导致 nginx 挂掉             | **先 `nginx -t` 再 `-s reload`**,脚本已内置                                 |
| 用 `restart` 代替 `reload`     | 秒级服务中断                        | 静态文件与证书变更用 `nginx -s reload` 零中断;只有改 compose 才需 `up -d`          |
| 挂载为 `:ro` 却想写入            | Permission denied                   | 只读是故意的,写入请在宿主机侧操作                                                     |
| zip 多套一层目录                  | 产物变成 `webroot/dist/index.html` | 脚本已做兼容判断;手动解压需留意                                                       |
| 磁盘被历史构建包占满              | 构建或解压失败                      | 限制保留版本数,定期清理临时包                                                         |
| 安全组未放通 443                  | 外网连不上但本机 curl 正常          | 云平台安全组入方向放通 `80/443` TCP,源 `0.0.0.0/0`                                 |
| HTTPS server 块早于证书存在       | nginx 启动失败或跳转死循环          | 先签好证书再启用 443 与 301 跳转                                                       |
| 密钥写进 crontab 命令行           | `ps` 可见、日志泄露               | 凭证放 600 权限 env 文件,脚本内 `source`                                             |

## 3. Challenge 方式决策树

```
需要通配符证书?
 ├─ 是 ──────────────────────────────▶ DNS-01(唯一选择)
 └─ 否
     │
     ├─ 80 端口能被外网访问吗?
     │   ├─ 不能(备案拦截 / 端口封锁 / 内网机器)──▶ DNS-01
     │   └─ 能
     │       │
     │       ├─ DNS 托管商有 API 且能拿到凭证?
     │       │   ├─ 是 ──▶ DNS-01(更稳,不依赖入站链路)
     │       │   └─ 否 ──▶ HTTP-01(webroot 模式)
```

### 备案与合规提醒(中国大陆节点)

> 🚨 大陆云服务器上,未完成 ICP 备案的域名通过 80/443 提供 Web 服务会被网关拦截(典型表现为 403)。部分顶级域(如 `.xyz`)不在国内可备案后缀白名单内,**无法通过备案解决**。长期稳定方案优先级:
>
> 1. **CDN 代理层**(如 Cloudflare 橙云):裸域直达、隐藏源站 IP、证书自动化
> 2. **服务器迁至境外/港澳节点**:无备案要求,两种 challenge 都可用
> 3. **更换可备案域名**(`.com` / `.cn`)走正式备案流程
> 4. **改用非标端口**(如 `4433`):能绕过拦截,但 URL 需带端口、生态兼容性差、仍有合规风险
>
> 注意:非标端口方案**不能**用于证书签发 —— HTTP-01 固定 80、TLS-ALPN-01 固定 443,协议层不可改,只有 DNS-01 完全不依赖端口。

## 关联引用

- 主页面 [[../SKILL]]
- 骨架配置 [[skeleton-config]]
- 证书签发 [[cert-issuance]]
- 部署脚本 [[deploy-scripts]]
