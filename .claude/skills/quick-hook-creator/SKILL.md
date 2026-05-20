---
name: quick-hook-creator
description: 当用户要"创建 hook 插件"、"实现 Stop/PreToolUse/PostToolUse/UserPromptSubmit/SessionStart hook"、"做 hook 最小 demo"、"拦截 Claude 退出/工具调用"、"参考 ralph-loop 写 hook"时触发。基于 ralph-loop 案例提供 Claude Code hook 插件的标准目录骨架、各文件模板、JSON 协议示例与 Windows/Bash 兼容写法。
---

# Quick Hook Creator — 快速创建规范 Claude Code Hook 插件

> 本 skill 把 `ralph-loop` 插件的实现拆解为可复用的最小模板，让用户能在 5 分钟内创建一个符合规范、跨平台可运行的 hook 插件。

## 触发条件

- "帮我做一个 hook 插件"
- "创建 Stop hook / PreToolUse hook / PostToolUse hook"
- "实现 hook 最小 demo"
- "拦截 Claude 的 xxx 事件"
- "参考 ralph-loop 写一个 hook"
- "我要写一个 Claude Code 插件"

## 核心机制（必须先理解）

Claude Code hook 是**进程间 JSON 协议**：

```
Claude 触发事件 → 调用 hook 命令(传 stdin JSON) → hook 输出 stdout JSON → Claude 根据返回决定行为
```

**5 种主要事件：**

| 事件             | 触发时机          | 典型用途                            |
| ---------------- | ----------------- | ----------------------------------- |
| `SessionStart`   | Claude 会话启动   | 注入上下文、初始化环境              |
| `UserPromptSubmit` | 用户提交 prompt | 改写/拦截用户输入                   |
| `PreToolUse`     | 工具调用之前      | 审核/阻止工具                       |
| `PostToolUse`    | 工具调用之后      | 记录/告警                           |
| `Stop`           | Claude 准备退出   | 拦截退出形成循环（ralph-loop 思路） |

**Stop hook 关键返回 JSON**（核心机制）：

```json
{
  "decision": "block",
  "reason": "要回喂给 Claude 的下一轮 prompt",
  "systemMessage": "在 UI 上显示给用户的状态行"
}
```

`decision: "block"` 阻止退出，`reason` 字段会作为下一轮用户消息被 Claude 处理。

## 标准目录骨架

```
<plugin-name>/
├── .claude-plugin/
│   └── plugin.json              # 插件元数据（必需）
├── hooks/
│   ├── hooks.json               # hook 事件注册（必需）
│   └── <event>-hook.sh          # hook 执行脚本（推荐 bash）
├── commands/
│   └── <slash-command>.md       # 配套 slash 命令（可选但推荐）
├── scripts/
│   └── setup-<...>.sh           # 初始化脚本（可选）
└── README.md
```

## 创建流程（按序执行）

### Step 1: 询问关键参数

向用户确认：

1. **插件名**（kebab-case，如 `my-stop-demo`）
2. **hook 事件**（Stop / PreToolUse / PostToolUse / UserPromptSubmit / SessionStart）
3. **拦截什么 / 注入什么**（决定 hook 脚本逻辑）
4. **是否需要状态文件**（如 ralph 的 `.claude/ralph-loop.local.md`）

### Step 2: 创建目录骨架

```bash
mkdir -p <plugin-name>/{.claude-plugin,hooks,commands,scripts}
```

### Step 3: 填充 4 个核心文件

**3.1 `.claude-plugin/plugin.json`**

```json
{
  "name": "<plugin-name>",
  "version": "0.1.0",
  "description": "<一句话描述>",
  "author": {
    "name": "<你的名字>",
    "email": "<可选>"
  }
}
```

**3.2 `hooks/hooks.json`**

```json
{
  "description": "<这组 hook 的用途>",
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/stop-hook.sh\""
          }
        ]
      }
    ]
  }
}
```

⚠️ `${CLAUDE_PLUGIN_ROOT}` 是 Claude Code 注入的环境变量，**永远不要写绝对路径**。

**3.3 `hooks/stop-hook.sh`（最小可运行示例）**

