---
name: mmx-research-gitclone
description: |
  使用mmx进行深度搜索并git clone开源项目到.claude/repo目录，并在clone完成后直接append origin到.claude/www/git.remote清单（不调任何sl-git-standard脚本，纯shell dedup）。
  当用户想要搜索技术资料、调研开源项目、查找最佳实践时触发。
  例如："搜索Flutter liquid glass实现"、"搜索React组件库并clone"、"调研某个技术的开源方案"。
  优先使用SSH (git@)进行克隆，限制最多clone 2个最有价值的项目。
---

# mmx-research-gitclone 工作流程

## 工作流程

### 1. 深度搜索 (使用mmx)

执行3-5次并行搜索，覆盖不同角度：

```bash
# 主搜索 - 找github项目
mmx search query --q "<技术方向> github implementation 2025" --output json --quiet

# 技术细节搜索
mmx search query --q "<技术方向> fragment shader implementation code" --output json --quiet

# 包/库搜索
mmx search query --q "<技术方向> pub.dev package widget 2025" --output json --quiet

# 最佳实践搜索
mmx search query --q "<技术方向> best practice example tutorial" --output json --quiet
```

### 2. 分析搜索结果

从搜索结果中识别最有价值的项目：

- GitHub stars数量高
- 最近更新 (2024-2025)
- 与需求最匹配
- 有实际代码实现

### 3. Git Clone 克隆

**第一步：锁定项目根目录，后续全部用绝对路径**（防止 shell 工作目录漂移导致嵌套克隆）：

```bash
# 锁定根目录（clone 和验证都基于 $REPO_ROOT，禁止裸相对路径）
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
echo "克隆目标: $REPO_ROOT/.claude/repo/"
mkdir -p "$REPO_ROOT/.claude/repo"
```

**克隆前先确认仓库存在，不要猜 URL**：

```bash
# 已知 owner/repo 时，先确认存在（404 就换目标，不重试）
gh api repos/<owner>/<repo> --jq '.full_name'

# 只有 npm 包名时，反查源仓库；无 repository 字段 = 未开源，放弃 clone
curl -s https://registry.npmjs.org/<pkg> | grep -o '"repository":{[^}]*}'
```

**优先使用SSH，失败双向回退**：

```bash
# SSH (更快，本机环境通常比HTTPS稳)
git clone --depth 1 git@github.com:<owner>/<repo>.git "$REPO_ROOT/.claude/repo/<repo-name>"

# SSH不可用回退HTTPS；反之HTTPS失败也可回退SSH，两个通道都要试
git clone --depth 1 https://github.com/<owner>/<repo>.git "$REPO_ROOT/.claude/repo/<repo-name>"
```

### 4. 验证克隆结果

**必须用绝对路径验证（与克隆同一路径变量），并确认位置符合预期**：

```bash
# 位置正确性检查：绝不能出现在嵌套路径里
if [ -d "$REPO_ROOT/.claude/repo/pi/.claude/repo" ]; then
    echo "错误: 发生嵌套克隆，移出嵌套目录后重验证"
fi

# 目录存在 + 真实内容检查（.git 存在说明 clone 真的完成）
if [ -d "$REPO_ROOT/.claude/repo/<repo-name>/.git" ]; then
    echo "克隆完成: $REPO_ROOT/.claude/repo/<repo-name>"
else
    echo "错误: 目录不存在或克隆不完整"
    exit 1
fi

# 检查关键文件是否存在
if [ -f "$REPO_ROOT/.claude/repo/<repo-name>/README.md" ] || [ -f "$REPO_ROOT/.claude/repo/<repo-name>/package.json" ]; then
    echo "关键文件存在"
else
    echo "警告: 可能克隆不完整，缺少关键文件"
fi

ls "$REPO_ROOT/.claude/repo/<repo-name>/"
```

### 5. 登记到 git.remote 清单（不调脚本，直接 append）

