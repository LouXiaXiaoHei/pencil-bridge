#!/usr/bin/env bash
# tests/check.test.sh —— 在隔离目录验证 bin/check 的判定能力
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0

# $1=描述 $2=期望退出码 $3=skills 目录 $4=期望输出中出现的子串（可空）
check_case() {
  local desc="$1" want="$2" dir="$3" needle="${4:-}" got out
  out="$(PENCIL_BRIDGE_SKILLS_DIR="$dir" bash "$REPO_ROOT/bin/check" 2>&1)"; got=$?
  if [ "$got" -ne "$want" ]; then
    echo "  FAIL: $desc（期望退出码 $want，实得 $got）"; FAIL=$((FAIL+1)); return
  fi
  if [ -n "$needle" ] && ! printf '%s\n' "$out" | grep -qF -- "$needle"; then
    echo "  FAIL: $desc（退出码正确，但输出未含: $needle）"; FAIL=$((FAIL+1)); return
  fi
  echo "  ok:   $desc"; PASS=$((PASS+1))
}

REFS="mcp-toolbox document-routing write-safety design-map assets-extraction init-and-mcp stack-flutter stack-kotlin stack-web"
SKILLS="pencil-bridge pencil-init pencil-map pencil-sync pencil-assets"

# 结构完整的最小技能包：5 个技能 + 9 个 reference
mk_full() { # $1=目录
  local dir="$1" s r
  mkdir -p "$dir"
  for s in $SKILLS; do
    mkdir -p "$dir/$s"
    { echo "---"; echo "name: $s"; echo "description: 测试用技能。"
      echo "---"; echo; echo "# $s"; } > "$dir/$s/SKILL.md"
  done
  mkdir -p "$dir/pencil-bridge/references"
  for r in $REFS; do echo "# $r" > "$dir/pencil-bridge/references/$r.md"; done
}

# 往 frontmatter 块内插入一行
inject_fm() { # $1=file $2=要插入的行
  awk -v line="$2" 'NR==1{print; print line; next} {print}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

GOOD="$TMP/good"; mk_full "$GOOD"
check_case "结构完整时通过" 0 "$GOOD" "全部通过"

BAD1="$TMP/bad1"; mk_full "$BAD1"
rm -rf "$BAD1/pencil-bridge/references"
check_case "缺 references 时失败" 1 "$BAD1" "缺 reference"

BAD2="$TMP/bad2"; mk_full "$BAD2"
inject_fm "$BAD2/pencil-bridge/SKILL.md" "disableModelInvocation: true"
check_case "含 legacy 驼峰键时失败" 1 "$BAD2" "legacy 键 disableModelInvocation"

BAD3="$TMP/bad3"; mk_full "$BAD3"
inject_fm "$BAD3/pencil-map/SKILL.md" "allowed-tools: [Bash]"
check_case "含 allowed-tools 时失败" 1 "$BAD3" "使用 allowed-tools"

BAD4="$TMP/bad4"; mk_full "$BAD4"
echo '见 ../pencil-bridge/references/nonexistent.md' >> "$BAD4/pencil-map/SKILL.md"
check_case "引用不存在的 reference 时失败" 1 "$BAD4" "引用了不存在的 reference"

BAD5="$TMP/bad5"
mkdir -p "$BAD5/Pencil_Map"
printf -- '---\nname: Pencil_Map\ndescription: 名字非法。\n---\n' > "$BAD5/Pencil_Map/SKILL.md"
check_case "name 不合 kebab-case 时失败" 1 "$BAD5" "不合 kebab-case"

BAD6="$TMP/bad6"; mk_full "$BAD6"
echo '见 /Users/someone/Project/pencil-bridge/skills/x.md' >> "$BAD6/pencil-sync/SKILL.md"
check_case "出现绝对路径时失败" 1 "$BAD6" "绝对路径"

BAD7="$TMP/bad7"; mk_full "$BAD7"
mkdir -p "$BAD7/pencil_assets"
printf -- '---\nname: pencil-assets\ndescription: 目录名与 name 不一致。\n---\n' > "$BAD7/pencil_assets/SKILL.md"
rm -rf "$BAD7/pencil-assets"
check_case "目录名与 frontmatter name 不一致时失败" 1 "$BAD7" "目录名与 frontmatter name"

# DSH 只读 frontmatter：正文里出现 banned 键字样不应误报
BAD8="$TMP/bad8"; mk_full "$BAD8"
printf '\nallowed-tools: [Bash]\n' >> "$BAD8/pencil-bridge/SKILL.md"
check_case "正文提及 allowed-tools 不误报" 0 "$BAD8" "全部通过"

echo
echo "通过 $PASS 项，失败 $FAIL 项。"
[ "$FAIL" -eq 0 ]