```bash
#!/bin/bash
set -euo pipefail

# 1. 读取 stdin 上的 hook 输入 JSON
HOOK_INPUT=$(cat)

# 2. 取关键字段
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""')

# 3. 写日志或做你的判断逻辑
echo "[hook] session=$SESSION_ID at $(date -u +%FT%TZ)" >> .claude/hook.log

# 4. 退出 0 = 放行；输出 JSON decision=block = 拦截
# 简单放行：
exit 0

# 拦截退出（Stop hook 专用）示例：
# jq -n --arg msg "继续干活" \
#       --arg sys "🔄 iteration $(date +%s)" \
#   '{decision:"block", reason:$msg, systemMessage:$sys}'
# exit 0
```

**3.4 `commands/<name>.md`（slash 命令）**

```markdown
---
description: "<命令一句话描述>"
argument-hint: "[OPTIONS]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh:*)"]
hide-from-slash-command-tool: "true"
---

# <Command Title>

调用初始化脚本：

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" $ARGUMENTS
```

执行后会发生什么的说明……
```

### Step 4: 在 marketplace.json 注册（如果是市场插件）

```json
{
  "plugins": [
    {
      "name": "<plugin-name>",
      "source": "./plugins/<plugin-name>",
      "description": "...",
      "version": "0.1.0"
    }
  ]
}
```

### Step 5: 验证

```bash
# 1. 检查 JSON 合法
cat plugin.json | jq .
cat hooks/hooks.json | jq .

