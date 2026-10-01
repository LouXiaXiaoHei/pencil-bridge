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
    echo "  FAIL: ${desc}（期望退出码 ${want}，实得 ${got}）"; FAIL=$((FAIL+1)); return
  fi
  if [ -n "$needle" ] && ! printf '%s\n' "$out" | grep -qF -- "$needle"; then
    echo "  FAIL: ${desc}（退出码正确，但输出未含: ${needle}）"; FAIL=$((FAIL+1)); return
  fi
  echo "  ok:   $desc"; PASS=$((PASS+1))
}

# $1=描述 $2=期望退出码 $3=skills 目录 $4=输出中不得出现的子串
check_case_absent() {
  local desc="$1" want="$2" dir="$3" bad="$4" got out
  out="$(PENCIL_BRIDGE_SKILLS_DIR="$dir" bash "$REPO_ROOT/bin/check" 2>&1)"; got=$?
  if [ "$got" -ne "$want" ]; then
    echo "  FAIL: ${desc}（期望退出码 ${want}，实得 ${got}）"; FAIL=$((FAIL+1)); return
  fi
  if printf '%s\n' "$out" | grep -qF -- "$bad"; then
    echo "  FAIL: ${desc}（输出不应含: ${bad}）"; FAIL=$((FAIL+1)); return
  fi
  echo "  ok:   $desc"; PASS=$((PASS+1))
}

