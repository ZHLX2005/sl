#!/bin/bash
# log-prompt.sh / UserPromptSubmit hook
# 单文件模式：.claude/prompts.log.md 的 YAML frontmatter 控制开关

set -euo pipefail

LOG_FILE=".claude/prompts.log.md"
HOOK_INPUT=$(cat)

# 文件不存在 → 默认关闭
if [[ ! -f "$LOG_FILE" ]]; then
  exit 0
fi

# 读取 frontmatter 的 enabled 字段
ENABLED=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$LOG_FILE" | grep '^enabled:' | sed 's/enabled: *//' || true)
if [[ "$ENABLED" != "true" ]]; then
  exit 0
fi

# 会话隔离
STATE_SESSION=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$LOG_FILE" | grep '^session_id:' | sed 's/session_id: *//' || true)
HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')
if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
  exit 0
fi

# 记录用户输入
PROMPT=$(echo "$HOOK_INPUT" | jq -r '.prompt // ""')
if [[ -z "$PROMPT" ]]; then
  exit 0
fi

TIMESTAMP=$(date -u +%FT%TZ)
echo "[$TIMESTAMP] [$HOOK_SESSION] $PROMPT" >> "$LOG_FILE"

exit 0