# 2. 检查脚本可执行
chmod +x hooks/*.sh scripts/*.sh

# 3. 在 Claude Code 中 /plugin 安装并测试事件触发
```

## Hook 输入 JSON 字段速查

不同事件 stdin 收到的字段：

| 字段                | Stop | PreToolUse | PostToolUse | UserPromptSubmit |
| ------------------- | ---- | ---------- | ----------- | ---------------- |
| `session_id`        | ✓    | ✓          | ✓           | ✓                |
| `transcript_path`   | ✓    | ✓          | ✓           | ✓                |
| `tool_name`         |      | ✓          | ✓           |                  |
| `tool_input`        |      | ✓          | ✓           |                  |
| `tool_response`     |      |            | ✓           |                  |
| `prompt`            |      |            |             | ✓                |

## Hook 输出 JSON（控制 Claude 行为）

```json
{
  "decision": "block" | "approve" | undefined,
  "reason": "传给 Claude 的下一轮消息（block 时）",
  "systemMessage": "UI 上显示的状态行（可选）"
}
```

- 不输出 JSON / 退出 0 = 放行
- 退出非 0 + stderr 输出 = 报错给用户
- 输出 `decision: "block"` = 拦截事件（Stop 拦截退出 / PreToolUse 拦截工具调用）

## 错误案例（高频坑）

| 错误操作                                                    | 实际后果                                              | 正确做法                                                                          |
| ----------------------------------------------------------- | ----------------------------------------------------- | --------------------------------------------------------------------------------- |
| hook 脚本写绝对路径 `/Users/xxx/hook.sh`                    | 别人安装后路径不存在，hook 静默失败                   | 永远用 `${CLAUDE_PLUGIN_ROOT}/hooks/xxx.sh`                                       |
| Windows 上 `bash` 解析到 WSL bash                           | hook 报 `wsl: Unknown key` / `No such file`           | 在 `hooks.json` 显式写 `"C:/Program Files/Git/bin/bash.exe" ${CLAUDE_PLUGIN_ROOT}/...` |
| Stop hook 退出时多个会话同时触发                            | 会话 A 启动的循环被会话 B 误中断                      | 在状态文件里记录 `session_id`，hook 里比对当前 `session_id`，不匹配直接 exit 0    |
| 用 `==` 在 bash `[[ ]]` 里比较带 `*` `?` `[` 的字符串       | 触发 glob 匹配，结果错误                              | 用 `=` 做字面比较                                                                 |
| 直接 `sed -i` 改状态文件                                    | macOS/Linux 行为不同，可能损坏文件                    | 写临时文件再 `mv` 原子替换                                                        |
| transcript 当作 JSON 整体解析                               | 失败——它是 JSONL 每行一个 JSON                        | 用 `grep` + `tail` 切片，再 `jq -s` slurp 解析                                    |
| hook 里 `decision:"block"` 但 `reason` 为空                 | Claude 拿不到下一轮 prompt，循环无意义                | `reason` 必须填非空字符串                                                         |
| 命令脚本里写 `$ARGUMENTS` 但 frontmatter 没声明 allowed-tools | 用户运行时被权限拦截                                  | 在 `allowed-tools` 中显式列出 Bash 模式                                           |
| 把 hook 状态文件提交进 git                                  | 状态泄漏到其他机器                                    | 用 `.claude/xxx.local.md` 后缀 + `.gitignore`                                     |
| 修改 `key_board_2` 自身                                     | 元模板被破坏                                          | 任何新 skill / 新 hook 都放在**独立目录**                                         |

## ralph-loop 启示（设计参考）

`ralph-loop` 是 Stop hook 的经典案例，值得学习的设计点：

1. **状态外置** —— 用 `.claude/ralph-loop.local.md` 而非环境变量保存状态，跨调用持久
2. **YAML frontmatter + markdown 主体** —— 状态文件既能机读（frontmatter）又能人读（prompt 主体）
3. **会话隔离** —— `session_id` 字段防止多会话相互干扰
4. **安全退出条件** —— `max_iterations` + `completion_promise` 双闸门，避免死循环
5. **错误自愈** —— 状态文件损坏时直接删除并报错退出，不试图修复
6. **原子写** —— 用 `temp.$$` + `mv` 保证状态文件写入原子性

## 成功标准检查清单

- [ ] 创建了 `<plugin-name>/` 目录，包含 `.claude-plugin/`、`hooks/`、`commands/`
- [ ] `plugin.json` 包含 name/version/description
- [ ] `hooks.json` 使用 `${CLAUDE_PLUGIN_ROOT}` 而非绝对路径
- [ ] hook 脚本第一行 `#!/bin/bash` + `set -euo pipefail`
- [ ] hook 从 stdin 读 JSON、用 jq 解析
- [ ] 若需循环，状态文件写入了 `session_id` 用于会话隔离
- [ ] 若需循环，设置了 `max_iterations` 或类似熔断条件
- [ ] 在 README 提示了 Windows Git Bash 兼容写法
- [ ] 给配套 slash 命令 frontmatter 写了 `allowed-tools`
- [ ] JSON 文件能通过 `jq .` 解析无错

## 最小可运行 demo（一键拷贝）

```bash
# 1. 创建骨架
PLUGIN=my-hook-demo
mkdir -p $PLUGIN/{.claude-plugin,hooks,commands}

# 2. plugin.json
cat > $PLUGIN/.claude-plugin/plugin.json <<'EOF'
{
  "name": "my-hook-demo",
  "version": "0.1.0",
  "description": "Minimal Claude Code hook demo",
  "author": {"name": "you"}
}
EOF

# 3. hooks.json（监听 Stop 事件）
cat > $PLUGIN/hooks/hooks.json <<'EOF'
{
  "description": "demo stop hook that logs and lets exit pass",
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command",
        "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/stop-hook.sh\""}]}
    ]
  }
}
EOF

# 4. hook 脚本
cat > $PLUGIN/hooks/stop-hook.sh <<'EOF'
#!/bin/bash
set -euo pipefail
HOOK_INPUT=$(cat)
SID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"')
mkdir -p .claude
echo "[$(date -u +%FT%TZ)] stop fired for $SID" >> .claude/hook-demo.log
exit 0
EOF
chmod +x $PLUGIN/hooks/stop-hook.sh
```

安装后每次 Claude 退出都会在当前项目的 `.claude/hook-demo.log` 写一行——验证 hook 已生效。

## 进阶：把 demo 升级成 ralph-loop 风格的循环

把 `stop-hook.sh` 改为：

```bash
# 如果存在 .claude/loop.active 则拦截退出
if [[ -f .claude/loop.active ]]; then
  jq -n '{decision:"block", reason:"继续完成任务", systemMessage:"🔄 looping"}'
fi
exit 0
```

然后 `touch .claude/loop.active` 即可开启循环，`rm` 即可关闭。

## 调用 skill-creator（可选）

创建完后可用 `skill-creator` 跑测试或优化 description 触发命中率。
