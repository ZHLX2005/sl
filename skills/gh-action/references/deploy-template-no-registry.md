# deploy-template-no-registry — 自包含部署模板

`deploy.yml` 的**自包含派**：本地构建 → `docker save` → SCP 传到服务器 → `docker load` → `docker run`。**全程不依赖 GHCR 或任何 registry**。

适用场景：服务器到 GHCR 网络慢/不通、镜像体积大、只需要单服务部署、registry 凭据不想管理。

**与 `deploy-template`（GHCR 派）的取舍**：

| 维度 | GHCR 派 (`deploy-template`) | 自包含派（本 ref） |
|---|---|---|
| 镜像分发 | push 到 GHCR → pull | `docker save` → SCP → `docker load` |
| 多服务编排 | `docker compose` | 单服务 `docker run` |
| 凭据管理 | 需要 `GHCR_TOKEN` | 仅 SSH 凭据 |
| 服务器到 registry 网络要求 | 高（必须可达 GHCR） | 无 |
| 镜像体积对 runner 影响 | 低（push 只上 registry） | 高（CI runner 要 tar+scp 整包） |
| 服务器磁盘占用 | 拉过的 layer 缓存复用 | 每次 load 完整 image |
| 适合场景 | 多服务、有私有 registry、网络好 | 单服务、网络受限、简化部署 |

---

## 完整模板

```yaml
name: Deploy (no-registry)

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build-and-ship:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Build Docker image
        run: docker build -t <IMAGE_NAME>:latest .

      - name: Save Docker image
        run: docker save <IMAGE_NAME>:latest | gzip > app.tar.gz

      - name: Diagnose secrets (length only)
        if: always()
        env:
          HOST_LEN:      ${{ secrets.HOST }}
          USERNAME_LEN:  ${{ secrets.USERNAME }}
          SSH_KEY_LEN:   ${{ secrets.SSH_KEY }}
          PORT_LEN:      ${{ secrets.PORT }}
        run: |
          echo "HOST length: ${#HOST_LEN}"
          echo "USERNAME length: ${#USERNAME_LEN}"
          echo "SSH_KEY length: ${#SSH_KEY_LEN}"
          echo "PORT length: ${#PORT_LEN}"

      - name: Copy image to server
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.HOST }}
          username: ${{ secrets.USERNAME }}
          key: ${{ secrets.SSH_KEY }}
          port: ${{ secrets.PORT || 22 }}
          source: "app.tar.gz"
          target: "~/app/"
          strip_components: 0

      - name: Deploy on server
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.HOST }}
          username: ${{ secrets.USERNAME }}
          key: ${{ secrets.SSH_KEY }}
          port: ${{ secrets.PORT || 22 }}
          timeout: 30s
          command_timeout: 15m
          script: |
            set -e
            APP_DIR="$HOME/app"
            CONTAINER_NAME="<CONTAINER_NAME>"
            IMAGE_NAME="<IMAGE_NAME>"
            PORT=<HOST_PORT>

            mkdir -p "$APP_DIR"
            cd "$APP_DIR"

            # Sanity check: image tar 必须存在且解压成功
            test -s app.tar.gz || { echo "MISSING app.tar.gz"; exit 1; }
            docker load < app.tar.gz

            # 加载后 sanity check：image tag 存在才能跑
            docker image inspect "${IMAGE_NAME}:latest" >/dev/null \
              || { echo "load failed — image tag missing"; exit 1; }
            rm -f app.tar.gz

            # 停掉旧容器
            docker stop "$CONTAINER_NAME" 2>/dev/null || true
            docker rm   "$CONTAINER_NAME" 2>/dev/null || true

            # 启动新容器（每次 load 的 image 都覆盖了同名 tag，所以一定是新版本）
            docker run -d \
              --name "$CONTAINER_NAME" \
              --restart unless-stopped \
              -p "${PORT}:<CONTAINER_PORT>" \
              ${{ env.EXTRA_RUN_ARGS }} \
              "${IMAGE_NAME}:latest"

            # 健康检查（带重试）
            MAX=6
            i=0
            ok=false
            while [ $i -lt $MAX ]; do
              i=$((i + 1))
              echo "Attempt $i/$MAX..."
              if curl -f -s "http://localhost:${PORT}/<HEALTH_PATH>" >/dev/null 2>&1; then
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

            echo "Deployment successful!"
```

