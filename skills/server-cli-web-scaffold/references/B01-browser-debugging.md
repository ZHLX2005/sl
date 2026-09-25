# B01 · 浏览器端到端排查（browser-harness + CDP 重操作）

> 归属主文档 [[server-cli-web-scaffold]]。这是一个**重量级排查手段**，**不接入创建流程**——
> 只在 Web 面板问题**反复出现、常规手段定位不了**时才升级到这里：
> 连通性验证（curl/fetch）、注入 JS 模拟点击观察按钮有效性、现象→层定位。
> 每一坑都来自真实事故（首个案例见第六节）。

## 一、什么时候读这个（升级条件）

排查按代价升序，**不要一上来就动浏览器**：

1. `curl http://127.0.0.1:PORT/api/xxx` —— 大多数「面板坏了」在这一步就定位了：
   本骨架 API 统一返回 `{ ok:false, error, code }`，error 字段就是答案
2. `netstat -ano | grep PORT` + `tasklist //FI "PID eq <pid>"` —— 确认谁在监听、进程还活着吗
3. **满足任一升级条件才读本 ref**：
   - 同一个问题修了又坏、反复出现
   - curl 响应正常但页面就是不对（JS 报错、路由、渲染、交互）
   - 需要真实浏览器复现 / 截图对比才能说清现象

## 二、前置：CDP 调试端点

browser-harness 不自己开浏览器时，连一个已开远程调试的 Chrome/Edge：

```bash
# 端点是谁在监听（9222 是常见约定端口）
netstat -ano | grep 9222
tasklist //FI "PID eq <pid>"        # msedge.exe / chrome.exe
```

**坑**：`curl http://127.0.0.1:9222/json/version` 返回 404 **不代表端点不可用**
（部分 Edge 版本行为如此）。别在端点探测上绕圈，直接用 browser-harness 试连。

连接方式：环境变量 `BU_CDP_URL=http://127.0.0.1:9222` 前缀到每条 browser-harness 命令；
不设则 browser-harness 自己发现/启动浏览器。

## 三、SOP：从「页面不对」到「定位代码」

### Step 1 连接 + 打开面板

```bash
BU_CDP_URL=http://127.0.0.1:9222 browser-harness <<'PY'
new_tab("http://127.0.0.1:7866/")   # 任务的首次导航用 new_tab；后续复用 tab 用 goto_url
wait_for_load()
print(page_info())                   # url / title / 视口——确认真的打开了
PY
```

daemon 会记住 attached tab，**后续脚本不要再调 new_tab**，否则开一堆重复 tab。

### Step 2 截图看现象

browser-harness **没有 `screenshot()` helper**（调用直接 NameError）：

```bash
BU_CDP_URL=http://127.0.0.1:9222 browser-harness <<'PY'
import base64
r = cdp("Page.captureScreenshot", format="png")
open("panel.png", "wb").write(base64.b64decode(r["data"]))
PY
```

### Step 3 在页面上下文里验前后端连通性

一次同时验证「浏览器渲染环境正常」和「后端可达」：

```bash
BU_CDP_URL=http://127.0.0.1:9222 browser-harness <<'PY'
r = cdp("Runtime.evaluate",
        expression="fetch('/api/bootstrap').then(r=>r.text()).then(t=>t.slice(0,300)).catch(e=>'FETCH_FAIL:'+e)",
        awaitPromise=True, returnByValue=True)
print(r["result"]["value"])
PY
```

- 返回 `FETCH_FAIL:...` → 前端环境到不了后端（代理 / 端口 / serve 没起）
- 返回 `{"ok":false,...}` → 后端活着但接口抛错，error 字段直接拿去 grep 源码
- 返回正常数据 → 问题在前端渲染层（查 console / view.jsx）

### Step 4 定位 → 修复 → 回浏览器验证

- 按 Step 3 的分层结果定位代码，修复
- **后端改动必须重启 serve**（Node ESM 无热加载，跑着的进程永远是旧代码）
- 回浏览器 `goto_url` 刷新 + 再截图，**看到现象消失才算修好**——只跑单元测试不算

## 四、注入 JS 模拟点击，观察按钮有效性

「按钮点了没反应」这类交互问题，截图看不出因果——要**主动点、点完看证据**。

### 两种点击方式怎么选

| 方式 | 手段 | 何时用 |
| --- | --- | --- |
| 坐标点击（真实输入） | AX 树取框 → `click_at_xy(x, y)` | 涉及受信事件的操作：写剪贴板、打开新窗口、文件选择 |
| **JS 注入点击**（本 ref 默认） | `Runtime.evaluate` 里 `el.click()` | 验证按钮有效性：handler 是否触发、状态是否更新、API 是否发出 |

React 18 的事件挂在 root 容器上，`el.click()` 派发的 click 会冒泡，`onClick` 能正常触发。
但注入点击的 `isTrusted=false`——受信限制的操作（剪贴板等）用 JS 点**必然失败**，
那不是按钮坏了，是点的方式不对，换坐标点击再下结论。

