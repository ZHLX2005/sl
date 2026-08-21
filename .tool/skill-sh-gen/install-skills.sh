#!/usr/bin/env bash
# install-skills.sh — 由 collect-skills.sh 自动生成,请勿手改
# 用法: bash install-skills.sh [skills根目录]
#   不传参 → 安装到 ./.claude/skills(当前项目)
#   传参   → 安装到指定目录,例: bash install-skills.sh ~/.claude/skills
set -euo pipefail
SKILLS_BASE="${1:-./.claude/skills}"

# ===== skill: tool-isolation =====
mkdir -p "$SKILLS_BASE/tool-isolation/."
cat > "$SKILLS_BASE/tool-isolation/SKILL.md" << 'SKILL_EOF'
---
name: tool-isolation
description: |
  当用户提到"安装工具"、"装 esbuild"、"装 eslint"、"npm install"、
  "用 python 脚本"、"跑个外部工具"、"临时脚本"、"scratch 工具"、
  "工具隔离"、"防止污染根目录"、"HTTP 测试"、"接口调试"、"curl 测试"时触发。
  本 skill 强制所有外部工具、npm 包、Python 脚本创建到 .tool/{tool-name}/ 下，
  与项目代码完全隔离。**遇到问题优先用 Python / npm 脚本解决**（尤其是 HTTP 指令测试）。
---

# tool-isolation — 外部工具隔离规范

## 核心原则（最高优先级）

> **遇到问题先想 Python / npm 脚本，再考虑直接调项目二进制。**

AI 在调试 / 验证 / 测试时倾向于「直接跑项目二进制 + curl」，这常常导致：
- 反复 `docker-compose up` / `air` 启动耗时
- 端口被占用、状态污染
- 写不出可复用的验证脚本

**强制优先级**：

| 场景 | 优先方案 | 备选 | 避免 |
|------|---------|------|------|
| **HTTP 指令测试** | **Python（httpx + JWT 头）** | npm（axios / undici） | 直接 curl / 启项目 curl |
| **API 接口验证** | Python httpx 脚本 | npm axios | 重启服务手测 |
| **JSON 数据处理** | Python（jq 不可读时） | node | 复杂 jq 表达式 |
| **CSV / Excel 解析** | Python（pandas） | node xlsx | 手工解析 |
| **性能基准（HTTP）** | npm（k6 / autocannon） | Python（locust） | 直接 ab / wrk |
| **文件批量处理** | Python | node | shell 循环 |
| **正则提取 / 文本处理** | Python `re` | node | 复杂 grep/sed/awk |
| **协议 / 编解码** | Python（库丰富） | node | 项目代码 import |
| **图像 / PDF 处理** | Python（pillow / pypdf） | node | 系统工具 imagemagick |
| **数据库查询 / 迁移** | Python（psycopg / SQLAlchemy） | node | 项目内 ORM 调用 |

### Python 两铁律（按优先级）

> **优先 python3 解释器，其次 uv 指令管理环境与依赖。缺一不可。**

| # | 铁律 | 做法 | 禁止 |
|---|------|------|------|
| ① | **优先 `python3`** | 所有 Python 调用显式写 `python3` | `python xxx.py`（部分系统 `python` → Python 2 或 command not found） |
| ② | **其次 `uv` 指令** | `uv venv` 建环境、`uv pip install`/`uv add` 装包、`uv run python3` 运行 | 裸 `pip install`、`python -m venv`、直接 `python3`（不走 uv） |

**执行模板**：
```bash
# ✅ 标准执行（uv 自动激活 .venv，无需手动 activate）
uv run python3 scripts/probe.py

# ✅ 建环境 + 装依赖
uv venv                     # 建 .venv/
uv pip install -r requirements.txt   # 装到 .venv/ 内
uv add httpx                # 添加到 .venv/ 并更新 requirements.txt

# ❌ 禁止
python scripts/probe.py
python -m venv venv
pip install -r requirements.txt
```

> **Windows 用户**：在 Git Bash 下 `python3` 通常可用。若 `python3` 不存在，用 `python` 替代（Windows 上 `python` 始终为 Python 3），并保持 `uv run python`。

### 为什么 Python 优先？

1. **stdlib 覆盖广**：`http.client`、`json`、`urllib`、`hashlib`、`secrets` 足够应付 80% 场景
2. **包生态成熟**：httpx / requests / pandas / pydantic 比 node 同类更稳
3. **零额外工具**：写 `.py` 单文件 + `uv venv` 即可，npm 需 `package.json` + ts 配置
4. **可读性高**：调试 / 改写 / 重跑成本低

### 为什么 npm 次选？

- 项目本身已是 Node 生态（前端构建、k6、esbuild）时，复用现有工具链
- 流式 / WebSocket / SSE 长连接场景 node 更顺
- 与项目 `package.json` 解耦时（独立工具目录内私有 npm 工作流）也可

### ❌ 必须避免的反模式

- `curl http://localhost:8080/api/xxx` 反复手测 → 写 `.tool/http-tester/scripts/probe.py`
- 启动完整 GoFrame 服务只为测一个端点 → 用 httpx 直接构造请求
- 写复杂 `jq -r '.data[] | select(.x.y)'` → Python 3 行 `data['x']['y']`
- 用 `sed -i 's/foo/bar/g'` 批量改文件 → Python `pathlib` + `re`

---

## 基础规范

**所有外部工具、临时脚本、第三方 CLI 一律放进 `.tool/{tool-name}/`**。

- `.tool/` 由 `git-repo-cleanup` 模式 C 维护，已在 `.gitignore` 中
- 每个工具独立子目录，**严禁**所有工具共用一个 `package.json` / `node_modules`
- 项目根目录的 `package.json` 仅用于项目自身的 npm 工作流，不混用

## 标准目录结构

```
.tool/
├── README.md                      # 工具目录索引（可选但强烈推荐）
├── http-tester/                   # 例：HTTP 指令测试器（Python）
│   ├── pyproject.toml             # 或 requirements.txt
│   ├── .venv/                     # uv 虚拟环境（uv venv 生成）
│   ├── scripts/
│   │   └── probe.py
│   └── README.md
├── esbuild-checker/               # 例：esbuild 检查器（npm）
│   ├── package.json               # 仅本工具的依赖声明
│   ├── package-lock.json
│   ├── node_modules/              # 仅本工具的依赖
│   ├── src/
│   │   └── check.ts
│   └── README.md
├── k6-runner/                     # 例：k6 性能测试（npm）
│   ├── package.json
│   ├── scripts/
│   │   └── load.js
│   └── README.md
└── python-helper/                 # 例：Python 临时脚本
    ├── pyproject.toml
    ├── .venv/                     # uv 虚拟环境
    ├── scripts/
    │   └── main.py
    └── README.md
```

## 创建流程（必须按序）

### Step 1: 按场景选工具栈

参照上面的「强制优先级表」决定使用 Python 还是 npm。

### Step 2: 命名工具子目录

按用途命名，**kebab-case**：

| 工具用途 | 目录名示例 |
|----------|-----------|
| HTTP 指令测试（Python 优先） | `.tool/http-tester/` |
| esbuild 代码检查（npm） | `.tool/esbuild-checker/` |
| eslint 配置实验 | `.tool/eslint-lab/` |
| k6 性能测试 | `.tool/k6-runner/` |
| 临时 Python 脚本 | `.tool/python-helper/` |
| Markdown 检查器 | `.tool/md-lint/` |
| 协议生成器 | `.tool/proto-gen/` |

### Step 3: 创建工具目录

```bash
TOOL_NAME="http-tester"   # 或 "esbuild-checker"
mkdir -p ".tool/${TOOL_NAME}/scripts"
cd ".tool/${TOOL_NAME}"
```

---

## Python 工具流程（HTTP 测试推荐栈）