**把模板里 `<...>` 占位符替换成实际值**：

| 占位符 | 含义 | 示例 |
|---|---|---|
| `<IMAGE_NAME>` | Docker image 名（本地 build 用） | `my-app` |
| `<CONTAINER_NAME>` | 容器名 | `my_app` |
| `<HOST_PORT>` | 服务器对外端口 | `80` |
| `<CONTAINER_PORT>` | 容器内应用端口 | `8080` |
| `<HEALTH_PATH>` | 健康检查 URL path | `/health` |
| `EXTRA_RUN_ARGS` | 额外 docker run 参数 | `-e NODE_ENV=production` |

---

## 必填 Secrets

| Secret | 用途 | 必填 |
|---|---|---|
| `HOST` | 服务器 IP | ✅ |
| `USERNAME` | SSH 用户 | ✅ |
| `SSH_KEY` | 私钥全文 | ✅ |
| `PORT` | SSH 端口（默认 22） | ⬜ |

**不需要任何 registry token**。

---

## 4 个实战设计点（从 ve 项目提炼）

### 1. 诊断 secrets 长度（fail-fast for 配置错误）

```yaml
- name: Diagnose secrets (length only)
  if: always()
  env:
    HOST_LEN:      ${{ secrets.HOST }}
  run: |
    echo "HOST length: ${#HOST_LEN}"
```

为什么这样做：
- **`if: always()`**：即使前面 build/scp 失败也跑，专门诊断用
- **不打印 secret 本身**：避免被 GitHub Actions 的 secret-scanner 误报为泄漏
- **只打印长度**：4 个 secret 任一没配，长度都是 0；配错（比如 SSH_KEY 粘了别的字段）长度异常——一眼看出问题
- 比"workflow 跑到 ssh 步骤才发现 key 错"早一步定位

### 2. `docker load` 后 sanity check

```bash
docker load < app.tar.gz
docker image inspect "${IMAGE_NAME}:latest" >/dev/null \
  || { echo "load failed — image tag missing"; exit 1; }
```

为什么：
- `docker load` 对损坏 tarball 会静默失败 / 抛非致命错
- 没有 sanity check 的话，`docker run` 用的可能是**上次 load 残留的旧 image**——workflow 绿，线上没换
- `docker image inspect` 能在 `docker load` 真失败时立即 fail-fast

### 3. 每次 build 后 `docker save` 强覆盖

```bash
docker save <IMAGE_NAME>:latest | gzip > app.tar.gz
```

- 模板里 image tag 永远是 `:latest`，但**每次 build 都是新 image**（不同 SHA）
- `docker save` 的内容是**完整 layer 集合**（不是 diff）
- 服务器 `docker load` 后会**覆盖本地同名 tag**——比 `:latest` 缓存复用更可靠
- 比 GHCR 派的"`docker compose up -d` 不 pull 新 :latest"那个坑更省心

### 4. 触发器只挂 main + 手动，避免误触

```yaml
on:
  push:
    branches: [ main ]
  workflow_dispatch:
```

- 没标签触发 → 每次 merge 都是部署
- 手动触发作为 rollback / hotfix 应急
- 想要"合并到 deploy 分支才部署"，加 `branches: [ main, deploy ]`

---

## 5 个高频坑（按出现频率排序）

### 坑 1：`docker save` 体积过大，CI runner 磁盘爆
**症状**：workflow 在 build 后失败，`no space left on device`。
**解法**：
- 用多阶段 build 减小镜像（参考 `deploy-template.md` 的 Dockerfile 关键点）
- `docker save` 后 `gzip` 是必须的（裸 save 通常比 gzip 大 2-3 倍）
- runner 默认 14 GB 空间，>1 GB 镜像建议提前估算

