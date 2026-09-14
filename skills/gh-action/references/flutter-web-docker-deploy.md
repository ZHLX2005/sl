# flutter-web-docker-deploy — Flutter Web → nginx 镜像 → 服务器全自动部署

Flutter 应用的 web 版全自动部署：`flutter build web` → nginx:alpine 镜像 → `docker save` → SCP → 服务器 `docker run`。**含 gh CLI 一条龙设密钥 + 端到端自测验证全流程**。

与 ref4 `deploy-template-no-registry` 的关系：**部署链路完全相同**（save → scp → load → run，不依赖 registry）。差异在三点：

| 维度 | ref4（通用） | 本 ref（Flutter Web 特化） |
|---|---|---|
| 构建源 | 直接 `docker build` | CI 先 `flutter build web`，产物拷进 context |
| 镜像内容 | 应用运行时 | 纯静态文件 + nginx |
| 触发方式 | push main / 手动 | **commit message 含 `web` 才触发** + 手动 |

---

## 决策清单（动手前先定，缺一个返工一次）

| 决策点 | 本次选择 | 备选 |
|---|---|---|
| 配置文件位置 | `web_deploy/` 单目录（不放仓库根） | 放根（Docker 默认习惯） |
| Docker context | `web_deploy/` | 仓库根 `.` |
| 触发条件 | `workflow_dispatch` + push master 且 message 含 `web` | paths 过滤 |
| secrets | `HOST` `USERNAME` `SSH_KEY` `PORT`（4 个，与 ref4 一致） | — |
| 端口映射 | 服务器 82 → 容器 80 | — |

---

## Docker context 陷阱与 `web_deploy/` 模式

**硬限制**：Docker 不允许 `COPY ../xxx`（"Forbidden path outside the build context"）。context 不能是 Dockerfile 上方的目录。

所以**不能**让 Dockerfile 里 COPY 仓库根的 `pubspec.yaml` / `lib/`。解法是 **CI 预构建 + 拷产物进 context**：

```
CI 流程:
1. checkout                    → 仓库根
2. flutter pub get
3. flutter build web --release → 产出 build/web/
4. cp -r build/web web_deploy/build-web   ← 产物进 context
5. docker build web_deploy/              ← context=web_deploy，只 COPY build-web/
6. docker save | gzip → scp → 服务器 load → run
```

配套动作：`.gitignore` 追加 `web_deploy/build-web/`（CI 中间产物不入版本控制）。

`.dockerignore` 放 `web_deploy/` 内即可生效（context 就是 `web_deploy/`）——这是本模式对 ref4 的一个改善：`.dockerignore` 也不用污染仓库根。

---

## 文件模板（4 个）

### `web_deploy/Dockerfile`

```dockerfile
FROM nginx:alpine

# nginx.conf 覆盖默认配置（针对 Flutter SPA）
COPY nginx.conf /etc/nginx/conf.d/default.conf

# CI 预构建的 Flutter Web 产物（来自 cp -r build/web web_deploy/build-web）
COPY build-web/ /usr/share/nginx/html/

EXPOSE 80
```

### `web_deploy/nginx.conf`

```nginx
server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    # gzip 压缩（Flutter web bundle 体积大，效果明显）
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript
               application/javascript application/json application/xml
               image/svg+xml;

    # Flutter SPA 路由：所有未知 path 回退到 index.html
    location / {
        try_files $uri $uri/ /index.html;
    }

    # 静态资源缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Flutter web canvaskit 体积大，单独给长缓存
    location ~* canvaskit\.js$ {
        expires 7d;
        add_header Cache-Control "public";
    }

    # 隐藏 nginx 版本
    server_tokens off;
}
```

### `web_deploy/.dockerignore`

```
build-web/.git
build-web/.cache
build-web/.dart_tool
build-web/.idea
build-web/.vscode
*.md
*.log
```

### `.github/workflows/deploy-web.yml`