### 初始化 uv 环境

```bash
cd ".tool/http-tester"

# ① 建独立虚拟环境（uv 默认基于 python3）
uv venv

# ② 写依赖清单
cat > requirements.txt <<'EOF'
httpx>=0.27
pyjwt>=2.8
pydantic>=2.5
EOF

# ③ 装依赖（仅装到本工具的 .venv 内）
uv pip install -r requirements.txt

# 注：以上①-③等价于一步 uv add httpx pyjwt pydantic
#    但 requirements.txt 让依赖声明更显式（推荐）
```

> **对比旧式（禁止）**：
> - `python -m venv venv` → ✅ `uv venv`
> - `pip install -r requirements.txt` → ✅ `uv pip install -r requirements.txt`
> - 激活 venv 再运行 → ✅ `uv run python3 xxx.py`（自动激活）

### 写工具入口（HTTP 测试模板）

`.tool/http-tester/scripts/probe.py`：

```python
"""HTTP 指令测试器：构造请求 + 验证响应 + 报告状态。"""
import argparse
import json
import sys
from typing import Any

import httpx
import jwt  # PyJWT

BASE_URL = "http://localhost:8080"
AUTH_TOKEN = "your-secret-token-change-me"  # 与 .env 对齐


def build_headers(token: str | None = None) -> dict[str, str]:
    """构造带 JWT 头的请求头。"""
    payload = {"sub": "tester", "role": "admin"}
    jwt_token = jwt.encode(payload, AUTH_TOKEN, algorithm="HS256")
    return {
        "Authorization": f"Bearer {jwt_token}",
        "Content-Type": "application/json",
    }


def probe(path: str, method: str = "GET", body: dict | None = None) -> dict[str, Any]:
    """发请求并返回结构化结果。"""
    headers = build_headers()
    with httpx.Client(base_url=BASE_URL, headers=headers, timeout=10.0) as client:
        resp = client.request(method, path, json=body)
        return {
            "status": resp.status_code,
            "ok": resp.is_success,
            "elapsed_ms": int(resp.elapsed.total_seconds() * 1000),
            "body": resp.json() if resp.headers.get("content-type", "").startswith("application/json") else resp.text[:500],
        }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", help="API 路径，如 /api/v1/kv/list")
    parser.add_argument("--method", "-X", default="GET")
    parser.add_argument("--body", "-d", type=json.loads, default=None)
    args = parser.parse_args()

    result = probe(args.path, args.method, args.body)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
```

### 运行

```bash
cd ".tool/http-tester"

# ✅ 正确：uv run 自动激活 .venv，python3 显式
uv run python3 scripts/probe.py /api/v1/kv/list
uv run python3 scripts/probe.py /api/v1/user/login -X POST -d '{"username":"alice","password":"xxx"}'

# ❌ 禁止：直接 python 绕过 uv，可能用错解释器
# python scripts/probe.py /api/v1/kv/list
```

### 工具内子 .gitignore

`.tool/http-tester/.gitignore`：

```gitignore
.venv/
__pycache__/
*.pyc
.pytest_cache/
.env
```

---

## npm 工具流程（性能测试 / 构建工具栈）

### Step A: 初始化 package.json

```bash
cd ".tool/esbuild-checker"
npm init -y
# 必须手动编辑加 "private": true
```

### Step B: 安装依赖

```bash
cd ".tool/esbuild-checker"
npm install --save-dev esbuild       # 依赖装到本工具的 node_modules
```

### Step C: 写工具入口

```bash
mkdir -p src
cat > src/check.ts <<'EOF'
import * as esbuild from 'esbuild';
// ... 工具实现
EOF
```

### Step D: 配置 npm scripts（在工具目录下）

```json
{
  "name": "esbuild-checker",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "check": "ts-node src/check.ts",
    "build": "esbuild src/check.ts --bundle --platform=node --outfile=dist/check.js"
  },
  "devDependencies": {
    "esbuild": "^0.20.0",
    "ts-node": "^10.9.0"
  }
}
```

### Step E: 运行

```bash
cd ".tool/esbuild-checker"
npm run check
```

### 工具内子 .gitignore

`.tool/esbuild-checker/.gitignore`：

```gitignore
node_modules/
dist/
*.log
.tsbuildinfo
```

---

## 添加 README 索引（推荐）

`.tool/README.md`：

```markdown
# .tool/ 工具目录

| 工具 | 类型 | 用途 | 入口 |
|------|------|------|------|
| http-tester | Python | HTTP 指令/API 验证 | `cd .tool/http-tester && uv run python3 scripts/probe.py <path>` |
| esbuild-checker | npm | esbuild 类型/语法检查 | `cd .tool/esbuild-checker && npm run check` |
| k6-runner | npm + k6 | 性能/负载测试 | `cd .tool/k6-runner && npm run test:load` |
```

## 通用规则

| 规则 | 说明 |
|------|------|
| 每个工具独立 `package.json` / `requirements.txt` | 禁止共用，依赖列表互不污染 |
| 每个工具独立 `node_modules/` / `.venv/` | 默认就在工具目录下 |
| npm 工具必须 `private: true` | 防止误以为是可发布的包 |
| Python 工具用 `uv venv` 建 `.venv/` | 禁止系统全局 `pip install` |
| Python 运行必须 `uv run python3 xxx.py` | 禁止直接 `python`/`python3` 绕过 uv |
| Python 装包必须 `uv pip install` / `uv add` | 禁止裸 `pip install` |
| 工具入口必须在 `src/` 或 `scripts/` 下 | 禁止把脚本直接放 `.tool/{tool}/` 根 |
| 卸载工具 = 删除整个目录 | `rm -rf .tool/{tool-name}` 一键清理 |
| 在 `.tool/{tool}/` 内执行所有命令 | `cd` 进去再 `npm` / `uv`，严禁在项目根运行 |

## 反模式（绝对禁止）

| 反模式 | 后果 |
|--------|------|
| 项目根目录 `npm install xxx` | 污染根 `package.json` / `node_modules/` |
| 项目根目录 `pip install xxx` / `uv pip install xxx` | 污染系统 Python |
| 项目根目录直接写 `check.js` / `probe.py` | 散落脚本无法追踪 |
| 所有工具共用 `.tool/node_modules/` | 依赖耦合，升级一个工具牵连所有 |
| 在工具目录里改项目代码 | 工具与项目代码混杂 |
| 跳过 `private: true` | 误以为可发布，可能误推到 npm |
| Python 工具不走 `uv`（直接 `python/ python3/ pip install`） | 污染系统 Python 环境，解释器版本不保证 |
| Python 工具直接用 `python`（不写 `python3`） | 部分系统 `python` → Python 2，语法不兼容 |
| 用全局 `npx xxx` 不指定目录 | 仍会在当前目录产生缓存 |
| **HTTP 测试直接 `curl`** | 不可复用、无 JWT 头管理、无 JSON 格式化 |
| **启动完整服务只为测一个端点** | 浪费 5-30 秒启动时间 |

## 易错与坑点

| 错误 | 根因 | 预防 |
|------|------|------|
| `cd .tool/esbuild-checker` 失败 | 子目录未创建 | Step 3 强制 `mkdir -p` |
| `npm install` 仍在根目录执行 | 忘了 `cd` 进去 | 强调「在工具目录下运行」 |
| `uv pip install` 仍在根目录执行 | 忘了 `cd` 进去 | 强调在工具目录下运行 uv 命令 |
| 多个工具互相引用对方 `node_modules` / `.venv` | 路径写死 | 工具之间不共享依赖，每个工具自包含 |
| `package.json` 没设 `private: true` | `npm init -y` 默认无 private | 手动编辑补 `"private": true` |
| Python 工具没用 `uv run`，直接 `python3 xxx.py` | 用了系统环境而非 `.venv` | 一律 `uv run python3 xxx.py` |
| Python 工具裸 `pip install` | 装到全局 / 系统 Python | 在工具目录内 `uv pip install` |
| `.tool/` 没在 `.gitignore` | 工具被纳入版本控制 | 执行 `git-repo-cleanup` 模式 C |
| **HTTP 测试没传 JWT 头** | 直接 httpx.get 跳过鉴权 | 用 `build_headers()` 模板统一管理 |
| **httpx 默认 timeout 太短** | 长任务被截断 | 显式 `timeout=30.0` |
| **Windows 下 `python3` 不存在** | `python3` 在 cmd/PowerShell 上默认无 `python3` 别名 | Git Bash 下可用；PowerShell 用 `python`，但保持 `uv run python` |

## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 项目根 `npm install -D esbuild` | 根目录出现 `package.json`、`node_modules/`，与项目已有 `package.json` 冲突 | `cd .tool/esbuild-checker && npm install` |
| 项目根 `curl http://localhost:8080/api/v1/kv/list` | 不可复用、无 JWT、无 JSON 格式化、Authorization 头要每次手写 | `cd .tool/http-tester && uv run python3 scripts/probe.py /api/v1/kv/list` |
| 写 `tool/check.py` | 目录命名不符合 kebab-case，散落在根 | 创建 `.tool/python-helper/scripts/check.py` |
| 所有工具共用 `.tool/tools/package.json` | 工具之间依赖版本冲突 | 每个工具独立 `.tool/{name}/package.json` |
| Python 工具 `pip install --user` 或裸 `pip install` | 装到用户/系统目录，多项目互相干扰 | 在 `.tool/{name}/.venv/` 内用 `uv pip install` |
| Python 工具直接 `python scripts/probe.py` | 可能用错解释器版本（`python` → Python 2），依赖可能不在 .venv 中 | `uv run python3 scripts/probe.py` |
| `npx esbuild xxx` 在根目录 | esbuild 缓存写到根目录 `.npm/` | 显式 `cd .tool/esbuild-checker && npx esbuild` |
| HTTP 测试启完整 GoFrame 服务只为验一个端点 | 启动 5-30s，端口占用，状态污染 | httpx 直接构造请求，依赖 mock |
| 写 `jq -r '.data[] \| select(.meta.tags[] == "vip")'` | 嵌套表达式难调试 | Python `next(x for x in data if "vip" in x["meta"]["tags"])` |

## 验证清单

创建工具后必须验证：

- [ ] 工具目录为 `.tool/{tool-name}/`，**非** `tools/`、`tool/`、根目录
- [ ] **场景 → 工具栈匹配**：HTTP 测试用 Python（httpx）、性能测试用 npm（k6）
- [ ] npm 工具：在工具目录下有独立 `package.json`、`node_modules/`
- [ ] `package.json` 含 `"private": true`
- [ ] Python 工具：用 `uv venv` 建了 `.venv/`，依赖通过 `uv pip install` 装入
- [ ] Python 脚本入口在 `src/` 或 `scripts/` 子目录下
- [ ] **Python 执行满足两铁律**：解释器写 `python3`（非 `python`），运行/安装走 `uv run` 和 `uv pip install`
- [ ] 项目根目录的 `package.json`、`node_modules/` 未被新增/修改
- [ ] `git status` 不显示工具目录下的内容（`.tool/` 已在 `.gitignore`）
- [ ] 工具 README 说明了运行命令（`cd .tool/{name} && xxx`）

## 与现有 skill 的协作

| Skill | 协作方式 |
|-------|---------|
| `uv` | Python 环境与依赖全权交给 `uv`（`uv venv` / `uv run` / `uv pip install`），替代旧式 `pip` + `venv` |
| `git-repo-cleanup` 模式 C | 确保 `.tool/` 在 `.gitignore` 中 |
| `boot-work-flow` | 工作流 skill 的"启动命令"章节可引用 `.tool/{name}/` 路径 |
| `key_board_3` | 拆分本 skill 时，把 HTTP 测试 / npm 工具 / Python 工具各自沉淀为 reference |
| `k6-isolated-load-test` | HTTP 性能测试优先用 k6-isolated-load-test（已封装 k6 + .tool/k6） |
| `lottery-workflow` (ref) | 「多套风格并行 subagent + 文件投票」工作流；产物落到 `.tool/<test-name>/design/`，与 .tool 隔离规范一致 |

## 快速决策树

```
用户要解决问题 / 验证 / 调试
  │
  ├─ 是 HTTP / API 测试？
  │    ├─ 单次快速验证？   → .tool/http-tester/ (Python httpx + JWT，全程 uv run python3)
  │    ├─ 批量场景？       → .tool/http-tester/scripts/ 下加 .py
  │    └─ 性能压测？       → k6-isolated-load-test（强制走 k6）
  │
  ├─ 是 JSON / CSV / 数据处理？
  │    └─ → .tool/python-helper/ (Python pandas / json)
  │
  ├─ 是构建 / 类型检查 / 代码转换？
  │    └─ → .tool/esbuild-checker/ 或 .tool/eslint-lab/ (npm)
  │
  ├─ 是 shell 脚本 / 单文件工具？
  │    └─ → .tool/{tool-name}/{tool-name}.sh + chmod +x
  │
  ├─ 是 Docker 镜像 / 远程工具？
  │    └─ → .tool/{tool-name}/docker-compose.yml 或 README 说明
  │
  ├─ 是直接调项目二进制？
  │    └─ ⚠️ 先想能否用 Python / npm 脚本替代；不能替代时才启服务
  │
  └─ 是「多套风格并行生成让用户挑」的工作流（lottery）？
       └─ → .tool/<test-name>/design/ + 并行 subagent，详见 [[lottery-workflow]]
```
SKILL_EOF
mkdir -p "$SKILLS_BASE/tool-isolation/references"
cat > "$SKILLS_BASE/tool-isolation/references/lottery-workflow.md" << 'SKILL_EOF'
# Style Lottery — 风格抽奖生成器（自迭代版）

> 何时读：用户要求"一次性生成 N 套不同风格的文件/图标/设计让我挑"、"再生成几个备选"、多轮迭代挑选场景时。
>
> **本版的强制流程**：每次进入 lottery 都自检目录（保留/缺失 vs 目标数），缺则自动补足；同时把缺失样本视为负面投票、写入 `lottery-history.md`，作为后续 subagent 的"禁区"。不要等用户主动说"再生成"。
>
> 本文档原为 `styles-skill/references/lottery-workflow.md`，归档到 tool-isolation 后，路径约定改为 `.tool/<test-name>/design/`（与 .tool 隔离规范保持一致，所有产物落进隔离区）。

## 触发条件

当以下任一情况触发（AI 自动触发，不需要等用户开口）：

- 用户表达："生成 N 套不同风格的 …"、"来几个方案让我选"、"再生成一个/几个"
- 同一任务第二次及以上被调用，且输出目录中已有之前生成的文件
- AI 进入此任务时自动盘点目录，发现保留数 < 目标数
- 用户删除了某些文件（保留数下降，触发补差）

## 核心目标

用 subagent 并行产出多种风格的候选文件，让用户通过"删除不满意、保留满意"的方式投票。AI 根据保留下来的文件推断用户偏好，继续生成更符合口味的新方案。

## 输出约定

- **所有生成物放在 `.tool/<test-name>/design/` 目录下**（若用户未指定路径）。`.tool/` 由 `tool-isolation` 主文档管理，遵循隔离规范。
- 每个 subagent 负责一种独立风格，产出一个自包含文件（HTML/SVG/PNG/视频脚本/图片 prompt 等）。
- 文件名必须体现风格，例如 `icons_flat_illustration.html`。
- 单文件外层 HTML/SCSS/JS/CSS 不需要 npm 依赖时不必建 package.json；如需构建工具链，按 `tool-isolation` 的"npm 工具流程"补充。

