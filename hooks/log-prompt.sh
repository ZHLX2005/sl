#!/bin/bash
# log-prompt.sh / UserPromptSubmit hook
# AI 时代 prompt 就是代码——把每一条用户输入都记下来

set -euo pipefail

HOOK_INPUT=$(cat)

# 提取用户输入和会话 ID
PROMPT=$(echo "$HOOK_INPUT" | jq -r '.prompt // ""')
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"')

# 过滤空输入
if [[ -z "$PROMPT" ]]; then
  exit 0
fi

# 确保日志目录存在
mkdir -p .claude

# UTC 时间戳
TIMESTAMP=$(date -u +%FT%TZ)

# 追加写入日志，格式: [时间] [session] prompt
# 多行 prompt 中的换行会被 jq 正常处理，直接追加即可
echo "[$TIMESTAMP] [$SESSION_ID] $PROMPT" >> .claude/prompts.log

exit 0
