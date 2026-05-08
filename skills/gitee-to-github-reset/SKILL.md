---
name: gitee-to-github-reset
description: 开发者重置远程仓库指向 GitHub（管理员已创建仓库）
type: reference
---

# 重置远程到 GitHub

> 管理员已创建仓库，开发者只需重置本地远程。

## 一条命令

```bash
git remote remove origin 2>/dev/null; git remote remove orgin 2>/dev/null; git remote add origin git@github.com:ZHLX2005/br_ct.git && git remote -v && git pull origin main --rebase
```

## 分步操作

```bash
# 1. 删除旧远程（忽略不存在的错误）
git remote remove origin 2>/dev/null
git remote remove orgin 2>/dev/null

# 2. 添加 GitHub 远程
git remote add origin git@github.com:ZHLX2005/br_ct.git

# 3. 验证
git remote -v

# 4. 拉取代码
git pull origin main --rebase
```

## 预期输出

```
origin	git@github.com:ZHLX2005/br_ct.git (fetch)
origin	git@github.com:ZHLX2005/br_ct.git (push)
```