### 注入模式：找到 → 点 → 等一下

```bash
BU_CDP_URL=http://127.0.0.1:9222 browser-harness <<'PY'
import time
r = cdp("Runtime.evaluate", expression="""
  (() => {
    const btn = [...document.querySelectorAll('button')]
      .find(b => b.textContent.includes('刷新数据'));
    if (!btn) return 'BTN_NOT_FOUND';
    btn.click();
    return 'CLICKED';
  })()
""", returnByValue=True)
print(r["result"]["value"])
time.sleep(1.5)   # 给 handler → API → 重渲染留时间，点完立刻断言必假阴
PY
```

### 观察有效性：三样证据，按序收集

1. **DOM 断言**（最直接）——错误条消失 / 数据行出现 / 按钮变禁用：

```python
r = cdp("Runtime.evaluate", expression="document.body.innerText.slice(0, 500)", returnByValue=True)
print(r["result"]["value"])
```

2. **截图对比**——点击前后各一张，肉眼看状态差异（弹窗、列表刷新）。
3. **网络证据**——handler 跑了但 UI 无变化时，确认 API 到底发没发：
   curl 同一接口复现（回到第三节的连通性分层），或在页面里临时包一层
   `fetch` 记录调用（`window._calls=[]; const f=window.fetch; window.fetch=(...a)=>{window._calls.push(String(a[0])); return f(...a)}` 再点击，然后读 `window._calls`）。

### 「点了没反应」分层排查

| 证据 | 结论 | 下一步 |
| --- | --- | --- |
| `BTN_NOT_FOUND` | 选择器/文案不对，或按钮还没渲染 | 先 `page_info()` + 截图确认页面真到了那一态 |
| `CLICKED` 但 DOM 无变化、无网络请求 | handler 没绑上或抛异常 | 看 console（`Runtime.evaluate` 读不到的异常走截图看错误边界）；查 view.jsx 绑定 |
| 有网络请求但 UI 不更新 | 后端返回了，前端没接住 | 看 response（fetch 包装里顺手记 `r.status`）；查 view.jsx 的状态更新 |

## 五、现象 → 层定位表

| 现象 | 层 | 验证手段 |
| --- | --- | --- |
| 页面壳（标题 / tab）正常渲染 + 红色错误条 | 后端 API 抛错 | 错误条文案就是后端 error 原文；curl 复现 |
| 整页白屏 | 前端 JS 崩 | 截图 + console；查 view.jsx / 错误边界 |
| 页面能开但接口全挂 | serve 没起 / 端口 / 代理不对 | netstat + curl |
| 按钮点了没反应 | 走第四节「点没反应分层排查」 | 注入点击 + 三样证据 |
| 改了后端不生效 | serve 跑旧代码 | 重启 serve 进程 |

## 六、真实案例（nx-sk，2026-09-24）

**现象**：面板显示「读不到后端上下文：`migrationNote is not defined`」。

**定位过程**：browser-harness 连 9222（msedge）→ `new_tab` 打开面板 → 截图拿到错误文案
→ `curl /api/bootstrap` 复现 `{"ok":false,"error":"migrationNote is not defined","code":"INTERNAL"}`
→ 说明错误来自**服务端**，前端壳没崩 → grep 源码：`migrationNote` 的导出、导入、调用齐全
→ 指向运行中的 serve 进程跑的是**改动前的旧代码**。

**教训**：UI 报错 ≠ 前端 bug。本骨架的错误条文案就是后端 error 原文——服务端已经把答案
写在脸上了，先 curl 再动手。「源码看着全对但运行报错」优先怀疑进程没重启。

## 七、踩过的坑

| 坑 | 后果 | 正确做法 |
| --- | --- | --- |
| 跳过 curl 直接上浏览器排查 | 时间耗在 CDP 环境而非问题本身 | 升级条件（第一节）满足才用本 ref |
| 调 `screenshot()` helper | NameError | `cdp("Page.captureScreenshot")` + base64 落盘 |
| `/json/version` 404 就断定端点坏了 | 白绕一圈探测 | 直接 browser-harness 试连 |
| 每个脚本都 `new_tab` | 一堆重复 tab | daemon 记住 attached tab；复用 `goto_url` / `switch_tab()` |
| 修复后只跑测试不回浏览器 | 「修好了」没被验证过 | 刷新 + 截图确认现象消失 |
| 注入点击后立刻断言结果 | handler → API → 重渲染有延迟，必假阴 | `time.sleep(1.5)` 再收集 DOM / 截图 / 网络证据 |
| 剪贴板等受信操作用 `el.click()` 验证 | `isTrusted=false` 必然失败，误判按钮坏了 | 受信操作换坐标点击（AX 树 → `click_at_xy`） |
