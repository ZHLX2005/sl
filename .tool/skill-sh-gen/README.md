# skill-sh-gen — skill 打包器

把 skill 目录(SKILL.md + references/ 等)打包成一个自包含安装脚本,
安装脚本用 `cat << 'EOF'` heredoc 逐文件重建 `<目标>/.claude/skills/<skill名>/` 下的所有文本文件。

## 文件

| 文件 | 用途 |
|------|------|
| `collect-skills.sh` | 生成器:收集指定目录 → 生成安装脚本 |
| `install-skills.sh` | 生成的交付物(拷到任何 Linux/macOS/Git Bash 机器执行即可) |
| `test-roundtrip.sh` | round-trip 测试:生成 → 安装 → diff 逐字比对 |

## 用法

```bash
# 生成(默认输出到本目录 install-skills.sh)
bash .tool/skill-sh-gen/collect-skills.sh \
  skills/tool-isolation skills/intent-capture-discuss skills/find-skills

# 在目标机器上安装
bash install-skills.sh                    # → ./.claude/skills(当前项目)
bash install-skills.sh ~/.claude/skills   # → 用户全局

# 测试
bash .tool/skill-sh-gen/test-roundtrip.sh
```

## 保证(已被测试覆盖)

- heredoc 分隔符带引号(`<< 'SKILL_EOF'`),内容中 `$`、反引号、`${}` 一律不展开
- 文件内容恰有一行等于分隔符时,自动换用唯一分隔符(`SKILL_EOF_`)
- CRLF 自动归一化为 LF;无结尾换行的源文件恰好补一个换行
- 二进制文件(含 NUL)警告并跳过
- 文件名/路径含 `" $ \` \` 反斜杠时直接报错,防止生成的脚本被二次解释
