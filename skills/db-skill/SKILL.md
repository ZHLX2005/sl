---
name: db-skill
description: Use when any development task is completed, when encountering errors or bugs, or when starting work on a feature that may have prior solutions. Also use when user says /db-skill.
---

# db-skill: Project Development Knowledge Tracker

**Violating the letter of the rules is violating the spirit of the rules.**

This skill tracks every development task to a Notion database.
You do NOT decide whether to record. You ALWAYS record.
You do NOT decide whether to query. You ALWAYS query first.

## THE IRON LAWS

EVERY COMPLETED DEVELOPMENT TASK MUST BE RECORDED TO NOTION.

EVERY NEW TASK MUST QUERY THE KNOWLEDGE BASE FIRST.

No exceptions:
- Not for "it was too small"
- Not for "I'll record it later"
- Not for "the user didn't ask me to"
- Not for "it's just a config change"
- Not for "recording will interrupt the flow"
- Not for "I already know the answer"
- Not for "I'll batch record later"

Completed a task and didn't record? STOP. Record NOW before doing anything else.
Started solving a problem without querying? STOP. Query NOW before continuing.

## Precondition Check (MANDATORY on every activation)

1. `which notion` → not found → STOP, tell user:
   "Install Notion CLI: npm install -g @notionhq/notion-cli"
2. `notion auth status` → not logged in → STOP, tell user:
   "Run: notion auth login"
3. `.db-skill/config.json` exists?
   → No → If user said /db-skill init: proceed to Init
   → No → Otherwise: STOP, tell user:
     "Run /db-skill init <project description> first"
   → Yes → Load config, proceed

## /db-skill init <project description>

Trigger: User inputs /db-skill + project description, AND no .db-skill/ exists.

```
digraph init {
  "User says /db-skill init" [shape=box];
  "Extract project name from description" [shape=box];
  "mkdir -p .db-skill/entries .db-skill/pending" [shape=box];
  "notion db create with full schema" [shape=box];
  "Parse database ID from output" [shape=box];
  "Write config.json" [shape=box];
  "Write index.json (empty)" [shape=box];
  "Write .db-skill/.gitignore" [shape=box];
  "User mentioned reuse?" [shape=diamond];
  "Ask for ref database ID, write to refs" [shape=box];
  "Done" [shape=ellipse];

  "User says /db-skill init" -> "Extract project name from description";
  "Extract project name from description" -> "mkdir -p .db-skill/entries .db-skill/pending";
  "mkdir -p .db-skill/entries .db-skill/pending" -> "notion db create with full schema";
  "notion db create with full schema" -> "Parse database ID from output";
  "Parse database ID from output" -> "Write config.json";
  "Write config.json" -> "Write index.json (empty)";
  "Write index.json (empty)" -> "Write .db-skill/.gitignore";
  "Write .db-skill/.gitignore" -> "User mentioned reuse?";
  "User mentioned reuse?" -> "Ask for ref database ID, write to refs" [label="yes"];
  "User mentioned reuse?" -> "Done" [label="no"];
  "Ask for ref database ID, write to refs" -> "Done";
}
```

Notion database schema:

**数据库名称**: `<项目名称>`（从 init 命令提取，如 "B端电商管理系统"）

```
notion db create <parent-page-id> \
  --title "<project>" \
  --props "Type:select,Context:rich_text,Summary:rich_text,Tags:multi_select,Scope:rich_text,Status:status,Severity:select,Related:rich_text,Hit_Count:number"
```

Required properties:
- **Name**: title（简洁标题，如 "用户列表分页不刷新"）
- **Type**: select [Feature, Bug Fix, Decision, Refactor, Config, Doc]
- **Context**: rich_text（上下文 - 为什么改，解决什么问题）
- **Summary**: rich_text（一句话总结，≤50 chars）
- **Tags**: multi_select（技术标签，如 Vue, React, API, DB）
- **Scope**: rich_text（修改范围 - 具体文件/函数/行）
- **Status**: status [Not started, In progress, Done]
- **Severity**: select [Low, Medium, High, Critical]（仅 Bug 填写）
- **Related**: rich_text（关联的其他条目 ID）
- **Hit_Count**: number（查询命中次数）

