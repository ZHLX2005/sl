---
name: obsidian-repair-unresolved-links
description: Obsidian vault 中存在未解析的 `[[]]` 双链，需要补全为目标笔记。当存在多个链接时自动并发创建
---

# Obsidian 未解析双链补全

**触发：** 用户说 "[[某某]] 没创建" / "修复未解析链接" / "双链不存在"

---

## 流程

1. **查看** — `obsidian unresolved format=json`
2. **过滤** — 排除图片/附件链接，排除模板文件（`ctl/tmpl_*.md`）中的占位示例链接
3. **定位** — grep 找到源文件和行号
4. **生成 frontmatter** — **硬性步骤，不可跳过**。跑 `gen_frontmatter.py` 拿到完整 YAML 输出
5. **修文件名** — 脚本自动处理 `*"\/< > :|?`
6. **生成内容** — 按 `reffence/content-spec.md` 规范，读上下文后生成深入、不重复的笔记
7. **创建文件到 source 同目录** — 如 source 在 `日常/` 下，新文件也放 `日常/` 下
8. **验证** — `head -3` 确认 frontmatter 存在，`obsidian unresolved format=json` 确认链接消失

---

## ⚠️ 文件目录强制规则

**新笔记必须创建在 source 文件所在目录下，绝不要放在 vault 根目录。**

```
✅ 正确：source 在 日常/ 下 → 新文件也放 日常/
日常/
├── 如何成为一个动画制作工程师.md   ← source
├── 动画工程师需要养成哪些直觉.md    ← 新笔记（同目录）

❌ 错误（bad_eg）：丢到 vault 根目录
根目录/
├── 动画工程师需要养成哪些直觉.md    ← 和 source 分离，vault 混乱
```

根目录只应放 `base-root.md` 这样的 vault 入口文件，具体笔记按 source 目录归属。

---

## ⚠️ frontmatter 强制约束（必读）

**这是本 skill 最重要的一条规则，违反会导致 vault 一致性破坏：**

> **Write 调用的 content 字符串的第一个字符必须是 `---`（YAML 起始），文件最开头 3 行必须是有效的 YAML frontmatter。**

### 实际事故记录

| 时间 | 事故 | 后果 | 根因 |
|------|------|------|------|
| 2026-06-16 | 生成"按理来说...JIT 都是一样的吗"笔记时跳过 `gen_frontmatter.py` 步骤，直接 Write 内容 | 笔记没有 `creatime`/`tags`/`bklink`，Obsidian 视为"无元数据" | 流程把"步骤 4 写元数据"和"步骤 6 生成内容"列为并列步骤，没有"步骤 6 依赖步骤 4 输出"的硬耦合 |

### 漏 frontmatter 的实际危害

- Obsidian **双链反向链接**失效（`bklink` 缺失）
- **Dataview 查询** 查不到（`creatime`/`tags` 缺失）
- **Tags 聚合**失败（`tags: []` 缺失）
- **Templater / QuickAdd** 等插件的"按 frontmatter 处理"功能全部失效

### 反例：错误的 Write 调用

```python
# ❌ 错误：content 第一个字符是 '#'
content = """# 高级语言抽象层次与性能损失
> 关联笔记：...
"""
Write(file_path, content)
```

### 正例：正确的 Write 调用

```python
# ✅ 正确：先跑 gen_frontmatter.py，把输出放在 content 开头
content = """---
creatime: 2026-06-16 14:59:59
tags: []
bklink:
  - "[[base_日常]]"
---
# 高级语言抽象层次与性能损失
> 关联笔记：...
"""
Write(file_path, content)
```

---

## 并发模式

当存在 **多个未解析链接** 时：

```
发现 → 定位 → 元数据（主线程跑 gen_frontmatter.py）  ← 硬性步骤
              │
              ▼  把脚本输出（YAML 段）注入下面 prompt 的 {frontmatter_yaml} 占位符
              ├── subagent 1: 读上下文 → 生成内容 → 创建文件
              ├── subagent 2: 读上下文 → 生成内容 → 创建文件
              └── subagent 3: 读上下文 → 生成内容 → 创建文件
```