## 调用流程（每次都走完整闭环）

> **核心：每次进入 lottery 都强制走「盘点 → 补足 → 归档负面样例 → 推断偏好 → 派 subagent」五步闭环。
> 不是用户主动再说"再生成"才走后续流程 —— 是 AI 每次都主动审一遍。**

### Step 1. 盘点当前目录

读取 `.tool/<test-name>/design/` 目录全部文件，对每个文件做**保留/缺失**判定：

| 文件状态 | 含义 |
|---|---|
| 当前在目录里 | **正面投票**（用户喜欢） |
| 在 `.trash/` 目录里 | **负面投票**（用户看了不满意，已归档删除） |
| 名字出现在 `lottery-history.md` 但目录里完全没有 | 历史上产出过、被彻底删除 |
| 当前目录无文件 | 首次调用，跳到 Step 4 |

`.trash/` 目录约定：

- `.tool/<test-name>/design/.trash/<style>-<timestamp>.html`
- **AI 不要主动删** —— 由用户删除文件后**人工**或**watcher 钩子**移动到此处
- 如果没有 `.trash/`，把所有"产出过但不在目录"的也视作负面投票样本

### Step 2. 计算「补差量」

```
目标数 N（首次默认 4，后续默认保留峰值）
  = max(当前保留数, 上次目标数)
补差量 = N - 当前保留数
```

| 情况 | 行为 |
|---|---|
| 保留数 < 目标数 | 补差量 > 0，必须补足 |
| 保留数 ≥ 目标数 | 补差量 = 0，记录"已饱和"；继续走 Step 3 推断偏好，**不主动补** |
| 目录空 | 首次生成 N 个，跳到 Step 4 |

> **关键：「不足」是默认触发条件** —— 不会出现"以为已经够了"停止迭代的情况。

### Step 3. 推断偏好 + 归档负面样例

**正面**（在目录里）：
- 命名规律、色板、复杂度、情绪、材质、构图、设计语言

**负面**（在 `.trash/` 或历史删除）：
- **必须显式记录到 `lottery-history.md`，供后续 subagent 避开**

`lottery-history.md` 模板：

```markdown
# Lottery History — <test-name>

## 偏好（来自保留样本）
- 色板：<palette>
- 复杂度：<simple / moderate / rich>
- 情绪：<mood>
- 共同特征：<特征 1>、<特征 2>、…

## 反面（来自 .trash/ 删除样本）
- <style-1>：<一句话描述为什么差>（删除于 <timestamp>）
- <style-2>：<一句话描述为什么差>（删除于 <timestamp>）

## 迭代记录
- v1：生成 N 个 → 用户删 X 个
- v2：基于偏好补 Y 个 → …
```

### Step 4. 派发 subagent

**派发数量**：

| 情况 | 派发数 |
|---|---|
| 首次（目录空） | N（默认 4） |
| 补差（保留数 < 目标数） | 补差量 |
| 已饱和 | **不派发**，但可在 SUMMARY 里输出 "当前 N 个样本已饱和，请用户先评估并删除不喜欢的" |
| 出现明确瓶颈（负面样本已收敛到 2-3 类相同失败模式） | 按「瓶颈探索」模式派 1-2 个，刻意跨风格族突围 |

**并行 subagent 提示词模板**：

```
Create a file at `<path>` (under .tool/<test-name>/design/) in the style of <style_name>.
Purpose: <purpose>.
Quantity: <quantity>.
Unifying constraints: <color palette / dimensions / tone / format>.
Preferred (from kept samples): <palette>, <complexity>, <mood>.
Avoid (from .trash/ samples): <forbidden-style-1>, <forbidden-style-2>.
Output: single self-contained file, no external assets.
Write the file using the Write tool; do not paste the content back to chat.
```

**子 agent 拆分原则**：

| 维度 | 规则 |
|---|---|
| 风格族 | 每个 agent 必须属于不同的视觉族（neumorphism / flat / illustration / 3D / editorial / monochrome …） |
| 与负面样本距离 | 越靠近负面样本越危险；越跨族越安全 |
| 正面样本兼容 | 必须遵守 `lottery-history.md` 的偏好约束 |

### Step 5. 更新 history + 汇总

- 在 `lottery-history.md` 追加本次迭代的派发数 / 目标数 / 实际保留数
- 用 3-5 行 SUMMARY 输出当前状态：

```
[Lottery v3] .tool/<test-name>/design/
保留 4 / 目标 4 (饱和)
偏好：暖色调 + editorial 留白 + serif 标题
负面：渐变彩色（已归档 .trash/）、emoji-icon
本次未生成；建议：删除不喜欢的以触发自动补充
```

---

## 第一份（v0）走法

> 当 `design/` 空且无 `lottery-history.md`，按首次生成走：

1. **捕获需求**

   - 目标文件类型（图标、页面、组件、海报、视频、图片…）
   - 每个文件内包含的元素数量
   - 需要同时产出几种风格（默认 4）
   - 统一的约束（色板、尺寸、主题、格式、语言等）

2. **并行调用 subagent**（每个 agent 一种截然不同的风格）

   提示词只传递：
   - 目标文件路径（在 `.tool/<test-name>/design/<file>`）
   - 风格名称与定义
   - 产出目标与数量
   - 统一约束
   - 输出格式要求
   - "写文件即可，不要把内容贴回聊天"

   不预设 SVG/HTML/PNG/视频/图片等具体格式；由当前任务类型决定。

3. **初始化 `lottery-history.md`**（偏好留空、反面留空、迭代记录 v0）

4. **汇总结果**（列出文件 / 风格 / 路径，不贴代码）

## 第 N+1 份走法（每次进入 lottery 都自动跑 Step 1-5）

触发条件（任一即可）：
- 用户复述「再生成几个」/「再换风格」/「想看更多」
- 用户删除了某些文件（目录现存数 < 目标数）
- AI 主动重新打开这个测试时（每次任务启动都自检一次）

⚠️ **关键：AI 不要等用户开口**。每次 lottery 入口都自检 Step 1-2，缺则补。

## 一致性强约束

无论首次还是后续，每次生成时都必须向 subagent 强调：

- 同一批产出必须使用统一的设计语言（色板、比例、情绪、材质等）。
- 新方案在核心视觉语言上要尽量与保留方案兼容。
- 不允许每个文件各自为政、风格割裂。

## 与 tool-isolation 主规范的衔接

| 场景 | 路径 | 说明 |
|---|---|---|
| 纯静态 HTML / SVG / 图片 prompt | `.tool/<test-name>/design/<file>` | 无需 package.json，直接写文件 |
| 需要构建工具（esbuild / vite / sass） | `.tool/<test-name>/{src,dist,package.json}` + `design/<file>` | 按 `tool-isolation` 的 npm 工具流程建独立 `package.json`，`design/` 放产物 |
| 需要后端 / mock 数据 | `.tool/<test-name>/scripts/<file>.py` | 按 `tool-isolation` 的 Python 工具流程走 `uv venv` + `uv run python3` |
| 需要 CSS 预处理 | 嵌入 HTML 内 `<style>`，或 `.tool/<test-name>/design/<file>.css` | 不引入额外构建 |

> 关键：**路径统一以 `.tool/` 开头**，与项目代码、Git、Flutter 工程完全隔离。

## 自检脚本（建议）

`.tool/<test-name>/scripts/lottery-status.py` 一行命令即可查：

```bash
uv run python3 -c "
import os, sys
d = '.tool/<test-name>/design'
kept = [f for f in os.listdir(d) if not f.startswith('.')] if os.path.isdir(d) else []
trash = [f for f in os.listdir(d + '/.trash') if not f.startswith('.')] if os.path.isdir(d + '/.trash') else []
N = 4
gap = N - len(kept)
print(f'保留: {len(kept)}/{N}  缺失: {gap}  负面归档: {len(trash)}')
print('kept   :', sorted(kept))
print('trashed:', sorted(trash))
sys.exit(0 if gap == 0 else 1)
"
```

