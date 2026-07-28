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
