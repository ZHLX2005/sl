#!/usr/bin/env bash
# test-roundtrip.sh — collect-skills.sh 的 round-trip 测试
# 验证:生成的 install 脚本能逐字重建源目录
# 覆盖:真实三个 skill / 分隔符冲突 / shell 元字符 / CRLF 归一化 / 二进制跳过 / 默认目标
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GEN="$REPO_ROOT/.tool/skill-sh-gen/collect-skills.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "✘ $1" >&2; exit 1; }

# ---------- Case 1: 三个真实 skill round-trip ----------
bash "$GEN" "$REPO_ROOT/skills/tool-isolation" \
          "$REPO_ROOT/skills/intent-capture-discuss" \
          "$REPO_ROOT/skills/find-skills" \
          -o "$TMP/install.sh" || fail "case1: 生成器执行失败"

bash "$TMP/install.sh" "$TMP/skills" || fail "case1: 安装脚本执行失败"

# 逐文件对比:内容必须逐字一致;按设计,无结尾换行的源文件会恰好补一个换行
norm() { awk '{print}' "$1"; }
SRC_DIRS=(skills/tool-isolation skills/intent-capture-discuss skills/find-skills)
while IFS= read -r f; do
  rel="${f#"${REPO_ROOT}"/}"
  inst="$TMP/skills/${rel#skills/}"
  diff --strip-trailing-cr <(norm "$f") <(norm "$inst") \
    || fail "case1: $rel 内容不一致"
done < <(cd "$REPO_ROOT" && find "${SRC_DIRS[@]}" -type f)

# 文件数必须一致(防止安装端多出/漏掉文件)
src_n=$(cd "$REPO_ROOT" && find "${SRC_DIRS[@]}" -type f | wc -l)
dst_n=$(find "$TMP/skills" -type f | wc -l)
[ "$src_n" = "$dst_n" ] || fail "case1: 文件数不一致 ($src_n vs $dst_n)"

# lottery-workflow.md 源文件无结尾换行 → 安装后必须恰好补一个(结尾是 \n,倒数第二字节不是 \n)
ADV1="$TMP/skills/tool-isolation/references/lottery-workflow.md"
[ -z "$(tail -c 1 "$ADV1")" ] || fail "case1: 未补结尾换行"
[ -n "$(tail -c 2 "$ADV1" | head -c 1)" ] || fail "case1: 补了不止一个换行"
echo "✔ case1: 三个真实 skill round-trip 逐字一致"

# ---------- Case 2: 对抗样本(分隔符冲突 + shell 元字符 + CRLF) ----------
ADV="$TMP/src/adv-skill"
mkdir -p "$ADV/references"
printf 'SKILL_EOF\n`backtick` $(whoami) $HOME ${VAR}\n中文 + 特殊字符 ✘✔\n' > "$ADV/SKILL.md"
printf 'line1\r\nline2\r\nSKILL_EOF\r\n' > "$ADV/references/crlf.md"

bash "$GEN" "$ADV" -o "$TMP/install-adv.sh" || fail "case2: 生成器执行失败"
bash "$TMP/install-adv.sh" "$TMP/skills2" || fail "case2: 安装脚本执行失败"

diff --strip-trailing-cr "$ADV/SKILL.md" "$TMP/skills2/adv-skill/SKILL.md" \
  || fail "case2: 分隔符冲突或 shell 元字符被展开,内容不一致"
if LC_ALL=C grep -q $'\r' "$TMP/skills2/adv-skill/references/crlf.md"; then
  fail "case2: CRLF 未归一化为 LF"
fi
diff --strip-trailing-cr <(sed 's/\r$//' "$ADV/references/crlf.md") \
     "$TMP/skills2/adv-skill/references/crlf.md" \
  || fail "case2: crlf.md 内容不一致"
echo "✔ case2: 分隔符冲突 / shell 元字符不展开 / CRLF→LF 全部正确"

# ---------- Case 3: 默认安装目标是 ./.claude/skills 且可传参覆盖 ----------
grep -qF 'SKILLS_BASE="${1:-./.claude/skills}"' "$TMP/install.sh" \
  || fail "case3: 默认目标不是 ./.claude/skills"
echo "✔ case3: 默认安装目标为 ./.claude/skills(可传参覆盖)"

# ---------- Case 4: 二进制文件警告跳过,文本照常安装 ----------
BIN="$TMP/src/bin-skill"
mkdir -p "$BIN"
printf 'ok text\n' > "$BIN/SKILL.md"
printf 'a\0b' > "$BIN/blob.bin"

OUT4="$(bash "$GEN" "$BIN" -o "$TMP/install-bin.sh" 2>&1 >/dev/null)" || true
echo "$OUT4" | grep -q "blob.bin" || fail "case4: 警告未提到二进制文件名"
bash "$TMP/install-bin.sh" "$TMP/skills3" || fail "case4: 安装脚本执行失败"
diff --strip-trailing-cr "$BIN/SKILL.md" "$TMP/skills3/bin-skill/SKILL.md" \
  || fail "case4: 文本文件安装不一致"
echo "✔ case4: 二进制文件警告并跳过"

echo "=== 全部测试通过 ==="