- exit 0 = 饱和，可以休息
- exit 1 = 缺，必须补足（让脚本自己决定是否触发 lottery）

## 错误案例

| 错误操作                         | 实际后果                           | 正确做法                         |
| -------------------------------- | ---------------------------------- | -------------------------------- |
| 后续调用时重新询问"你要什么风格" | 打断用户投票流程，显得没有记忆     | 直接检查保留文件并推断偏好       |
| 生成新方案时不考虑已删除的文件   | 可能再次产出用户讨厌的风格         | 删除记录即负面反馈，应主动规避，写入 `lottery-history.md` |
| 让 subagent 把代码/内容贴回聊天  | 上下文爆炸，用户无法直观比较       | 要求 agent 只写文件并确认路径    |
| 不检查目录就生成，导致风格重复   | 用户看到与保留方案雷同的新方案     | 列出目录内容，优先生成差异化风格 |
| 忽略设计语言一致性约束           | 同一批产出像来自不同项目           | 每次提示词都加入统一约束要求     |
| 把产物直接写到 `design/` 或项目根  | 污染项目目录，绕过 .tool 隔离       | 一律写到 `.tool/<test-name>/design/` |
| **AI 等用户说"再生成"才迭代**     | 多轮迭代靠用户记忆提醒，体感差     | **每次 lottery 入口都强制走 Step 1-5 自检闭环** |
| **删了文件但 AI 没记录**          | 下次又产出被删过的同款             | 删除立刻归档 `.trash/` + 更新 `lottery-history.md` |
| **补差量已饱和但 AI 仍继续派发**  | 目录臃肿，用户疲劳                 | 补差=0 时显式说明"已饱和"，暂停派发，等用户动作 |

## 提示词模板（仅供参考，非强制格式）

> 以下只是面向"图标"场景的示例，用于展示如何向 subagent 传递关键信息。实际任务可能是海报、视频脚本、图片 prompt 等，格式和约束会随之变化。

### 首次生成单个 agent 的提示词示例

```
Create a file at `<path>` (under .tool/<test-name>/design/) in the style of <style_name>.
Purpose: <purpose>.
Quantity: <quantity>.
Unifying constraints: <color palette / dimensions / tone / format>.
Output: single self-contained file, no external assets.
Write the file using the Write tool; do not paste the content back to chat.
```

### 后续生成提示词示例（基于偏好）

```
The user has kept: <list_of_files>.
Inferred preferences: <palette>, <complexity>, <mood>.
Generate a NEW style at `<path>` that is different from kept styles but compatible with the inferred preferences.
Respect the unifying constraints identified from kept files.
```
SKILL_EOF

# ===== skill: intent-capture-discuss =====
mkdir -p "$SKILLS_BASE/intent-capture-discuss/."
cat > "$SKILLS_BASE/intent-capture-discuss/SKILL.md" << 'SKILL_EOF'
---
name: intent-capture-discuss
description: 当用户希望整理需求、明确目的、描述问题，或提到"生成文档"、"整理意图"、"明确现象"、"讨论项目结构"、"分析完成程度"、"梳理方案"、"对比参考实现"时触发 通过多轮对话收集需求、分析项目现状、对比外部参考实现，最终在项目目录的 .claude/repo/_self/ 下按主题生成结构化文档。纯文档产出，严禁修改任何代码。
---
# 🔴 铁律（最高优先级，不可违反）

| # | 规则                                                   | 说明                                                                                                                                                                                                                                  |
| - | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | **必须在项目目录内创建**                         | 所有文件**仅限**当前项目根目录下的 `.claude/repo/_self/` 路径内。绝对不写到项目外任何位置、不写到 home 目录、不写到系统临时目录。                                                                                             |
| 2 | **只做分析和文档编写，绝对不修改代码**           | 不创建、不编辑、不删除、不重命名任何源代码文件（包括但不限于`.py .ts .js .vue .go .rs .java .cpp .css .html .json .yaml .toml` 等）。不执行任何 `git commit`、`git add`、构建、测试命令。本 skill 的唯一产出物是 `.md` 文档。 |
| 3 | **版本不覆盖**                                   | `project/` 下每次生成新文件（含现状文档与 `compare_*` 比较文档），绝不覆写已有版本。旧文档只读。                                                                                                                                                                         |
| 4 | **现状/盘点/比较类文档 不要给出建议**，只给当前现象与问题 | 约束对象是「记录现状」的文档（`project/` 的现状与 `compare_*`、`intent/` 的常规意图文档 2a）：如实描述"现在是什么样、什么问题"，不写"应该怎么做"。**例外**：`intent/` 下的 Design 预测设计文档（2c）明确承载设计方案与建议——它讨论"打算怎么做"，是意图的延伸，不受本条约约束。                                                                                                                                                                                                                                       |

> ⚠️ 若 AI 在执行过程中有任何偏离上述规则的倾向，用户应立即叫停。AI 自身也应在每次文件操作前自检：目标路径是否在 `.claude/repo/_self/` 内？是否只涉及 `.md` 文件？

## 一、目录结构约定

所有产出**严格限定**在当前项目根目录下的 `.claude/repo/_self/` 中：

{项目根目录}/
└── .claude/repo/_self/
    └── {topic-slug}/                  # 主题目录，kebab-case
        ├── intent/                    # 原始意图 + 多版本设计稿（为什么做、打算怎么做）
        │   ├── {semantic-name}-{YYYY-MM-DD}-intent.md       # 常规意图文档
        │   ├── {design-name}-{YYYY-MM-DD}-v1-design.md      # Design 预测设计文档（设计想法 + 版本迭代）
        │   ├── {design-name}-{YYYY-MM-DD}-v2-design.md      # 同一想法的迭代版本，旧版保留
        │   └── ...
        └── project/                   # 解释当前版本的项目现状（扁平：全部平铺，不建子目录）
            ├── {YYYY-MM-DD}-v1-status.md       # 现状分析，首次产出
            ├── {YYYY-MM-DD}-v2-status.md       # 现状分析，迭代更新
            ├── {module-slug}-{YYYY-MM-DD}-v1-concepts.md   # 模块概念阐述，首次产出
            ├── {module-slug}-{YYYY-MM-DD}-v2-concepts.md   # 概念阐述迭代，旧版保留
            ├── compare_{subject}-{YYYY-MM-DD}-v1-status.md   # 比较文档（外部项目实现 vs 本项目实现程度）
            └── ...

**命名规则：**

- 主题名：从用户描述中提炼，小写 + 连字符（`docx-thesis-style-pipeline-design`）
- 命名总则：`{语义短名}-{YYYY-MM-DD}[-v{N}]-{类型后缀}.md`——类型后缀见名知意（`intent` / `design` / `concepts` / `status`）；文档**全部扁平平铺**，不建更深层子目录
- Project 现状文档：`{YYYY-MM-DD}-vN-status.md`（N 自增，从 1 开始）
- 模块概念阐述文档：`{module-slug}-{YYYY-MM-DD}-vN-concepts.md`（扁平放 project/ 下；module-slug 为模块语义短名 kebab-case；N 按 module 各自独立自增，旧版保留）
- Project 比较文档：`compare_{subject}-{YYYY-MM-DD}-vN-status.md`（`compare_pipeline_arch-2026-08-07-v1-status.md`）；N 按 subject 各自独立自增——对比的是**外部项目实现**（开源项目等的方法）与**本项目实现该主题的程度**，本身也是现状快照，故同用 `-status` 后缀
- Intent 常规意图文档：`{semantic-name}-{YYYY-MM-DD}-intent.md`（如 `initial-request-2026-08-14-intent.md`、`refined-goal-2026-08-14-intent.md`）
- Design 预测设计文档：`{design-name}-{YYYY-MM-DD}-v{N}-design.md`（如 `casbin-hybrid-2026-08-14-v1-design.md`）；`design-name` 为该设计想法的语义化短名（kebab-case）；N 从 1 自增，**同一 design-name 的迭代不覆盖旧版**；不同想法用不同 design-name 并存，可互相引用对比