.gitignore content:
```
config.json
pending/
```

## Save Process (MANDATORY after every completed task)

```
digraph save_process {
  rankdir=TB;

  "Task completed" [shape=box];
  "Thinking about skipping?" [shape=diamond style=filled fillcolor="#ffcccc"];
  "CHECK RATIONALIZATION TABLE" [shape=box style=filled fillcolor="#ffcccc"];
  "Extract: title, type, context, summary, tags, scope" [shape=box];
  "Type = bug?" [shape=diamond];
  "Extract: severity" [shape=box];
  "Read index.json, check existing tags for reuse" [shape=box];
  "Search index.json for similar entries" [shape=box];
  "Similar entry exists?" [shape=diamond];
  "Append to existing (notion db add + update)" [shape=box];
  "Create new (notion db add)" [shape=box];
  "Notion CLI succeeded?" [shape=diamond];
  "Save to .db-skill/pending/" [shape=box];
  "Update index.json + create entries/*.md" [shape=box];
  "Run SAVE VERIFICATION CHECKLIST" [shape=box style=filled fillcolor="#ccffcc"];
  "All checks pass?" [shape=diamond];
  "Fix failing checks" [shape=box];
  "Done - output: 📝 已记录" [shape=ellipse];

  "Task completed" -> "Thinking about skipping?";
  "Thinking about skipping?" -> "CHECK RATIONALIZATION TABLE" [label="yes"];
  "CHECK RATIONALIZATION TABLE" -> "Extract: title, type, context, summary, tags, scope";
  "Thinking about skipping?" -> "Extract: title, type, context, summary, tags, scope" [label="no"];
  "Extract: title, type, context, summary, tags, scope" -> "Type = bug?";
  "Type = bug?" -> "Extract: severity" [label="yes"];
  "Type = bug?" -> "Read index.json, check existing tags for reuse" [label="no"];
  "Extract: severity" -> "Read index.json, check existing tags for reuse";
  "Read index.json, check existing tags for reuse" -> "Search index.json for similar entries";
  "Search index.json for similar entries" -> "Similar entry exists?";
  "Similar entry exists?" -> "Append to existing (notion db add + update)" [label="yes"];
  "Similar entry exists?" -> "Create new (notion db add)" [label="no"];
  "Append to existing (notion db add + update)" -> "Notion CLI succeeded?";
  "Create new (notion db add)" -> "Notion CLI succeeded?";
  "Notion CLI succeeded?" -> "Update index.json + create entries/*.md" [label="yes"];
  "Notion CLI succeeded?" -> "Save to .db-skill/pending/" [label="no"];
  "Save to .db-skill/pending/" -> "Update index.json + create entries/*.md";
  "Update index.json + create entries/*.md" -> "Run SAVE VERIFICATION CHECKLIST";
  "Run SAVE VERIFICATION CHECKLIST" -> "All checks pass?";
  "All checks pass?" -> "Done - output: 📝 已记录" [label="yes"];
  "All checks pass?" -> "Fix failing checks" [label="no"];
  "Fix failing checks" -> "Run SAVE VERIFICATION CHECKLIST";
}
```

### Save Extraction Guide

| Field | What to Extract | Example |
|-------|----------------|---------|
| **title** | Specific, actionable title | "用户列表分页不刷新" not "修了bug" |
| **type** | One of: Feature/Bug Fix/Decision/Refactor/Config/Doc | Feature |
| **context** | WHY this change was made | "用户反馈列表切换分页后数据不变，需要重置watch" |
| **summary** | One-line summary ≤50 chars | "watch监听page参数变化" |
| **tags** | Tech stack + module names (min 2) | Vue, DataTable, watch |
| **scope** | Exact files/functions/lines changed | `src/views/UserList.vue:45-52`, `usePagination()` |
| **severity** | Bug impact (Low/Medium/High/Critical) | Medium |