**纪律**：本 skill **不调用** `get_git_remotes.py`（包括 extract / sync / check / preflight / discover）—— clone 落盘后直接 append URL 到 `<root>/.claude/www/git.remote` 即可。

**为什么仍要登记**：不登记则 `sl-git-standard check/sync` 看不到新克隆的仓库（漂移 +clone）；换机器/同事接手后 `sync` 拉不到这些参考（清单是仓库内容，缺了等于没源）。

**写入方式**（带 dedup + URL 谓词校验，谓词与 `get_git_remotes.py` 的 `URL_PREFIXES` 一致：`git@` / `https://` / `http://` / `file://`）：

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MANIFEST="$REPO_ROOT/.claude/www/git.remote"
mkdir -p "$(dirname "$MANIFEST")"
touch "$MANIFEST"

# 用 Step 3 实际 clone 用的那条 URL（替换为真实 URL）
URL="git@github.com:<owner>/<repo>.git"

# 1) URL 谓词校验：必须是 shareable URL（裸本地路径资产不入清单）
case "$URL" in
    git@*|https://*|http://*|file://*) ;;
    *) echo "错误: '$URL' 不是 shareable URL，跳过登记"; exit 1 ;;
esac

# 2) dedup：清单已有则跳过（grep -x 整行匹配，-F 视为固定串）
if grep -qxF "$URL" "$MANIFEST"; then
    echo "已登记: $URL"
else
    printf '%s\n' "$URL" >> "$MANIFEST"
    echo "新增登记: $URL"
fi

