# E2E 闭环控制器 — 后端启动 + 客户端黑盒测试 + 合并时间戳日志

> 何时读：需要 "启后端 → 检查 health → 跑客户端黑盒测试 → 拿到一份日志" 的端到端闭环时触发（"跑一遍前后端联调"、"启动服务再测客户端"、"生成 时间.log 日志"、"重跑控制器拿日志看结果"）。
> 配合 
>
> `tool-isolation`
>
>  主文档的 
>
> `.tool/`
>
>  隔离规范：控制器脚本落在 
>
> `.tool/e2e-loop/scripts/`
>
>  下，日志输出到 
>
> `.tool/e2e-loop/logs/{时间}.log`
>
> ，不进入项目源码。

## 触发场景



* "把后端跑起来，再跑客户端测试，日志都记下来"

* "启服务 → 等 health → 跑主文件的 python 客户端黑盒测试"

* "两个进程的输出合到一块，生成 时间.log"

* "以后我只需要重跑这个控制器看日志，就能知道前后端是否闭环"

## 闭环语义（agent 怎么用）

**控制器是唯一入口**：agent 每轮只做「执行控制器 → 读最新 log → 判断 → 修复 → 再执行」。



* 控制器负责：启动后端、重定向输出、健康检查、启动客户端、合并日志、清理进程、返回退出码

* 前后端任何一端的输出都进**同一份时间戳日志**，排查时只读一份文件即可还原整个闭环现场

## 与 tool-isolation 主规范的衔接



| 场景      | 路径                                     | 说明                                         |
| ------- | -------------------------------------- | ------------------------------------------ |
| 控制器脚本   | `.tool/e2e-loop/scripts/controller.py` | 按 Python 工具流程：`uv venv` → `uv run python3` |
| 日志产物    | `.tool/e2e-loop/logs/{时间}.log`         | `logs/` 加入工具子 `.gitignore`                 |
| 客户端黑盒入口 | 项目主文件（客户端脚本 /main.py）                  | `CLIENT_CMD` 指向它                           |

## 参考实现骨架

`.tool/e2e-loop/scripts/controller.py`（全部 stdlib，零额外依赖）：



```
"""端到端闭环控制器：启动后端 → 健康检查 → 客户端黑盒 → 合并时间戳日志。"""

import datetime

import subprocess

import sys

import time

import urllib.request

from pathlib import Path

\# --- 按项目修改 ---

BACKEND\_CMD = \["uv", "run", "python3", "-m", "app.main"]      # 后端启动命令

CLIENT\_CMD = \["uv", "run", "python3", "main.py"]              # 客户端黑盒测试入口（主文件）

HEALTH\_URL = "http://localhost:8080/health"                   # health 接口

HEALTH\_TIMEOUT = 60                                           # 秒

LOG\_DIR = Path(".tool/e2e-loop/logs")

\# ------------------

def make\_log\_path() -> Path:

&#x20;   ts = datetime.datetime.now().strftime("%Y-%m-%d\_%H-%M-%S")

&#x20;   return LOG\_DIR / f"{ts}.log"

def wait\_healthy(url: str, timeout: int, logf) -> bool:

&#x20;   """轮询 health 接口直到 200 或超时。"""

&#x20;   deadline = time.time() + timeout

&#x20;   while time.time() < deadline:

&#x20;       try:

&#x20;           with urllib.request.urlopen(url, timeout=2) as resp:

&#x20;               if resp.status == 200:

&#x20;                   logf.write(f"\[controller] health OK: {url}\n")

&#x20;                   logf.flush()

&#x20;                   return True

&#x20;       except Exception as exc:

&#x20;           logf.write(f"\[controller] health pending: {exc}\n")

&#x20;           logf.flush()

&#x20;       time.sleep(1)

&#x20;   return False

def main() -> int:

&#x20;   LOG\_DIR.mkdir(parents=True, exist\_ok=True)

&#x20;   log\_path = make\_log\_path()

&#x20;   with open(log\_path, "a", encoding="utf-8", buffering=1) as logf:

&#x20;       logf.write(f"=== E2E run started {datetime.datetime.now()} ===\n")

&#x20;       # 1. 启动后端，IO 重定向到日志文件（stderr 并入 stdout）

&#x20;       backend = subprocess.Popen(BACKEND\_CMD, stdout=logf, stderr=subprocess.STDOUT, text=True)

&#x20;       logf.write(f"\[controller] backend pid={backend.pid}\n")

&#x20;       logf.flush()

&#x20;       # 2. 健康检查：通过才启动客户端

&#x20;       if not wait\_healthy(HEALTH\_URL, HEALTH\_TIMEOUT, logf):

&#x20;           logf.write("\[controller] HEALTH CHECK FAILED, killing backend\n")

&#x20;           backend.terminate()

&#x20;           backend.wait(timeout=10)

&#x20;           return 1

&#x20;       # 3. 启动客户端黑盒测试，输出到同一日志文件

&#x20;       client = subprocess.Popen(CLIENT\_CMD, stdout=logf, stderr=subprocess.STDOUT, text=True)

&#x20;       logf.write(f"\[controller] client pid={client.pid}\n")

&#x20;       logf.flush()

&#x20;       rc\_client = client.wait()

&#x20;       logf.write(f"\[controller] client exit={rc\_client}\n")

&#x20;       # 4. 清理：停后端，防止端口占用 / 孤儿进程

&#x20;       backend.terminate()

&#x20;       try:

&#x20;           backend.wait(timeout=10)

&#x20;       except subprocess.TimeoutExpired:

&#x20;           backend.kill()

&#x20;       logf.write(f"=== E2E run finished: {log\_path} ===\n")

&#x20;       return rc\_client

if \_\_name\_\_ == "\_\_main\_\_":

&#x20;   sys.exit(main())
```

