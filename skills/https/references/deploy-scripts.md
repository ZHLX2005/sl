---
name: deploy-scripts
description: Use when writing or executing the static-site deploy.sh / rollback.sh, or running the post-deploy verification checklist — covers the version-snapshot + rsync --delete + nginx -t + reload dance, smoke-test via 127.0.0.1 with HTTPS Host header, N-version retention, and the curl + openssl s_client verification commands. Loaded from https/SKILL.md as ref3.
---

# deploy-scripts — 发版与回滚

## 加载时机

- 阶段 E 首次写 deploy.sh / rollback.sh
- 改部署流程(增加预热、灰度等)
- 阶段 D/E 每次发版后跑验收清单

## 1. CD 脚本 `deploy.sh`

```bash
#!/bin/bash
# 用法:  ./deploy.sh dist.zip     或     ./deploy.sh /path/to/dist/
set -euo pipefail

BASE=/srv/web-docker
WEBROOT=$BASE/webroot
RELEASES=$BASE/releases
CONTAINER=nginx
KEEP=5
HOST_HEADER=example.com

STAMP=$(date +%Y%m%d-%H%M%S)
NEW=$RELEASES/$STAMP
SRC=${1:?用法: ./deploy.sh <dist.zip 或 dist 目录>}

mkdir -p "$NEW" "$RELEASES"

# 1) 解包 / 拷贝到新版本目录
if [[ "$SRC" == *.zip ]]; then
  command -v unzip >/dev/null || { echo "缺少 unzip,请先安装"; exit 1; }
  unzip -q "$SRC" -d "$NEW.tmp"
  # 兼容 zip 内多套一层 dist/ 的情况
  if [ -d "$NEW.tmp/dist" ]; then mv "$NEW.tmp/dist"/* "$NEW"/; else mv "$NEW.tmp"/* "$NEW"/; fi
  rm -rf "$NEW.tmp"
else
  cp -a "$SRC"/. "$NEW"/
fi

# 2) 前置校验:必须有 index.html,防止发布空目录
[ -f "$NEW/index.html" ] || { echo "未找到 index.html,发布中止"; rm -rf "$NEW"; exit 1; }

# 3) 同步到 webroot(--delete 清理旧 chunk,避免残留导致白屏)
if command -v rsync >/dev/null; then
  rsync -a --delete "$NEW"/ "$WEBROOT"/
else
  rm -rf "$WEBROOT"/* && cp -a "$NEW"/. "$WEBROOT"/
fi

# 4) 先校验配置再热重载(★ 避免把线上打挂)
docker exec "$CONTAINER" nginx -t
docker exec "$CONTAINER" nginx -s reload

# 5) 冒烟测试
sleep 1
CODE=$(curl -s -o /dev/null -w '%{http_code}' -k "https://127.0.0.1" -H "Host: $HOST_HEADER")
echo "本地探测 HTTP 状态:$CODE"
[ "$CODE" = "200" ] || echo "非 200,请立即检查或回滚"

# 6) 只保留最近 N 个版本
ls -1dt "$RELEASES"/*/ 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -rf

echo "部署完成:$STAMP"
echo "回滚命令: ./rollback.sh $STAMP"
```

## 2. 回滚脚本 `rollback.sh`

```bash
#!/bin/bash
set -euo pipefail
BASE=/srv/web-docker
CONTAINER=nginx

if [ $# -eq 0 ]; then
  echo "可选版本:"; ls -1dt "$BASE"/releases/*/ | head -5
  echo "用法: ./rollback.sh <版本目录名>"; exit 1
fi

TARGET=$1
[ -d "$BASE/releases/$TARGET" ] || { echo "版本不存在:$TARGET"; exit 1; }

rsync -a --delete "$BASE/releases/$TARGET"/ "$BASE/webroot"/
docker exec "$CONTAINER" nginx -t && docker exec "$CONTAINER" nginx -s reload
echo "已回滚到 $TARGET"
```

```bash
chmod +x deploy.sh rollback.sh
```

## 3. 验收清单(每次发版必跑)

```bash
# 证书颁发者、有效期、SAN
echo | openssl s_client -connect example.com:443 -servername example.com 2>/dev/null \
  | openssl x509 -noout -issuer -dates -ext subjectAltName

# HTTP 是否 301 到 HTTPS
curl -sI http://example.com | head -3

# 内容是否为新版本(看带 hash 的资源文件名是否变化)
curl -s https://example.com | grep -oE '[a-z]+-[a-z0-9]{8,}\.js'

# 通配符是否生效
curl -sI https://anything.example.com | head -1

# 容器状态
docker compose ps
```

**通过标准**:颁发者含 `Let's Encrypt`;SAN 同时含裸域与通配符;HTTP 返回 301;HTTPS 返回 200;资源 hash 已更新;容器 `healthy`。

## 关联引用

- 主页面 [[../SKILL]]
- 骨架配置 [[skeleton-config]]
- 部署坑位 → [[pitfall-library]] §9.2 部署类
