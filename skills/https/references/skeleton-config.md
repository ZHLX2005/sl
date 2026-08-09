---
name: skeleton-config
description: Use when setting up the directory structure, writing docker-compose.yml + nginx config, or substituting your own domain/email/paths into the https skill template — covers the variable table, secrets management, the canonical /srv/web-docker directory layout, the nginx + acme.sh -mounted docker-compose.yml, and the full nginx site.conf with HSTS, SPA try_files, and cache-control. Load this ref when you are at stage B (骨架搭建) or need to modify domain / paths / TLS settings. Loaded from https/SKILL.md as ref1.
---

# skeleton-config — 骨架配置

## 加载时机

- 阶段 B 首次搭建骨架
- 改域名、改路径、改端口、改 docker-compose
- 修改 nginx 站点配置(TLS、HSTS、SPA、缓存头)
- 调整敏感信息管理规范

## 1. 变量约定(套用时只改这里)

| 变量              | 示例值                                | 说明                |
| ----------------- | ------------------------------------- | ------------------- |
| `DOMAIN`        | `example.com`                       | 主域名(裸域)      |
| `WILDCARD`      | `*.example.com`                     | 通配符域名          |
| `ACME_EMAIL`    | `you@example.com`                   | ACME 账户注册邮箱   |
| `DEPLOY_USER`   | `deploy`                            | 服务器部署用户      |
| `BASE`          | `/srv/web-docker`                   | 项目根目录          |
| `CONTAINER`     | `nginx`                             | Nginx 容器名        |
| `DNS_PLUGIN`    | `dns_ali` / `dns_cf` / `dns_dp` | acme.sh 的 DNS 插件 |
| `KEEP_RELEASES` | `5`                                 | 保留的历史版本数    |

下文所有命令中出现 `example.com`、`/srv/web-docker`、`you@example.com` 的地方,替换为你自己的值即可。

## 2. 敏感信息管理规范

> 🔐 **API 密钥、AccessKey、Token 绝不能出现在**:文档、聊天记录、Git 仓库、`crontab` 命令行、脚本正文里。

统一放在受限权限的 env 文件中:

```bash
mkdir -p /srv/web-docker/secrets
cat > /srv/web-docker/secrets/dns.env <<'EOF'
Ali_Key=你的AccessKeyId
Ali_Secret=你的AccessKeySecret
EOF
chmod 600 /srv/web-docker/secrets/dns.env
chmod 700 /srv/web-docker/secrets
echo 'secrets/' >> /srv/web-docker/.gitignore
```

使用时 `set -a; source /srv/web-docker/secrets/dns.env; set +a`,避免密钥出现在 `ps` 输出和 shell history 里。acme.sh 首次签发成功后会把凭证写入 `~/.acme.sh/account.conf`,该文件同样应为 `600`。

## 3. 目录结构(约定优于配置)

```
/srv/web-docker/
├── docker-compose.yml
├── .gitignore                 # 至少忽略 secrets/ 和 certs/
├── secrets/
│   └── dns.env                # chmod 600,DNS 商 API 凭证
├── nginx/
│   └── conf.d/
│       └── site.conf
├── certs/                     # acme.sh --install-cert 的落地目录(只读挂给 nginx)
│   ├── fullchain.cer
│   └── privkey.key
├── webroot/                   # ★ 前端构建产物放这里,通过挂载暴露给容器
│   └── index.html
├── releases/                  # 历史版本快照,用于回滚
│   ├── 20260101-120000/
│   └── 20260102-093000/
├── deploy.sh                  # CD 入口
└── rollback.sh                # 回滚入口
```

## 4. docker-compose.yml

```yaml
services:
  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./certs:/etc/nginx/certs:ro
      - ./webroot:/usr/share/nginx/html:ro   # ★ 关键:宿主机产物目录挂进容器
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://127.0.0.1/"]
      interval: 30s
      timeout: 5s
      retries: 3
```

## 5. nginx/conf.d/site.conf

> ⚠️ **顺序很重要**:证书还没签出来之前,先只保留一个最简的 80 端口 server 块(返回 200 或静态页)。等证书落地到 `certs/` 之后,再替换成下面这份完整配置,否则 nginx 会因找不到证书文件而启动失败。

```
# HTTP → HTTPS 跳转(证书就绪后再启用)
server {
    listen 80;
    server_name example.com *.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name example.com *.example.com;

    ssl_certificate     /etc/nginx/certs/fullchain.cer;   # ★ 必须是 fullchain,不是 cert.pem
    ssl_certificate_key /etc/nginx/certs/privkey.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    add_header Strict-Transport-Security "max-age=31536000" always;

    root  /usr/share/nginx/html;
    index index.html;

    # SPA 单页应用必备,否则刷新子路由 404
    location / {
        try_files $uri $uri/ /index.html;
    }

    # 带 hash 的静态资源长缓存
    location ~* \.(js|css|woff2?|png|jpg|jpeg|svg|ico)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # index.html 绝不缓存,否则发版后用户永远看旧页面
    location = /index.html {
        add_header Cache-Control "no-store, must-revalidate";
    }

    gzip on;
    gzip_types text/css application/javascript application/json image/svg+xml;
    gzip_min_length 1k;
}
```

## 关联引用

- 主页面 [[../SKILL]]
- 证书签发 [[cert-issuance]]
- 部署脚本 [[deploy-scripts]]
- 坑位库 [[pitfall-library]]