# 多仓库场景：把 URLS 数组按上述流程批量写
# URLS=( "git@github.com:a/b.git" "https://github.com/c/d.git" )
# for url in "${URLS[@]}"; do ... done
```

**踩坑提醒**：
- ❌ 调用 `get_git_remotes.py extract` —— 本 skill 明确不调任何 sl-git-standard 脚本（用户指示）
- ❌ 写裸本地路径（`C:/...`、`/home/...`）—— `sl-git-standard` 读取侧静默拒收，该行实际无效
- ❌ 漏 dedup —— 重复执行会污染清单（每次执行 append 一行）
- ❌ 漏 URL 谓词校验 —— 可能塞入 npm 短名、搜索页面 URL、SSH 别名简写
- ❌ 不 commit 清单 —— 换机器后 `sl-git-standard sync` 无输入

**前置依赖**：宿主仓库的 `.gitignore` 必须包含 sl-git-standard 的标准声明结构（`.claude/repo/*` 父目录半透明 + 白名单 `_self/`）—— 否则 `.claude/repo/<repo-name>/.git` 会污染 `git status`。此结构由 `sl-git-standard` 写入，mmx-research-gitclone 不重复声明。

**跳过 Step 5 的判据**（按需，不默认）：
- 用户明确说"只 clone 不入清单" → 跳过整张 Step 5 + Step 6
- clone 全部失败（Step 4 全挂）→ 没产物可登记，Step 5 无 URL 可写

### 6. 提交清单入宿主仓库

`www/git.remote` 是仓库内容（sl-git-standard 原则 6：清单随宿主走），不是工具产物。Step 5 append 后必须 commit，否则换机器后 `sync` 无输入：

```bash
cd "$REPO_ROOT"
git add .claude/www/git.remote
git diff --cached --quiet .claude/www/git.remote || \
  git commit -m "chore(git.remote): register <repo-name> after mmx-research clone"
```

### 7. 限制

- **最多克隆2个**最有价值的项目
- 优先克隆与当前任务最相关的
- 使用 `--depth 1` 进行浅克隆减少体积

## 输出格式

完成后报告：

```
## 搜索结果总结

已克隆项目到 .claude/repo/ 目录：

1. [项目名](github链接) - stars数
   - 主要功能
   - 技术栈

2. [项目名](github链接) - stars数
   - 主要功能
   - 技术栈

项目位置: .claude/repo/<project-name>/

已登记到清单 .claude/www/git.remote（直接 append + dedup，未调 sl-git-standard 脚本）:
  新增: 1, 已存在跳过: 0, Manifest 总条目: N
清单是否已 commit: yes / no
```

## 常见搜索示例

### Flutter相关
```bash
mmx search query --q "Flutter liquid glass iOS 26 implementation github 2025" --output json --quiet
mmx search query --q "flutter glassmorphism widget github pub.dev 2025" --output json --quiet
mmx search query --q "flutter ImageFilter.blur sigmaX sigmaY implementation" --output json --quiet
```

### React/Vue相关
```bash
mmx search query --q "React liquid glass component github implementation 2025" --output json --quiet
mmx search query --q "Vue glassmorphism UI component github" --output json --quiet
```

### Swift/iOS相关
```bash
mmx search query --q "SwiftUI liquid glass iOS 26 implementation" --output json --quiet
mmx search query --q "iOS glassmorphism swift package github" --output json --quiet
```

## 错误处理

- **SSH clone失败**：回退到HTTPS；HTTPS超时/连接重置也应回退SSH，双向都试
- **目录已存在**：跳过，使用已有目录
- **clone被拒绝**：尝试另一个项目
- **GitHub 404 (Repository not found)**：URL是猜的，不要换用户名重试；用 `gh search repos` 或 npm registry 反查真实地址，查不到 = 未开源，换目标

## 踩坑记录

### [2026-09-26] piagent插件市场调研踩坑

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| clone/验证全用相对路径，且 shell CWD 已 `cd` 进 `.claude/repo/pi` | 实际克隆到 `.claude/repo/pi/.claude/repo/awesome-pi-agent` 嵌套位置；验证也用相对路径执行所以"通过"，向用户报告了错误路径，用户找不到 | clone 前先 `git rev-parse --show-toplevel` 锁定 `$REPO_ROOT`，克隆和验证全用绝对路径；验证时额外检查嵌套目录 |
| 搜索结果只给 pi.dev 页面，没核实源仓库就直接猜 owner/repo 去 clone | 两次 404（`tuanpnt/`、`dbachelder/` 均不存在），浪费重试 | clone 前用 `gh api repos/<owner>/<repo>` 确认存在；只有 npm 包名时先 `curl registry.npmjs.org/<pkg>` 反查 repository 字段，无字段 = 未开源，放弃 |
| HTTPS 连接重置后准备放弃该项目 | 差点错过目标仓库 | SSH/HTTPS 双向回退：SSH 失败试 HTTPS，HTTPS 超时也试 SSH |

### [2026-10-12] 注册 git.remote 踩坑

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 调 `get_git_remotes.py extract` 走脚本回填（2026-10-12 之前的 Step 5 写法） | 引入解释器依赖（py3 / py2 / uv）+ Windows py launcher stub 退出码 49 风险；脚本调用不属于 mmx-research-gitclone 的职责（用户明确：本 skill 不调任何 sl-git-standard 脚本） | 直接 `echo/printf + grep dedup` append URL 到 `.claude/www/git.remote`；零脚本依赖 |
| 手工 `echo "git@github.com:..." >> .claude/www/git.remote` 但漏 dedup | 重复执行会污染清单，重复行让 `sl-git-standard check` 把同一仓库算多次 | 用 `grep -qxF "$URL" "$MANIFEST"` 整行匹配判断是否已存在，再决定 append |
| 写裸本地路径（`C:/...`、`/home/...`）到清单 | `sl-git-standard` 读取侧的 `is_shareable_url()` 静默拒收，该行实际无效，但 `cat` 看到行在容易误以为生效 | URL 入口加 `case "$URL" in git@*\|https://*\|http://*\|file://*) ... ;; *) 报错 ;; esac` 谓词校验 |
| extract/append 之后不 commit `www/git.remote` | 清单是仓库内容（sl-git-standard 原则 6），不 commit 等于只在本机生效；换机器/同事接手 `sync` 无输入 | Step 6 `git add .claude/www/git.remote && git commit` 落清单进宿主仓库 |