## 关键设计点



1. **同一 log 文件对象传给两个 Popen**：`stdout=logf, stderr=subprocess.STDOUT` → 前后端输出交错合流到一份文件，时序天然可还原

2. **行缓冲 + 显式 flush**：`open(..., buffering=1)` 并逐条 `logf.flush()` → 日志实时落盘，进程崩溃也留下现场

3. **健康检查用 stdlib&#x20;**`urllib`：零额外依赖；若 `.venv` 已有 httpx 也可换 `httpx.Client`，同样 2s 超时轮询

4. **时间戳日志名**：`%Y-%m-%d_%H-%M-%S.log` → 每轮新文件、旧日志不覆盖，可对比前后轮

5. **清理必做**：客户端结束后 `terminate` 后端（超时 `kill`），防止端口占用 / 孤儿进程 —— 正是主文档反模式之一

6. **退出码透传**：health 失败立即退出 1；客户端退出码作为控制器退出码，agent 凭「退出码 + 日志」判断成败

## 环境坑



* **Windows**：`python3` 在 Git Bash 可用，PowerShell 用 `python`；命令一律走 `uv run python`

* 后端启动命令按项目改：`uv run python3 -m app.main` / `npm run dev` / `go run main.go`

* `HEALTH_URL` 的端口必须与后端实际监听端口一致；health 路径按项目（`/health`、`/api/health`、`/ping`）

* 若后端依赖数据库等需 `docker-compose` 的服务，先单独起依赖，再跑控制器

* 客户端黑盒测试若需参数（如用例路径），写进 `CLIENT_CMD` 或由控制器读环境变量

## 错误案例



| 错误操作             | 后果                     | 正确做法                         |
| ---------------- | ---------------------- | ---------------------------- |
| 两个进程各写各的文件       | 排查要翻两份日志、前后端时序对不上      | 同一文件对象传给两个 Popen             |
| 不 flush          | 进程被杀 / 崩溃时日志丢失         | `buffering=1` + 显式 `flush()` |
| 不清理后端            | 端口占用、下一轮启动失败           | 客户端结束必 `terminate` 后端        |
| health 不轮询直接跑客户端 | 后端未就绪，客户端大量连接失败，日志全是噪音 | `wait_healthy` 轮询至 200 或超时   |
| 日志不按时间戳命名        | 覆盖旧日志，无法对比前后轮          | `{时间}.log` 每轮新文件             |
| 控制器脚本写到项目根       | 污染项目源码                 | 落到 `.tool/e2e-loop/scripts/` |

## 成功标准检查清单



* [ ] 脚本在 `.tool/e2e-loop/scripts/` 下，非项目根

* [ ] 一次运行产出 `logs/{时间}.log`，前后端输出都在同一份里

* [ ] health 未通过时不会启动客户端，且退出码非 0

* [ ] 客户端退出后后端被清理（无残留进程 / 端口释放）

* [ ] 重跑控制器生成新的时间戳日志，旧日志保留

* [ ] 全程 `uv run python3`，无裸 `python` / `pip`