```yaml
name: Deploy Web

on:
  push:
    branches: [ master ]
  workflow_dispatch:

jobs:
  deploy-web:
    runs-on: ubuntu-latest
    environment: production

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.4'   # ← 对齐项目现有 CI 的版本
          channel: 'stable'
          cache: true

      - name: Get Flutter dependencies
        run: flutter pub get

      # GitHub Actions 无原生 commit message filter，用 step 判断。
      # 代价：普通 push 也会跑到这里才 exit（约 1 分钟 CI 时间）
      - name: Check commit message
        if: github.event_name == 'push'
        run: |
          MSG="${{ github.event.head_commit.message }}"
          echo "Commit message: $MSG"
          if ! echo "$MSG" | grep -qi 'web'; then
            echo "Commit message does not contain 'web', skipping deploy."
            exit 1
          fi

      - name: Build Flutter web
        run: flutter build web --release --pwa-strategy=none

      - name: Prepare deploy context
        run: |
          rm -rf web_deploy/build-web
          cp -r build/web web_deploy/build-web
          echo "build-web size:"
          du -sh web_deploy/build-web

      - name: Diagnose secrets (length only)
        if: always()
        env:
          HOST_LEN:     ${{ secrets.HOST }}
          USERNAME_LEN: ${{ secrets.USERNAME }}
          SSH_KEY_LEN:  ${{ secrets.SSH_KEY }}
          PORT_LEN:     ${{ secrets.PORT }}
        run: |
          echo "HOST length: ${#HOST_LEN}"
          echo "USERNAME length: ${#USERNAME_LEN}"
          echo "SSH_KEY length: ${#SSH_KEY_LEN}"
          echo "PORT length: ${#PORT_LEN}"

      - name: Build Docker image
        run: docker build -t <IMAGE_NAME>:latest web_deploy/

      - name: Save Docker image
        run: docker save <IMAGE_NAME>:latest | gzip > app.tar.gz

      - name: Copy image to server
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.HOST }}
          username: ${{ secrets.USERNAME }}
          key: ${{ secrets.SSH_KEY }}
          port: ${{ secrets.PORT || 22 }}
          source: "app.tar.gz"
          target: "~/app/"
          timeout: 30m          # 默认 5m，大镜像+慢网络必爆
          strip_components: 0

      - name: Load and run on server
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.HOST }}
          username: ${{ secrets.USERNAME }}
          key: ${{ secrets.SSH_KEY }}
          port: ${{ secrets.PORT || 22 }}
          timeout: 30s
          command_timeout: 15m
          script: |
            bash -c '
            set -e
            APP_DIR="$HOME/app"
            CONTAINER_NAME="<IMAGE_NAME>"
            IMAGE_NAME="<IMAGE_NAME>"
            HOST_PORT=82
            CONTAINER_PORT=80
            HEALTH_PATH="/"

            mkdir -p "$APP_DIR"
            cd "$APP_DIR"

            test -s app.tar.gz || { echo "MISSING app.tar.gz"; exit 1; }
            docker load < app.tar.gz
            docker image inspect "${IMAGE_NAME}:latest" >/dev/null \
              || { echo "load failed - image tag missing"; exit 1; }
            rm -f app.tar.gz

            docker stop "$CONTAINER_NAME" 2>/dev/null || true
            docker rm   "$CONTAINER_NAME" 2>/dev/null || true
            docker network prune -f 2>/dev/null || true

            docker run -d \
              --name "$CONTAINER_NAME" \
              --restart unless-stopped \
              -p "${HOST_PORT}:${CONTAINER_PORT}" \
              "${IMAGE_NAME}:latest"

            # 健康检查（nginx 秒起，前 1-2 次失败属启动窗口，MAX=6 兜底）
            MAX=6
            ok=false
            for i in $(seq 1 $MAX); do
              echo "Health check attempt $i/$MAX..."
              if curl -f -s "http://localhost:${HOST_PORT}${HEALTH_PATH}" >/dev/null 2>&1; then
                ok=true
                echo "Health check passed!"
                break
              fi
              sleep 10
            done

            if [ "$ok" = false ]; then
              echo "Health check FAILED. Recent logs:"
              docker logs "$CONTAINER_NAME" --tail 60
              exit 1
            fi

            docker image prune -f || true

            echo "Deployment successful!"
            '
```

---

## gh CLI 一条龙设密钥

先 `gh auth status` 确认登录 + `gh repo view --json nameWithOwner` 确认仓库对得上。

### 三个明文 secret 直接 `--body`

```bash
gh secret set HOST     --body '47.110.80.47'
gh secret set USERNAME --body 'root'
gh secret set PORT     --body '22'
```

### SSH_KEY 必须走临时文件，不能 `--body`

两个原因：① 私钥多行，`--body` 传多行字符串有转义坑；② `--body` 会进 shell history。

```bash
# 1. 私钥写到临时文件（必须以 LF 结尾！见下方坑 1）
#    Windows 上注意：PowerShell 的 $TEMP 可能指向 D:\Temp，
#    git-bash 的路径是 /c/Users/<u>/AppData/Local/Temp —— 两边不一致，用绝对路径
KEYFILE="/c/Users/<user>/AppData/Local/Temp/deploy_key.tmp"

# 2. stdin 传入
gh secret set SSH_KEY < "$KEYFILE"

# 3. 验证 + 立刻删
gh secret list
rm -fv "$KEYFILE"
```

写入前校验（防 BOM / 缺尾换行）：

```bash
wc -c "$KEYFILE"                    # 期望字节数（ed25519 无密码约 399）
tail -c 1 "$KEYFILE" | xxd          # 必须 0a（LF）
```

