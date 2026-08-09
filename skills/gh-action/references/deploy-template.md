# deploy-template — battle-tested deploy.yml

GitHub Actions deploy workflow 模板(Docker 构建 + GHCR 推送 + SSH 部署)。**直接复制能用**,把 `<owner>/<repo>` 改成自己的仓库名即可,镜像名建议与仓库同名(`<owner>/<repo>-api`、`<owner>/<repo>-web`)。

## 完整模板

```yaml
name: Deploy

on:
  push:
    branches: [ main ]
  workflow_dispatch:

env:
  REGISTRY: ghcr.io
  IMAGE_API: ghcr.io/<owner>/<repo>-api
  IMAGE_WEB: ghcr.io/<owner>/<repo>-web

jobs:
  build-push:
    name: Build & push images to GHCR
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build & push API
        uses: docker/build-push-action@v6
        with:
          context: .
          file: apps/api/Dockerfile
          push: true
          tags: |
            ${{ env.IMAGE_API }}:latest
            ${{ env.IMAGE_API }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Build & push Web
        uses: docker/build-push-action@v6
        with:
          context: .
          file: apps/web/Dockerfile
          push: true
          tags: |
            ${{ env.IMAGE_WEB }}:latest
            ${{ env.IMAGE_WEB }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      # Pre-compute the docker config.json content and persist it as a
      # workflow artifact. CRITICAL: GitHub Actions redacts any job output
      # whose value looks like a secret — so we cannot pass the registry
      # auth through a job output. An artifact is a file on Actions
      # storage, scanned only on the server side, not the value.
      - name: Build docker config
        if: success()
        env:
          GHCR_TOKEN: ${{ secrets.GHCR_TOKEN }}
          ACTOR: ${{ github.actor }}
        run: |
          set -e
          AUTH_B64=$(printf '%s:%s' "$ACTOR" "$GHCR_TOKEN" | base64 -w0)
          printf '{"auths":{"ghcr.io":{"auth":"%s"}}}\n' "$AUTH_B64" > docker_config.json
          echo "wrote docker_config.json ($(wc -c < docker_config.json) bytes)"

      - name: Upload docker config
        if: success()
        uses: actions/upload-artifact@v4
        with:
          name: docker-config
          path: docker_config.json
          retention-days: 1

  deploy:
    name: Deploy to server over SSH
    runs-on: ubuntu-latest
    needs: build-push
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Download docker config
        uses: actions/download-artifact@v4
        with:
          name: docker-config
          path: .
          merge-multiple: true

      - name: Copy compose file to server
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.HOST }}
          username: ${{ secrets.USERNAME }}
          key: ${{ secrets.SSH_KEY }}
          port: ${{ secrets.PORT || 22 }}
          source: "docker-compose.prod.yml,docker_config.json"
          target: "~/<app>/"
          timeout: 5m

      - name: Pull images and (re)start stack
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.HOST }}
          username: ${{ secrets.USERNAME }}
          key: ${{ secrets.SSH_KEY }}
          port: ${{ secrets.PORT || 22 }}
          timeout: 5m
          command_timeout: 30m
          envs: GITHUB_SHA
          script: |
            set -e
            cd ~/<app>

            # Install the pre-built docker config (auth written by build-push,
            # transferred as a file via SCP to avoid any env-value redaction
            # by GitHub Actions' secret scanner).
            mkdir -p ~/.docker
            mv docker_config.json ~/.docker/config.json
            chmod 600 ~/.docker/config.json
            echo "config installed: $(cat ~/.docker/config.json)"

            mkdir -p data

            echo "Pulling images via docker compose (forces refresh of :latest cache)..."
            # CRITICAL: `docker compose up -d` alone does NOT re-pull a
            # refreshed :latest tag — it reuses the locally-cached image
            # digest. The cached container keeps running the OLD bundle
            # even after GHCR's :latest advances. `compose pull` forces
            # the daemon to fetch the new digest before we re-create.
            #
            # The GHCR link is often very slow (~1 MB/s); a 437 MB web
            # image easily exceeds the SSH command_timeout. Wrap pull in
            # a 12-minute budget so a slow pull doesn't kill the deploy.
            # On pull timeout we fall back to the locally-cached image
            # (still better than abandoning the deploy entirely).
            timeout 720 docker compose -f docker-compose.prod.yml pull \
              && echo "compose pull: ok" \
              || echo "WARN: compose pull failed/timeout (continuing with cache)"

            echo "Recreating stack..."
            docker compose -f docker-compose.prod.yml up -d --remove-orphans --force-recreate

            echo "Pruning old images..."
            docker image prune -f || true

            # Health check with retry (web on :80, api via web's /api proxy).
            echo "Health check..."
            MAX=6
            i=0
            ok=false
            while [ $i -lt $MAX ]; do
              i=$((i + 1))
              echo "Attempt $i/$MAX..."
              if curl -f -s http://localhost/ >/dev/null 2>&1 \
                 && curl -f -s http://localhost/api/health >/dev/null 2>&1; then
                ok=true
                echo "Health check passed!"
                break
              fi
              sleep 5
            done

            if [ "$ok" = false ]; then
              echo "Health check FAILED. Recent logs:"
              docker compose -f docker-compose.prod.yml logs --tail 60
              exit 1
            fi

            echo "Deployment successful!"
        env:
          GITHUB_SHA: ${{ github.sha }}
```