### 坑 2：SCP 传大文件超时
**症状**：`appleboy/scp-action` 报 `context deadline exceeded`，默认 5 分钟。
**解法**：
```yaml
- uses: appleboy/scp-action@v0.1.7
  with:
    timeout: 30m   # 默认 5m 太短，大镜像+慢网络必爆
```
或者先 `gzip`（必须）+ 走内网 runner。

### 坑 3：服务器磁盘被旧 image 撑爆
**症状**：多次部署后 `docker images` 列出几十个 `<none>` 的旧 image。
**解法**：在 `ssh script` 末尾加清理：
```bash
docker image prune -f || true
```
比 GHCR 派更需要这一步——每次都 load 完整 image，不像 `docker pull` 会复用 layer 缓存。

### 坑 4：服务器 `docker load` 找不到对应 tag
**症状**：`docker load < app.tar.gz` 成功，但 `docker image inspect my-app:latest` 报 `No such image`。
**根因**：CI 构建时 image 名大小写、`/` 等与服务器预期不一致（多见于带 registry prefix 的 image 名）。
**解法**：
- CI 端 `docker build -t my-app:latest`（无 registry 前缀）
- 服务器端 inspect 用一模一样的字符串
- 建议把 image 名作为 workflow 顶部 env 变量集中管理

### 坑 5：服务器健康检查 endpoint 路径错
**症状**：健康检查 6 次都失败，但应用其实正常起来了。
**根因**：模板里 `<HEALTH_PATH>` 是占位符，要替换成实际路径。常见错误：
- 应用暴露 `/healthz` 或 `/api/health`，模板默认 `/health` → 失败
- 应用启动慢，启动窗口 > 60 秒（MAX=6 × 10s）→ 全失败
**解法**：
- 对照应用的健康 endpoint 实际路径
- 慢启动应用：把 `MAX` 提到 12 或 `sleep` 改 30s

---

## 触发器选择：何时选这条 vs 走 GHCR 派

**选自包含派（本 ref）如果**：
- 服务器到 GHCR 网络不稳 / 慢
- 单服务部署，不需要 compose
- 不希望管理 `GHCR_TOKEN` 类凭据
- 镜像 < 500 MB（GHA runner 14 GB 空间足够）
- 服务器磁盘足够（每次部署留一份新 image）

**选 GHCR 派（`deploy-template`）如果**：
- 多服务（api + web + worker）
- 服务器到 GHCR 速度快（>= 5 MB/s）
- 镜像经常复用 layer（pull 比 save 更省带宽）
- 想用 release-please + image tag `${GITHUB_SHA}` 做版本管理

---

## 与其它 skill 的关系

- **deploy-template（GHCR 派）**——多服务场景首选
- **gh-troubleshoot**——CI 卡住 / 服务器侧 Docker 状态异常时排查
- **npm-publish**——本 skill 同主题的发布场景

---

## 实战案例：`ve/.github/workflows/deploy.yml`

下面贴出真实的 ve 项目 deploy.yml（`D:\DevProjects\my\github\ve\.github/workflows/deploy.yml`），逐处标注与通用模板的差异和设计意图。