> **目录分工原则**：`intent/` 存**原始意图 + 多个版本的设计稿**（为什么做、打算怎么做）；`project/` 存**对当前版本项目现状的解释**（现在是什么样：现状分析、模块概念阐述、横向比较）。整个 skill 的原则是**讨论落文档**——多轮对话中形成的理解与决定，最终都要沉淀为上述结构化文档。
>
> 比较文档归属 `project/` 而非 `intent/`：compare 对比的是**外部项目的实现方法**（开源库、参考仓库）与**本项目当前实现该主题的程度**，属于现状盘点，不是意图表达，也**不是对比设计稿**（多份 design 稿之间的取舍走 2c 的"想法对比"，不产出 compare 文档）。因此它同样受版本号约束，旧版只读保留。

## 二、文档类型

### 2a · Intent 常规意图文档 `intent/{semantic-name}-{YYYY-MM-DD}-intent.md`

**用途：** 记录为什么做、做什么、约束是什么。

**模板：**

markdown
Intent: {标题}

背景与动机

{为什么提出这个需求，解决什么问题}

目标

• {目标 1}

• {目标 2}

约束与边界

• {约束 1}

• {约束 2}

关键决策

决策点 结论 理由

... ... ...

待定问题
{问题 1}

{问题 2}

---

### 2b · Project 比较文档 `project/compare_{subject}-{YYYY-MM-DD}-vN-status.md`（用户可选）

**用途：** 针对当前主题，把**外部项目的实现方法**（开源项目、参考仓库怎么做这个主题）与**本项目当前实现该主题的程度**逐维对照——别人用什么方法、实现到什么程度，我们实现到什么程度、差在哪。比较的对象是外部实现与本项目现状，**不是设计稿**（多份 design 稿之间的取舍属于 2c 的想法对比，不产出 compare 文档）。所以它放在 `project/` 下并带版本号，每次重新比较生成新版本，旧版保留不删不改。

调用 /project-index-reader   skill,分析 ".claude/repo"存在的项目 对他们进行分析 从而进行比较,不需要联网,一般都有现成的仓库

**触发方式：**

- 用户说"看看别人怎么做的"、"对比一下 xxx 的实现"、"找几个参考项目"
- 或在讨论中 AI 主动提议："要不要看看同类项目是怎么处理的？"

**表格使用原则：**

- 至少包含 2 个对比对象 + 1 列"本项目现状"
- 维度由 AI 与用户讨论确定（通常 4~7 个维度，不宜过多）
- 对比要具体到技术选型、API 设计、数据流，而非泛泛而谈
- "本项目现状"一列必须基于实际扫描到的代码结构填写，不写期望、不写规划

### 2c · Design 预测设计文档 `intent/{design-name}-{YYYY-MM-DD}-v{N}-design.md`（设计想法讨论载体）

**用途：** 记录一个**具体的、预测性的系统设计**（架构骨架、数据流、关键决策、验收标准、待拍板决策），用于设计阶段的讨论与迭代。它不描述"现在是什么样"（那是 `project/` 的职责），而是描述"打算怎么做"——对未来实现的预测。它是 2a 意图的延伸，专门承载各种设计想法的记录与反复迭代。

**触发方式：**

- 用户在讨论中提出设计方案 / "这个方案怎么设计" / 给出架构想法
- 多轮讨论中出现**多个候选设计**，需要各自记录、互相比较
- 设计在讨论中被推翻/调整，需要产出新版本

**版本语义（版本号 = 讨论迭代的刻度）：**

| 要素 | 规则 |
| --- | --- |
| 命名 | `{design-name}-{YYYY-MM-DD}-v{N}-design.md`，`design-name` 为 kebab-case（如 `casbin-hybrid`） |
| 版本自增 | 同一 design-name 每次迭代产出 `v{N+1}`，**旧版保留不删不改**（与 `project/` 铁律一致） |
| 并行想法 | 不同想法用不同 `design-name` 并存（如 `filter-sql-2026-08-16-v1-design.md` 与 `casbin-2026-08-16-v1-design.md` 可同时存在），用于"各种想法的讨论"与横向对比 |
| 试验/测试版本 | 早期版本头部标 `状态: 试验`，并在「本版要验证的假设」写明该版想验证什么；成熟后改标 `候选` / `已采纳` |
| 落地后闭环 | 设计落地后，可选生成 `project/{design-name}-design-vs-actual-{YYYY-MM-DD}-status.md` 对照审计（预测 vs 实际），回到 Phase 2 推动下一轮迭代 |

**模板（节结构）：**

Intent: {标题}

> **Date:** {YYYY-MM-DD}
> **Topic:** {topic-slug}
> **类型:** intent doc(预测设计)
> **版本:** v{N}（相对上一版：新增/推翻/保留了什么）
> **状态:** 试验 / 候选 / 已采纳
> **核心问题:** {一句话：这个设计要解决什么}

本版要验证的假设

{该设计想验证的核心假设；试验版本必填}

一、设计原则

| # | 原则 | 体现 |
| - | --- | --- |
| 1 | ... | ... |

二、模块拆分

{新增/修改/保留的文件与职责；用代码块画目录树}

三、数据流（关键场景）

{每个场景：入口 → 中间件 → 服务 → 数据层 → 出口；附关键代码骨架}

四、关键决策（含选型说明）

{每个决策：结论 + 理由 + 备选；选型坑要写"为什么不能用 X"}

五、接口 / SQL / 代码骨架

{签名、SQL、用法示例}

六、职责边界

{各关注点由谁负责，防职责蔓延}

七、改动范围（影响面）

| 模块 | 现状 | 改后 | 影响 |
| --- | --- | --- | --- |
| ... | ... | ... | ... |

八、迁移 / 实施路径

{分几步 ship，每步可独立验收}

九、验收标准

| # | 验证项 | 方法 |
| - | ------ | ---- |
| 1 | ... | ... |

十、待用户拍板的决策

| # | 决策 | 推荐 |
| - | ---- | ---- |
| 1 | ... | ... |

十一、参考

{现状文档 / 比较文档 / 相关代码行号}

**设计指导（怎么写好一份预测设计文档）：**

1. **聚焦一个想法**：一份 design 文档只承载一个设计想法（一个 `design-name`）。有第二个想法就另开一份，别混在同一份里。
2. **先写假设再写结论**：「本版要验证的假设」放在最前——试验版本尤其要写明想验证什么，落地后才能对照检验。
3. **决策给"推荐 + 理由 + 备选"**：每个关键决策写清推荐项、为什么、备选是什么，不要只写结论。
4. **写"预测"，不写"现状"**：设计文档描述打算怎么做；当前项目长什么样交给 `project/` 现状文档。改动范围表里的"现状"列只引用实际代码行号，不臆测。
5. **可验收**：验收标准必须落到具体验证动作（测试、命令、矩阵），不写"实现正确即可"。
6. **版本差异显式化**：每个新版本头部标注相对上一版新增/推翻/保留了什么，让迭代历史可追溯。
7. **想法对比**：多个候选设计用多个 `design-name` 并存，需要对比时引用对方（如"与 `xxx-{YYYY-MM-DD}-v1-design.md` 相比，本方案…"）。

### 2d · 模块概念阐述文档 `project/{module-slug}-{YYYY-MM-DD}-vN-concepts.md`（扁平，无子目录）

