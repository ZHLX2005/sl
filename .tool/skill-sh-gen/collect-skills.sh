#!/usr/bin/env bash
# collect-skills.sh — 收集指定 skill 目录,生成用 cat << 'EOF' heredoc 重建全部文件的安装脚本
# 用法: bash collect-skills.sh <skill目录>... [-o 输出文件]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_OUT="$SCRIPT_DIR/install-skills.sh"
BASE_DELIM="SKILL_EOF"

usage() {
  cat <<'USAGE'
用法: bash collect-skills.sh <skill目录>... [-o 输出文件]

把每个 skill 目录(SKILL.md + references/ 等)打包成一个自包含安装脚本。
安装脚本用 cat << 'EOF' heredoc 逐文件重建 <目标>/.claude/skills/<skill名>/ 下的所有文本文件。

选项:
  -o <文件>   安装脚本输出路径(默认: 本工具目录下 install-skills.sh)
              传 "-o -" 则输出到 stdout
示例:
  bash collect-skills.sh skills/tool-isolation skills/intent-capture-discuss skills/find-skills
  bash collect-skills.sh skills/tool-isolation -o install-my.sh
USAGE
}

die() { echo "✘ $*" >&2; exit 1; }

# ---------- 参数解析 ----------
OUT="$DEFAULT_OUT"
DIRS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -o) [ $# -ge 2 ] || die "-o 需要一个路径参数"; OUT="$2"; shift 2 ;;
    -o*) OUT="${1#-o}"; shift ;;
    -*) usage >&2; die "未知选项: $1" ;;
    *)  DIRS+=("$1"); shift ;;
  esac
done
[ ${#DIRS[@]} -gt 0 ] || { usage >&2; exit 2; }

# 路径中不允许出现会被生成的 sh 二次解释的字符
check_safe() {
  if printf '%s' "$2" | grep -qE '["$`\\]'; then
    die "$1 含 shell 特殊字符,请先重命名: $2"
  fi
}

# ---------- 生成 ----------
TMP_OUT="$(mktemp)"
trap 'rm -f "$TMP_OUT"' EXIT
exec 3>"$TMP_OUT"

nskills=0
nfiles=0

cat >&3 <<'HDR'
#!/usr/bin/env bash
# install-skills.sh — 由 collect-skills.sh 自动生成,请勿手改
# 用法: bash install-skills.sh [skills根目录]
#   不传参 → 安装到 ./.claude/skills(当前项目)
#   传参   → 安装到指定目录,例: bash install-skills.sh ~/.claude/skills
set -euo pipefail
SKILLS_BASE="${1:-./.claude/skills}"
HDR

for dir in "${DIRS[@]}"; do
  dir="${dir%/}"
  [ -d "$dir" ] || die "目录不存在: $dir"

  name="$(basename "$dir")"
  check_safe "skill 目录名" "$name"
  [ -f "$dir/SKILL.md" ] || echo "⚠ $name 缺少 SKILL.md(仍继续收集)" >&2

  nskills=$((nskills + 1))
  count=0
  printf '\n# ===== skill: %s =====\n' "$name" >&3

  while IFS= read -r f; do
    rel="${f#"$dir"/}"
    [ -n "$rel" ] || rel="${f#./}"
    check_safe "文件路径" "$rel"
    parent="$(dirname "$rel")"

    # 二进制文件(含 NUL)警告跳过
    if ! tr -d '\0' < "$f" | cmp -s - "$f"; then
      echo "⚠ 跳过二进制文件: $f" >&2
      continue
    fi

    # 分隔符冲突检测:内容里恰好有一行等于分隔符时,自动加下划线直到唯一
    delim="$BASE_DELIM"
    while grep -qxF -- "$delim" "$f"; do
      delim="${delim}_"
    done

    printf 'mkdir -p "$SKILLS_BASE/%s/%s"\n' "$name" "$parent" >&3
    printf 'cat > "$SKILLS_BASE/%s/%s" << '\''%s'\''\n' "$name" "$rel" "$delim" >&3
    sed 's/\r$//' "$f" >&3
    # 源文件无结尾换行时补一个(heredoc 结束分隔符必须独立成行)
    [ -n "$(tail -c 1 "$f")" ] && printf '\n' >&3 || true
    printf '%s\n' "$delim" >&3

    count=$((count + 1))
    nfiles=$((nfiles + 1))
  done < <(LC_ALL=C find "$dir" -type f | LC_ALL=C sort)

  [ "$count" -gt 0 ] || echo "⚠ $name 中没有收集到任何文本文件" >&2
done

printf '\necho "✔ 已安装 %s 个 skill / %s 个文件 -> $SKILLS_BASE"\n' "$nskills" "$nfiles" >&3

# ---------- 输出 ----------
exec 3>&-
if [ "$OUT" = "-" ]; then
  cat "$TMP_OUT"
else
  cat "$TMP_OUT" > "$OUT"
  chmod +x "$OUT"
  echo "生成: $OUT (skills: $nskills, 文件: $nfiles)"
fi
