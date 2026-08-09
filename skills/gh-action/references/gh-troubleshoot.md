# gh-troubleshoot — CI/CD 失败时用 gh CLI 自动诊断

CI 跑红后,从这里开始。所有命令默认在仓库根目录执行,已 `gh auth login`。

## 1. 快速看状态

```bash
# 最近 5 次 deploy 运行
gh run list --workflow=deploy.yml --limit 5

# 跟踪最近一次运行(轮询,默认 5s 间隔)
gh run watch

# 仅看失败步骤日志(自动跳转)
gh run view --log-failed

# 看指定 run 的所有步骤 + 结论
gh run view <run-id> --json jobs,status,conclusion \
  --jq '{state:(.status+"|"+.conclusion), jobs:[.jobs[]|{name,conclusion}]}'
```

## 2. 卡住的 run

```bash
# 取消(workflow_dispatch / push 触发的,GitHub UI 不能 cancel,只能 API)
gh run cancel <run-id>

# 看为什么 step 还没结束(列出 step 状态)
gh api repos/<owner>/<repo>/actions/runs/<run-id>/jobs \
  --jq '.jobs[] | {name, status, steps: [.steps[] | {name, status, conclusion, number}]}'
```

## 3. 客户端看不到 log 时,直接 API 抓

**症状**:`gh run view --log-failed` 报 `job ... is still in progress` 但实际已经卡死。

```bash
# 拿到 job id
gh api "repos/<owner>/<repo>/actions/runs/<run-id>/jobs" \
  --jq '.jobs[] | select(.name=="<job name>") | .id'

# 直接抓 raw log(可能是 text/plain 也可能是 zip)
gh api "repos/<owner>/<repo>/actions/jobs/<job-id>/logs" > /tmp/log.txt
# 看 size 看是否 zip
ls -la /tmp/log.txt
file /tmp/log.txt
# 如果是 zip:
unzip -p /tmp/log.txt "<step_name>"/*.txt | tail -100
```

## 4. 关键诊断 grep 模式

```bash
# 找真正的错误(过滤掉 docker pull 的 progress 噪音)
grep -vE "Pulling|MB/54\.|err:.*MB/54" /tmp/log.txt \
  | grep -E "error|err:|denied|unauthor|401|403|exit|Health check|Attempt"
```

## 5. GHCR 镜像状态(anonymous + authed)

```bash
# 匿名 probe(应返回 200 if public,401 if private)
curl -sS -o /dev/null -w "HTTP %{http_code}\n" \
  "https://ghcr.io/v2/<owner>/<image>/manifests/latest"

# 带 PAT
curl -sS -H "Authorization: Bearer <PAT>" -o /dev/null -w "HTTP %{http_code}\n" \
  "https://ghcr.io/v2/<owner>/<image>/manifests/latest"
```

**401 但 UI 显示 public** → user-namespace GHCR visibility 怪现象,用 fine-grained PAT 走认证。

## 6. 服务器侧诊断

在本地通过 SSH 跳到服务器(或在 server 上直接跑):

```bash
# 容器状态
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
# Up 5 hours (unhealthy)  ← 注意 unhealthy 可能是 nginx healthcheck 路径问题,不是 docker 问题

# 当前 image 列表(看是否拉到了新 commit)
docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep <owner>

# 拉取某个 tag(带超时)
timeout 30 docker pull ghcr.io/<owner>/<image>:<tag>

# in-flight 进程(看是否 docker pull 卡住)
ps aux | grep -E 'docker pull|compose pull' | grep -v grep

# 杀卡住的 pull(要避免 kill 自己)
PIDS=$(ps -e -o pid,cmd | grep -E 'docker (pull|compose)' | grep -v grep | awk '{print $1}')
for p in $PIDS; do kill -9 $p 2>/dev/null; done

# 查看 config.json auth(如果空,deploy 没传对)
cat ~/.docker/config.json
# 期望:{"auths":{"ghcr.io":{"auth":"<base64><owner>:<token>"}}}

# health check(确认服务活着)
curl -sf http://localhost/api/health
curl -sf -o /dev/null -w "web: HTTP %{http_code}\n" http://localhost/

# 容器日志
cd ~/<app>
docker compose -f docker-compose.prod.yml logs --tail 100 -f
```

## 7. 容器"unhealthy" 但实际能访问

**症状**:`docker ps` 显示 `(unhealthy)`,但 `curl /` 200。
**原因**:nginx 容器 healthcheck 用了 `wget --spider http://localhost/`,这个 URL 总是返回 HTML,**理论上应该 healthy**。但 Docker 把 `(unhealthy)` 当 status 写出去,通常是因为 `start_period` 期间还没 probe 完。等下一次重试,或改 `apps/web/Dockerfile` 里的 healthcheck URL 为 `http://localhost/api/health`(走 nginx 反代到 api 容器)。