# $1=描述 $2=期望退出码 $3=skills 目录 $4=必须出现的子串 $5=不得出现的子串
# 用于「同一个技能名不得同时出现在 ok 行与 FAIL 行」这类互斥断言
check_case_exclusive() {
  local desc="$1" want="$2" dir="$3" need="$4" bad="$5" got out
  out="$(PENCIL_BRIDGE_SKILLS_DIR="$dir" bash "$REPO_ROOT/bin/check" 2>&1)"; got=$?
  if [ "$got" -ne "$want" ]; then
    echo "  FAIL: ${desc}（期望退出码 ${want}，实得 ${got}）"; FAIL=$((FAIL+1)); return
  fi
  if ! printf '%s\n' "$out" | grep -qF -- "$need"; then
    echo "  FAIL: ${desc}（输出未含: ${need}）"; FAIL=$((FAIL+1)); return
  fi
  if printf '%s\n' "$out" | grep -qF -- "$bad"; then
    echo "  FAIL: ${desc}（输出不应含: ${bad}）"; FAIL=$((FAIL+1)); return
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

# ── Fix 轮新增：绝对路径守卫覆盖全部 .md、期望技能目录、hub 悬空引用、ok 行条件化 ──
# 绝对路径扫描必须覆盖 references/ 与任意子目录（旧实现只 grep 五个 SKILL.md）
FX_A1="$TMP/fx_a1"; mk_full "$FX_A1"
echo '见 /Users/someone/x.md' >> "$FX_A1/pencil-bridge/references/mcp-toolbox.md"
check_case "reference 文件里的绝对路径被发现" 1 "$FX_A1" "绝对路径"

# 对照：URL 不是绝对路径
FX_A2="$TMP/fx_a2"; mk_full "$FX_A2"
echo '参考 https://example.com/tmp/a' >> "$FX_A2/pencil-bridge/references/mcp-toolbox.md"
check_case "URL 不被误判为绝对路径" 0 "$FX_A2" "全部通过"

# 对照：相对路径不是绝对路径
FX_A3="$TMP/fx_a3"; mk_full "$FX_A3"
echo '见 ../pencil-bridge/references/x.md' >> "$FX_A3/pencil-bridge/references/mcp-toolbox.md"
check_case "相对路径不被误判为绝对路径" 0 "$FX_A3" "全部通过"

# 任意更深子目录里的 .md 也要扫到
FX_A4="$TMP/fx_a4"; mk_full "$FX_A4"
mkdir -p "$FX_A4/pencil-bridge/references/nested"
echo '见 /opt/pencil-bridge/x.md' > "$FX_A4/pencil-bridge/references/nested/deep.md"
check_case "嵌套子目录里的绝对路径被发现" 1 "$FX_A4" "绝对路径"

# URL 剥离必须逐词进行：同一行里真正的绝对路径仍要被抓到
FX_A5="$TMP/fx_a5"; mk_full "$FX_A5"
echo '先看 https://example.com/x ，再看 /tmp/b' >> "$FX_A5/pencil-sync/SKILL.md"
check_case "同一行 URL 与真实绝对路径共存仍被发现" 1 "$FX_A5" "绝对路径"

# URL 剥离本身要有牙齿：query 里带 /tmp/ 的 URL 朴素正则会被误判
FX_A6="$TMP/fx_a6"; mk_full "$FX_A6"
echo '见 https://example.com?p=/tmp/a' >> "$FX_A6/pencil-init/SKILL.md"
check_case "URL query 里的类路径不被误判" 0 "$FX_A6" "全部通过"

# 整个技能目录缺失必须失败（不能在 skills/ 下静默消失）
FX_B="$TMP/fx_b"; mk_full "$FX_B"
rm -rf "$FX_B/pencil-sync"
check_case "整个技能目录缺失时失败" 1 "$FX_B" "缺技能目录"

# hub skills/pencil-bridge/SKILL.md 的悬空引用必须被发现
FX_C="$TMP/fx_c"; mk_full "$FX_C"
echo '见 ../pencil-bridge/references/nonexistent.md' >> "$FX_C/pencil-bridge/SKILL.md"
check_case "hub SKILL.md 的悬空引用被发现" 1 "$FX_C" "pencil-bridge 引用了不存在的 reference"

# 有 finding 的技能不得再打印 ok 行
FX_D="$TMP/fx_d"; mk_full "$FX_D"
inject_fm "$FX_D/pencil-map/SKILL.md" "allowed-tools: [Bash]"
check_case_absent "有 finding 的技能不再打印 ok 行" 1 "$FX_D" "ok:   pencil-map"

# ── Fix 轮 2 新增：悬空引用必须计入本技能 finding，禁止「ok: X」与「FAIL: X …」并存 ──
# 薄壳（只有一个技能目录、没有任何 reference）里的悬空引用：FAIL 要出现，ok 行必须消失
FX_E1="$TMP/fx_e1"; mkdir -p "$FX_E1/pencil-map"
printf -- '---\nname: pencil-map\ndescription: 薄壳。\n---\n见 ../pencil-bridge/references/nope.md\n' \
  > "$FX_E1/pencil-map/SKILL.md"
check_case_exclusive "薄壳悬空引用：FAIL 出现且无同名 ok 行" 1 "$FX_E1" \
  "FAIL: pencil-map 引用了不存在的 reference: nope.md" "ok:   pencil-map"
check_case_absent "薄壳悬空引用的 ok 行必须消失" 1 "$FX_E1" "ok:   pencil-map"

# hub 同样处理
FX_E2="$TMP/fx_e2"; mkdir -p "$FX_E2/pencil-bridge"
printf -- '---\nname: pencil-bridge\ndescription: 薄壳 hub。\n---\n见 ../pencil-bridge/references/nope.md\n' \
  > "$FX_E2/pencil-bridge/SKILL.md"
check_case_exclusive "薄壳悬空引用（hub）：FAIL 出现且无同名 ok 行" 1 "$FX_E2" \
  "FAIL: pencil-bridge 引用了不存在的 reference: nope.md" "ok:   pencil-bridge"
check_case_absent "薄壳悬空引用（hub）的 ok 行必须消失" 1 "$FX_E2" "ok:   pencil-bridge"

# 同一不变式对其它 finding 类别也成立：reference 文件里的绝对路径
FX_E3="$TMP/fx_e3"; mk_full "$FX_E3"
echo '见 /Users/someone/x.md' >> "$FX_E3/pencil-bridge/references/mcp-toolbox.md"
check_case_exclusive "绝对路径类 finding 也不打印同名 ok 行" 1 "$FX_E3" \
  "绝对路径" "ok:   pencil-bridge"

# 反向守卫：全局「缺 reference」不点名技能，故不抑制 ok 行（控制器裁决：保持原样）
FX_E4="$TMP/fx_e4"; mk_full "$FX_E4"
rm -rf "$FX_E4/pencil-bridge/references"
check_case "全局缺 reference 不抑制技能 ok 行" 1 "$FX_E4" "ok:   pencil-bridge"

# ── R25(c)：UTF-8 locale 静态守卫 ──
# bash 3.2 在 UTF-8 locale 下会把紧跟变量的非 ASCII 字节当作变量名的一部分，
# 一个变量名后面直接放全角标点就会被解析成「名字 + 全角字符」，报 unbound
# variable 并让整个套件当场死掉。本机默认环境没有 LANG/LC_* 变量，运行时
# 碰不到这个雷，只有静态扫描能防它回归。
# 子 shell 先 cd 到仓库根，所以下面跑的就是约定的那行 grep 命令；
# 正则里 $ 的后面紧跟 [，因此这一行不会匹配到它自己。
UTF8_FRAGILE="$(cd "$REPO_ROOT" && LC_ALL=C grep -nE \
  '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' bin/check bin/link tests/*.sh)"
UTF8_RC=$?
if [ -z "$UTF8_FRAGILE" ] && [ "$UTF8_RC" -le 1 ]; then
  echo "  ok:   无变量紧跟非 ASCII 字节的 UTF-8 脆弱写法"; PASS=$((PASS+1))
else
  echo "  FAIL: 存在变量紧跟非 ASCII 字节的 UTF-8 脆弱写法："
  printf '%s\n' "$UTF8_FRAGILE"
  FAIL=$((FAIL+1))
fi

echo
echo "通过 $PASS 项，失败 $FAIL 项。"
[ "$FAIL" -eq 0 ]
