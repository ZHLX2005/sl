# kvcli todo 命令参考（CLI 使用手册）

> 这是 `taskget` 主 SKILL.md 的命令参考。**当且仅当**要执行 kvcli todo 命令或校验输出时加载本文件。
> 覆盖：前置条件、命令清单、数据结构、退出码、典型用法、交互菜单、避坑、相关文件。

## 前置条件

1. **二进制就绪**：`kvcli` 已经在系统可执行路径上（构建产物 `D:\code\a_go\env\mods\bin\kvcli.exe` 或当前目录 `./kvcli`）。
2. **登录态**：已执行 `kvcli auth login`，token 存在 `~/.kvcli/config.json`。**所有 todo 子命令都需要登录**，否则报「未登录」并 exit 1。
3. **后端可达**：默认 `http://47.110.80.47:8988`，可用 `kvcli --base-url <url>` 临时覆盖。

## 命令清单

```bash
# 提交任务（topic 必填）
kvcli todo add --topic <topic> "<任务内容>"

# 取第一条待办（可按 topic 过滤；可选 --json 机器可读）
kvcli todo first [--topic <topic>] [--json]

# 全量查看（待办 + 已完成；可选 --json 输出 {open:[], done:[]}）
kvcli todo list [--json]

# 标记完成（可带 --result 写完成结果到任务的 note 字段）
kvcli todo done <id> [--result "完成结果摘要"]

# 主题提示词（key=todo:prompt:<topic>，value=该主题上下文知识）
kvcli todo prompt set --topic <topic> "<提示词内容>"   # 覆盖写
kvcli todo prompt get --topic <topic> [--json]          # 查看（--json 输出 {topic,prompt,hasPrompt}）
kvcli todo prompt del --topic <topic>                   # 删除
```

## 数据结构

```
todo:open          → [{"id":1,"topic":"bug","text":"...","createdAt":"...","doneAt":"","note":""}]
todo:done          → [{"id":1,"topic":"bug","text":"...","createdAt":"...","doneAt":"...","note":"..."}]
todo:prompt:<topic> → 一段纯文本（该 topic 的上下文/提示词，非 JSON）
```

- `id` = `max(id in todo:open) + 1` 自增；移到 done 后 id 不复用
- `topic` 必填，路由维度（不同消费者只拉自己 topic 的任务）
- `doneAt` 在待办时为空，完成时写 RFC3339
- `note` 在待办时为空；`done --result "..."` 写完成结果
- `todo:prompt:<topic>` 的 value 是**纯文本**（不是 JSON）；`prompt set` 覆盖写，不存在时 `get` 返回空串

## 退出码

| 情形 | 退出码 |
|---|---|
| 成功 | 0 |
| `--topic` 缺失、文本为空、`done <id>` 的 id 非数字或不存在、未登录 | 非零 |

**脚本里只看退出码判定成败，不要去 parse 人类文案**。

## 典型用法

**提交 + 拉取 + 完成 一条龙：**
```bash
# 提交
kvcli todo add --topic bug "修复登录页 500"

# 拉取（agent 用 --json 解析）
TASK_JSON=$(kvcli todo first --topic bug --json)
# 带 --topic 时，JSON 额外带上该 topic 的提示词：
# {"id":N,"topic":"bug","text":"...","createdAt":"...","doneAt":"","note":"","prompt":"<topic 的上下文>"}
# 不带 --topic 时，JSON 只有任务字段（无 prompt），向后兼容。

# 提取字段
ID=$(echo "$TASK_JSON" | python -c "import sys,json;print(json.load(sys.stdin)['id'])")

# 完成 + 回填结果
kvcli todo done "$ID" --result "已修复根因: ..."
```

**主题提示词（让 AI 拿任务即拿上下文）：**
```bash
# 1) 给 topic 配一段上下文知识（只写一次，长期复用）
kvcli todo prompt set --topic go "Go 1.25; lab/kvcli 独立 module, 模块内 go 命令需 GOWORK=off; 优先标准库; 错误用 fmt.Errorf+%w"

# 2) 消费者拉 go 任务时，prompt 字段自动带上下文
kvcli todo first --topic go --json   # → {...任务字段..., "prompt":"Go 1.25; ..."}

# 3) 单独查看/删除提示词
kvcli todo prompt get --topic go --json   # → {"topic":"go","prompt":"...","hasPrompt":true}
kvcli todo prompt del --topic go
```
`prompt` 是 topic 级的共享上下文，与具体任务解耦：同一 topic 的所有任务拉取时都带上这段提示，不用在每个任务文本里重复写。

**按 topic 分流（多消费者各拉各的）：**
```bash
# 提交方一次发多主题
kvcli todo add --topic docs "更新 API 文档"
kvcli todo add --topic bug  "登录页 500"

# docs 消费者
kvcli todo first --topic docs --json

# bug 消费者
kvcli todo first --topic bug --json
```

**空 open 的处理：**`first` 在 open 为空或 topic 无匹配时打印 `null`（JSON 模式）或「暂无待办任务」（表格模式），exit 0。脚本据此判定无任务可做。

## 交互菜单

无参启动 `kvcli` 进入交互菜单，里面有 `todo` 模块：
- `add` 选后会提示输入 topic + 内容
- `done` 选后会提示输入 id + 完成结果
- `prompt` 进二级菜单选 set/get/del，提示输入 topic（set 再输入内容）
- `first` / `list` 直接走子命令

CLI 直接调用是零交互的（脚本友好）。两种用法并存，按场景选。

## 避坑

| 坑 | 后果 | 注意 |
|---|---|---|
| `add` 漏 `--topic` | exit 1，报 `--topic 必填` | 提交时必带 |
| `done <非数字>` | exit 1，报 `id 必须为数字` | 解析 first 输出时确保提取的是数字 |
| `done <不存在的 id>` | exit 1，报 `task id=N not found in todo:open` | id 只在 open 里匹配，done 列表里的 id 不接受 |
| 未登录就调 todo 子命令 | exit 1，报「未登录」 | 先 `kvcli auth login` |
| 改 base-url 想测不同后端 | 每次要带 `--base-url` | 或写到 `~/.kvcli/config.json` 的 baseURL |

## 相关文件

- `lab/kvcli/internal/todo/todo.go` — Store + Task 类型 + LoadPrompt/SavePrompt/DeletePrompt（todo:prompt:<topic>）
- `lab/kvcli/cmd/todo.go` — cobra 子命令：add/first/list/done + prompt set/get/del
- `docs/superpowers/specs/2026-08-05-kvcli-todo-design.md` — 设计文档
- `docs/superpowers/plans/2026-08-05-kvcli-todo.md` — 实现计划