**关键约束：** 主线程必须在派发 subagent **之前** 跑完 `gen_frontmatter.py`，把脚本输出的 YAML 段（即 `---` 到下一个 `---` 之间的内容）复制到 subagent prompt 的 `{frontmatter_yaml}` 占位符位置。subagent **不要自己写** frontmatter——直接用主线程注入的 YAML。

### Prompt 模板（所有 `{xxx}` 都是占位符，必须由主线程替换）

派发前，主线程执行：

```bash
python .claude/skills/obsidian-repair-unresolved-links/gen_frontmatter.py \
  --source {file} --link "{link}" --locate
# 把输出里 --- 到 --- 之间的内容抓出来，替换 {frontmatter_yaml}
```

然后把替换后的整个 prompt 喂给 subagent：

```
=== FRONTMATTER（主线程已生成，subagent 必须原样作为 Write content 开头）===
{frontmatter_yaml}
===

=== 任务（占位符在派发前已替换为具体值）===

1. 源文件 {file} 第 {line} 行引用了 [[{link}]]
2. 读源文件上下文，理解链接含义
3. 按 reffence/content-spec.md 的规范生成内容
   - 根据主题选择对应模式：概念深潜 / 实践拆解 / 还原论拆解 / 概念拓扑
   - 锚点前置：第一段先给具体问题或反直觉现象
   - 量级感知：用具体数字，不用"快"、"慢"、"大量"
   - trade-off 讨论：展示工程妥协而非列出"优点"
   - 双链链接 vault 内已有相关笔记，避免重复

=== 输出要求 ===

- Write 的 content 字符串必须以"=== FRONTMATTER"块的 YAML 开头
- 然后接 # 标题 和正文
- 文件名 {safe}.md，写入 source 文件同目录（如 source 在 `日常/` 下，则写 `日常/{safe}.md`）
- 写完后用 Read 工具读回前 3 行验证 frontmatter 存在
```

---

## 问卷模式（特殊需求时）

**触发条件：** 源文件是问卷模板（含问题+用户填写内容），且用户要求生成定制化响应。

**判断特征：**
- 源文件包含问题列表（段落/表格）和用户填写内容
- 末尾有触发双链，如 `[[我已经完成了问卷 帮我规划吧]]`

**处理方式：**

1. 读取源文件，解析用户的所有问卷回答
2. 分析关键数据：约束条件、偏好/厌恶、限制因素、基线能力
3. 读取 `reffence/questionnaire-spec.md` 获取问卷模式的写作规范
4. 生成与用户情况匹配的针对性响应
5. 写入位置：
   - 如果触发双链是"响应锚点"（如 `[[xxx规划]]`）→ 直接写入该文件（文件在 source 同目录）
   - 如果触发双链是"新建笔记名"（如 `[[张三的4周计划]]`）→ 在 source 同目录创建独立文件

> ⚠️ 无论是哪种情况，**文件必须放在 source 同目录**，不要丢到 vault 根目录（根目录存放见上方的 ⚠️ 文件目录强制规则）。

---

## 参考文件

skill 目录下的辅助文件：

| 文件 | 用途 |
|------|------|
| `gen_frontmatter.py` | 步骤 4：自动生成 frontmatter |
| `reffence/content-spec.md` | 通用模式：内容生成规范 |
| `reffence/questionnaire-spec.md` | 问卷模式：针对性响应生成规范 |

---

## 验证清单（每篇笔记写完后必过）

- [ ] `head -3 <新文件>` 第一行是 `---`（YAML 起始）
- [ ] `head -10 <新文件>` 能看到 `creatime:`、`tags:`、`bklink:` 三段
- [ ] `obsidian unresolved format=json` 列表里**没有**刚才的链接
- [ ] Obsidian 打开新文件后能看到 tags 列表、双链面板有反向链接

---

## 注意
- `ctl/tmpl_*.md` 中的示例链接已用反引号转义，不会误判
- 元数据由脚本自动生成，AI 专注于内容
- **绝不要"为了节省时间"跳过 `gen_frontmatter.py` 步骤**——漏掉的 frontmatter 需要事后手动补全
- 单文件路径含中文/特殊字符时，`gen_frontmatter.py` 的 `--source` 参数必须用 UTF-8 编码的字符串