```yaml
name: Deploy

on:
  push:
    branches: [ main, deploy ]      # ← 多了 deploy 分支（hotfix 应急）
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Build Docker image
      run: |
        docker build -t ve:latest .    # ← image 名是项目名小写

    - name: Save Docker image
      run: |
        docker save ve:latest | gzip > app.tar.gz

    - name: Diagnose secrets (length only)
      if: always()
      env:
        HOST_LEN:      ${{ secrets.HOST }}
        USERNAME_LEN:  ${{ secrets.USERNAME }}
        SSH_KEY_LEN:   ${{ secrets.SSH_KEY }}
        PORT_LEN:      ${{ secrets.PORT }}
      run: |
        echo "HOST length: ${#HOST_LEN}"
        echo "USERNAME length: ${#USERNAME_LEN}"
        echo "SSH_KEY length: ${#SSH_KEY_LEN}"
        echo "PORT length: ${#PORT_LEN}"

    - name: Copy files to server
      uses: appleboy/scp-action@v0.1.7
      with:
        host: ${{ secrets.HOST }}
        username: ${{ secrets.USERNAME }}
        key: ${{ secrets.SSH_KEY }}
        port: ${{ secrets.PORT || 22 }}
        source: "app.tar.gz"
        target: "~/app/"
        strip_components: 0
        # ⚠ 没显式设 timeout，依赖 scp-action 默认（5 分钟）——大镜像+慢网络会爆

    - name: Deploy using Docker
      uses: appleboy/ssh-action@v1.0.3
      with:
        host: ${{ secrets.HOST }}
        username: ${{ secrets.USERNAME }}
        key: ${{ secrets.SSH_KEY }}
        port: ${{ secrets.PORT || 22 }}
        timeout: 30s
        command_timeout: 10m          # ← 10 分钟够单容器启停，不够大镜像+慢启动
        script: |
          bash -c '
          APP_DIR="$HOME/app"
          CONTAINER_NAME="ve_app"      # ← 项目固定名 + _app 后缀
          IMAGE_NAME="ve"
          PORT=80

          mkdir -p $APP_DIR
          cd $APP_DIR

          docker load < app.tar.gz     # ⚠ 没做 sanity check —— 损坏 tarball 会静默失败
          rm app.tar.gz

          docker stop $CONTAINER_NAME 2>/dev/null || true
          docker rm $CONTAINER_NAME 2>/dev/null || true

          docker run -d \
            --name $CONTAINER_NAME \
            --restart unless-stopped \
            -p $PORT:80 \
            -e NODE_ENV=production \
            $IMAGE_NAME:latest
          # ⚠ 没加 docker image prune —— 服务器磁盘会持续增长

          sleep 15                    # ⚠ 硬编码启动等待，不如模板里的健康检查循环

          docker ps | grep $CONTAINER_NAME    # ← 仅做"容器在跑"检查，不验证 HTTP

          for i in {1..6}; do
            if curl -f http://localhost:$PORT/health; then
              echo "✅ Deployment successful!"
              exit 0
            fi
            sleep 10
          done
          # ← 失败时打日志再退出，比"无脑 exit 1"略好
          docker logs $CONTAINER_NAME
          exit 1
          '
```

### 与通用模板的 6 处差异

| ve 的写法 | 通用模板的写法 | 差异说明 |
|---|---|---|
| `branches: [ main, deploy ]` | `branches: [ main ]` | ve 多了 deploy 分支作为 hotfix 入口。模板默认保守，需要时再加 |
| `command_timeout: 10m` | `command_timeout: 15m` | 模板给大镜像+慢启动留余量；ve 单容器小镜像 10m 够 |
| `docker load < app.tar.gz` 直接继续 | load 后 `docker image inspect` sanity check | **ve 缺这道防线**——已在模板里补上 |
| `sleep 15` 硬编码启动等待 | 健康检查循环（最多 60s） | 模板更鲁棒，慢启动应用也能等到 |
| `docker ps \| grep` 后才开始 HTTP 检查 | 直接 HTTP 重试 | 模板省一步；ve 多一保险 |
| 无 `docker image prune` | `docker image prune -f \|\| true` | **ve 缺这道清理**——已在模板里补上 |

### ve 这套设计的 4 个亮点（值得保留）

1. **`Diagnose secrets (length only)` 步骤**：这是 ve 独有的 debug 友好设计，**通用模板原样保留**
2. **`if: always()`**：让诊断步骤在前面失败时也跑，定位更快
3. **`exit 1` 前打 `docker logs`**：比模板的"无脑 exit 1"信息更全
4. **不依赖任何 registry**：服务器到 GHCR 网络差时这套比 GHCR 派更省心

### ve 这套的 2 个改进点（已沉淀到模板）

1. **`docker load` 后缺 sanity check**——加 `docker image inspect` 防线
2. **缺 `docker image prune`**——加到 ssh script 末尾清旧 image

---

## 版本

- 1.0.0（2026-08-01）—— 从 `ve` 项目实战总结，提炼 4 个设计点 + 5 个高频坑
- 1.0.1（2026-08-01）—— 补「实战案例」小节，贴 `ve/.github/workflows/deploy.yml` 全文并标注 6 处差异