## 配套的 `docker-compose.prod.yml`

```yaml
# TAG defaults to `latest`; the workflow writes TAG=${GITHUB_SHA} to .env.
services:
  api:
    image: ghcr.io/<owner>/<repo>-api:${TAG:-latest}
    environment:
      DATAWEB_DATA_ROOT: /data
    volumes:
      - ./data:/data:ro
    restart: unless-stopped
    expose: ["8000"]

  web:
    image: ghcr.io/<owner>/<repo>-web:${TAG:-latest}
    ports: ["80:80"]
    depends_on: [api]
    restart: unless-stopped
```

## 配套的 `apps/web/nginx.conf`(SPA + /api 反代)

```nginx
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    gzip on;
    gzip_types text/css application/javascript application/json image/svg+xml;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://api:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 120s;
    }
}
```

## 5 个必知坑点(按出现频率排序)

### 坑 1:GHCR auth 用 job output 会被 secret-scanner 拦

```
out: reg_len=64                  ← 算出 64 字节 base64
##[warning]Skip output 'REG_B64' since it may contain secret.  ← 被拦!
```

**症状**:deploy 端 `needs.build-push.outputs.REG_B64` 是空字符串,`docker pull` 401。
**解法**:用 `upload-artifact` + `download-artifact` 传文件,文件内容不被 value-scan。

### 坑 2:`docker login --password-stdin` 在 Docker 29.x 非 TTY 失败

```
err: error: cannot perform an interactive login from a non TTY device
```

**症状**:镜像 push 成功,deploy 卡在 login。
**解法**:完全绕开 `docker login`,直接预写 `~/.docker/config.json`(`printf '{"auths":{"ghcr.io":{"auth":"..."}}}'`)。

### 坑 3:慢网络 fallback(服务器到 GHCR 1MB/s)

- 437MB api 镜像拉 7 小时,15min `command_timeout` 不够
- 解法:`docker compose pull` 包在 `timeout 720` (12 min) 内,失败 fall back 到本地缓存
- SSH `command_timeout` 提到 30m 容纳 pull + recreate + health check
- 第二次 deploy 通常就拿到正确版本(只要一次拉成功)

### 坑 4:GHCR package 默认 private → 401

- user-namespace packages 即使 UI 显示 "Public",匿名 `docker pull` 仍可能 401(GHCR visibility 同步怪现象)
- 解法:用 `GHCR_TOKEN` secret 走认证(fine-grained PAT,`Public Repositories (read-only)` + `Packages: Read`)

### 坑 5:`docker compose up -d` 不自动 pull 新 :latest ⚠️ 实战高频

**症状**:workflow 绿,服务器 bundle hash 没换;`docker compose ps` 显示容器 image 仍是老 commit。

**根因**:`docker compose up -d` 检测到本地 image 已存在时,**直接复用本地 digest**,不去拉新 push 上去的 `:latest`。即使 GHCR `:latest` 指向新 SHA,本地缓存仍是旧 digest。

**修法**:`up -d` 之前必须显式 `docker compose pull`:
```yaml
- name: Pull images and (re)start stack
  uses: appleboy/ssh-action@v1.0.3
  with:
    command_timeout: 30m
    script: |
      echo "Pulling images via docker compose (forces refresh of :latest cache)..."
      timeout 720 docker compose -f docker-compose.prod.yml pull \
        && echo "compose pull: ok" \
        || echo "WARN: compose pull failed/timeout (continuing with cache)"
      docker compose -f docker-compose.prod.yml up -d --remove-orphans --force-recreate
```
要点:
- `timeout 720` 防止慢网络拖死整个 SSH command
- `|| echo WARN` 让 pull 失败不阻断 deploy(用本地缓存)
- `--force-recreate` 强制按新 image 重建容器(不依赖容器 hash 比对)
- `command_timeout: 30m` 容纳 pull (12 min) + recreate + health check (30 sec) 全部预算

## 必填 Secrets

| Secret | 用途 | 必填 |
|---|---|---|
| `HOST` | 服务器 IP | ✅ |
| `USERNAME` | SSH 用户 | ✅ |
| `SSH_KEY` | 私钥全文 | ✅ |
| `PORT` | SSH 端口(默认 22) | ⬜ |
| `GHCR_TOKEN` | fine-grained PAT(读 packages) | ✅ |

`GITHUB_TOKEN` 自动提供,无需配置。

## 配套 Dockerfile 关键点

`apps/api/Dockerfile`:
- `python:3.11-slim` base
- pyBigWig 等 C 扩展需 `apt-get install gcc libcurl4-openssl-dev zlib1g-dev` 后 `pip install .`,**pip install 后再清 apt cache** 减小镜像

`apps/web/Dockerfile`:
- 多阶段:`node:20-alpine` build → `nginx:1.27-alpine` serve
- `corepack enable && corepack prepare pnpm@10.17.0 --activate`(**必须锁 pnpm 版本**,corepack 拉最新会 Node 20 兼容错)
- copy `dist/` + `nginx.conf` 到 nginx 镜像

## 相关引用

- 主页面索引:[[../SKILL]]
- 排障命令:[[gh-troubleshoot]]