**用途：** 当讨论的本质是**项目分析**——把某模块/子系统中形成的概念模型与命名体系（自定义概念如 slot，布局内部模块如 cell/item）沉淀为概念阐述文档，让用户把握该模块的整体框架，并知道后续提问如何准确指称各实体。

**触发方式：**

- 用户说"总结这个模块的概念"、"梳理我们聊的术语/指称"、"生成指称表"
- 或由 history-collect skill 委托（见其"特殊模式：项目分析"段）

**完整模板、两层指称体系（L1 对话级概念 / L2 布局模块）、常见坑见 [[概念阐述文档]]。**

核心约束：概念阐述属于**现状盘点**性质——概念名必须是项目/对话中实际使用的原名，不自创同义词；未命名实体单独列出并建议命名，不虚构。

## 三、工作流程

### Phase 1：主题确认与目录初始化

1. 从用户输入中提炼核心主题，提议 `topic-slug`，用户确认
2. 在**当前项目目录**下确保路径存在：
   - `.claude/repo/_self/{topic-slug}/project/`
   - `.claude/repo/_self/{topic-slug}/intent/`
3. 若 `project/` 已有文件，列出「现状文档」「比较文档」的版本历史；若 `intent/` 已有 design 文档，列出各 `design-name` 的版本历史；分别告知本次将生成 `v{N+1}`
4. **自检**：确认创建路径以 `.claude/repo/_self/` 开头，否则中止并报错

### Phase 2：多轮讨论

**① 分析现状**（只读扫描，不改动任何文件）

- 扫描项目中与主题相关的目录和文件
- 给出结构概览

**② 逐维探讨**（按需选取）：

| 维度       | 内容                         |
| ---------- | ---------------------------- |
| 背景与动机 | 为什么做                     |
| 目标定义   | 完成标准                     |
| 现状盘点   | 已有哪些、缺哪些             |
| 约束条件   | 技术栈/时间/兼容性           |
| 方案方向   | 可能的实现路径（仅讨论）     |
| 设计方案   | → 触发 `intent/{design-name}-{YYYY-MM-DD}-v{N}-design.md`；候选想法各自记录、迭代、对比 |
| 参考对比   | → 触发 `project/compare_*`：外部项目实现（开源等）vs 本项目实现程度 |
| 优先级     | 先后次序                     |
| 风险与待定 | 不确定项                     |

**③ 设计方案讨论**（用户想讨论"怎么做"时）：
- 每出现一个**设计想法**，为其分配一个 `design-name`
- 想法被调整/推翻 → 产出新版本 `v{N+1}`（旧版保留）
- 多个候选想法并存 → 各归各的 `design-name`，可互相引用对比
- 明确标注版本状态：试验（想验证假设）/ 候选 / 已采纳

**④ 阶段性总结** — 每 2~3 轮输出小结，请用户确认

**⑤ 完成度评估** — 逐项给百分比 + gap 说明

### Phase 3：文档生成

用户发出"可以了 / 生成文档 / 确认 / 总结"信号后执行。

| 文档类型     | 输出路径                                                                    |
| ------------ | --------------------------------------------------------------------------- |
| Intent 意图  | `.claude/repo/_self/{topic}/intent/{semantic-name}-{YYYY-MM-DD}-intent.md`            |
| Design 预测设计 | `.claude/repo/_self/{topic}/intent/{design-name}-{YYYY-MM-DD}-v{N}-design.md`     |
| Project 现状 | `.claude/repo/_self/{topic}/project/{date}-v{N}-status.md`              |
| Project 比较 | `.claude/repo/_self/{topic}/project/compare_{subject}-{date}-v{N}-status.md` |
| 模块概念阐述 | `.claude/repo/_self/{topic}/project/{module}-{date}-v{N}-concepts.md`     |

生成后展示摘要 + 文件路径，询问是否需调整。

### Phase 4：迭代

- 用户要求修改 → 回到 Phase 2 → 生成新版本（`v{N+1}`），**旧版保留不删不改**。
- 对已落地的设计 → 可选生成 `project/{design-name}-design-vs-actual-{YYYY-MM-DD}-status.md` 对照审计（预测 vs 实际），对照结果回到 Phase 2 推动下一轮设计迭代。

## 五、自检清单（每次生成前 AI 必须内心确认）

☐ 目标路径是否在 当前项目根目录/.claude/repo/_self/ 之内？
☐ 是否只涉及 .md 后缀的文件？
☐ 是否没有触碰任何源码文件？
☐ project/ 与 intent/ 下是否是全新文件名（不覆盖旧版）？
☐ 若是 design 文档，命名是否满足 `{design-name}-{YYYY-MM-DD}-v{N}-design.md` 且版本自增？
☐ 若是 现状/盘点/比较 文档，是否只写当前现象与问题、没有混入设计建议？
☐ 若是 模块概念阐述文档，文件名是否为 `project/{module-slug}-{YYYY-MM-DD}-vN-concepts.md`（扁平无子目录）且概念名用的是实际原名？

## 引用索引（按需加载）

| ref | 何时读取 | 路径 |
| --- | --- | --- |
| [[概念阐述文档]] | 生成 2d 模块概念阐述文档时（必读） | references/概念阐述文档.md |
SKILL_EOF
mkdir -p "$SKILLS_BASE/intent-capture-discuss/references"
cat > "$SKILLS_BASE/intent-capture-discuss/references/概念阐述文档.md" << 'SKILL_EOF'
w

# 概念阐述文档 — 2d 模块概念阐述的执行指导

> 本 ref 是 intent-capture-discuss 文档类型 2d（`project/{module-slug}-{YYYY-MM-DD}-vN-concepts.md`，扁平无子目录）的必读执行指导。方法论源自 history-collect skill（对话概念框架沉淀），两者共用同一套两层指称体系。

## 定位

当讨论的本质是**项目分析**——用户与 AI 在多轮对话中围绕某模块形成了一套概念模型与命名体系，但名字只活在对话历史里。本文档类型把这套体系沉淀为 `_self/{topic}/project/` 下的扁平文件 `{module-slug}-{YYYY-MM-DD}-vN-concepts.md`，版本不覆盖、旧版只读（铁律 3）。

## 两层指称体系（核心判据）

概念分两层，**永远分开总结，不混一张表**：

| 层                           | 是什么                                      | 例子                     | 判据                                                      |
| ---------------------------- | ------------------------------------------- | ------------------------ | --------------------------------------------------------- |
| **L1 模型级概念**      | 项目/对话中提出或采纳的模型、机制、架构概念 | slot、pipeline、registry | 脱离具体界面也存在，是抽象模型的一部分                    |
| **L2 布局/视图级模块** | 某个具体布局或视图内部被指称的组成部分      | cell、item、panel、lane  | 依赖具体环境（某个布局/组件树内部），出了那个视图就没意义 |

判定口诀：**换个界面它还成立吗？成立 → L1；不成立 → L2。**

## 文档模板

```markdown
# {module-slug} 概念阐述（{YYYY-MM-DD} v{N}）

> **Topic:** {topic-slug}
> **类型:** project doc(模块概念阐述)
> **版本:** v{N}（相对上一版：新增/修正/保留了什么）

## 1. 整体框架
一段话 +（可选）层级图/mermaid，说明该模块各概念如何组成整体。
让读者 30 秒内把握"这个模块的模型长什么样"。

## 2. L1 概念名称表
| 概念名 | 一句话定义 | 首次提出语境 | 与其他概念的关系 |
| --- | --- | --- | --- |
| slot | ... | 讨论数据分发时提出 | 由 registry 管理，注入到 cell |

## 3. 指称映射表（用户怎么说话 → 指什么）
| 用户以后说 | 实际指 | 别再用的模糊说法 |
| --- | --- | --- |
| "slot" | 数据占位/分发单元 | "那个中心的东西" |
| "主布局" | HomeView 的 grid 区域 | "那个大格子" |

## 4. L2 布局内部模块指称表（按布局/视图分组）
### {布局名，如 MainLayout / HomeView}
| 模块名 | 是什么 | 父子关系 |
| --- | --- | --- |
| cell | grid 的最小单元 | grid > cell |
| item | cell 内的内容条目 | cell > item |

## 5. 未命名实体（待命名）
| 描述 | 出现位置 | 建议命名 |
| --- | --- | --- |
| "每次刷新触发的重算过程" | 对话第 N 轮 | recompute-cycle |
```