## 8. 容器不是新 commit(workflow 显示 success 但 image 没换)

**症状**:deploy 绿,`docker compose ps` 显示容器 image 还是老 commit,bundle hash 不变。
**根因**:`docker compose up -d` 默认**不重新拉**已存在 image,即使 `.env` 里 TAG 改了或 `:latest` 在 GHCR 上指向新 SHA,本地缓存的 image digest 也不会更新。
**修法**(deploy-template 已包含):
- `up -d` 之前显式 `docker compose pull` 强制拉新 digest
- `--force-recreate` 强制按新 image 重建容器
- 慢网络场景:把 `pull` 包在 `timeout 720` (12 min) 内,失败 fall back 到本地缓存
- SSH `command_timeout` 提到 30m
- 验证:`docker images --format "{{.Repository}}:{{.Tag}}\t{{.CreatedAt}}" | grep <owner>` 看 image 创建时间
- 二次 deploy 通常就拉到正确版本(第一次只完成 pull,第二次走 upgrade)

## 9. SSH 私钥路径问题(Windows 本地调用)

**症状**:`Warning: Identity file $env:USERPROFILE\.ssh\key not accessible: No such file or directory`。
**原因**:Win32 ssh 客户端**不解析** PowerShell 环境变量,`$env:USERPROFILE` 当字面量传。
**修法**:
```powershell
# 写绝对路径,反斜杠或正斜杠都行
ssh -i C:\Users\<user>\.ssh\key root@host ...
ssh -i /c/Users/<user>/.ssh/key root@host ...
```

## 10. 触发新 run 而不 push

```bash
# workflow_dispatch 触发
gh workflow run deploy.yml --repo <owner>/<repo>

# 带 inputs(若 workflow 接受)
gh workflow run deploy.yml --repo <owner>/<repo> -f key=value
```

## 11. 常见症状速查表

| 症状 | 优先排查 |
|---|---|
| `error: cannot connect without a private SSH key or password` | secrets 是空,填 `HOST`/`USERNAME`/`SSH_KEY`/`PORT` |
| `err: cannot perform an interactive login from a non TTY` | `docker login` 不可用,改用预写 config.json |
| `##[warning]Skip output '... ' since it may contain secret` | output 名含 `AUTH`/`TOKEN` 关键词被 secret-scanner 拦,改名 + 用 artifact |
| `Pulling images (authenticated)...` 后 hang 15min timeout | 服务器到 GHCR 慢,加 `compose pull` + `timeout 720` + SSH `command_timeout: 30m` |
| 容器 image 是老 commit(workflow green 但没换) | `docker compose up -d` 不 re-pull,deploy-template 需 `compose pull` + `--force-recreate`(详见坑 5) |
| web 200 但 api 502 | 容器没起,`docker compose logs` 看 pyBigWig 编译错 |
| `docker compose pull` 401 | PAT 失效或权限不够,regenerate fine-grained PAT with `Packages: Read` |
| `Warning: Identity file ... not accessible` | PowerShell `$env:USERPROFILE` 没展开,改绝对路径 |

## 12. 一键诊断脚本(粘贴即用)

```bash
# 在仓库根目录跑
set -e
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')
# 探针要测的镜像名(改成你的真实镜像,如 myorg/myrepo-api)
IMAGE="${IMAGE:-$REPO-api}"

echo "=== latest deploy runs ==="
gh run list --workflow=deploy.yml --limit 5 \
  --json databaseId,displayTitle,conclusion,headBranch,createdAt \
  --jq '.[] | "\(.databaseId)  \(.conclusion)  \(.headBranch)  \(.createdAt)"'

RID=$(gh run list --workflow=deploy.yml --limit 1 --json databaseId --jq '.[0].databaseId')
echo
echo "=== run $RID jobs ==="
gh run view $RID --json jobs,status,conclusion \
  --jq '{state:(.status+"|"+.conclusion), jobs:[.jobs[]|{name,conclusion}]}'

echo
echo "=== GHCR anonymous probe ==="
curl -sS -o /dev/null -w "$IMAGE HTTP %{http_code}\n" \
  "https://ghcr.io/v2/$OWNER/$IMAGE/manifests/latest"

echo
echo "=== server side ==="
ssh -i ~/.ssh/<deploy_key> <user>@<HOST> \
  "docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | grep <app>; \
   curl -sf http://localhost/api/health"
```

## 相关引用

- 主页面索引:[[../SKILL]]
- deploy.yml 模板:[[deploy-template]]
