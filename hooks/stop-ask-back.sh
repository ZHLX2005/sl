#!/bin/bash
# ask-back-hook / Stop hook
# 第 1 次退出 → 拦截，把反问喂给 Claude
# 第 2 次退出 → 放行（避免死循环）
#
# 反问内容写在 QUESTION 变量里，按需修改

set -euo pipefail

QUESTION="完成真实的启动了吗？请直接回答 是 / 否，并给出 1 行证据。"

# 读 stdin 的 hook 输入 JSON
HOOK_INPUT=$(cat)
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "default"')

# 每个会话独立的 flag 文件，避免多窗口互相干扰
mkdir -p .claude
FLAG=".claude/ask-back.${SESSION_ID}.flag"

if [[ -f "$FLAG" ]]; then
  # 已经反问过 → 放行退出
  rm -f "$FLAG"
  exit 0
fi

# 第一次进入 Stop：写 flag、拦截退出、把反问回喂
touch "$FLAG"

jq -n \
  --arg q "$QUESTION" \
  --arg sys "❓ ask-back-hook: 已自动追问，请回答后再结束本轮" \
  '{decision:"block", reason:$q, systemMessage:$sys}'

exit 0