### Save Rationalizations - BLOCKED

| Common Excuse | Reality |
|---|---|
| "Too small to record" | Small fixes are hardest to remember. Record takes 2 seconds. |
| "User didn't ask me to record" | Recording is AUTOMATIC. No ask needed. EVER. |
| "I'll batch record later" | You won't. Context is lost after each task. Record NOW. |
| "Similar to last entry" | Then APPEND. Never skip. |
| "Recording will interrupt flow" | One notion command = 2 seconds. Not an interruption. |
| "Just a dependency update" | Dependency changes cause the most bugs. RECORD. |
| "Just a config change" | Config errors are the hardest to debug. RECORD. |
| "This is obvious, no need" | Obvious to you now ≠ obvious in 2 weeks. RECORD. |
| "Efficiency - batch later" | Batch = context loss = incomplete records. Record each task. |

### Save Verification Checklist (MANDATORY)

After EVERY save, verify ALL of these:

- [ ] **Title** is specific (not "修了bug" but "用户列表分页不刷新")
- [ ] **Context** explains WHY this change was made
- [ ] **Summary** is ≤ 50 chars and actionable
- [ ] **Tags** include tech stack + module name (minimum 2)
- [ ] **Tags** reuse existing terms from index.json where applicable
- [ ] **Scope** lists exact files/functions/lines changed
- [ ] **Type** is correct (Feature/Bug Fix/Decision/Refactor/Config/Doc)
- [ ] For bugs: **Severity** is set based on impact scope
- [ ] index.json has been updated
- [ ] entries/*.md has been created or updated
- [ ] Notion write succeeded OR entry is in pending/

Cannot check all boxes? Fix before proceeding to next task.

## Query Process (MANDATORY before solving any problem)

```
digraph query_process {
  rankdir=TB;

  "New task or problem" [shape=box];
  "Thinking about skipping query?" [shape=diamond style=filled fillcolor="#ffcccc"];
  "CHECK RATIONALIZATION TABLE" [shape=box style=filled fillcolor="#ffcccc"];
  "Extract 2-4 search keywords" [shape=box];
  "Read .db-skill/index.json" [shape=box];
  "Match: errorPattern exact > keywords overlap >= 2 > title contains > summary contains" [shape=box];
  "Has refs in config.json?" [shape=diamond];
  "notion db query ref databases" [shape=box];
  "Any matches?" [shape=diamond];
  "0 matches: proceed normally" [shape=box];
  "Low confidence match" [shape=box];
  "High confidence match" [shape=box];
  "Cite title + summary only (L1)" [shape=box];
  "Read entries/*.md for details (L2)" [shape=box];
  "Need full solution?" [shape=diamond];
  "notion page get for complete content (L3)" [shape=box];
  "Update hitCount (local + Notion)" [shape=box];
  "Proceed with task" [shape=ellipse];

  "New task or problem" -> "Thinking about skipping query?";
  "Thinking about skipping query?" -> "CHECK RATIONALIZATION TABLE" [label="yes"];
  "CHECK RATIONALIZATION TABLE" -> "Extract 2-4 search keywords";
  "Thinking about skipping query?" -> "Extract 2-4 search keywords" [label="no"];
  "Extract 2-4 search keywords" -> "Read .db-skill/index.json";
  "Read .db-skill/index.json" -> "Match: errorPattern exact > keywords overlap >= 2 > title contains > summary contains";
  "Match: errorPattern exact > keywords overlap >= 2 > title contains > summary contains" -> "Has refs in config.json?";
  "Has refs in config.json?" -> "notion db query ref databases" [label="yes"];
  "Has refs in config.json?" -> "Any matches?" [label="no"];
  "notion db query ref databases" -> "Any matches?";
  "Any matches?" -> "0 matches: proceed normally" [label="no"];
  "Any matches?" -> "Low confidence match" [label="maybe"];
  "Any matches?" -> "High confidence match" [label="yes"];
  "Low confidence match" -> "Cite title + summary only (L1)";
  "High confidence match" -> "Read entries/*.md for details (L2)";
  "Read entries/*.md for details (L2)" -> "Need full solution?";
  "Need full solution?" -> "notion page get for complete content (L3)" [label="yes"];
  "Need full solution?" -> "Update hitCount (local + Notion)" [label="no"];
  "notion page get for complete content (L3)" -> "Update hitCount (local + Notion)";
  "Cite title + summary only (L1)" -> "Update hitCount (local + Notion)";
  "0 matches: proceed normally" -> "Proceed with task";
  "Update hitCount (local + Notion)" -> "Proceed with task";
}
```

### Query Rationalizations - BLOCKED

| Common Excuse | Reality |
|---|---|
| "I already know how to solve this" | Check anyway. Past root cause may save 30 min. |
| "Knowledge base is probably empty" | Reading index.json takes 0ms. Check anyway. |
| "This problem is unique" | Search by domain + error pattern. You'll be surprised. |
| "Querying will slow my response" | L1 is local file read. Zero latency. |
| "I'll check if I get stuck" | Check FIRST. Not after failing for 10 minutes. |
| "Too early in the project" | Even 1 entry is worth checking. |
| "User is urgent - skip query" | User didn't ask you to skip the process. Query first. |

### Progressive Disclosure Rules

- **L1 (index.json, 0ms)**: title + keywords + summary → decide relevance
- **L2 (entries/*.md, 0ms)**: rootCause + fixPoints + filesChanged → actionable detail
- **L3 (notion page get, 200-500ms)**: full solution + code + discussion → only when L2 insufficient

Never jump to L3 directly. Always L1 → L2 → L3.

## /db-skill ref

- `/db-skill ref add <database-ID>` [--scope all|bugs|features]
  Add cross-project reference to config.json refs
- `/db-skill ref list`
  List all current references
- `/db-skill ref remove <database-ID>`
  Remove a reference

When querying with refs:
- Search ref databases via `notion db query <ref-db-id>`
- Always label results with source project name
- Ref results rank below local results at same confidence level

## Red Flags - STOP and Correct

If you catch yourself thinking ANY of these, STOP immediately:

- "I don't need to query first" → QUERY FIRST. Always.
- "This isn't worth recording" → IT IS. Record it.
- "I'll record multiple tasks at once" → Record EACH task separately. NOW.
- "The user will manually record this" → NO. YOU record. Automatically.
- "I already know the answer" → CHECK history. Then answer.
- "Recording this would be redundant" → Check index.json. If duplicate: APPEND. Never skip.
- "This is just a follow-up" → Separate entry unless IDENTICAL scope.
- "It's about the spirit, not the letter" → Spirit = Letter. Follow the process.
- "This is different because..." → It's not. Follow the process.
- "Just this once" → No. Not even once.
- "This is too small to record" → NO TASK IS TOO SMALL. Record it.
- "Efficiency - batch record later" → NO. Record each task separately.

**ALL of these mean: You are rationalizing. Follow the process.**

## Offline / Network Failure Handling

If `notion` CLI command fails:
1. Save full entry to `.db-skill/pending/<id>.json`
2. Update local index.json with `synced: false`
3. Create local entries/*.md as normal
4. Tell user: "📝 已本地记录，Notion 同步待恢复"

On next successful `notion` CLI call:
1. Check `.db-skill/pending/` for unsynced entries
2. Sync ALL pending entries to Notion
3. Update index.json: set `synced: true`
4. Delete synced files from pending/

Never skip pending sync. Check EVERY time.