> **私钥泄露面提醒**：私钥若曾在对话 / 粘贴板中明文出现过，它已经扩散。GitHub Secret 本身加密，但 secret 只保护"入库之后"。正确姿势是给 CI 单独生成一把 key（服务器 `ssh-keygen` → 公钥进 `authorized_keys` → 私钥进 secret），不与人肉登录 key 复用。

---

## 端到端自测 SOP（部署后自己跑完全程）

### 1. workflow 必须先 push 到默认分支

**最高频翻车点**：本地写好 workflow 没 push，GitHub 完全不知道它存在。症状：

```
gh run list --workflow deploy-web.yml
→ HTTP 404: workflow deploy-web.yml not found on the default branch
```

以及目标端口 `Connection refused`（什么都没部署，当然 refused）。

### 2. 触发

```bash
git add web_deploy/ .github/workflows/deploy-web.yml .gitignore
git commit -m "ci(deploy): xxx web"    # message 含 web → 自动触发
git push origin master
```

或网页手动 Run workflow（`workflow_dispatch` 不走 message 检查）。

### 3. 监控 CI

```bash
gh run list --workflow deploy-web.yml --limit 3
# 拿到 run_id 后 30s 轮询：
gh run view <run_id> --json status,conclusion
# 完成 = status: completed；conclusion: success/failure
```

经验时长：**11 分钟左右**（flutter pub get ~1m + build web ~4m + docker build ~1m + scp ~1m + 服务器 load/run/健康检查 ~2m）。

### 4. 服务器侧验证

```bash
ssh <server> "docker ps | grep <container>"          # 容器在跑
ssh <server> "ss -tln | grep :82"                    # 端口监听（0.0.0.0 双栈）
ssh <server> "curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:82/"
```

### 5. 公网验证

```bash
curl -I http://<服务器IP>:82/       # HTTP 200
```

---

## 坑清单（按本次实战踩到的顺序）

### 坑 1：私钥末尾必须 LF，OpenSSH 9.5p2 严格校验

症状：`ssh-keygen -lf` 报 `is not a key file`，ssh 报 `Load key ... invalid format`，但 `cat` 出来格式完全正常。

根因：文件末尾缺 `\n`（Windows 工具链写的文件常缺）。校验 `tail -c 1 | xxd` 必须 `0a`，缺了就 `printf '\n' >> keyfile` 补上。

### 坑 2：workflow 未 push → 目标端口 refused

见上方 SOP 第 1 步。`gh run list` 能列出 = GitHub 已注册该 workflow。

### 坑 3：健康检查日志出现 `Health check FAILED` 但 conclusion 是 success

早期 1-2 次尝试落在 nginx 启动窗口内属正常，循环重试通过即 success。**别看到 FAILED 字样就当失败**，以 `conclusion` 为准。

### 坑 4：`flutter build web` 的产物依赖根 `web/` 目录

仓库根 `web/`（index.html / manifest.json / icons）是 Flutter Web 入口壳，改动会自动进构建产物，无需额外 COPY。`build/` 整目录已被 .gitignore 屏蔽，Docker 里不要 COPY 它。

### 坑 5：scp-action 默认 5 分钟超时

Flutter web 镜像 gzip 后仍可能 >50MB，国内服务器带宽下 5m 不够。必须显式 `timeout: 30m`。

### 坑 6：message filter 的隐性成本

master 上**每个** push 都会跑到 `Check commit message` step 才 exit（checkout + pub get 约 1 分钟）。介意的话加 `paths: [web_deploy/**, lib/**, web/**]` 收紧。

### 坑 7：Node 20 deprecation warning

`actions/checkout@v4` 会打 Node 20 弃用 warning（被强制跑 Node 24）。无害，不处理。

### 坑 8：服务器 OpenSSH 8.0 的 post-quantum KEX warning

每次 ssh 连接打 `WARNING: connection is not using a post-quantum key exchange algorithm`。服务端 openssh 版本旧导致，不影响功能。

---

## 实战案例：xiaodouzi_fr → 47.110.80.47:82

- 项目：Flutter 应用（xiaodouzi_fr，仓库 `ZHLX2005/fr`，master 分支）
- 首次部署 commit：`ci(deploy): add deploy-web workflow to aliyun47:82 web`
- CI 耗时：11 分 02 秒（run 34698001300）
- 验证全过：容器 Up、`:82` 双栈监听、本机 curl 200（1.9ms）、公网 curl 200（151ms）
- secrets 4 个全部 `gh secret set` 写入（SSH_KEY 走临时文件 + LF 校验）

## 版本

- 1.0.0（2026-09-13）—— 从 xiaodouzi_fr 实战沉淀：web_deploy/ context 模式 + gh secret 一条龙 + 端到端自测 SOP + 8 坑