## 执行要点

1. **先框架后清单**：先写整体框架让读者有全局感，再落到逐条命名。
2. **概念名必须用项目/对话中的实际原名**，不自创同义词；多个叫法的选一个为主、其余记"又称"。
3. **指称映射表是本文档类型的灵魂**——每行消灭一个"那个中心的东西"式模糊指称。
4. **L2 必须挂靠具体布局/视图名**：cell/item 这类词在不同布局里指不同东西。
5. **未命名实体不是可选项**：没名字的实体就是未来模糊指称的来源，必须单列并给建议命名。
6. 生成后把"指称映射表"精简版直接贴在回复里给用户。
7. 受铁律 4 约束：概念阐述属现状盘点，**概念以实际使用为准，不写"应该叫什么"的重构建议**；确有命名改进想法，记录在"未命名实体/建议命名"列，正式方案走 2c design 文档。

## 常见坑

| 坑                     | 后果                                | 预防                              |
| ---------------------- | ----------------------------------- | --------------------------------- |
| L1/L2 混在一张表       | "cell" 不知道是模型概念还是界面模块 | 换界面判据先分层                  |
| 自创概念名替代原名     | 用户说的名字和文档对不上            | 原名优先，多叫法记"又称"          |
| 跳过整体框架直接列表格 | 读者有名词但没有全局模型感          | 模板第 1 节不可省                 |
| L2 不写所属布局        | 同名模块跨布局歧义                  | 每个 L2 小节以布局名开头          |
| 混入重构/设计建议      | 违反铁律 4（现状文档不给建议）      | 命名建议只进"待命名"列，方案走 2c |
| 覆盖旧版本             | 违反铁律 3                          | 每次`v{N+1}` 新文件，旧版只读   |

## 与 history-collect 的协作

- 独立对话的概念沉淀（无项目上下文）→ 由 history-collect 自行处理，产物在 `.claude/history/`。
- **项目内**模块概念阐述 → 走本文档类型（2d），产物为 `.claude/repo/_self/{topic}/project/` 下的扁平文件 `{module-slug}-{YYYY-MM-DD}-vN-concepts.md`，并遵守本 skill 全部铁律。
SKILL_EOF

# ===== skill: find-skills =====
mkdir -p "$SKILLS_BASE/find-skills/."
cat > "$SKILLS_BASE/find-skills/SKILL.md" << 'SKILL_EOF'
---
name: find-skills
description: Helps users discover and install agent skills when they ask questions like "how do I do X", "find a skill for X", "is there a skill that can...", or express interest in extending capabilities. This skill should be used when the user is looking for functionality that might exist as an installable skill.
---

# Find Skills

This skill helps you discover and install skills from the open agent skills ecosystem.

## When to Use This Skill

Use this skill when the user:

- Asks "how do I do X" where X might be a common task with an existing skill
- Says "find a skill for X" or "is there a skill for X"
- Asks "can you do X" where X is a specialized capability
- Expresses interest in extending agent capabilities
- Wants to search for tools, templates, or workflows
- Mentions they wish they had help with a specific domain (design, testing, deployment, etc.)

## What is the Skills CLI?

The Skills CLI (`npx skills`) is the package manager for the open agent skills ecosystem. Skills are modular packages that extend agent capabilities with specialized knowledge, workflows, and tools.

**Key commands:**

- `npx skills find [query]` - Search for skills interactively or by keyword
- `npx skills add <package>` - Install a skill from GitHub or other sources
- `npx skills check` - Check for skill updates
- `npx skills update` - Update all installed skills

**Browse skills at:** https://skills.sh/

## How to Help Users Find Skills

### Step 1: Understand What They Need

When a user asks for help with something, identify:

1. The domain (e.g., React, testing, design, deployment)
2. The specific task (e.g., writing tests, creating animations, reviewing PRs)
3. Whether this is a common enough task that a skill likely exists

### Step 2: Check the Leaderboard First

Before running a CLI search, check the [skills.sh leaderboard](https://skills.sh/) to see if a well-known skill already exists for the domain. The leaderboard ranks skills by total installs, surfacing the most popular and battle-tested options.

For example, top skills for web development include:
- `vercel-labs/agent-skills` — React, Next.js, web design (100K+ installs each)
- `anthropics/skills` — Frontend design, document processing (100K+ installs)

### Step 3: Search for Skills

If the leaderboard doesn't cover the user's need, run the find command:

```bash
npx skills find [query]
```

For example:

- User asks "how do I make my React app faster?" → `npx skills find react performance`
- User asks "can you help me with PR reviews?" → `npx skills find pr review`
- User asks "I need to create a changelog" → `npx skills find changelog`

### Step 4: Verify Quality Before Recommending

**Do not recommend a skill based solely on search results.** Always verify:

1. **Install count** — Prefer skills with 1K+ installs. Be cautious with anything under 100.
2. **Source reputation** — Official sources (`vercel-labs`, `anthropics`, `microsoft`) are more trustworthy than unknown authors.
3. **GitHub stars** — Check the source repository. A skill from a repo with <100 stars should be treated with skepticism.

### Step 5: Present Options to the User

When you find relevant skills, present them to the user with:

1. The skill name and what it does
2. The install count and source
3. The install command they can run
4. A link to learn more at skills.sh

Example response:

```
I found a skill that might help! The "react-best-practices" skill provides
React and Next.js performance optimization guidelines from Vercel Engineering.
(185K installs)

To install it:
npx skills add vercel-labs/agent-skills@react-best-practices

Learn more: https://skills.sh/vercel-labs/agent-skills/react-best-practices
```

### Step 6: Offer to Install

If the user wants to proceed, you can install the skill for them:

```bash
npx skills add <owner/repo@skill> -g -y
```

The `-g` flag installs globally (user-level) and `-y` skips confirmation prompts.

## Common Skill Categories

When searching, consider these common categories:

| Category        | Example Queries                          |
| --------------- | ---------------------------------------- |
| Web Development | react, nextjs, typescript, css, tailwind |
| Testing         | testing, jest, playwright, e2e           |
| DevOps          | deploy, docker, kubernetes, ci-cd        |
| Documentation   | docs, readme, changelog, api-docs        |
| Code Quality    | review, lint, refactor, best-practices   |
| Design          | ui, ux, design-system, accessibility     |
| Productivity    | workflow, automation, git                |

## Tips for Effective Searches

1. **Use specific keywords**: "react testing" is better than just "testing"
2. **Try alternative terms**: If "deploy" doesn't work, try "deployment" or "ci-cd"
3. **Check popular sources**: Many skills come from `vercel-labs/agent-skills` or `ComposioHQ/awesome-claude-skills`

## When No Skills Are Found

If no relevant skills exist:

1. Acknowledge that no existing skill was found
2. Offer to help with the task directly using your general capabilities
3. Suggest the user could create their own skill with `npx skills init`

Example:

```
I searched for skills related to "xyz" but didn't find any matches.
I can still help you with this task directly! Would you like me to proceed?

If this is something you do often, you could create your own skill:
npx skills init my-xyz-skill
```
SKILL_EOF

echo "✔ 已安装 3 个 skill / 5 个文件 -> $SKILLS_BASE"
