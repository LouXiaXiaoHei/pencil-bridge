# pencil-bridge 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 pencil-bridge 技能包 —— 一个主知识 bundle + 四条命令（`/pencil-init`、`/pencil-map`、`/pencil-sync`、`/pencil-assets`）+ 一个幂等扇出脚本，让 DSH / Claude Code / Codex CLI 三个 harness 都能通过 pencil MCP 连到 Pen.app 指定的 `.pen` 与节点，按设计改代码样式、提取素材、反写设计稿。

**Architecture:** 仓库 `~/Project/pencil-bridge/` 是**唯一物理真源**。`bin/link` 把它扇出成三种形态：DSH 与 Claude Code 建**目录软链**，Codex 落**复制副本**（是否跟随软链未证实，不赌）。`skills/pencil-bridge/` 是主 bundle，承载全部 9 个 reference；另外四个技能目录是约 40 行的薄壳，只用**相对路径** `../pencil-bridge/references/<file>.md` 指回主 bundle，自身不含知识。全部能力通过技能文本交付，不写运行时程序。

**Tech Stack:** Markdown（SKILL.md + references）、Bash 4（`bin/link`、`bin/check`，零第三方依赖）。被操作的外部系统是 Pen.app 的 pencil MCP（5 个工具：`browser` / `execute` / `get_app_state` / `get_style` / `read_skill`）。

**Spec:** `docs/superpowers/specs/2026-10-01-pencil-bridge-design.md`（617 行，已批准）
**参考资料:** `docs/reference/pencil-write-api-manual.md`（554 行，写操作 API 逐字手册）

---

## Global Constraints

每个任务的要求**默认包含**本节全部内容。违背任一条即为任务失败。

**交付形态**
- 一切能力通过 SKILL.md 与 references 文本交付。**不写运行时守护进程、不写 MCP 客户端库、不写 GUI**。
- 仓库根就是 `~/Project/pencil-bridge/`，将来整仓上传 GitHub。**任何绝对路径引用都是缺陷** —— 技能文本里一律用 `../pencil-bridge/references/<file>.md`。
- Bash 脚本必须 `#!/usr/bin/env bash` + `set -euo pipefail`，**零第三方依赖**（不用 node / python / jq）。

**frontmatter 铁律（三个 harness 的安全交集，spec §4.4）**
- 只使用 `name` + `description` + 可选 `metadata`（对象型）。
- `name` 必须匹配 `^[a-z0-9]+(?:-[a-z0-9]+)*$`，且**目录名 == frontmatter `name`**。
- `description` 必填（DSH 缺它会**丢弃整个技能**），且注意 DSH 目录按 500 字符截断。
- **严禁 legacy 驼峰键** `disableModelInvocation` / `modelInvocable` / `userInvocable` —— DSH 抛错并丢弃整个技能。
- **严禁 `_` 前缀技能名**（DSH 直接看不见）。
- **不使用** `allowed-tools` 与 `argument-hint`（只在 Claude 生效，会导致三 harness 行为不一致）。
- 五个技能全部 `user-invocable`（即默认值，**不要写这个键**，省略即为 true）。

**安全铁律（spec §2 / §3.7 / §10 / §11）**
- **禁止读入**这些凭据文件（连 `grep` 都不行）：`~/.pencil/session-desktop.json`、`~/.pencil/agent-auth`、`~/.dsh/.credentials.yaml`、`~/.claude/.credentials.json`、`~/.claude.json` 里的 `github` MCP 条目、`~/.claude/settings.json` 的 `env` 段、`~/.continue/config.json` 的 `models[]`。
- **绝不修改** `~/.dsh/profiles/desktop/cordis.patch.yml` 里 `# >>> dsh-skill-mcp-panel:mcp:begin` 与 `# <<< …:end` 之间的内容。
- **禁止整文件序列化写回**任何 harness 配置文件（会摧毁注释与键序）。
- 每次 `execute` **必须显式传 `filePath`**（`file://` 绝对 URI）。
- **永不使用 `get_app_state` 判断写入目标** —— 它跟随用户焦点。
- 哨兵不符或收到 `Failed to access file "…"` → **立即停机，不重试**。
- `Update` 的 `updateData` **绝不带 `type`**；**不传 `children`**。
- `SetVariables` **禁止 `replace: true`**。
- 不假设写操作已落盘，收尾**必须提示用户保存**。

**验收基线（spec §14，Task 15 逐条实测）**
- yuexiaoshi.pen 顶层节点数 136、hanzi_write.pen 顶层节点数 183。
- hanzi_write 的 `E5QUX` 子树类型直方图 `{frame:60, text:18, icon:34, path:7}`。

---

## File Structure

**新建：**

| 路径 | 职责 |
|---|---|
| `README.md` | 人读入口：这是什么、怎么装、四条命令怎么用、Codex 差异说明 |
| `bin/link` | 幂等扇出：两个软链根 + 一个复制根 |
| `bin/check` | 结构校验：frontmatter、目录名==name、legacy 键、reference 齐全与引用有效 |
| `tests/check.test.sh` | 在隔离目录验证 `bin/check` 能抓出各类坏技能 |
| `tests/link.test.sh` | 在隔离 `$HOME` 验证 `bin/link` 的软链/复制/幂等行为 |
| `skills/pencil-bridge/SKILL.md` | 主 bundle 总纲：模型解释、命令路由、栈探测、Critical Rules |
| `skills/pencil-bridge/references/mcp-toolbox.md` | 5 个工具、`execute` API 全貌、visitor 正确写法、`Print` 通道 |
| `skills/pencil-bridge/references/document-routing.md` | `filePath` / 静默回退 / 哨兵 / 会话启动检查单 |
| `skills/pencil-bridge/references/write-safety.md` | 写操作安全规程（spec §11 全文） |
| `skills/pencil-bridge/references/design-map.md` | design-map 协议 schema 与建立流程 |
| `skills/pencil-bridge/references/assets-extraction.md` | 四类素材提取 |
| `skills/pencil-bridge/references/init-and-mcp.md` | 逐 harness 路径、容器键名、写入铁律、生效条件 |
| `skills/pencil-bridge/references/stack-flutter.md` | pubspec、widget 定位、Dart 常量输出 |
| `skills/pencil-bridge/references/stack-kotlin.md` | gradle、XML/Compose、`colors.xml` 输出 |
| `skills/pencil-bridge/references/stack-web.md` | package.json、CSS 变量输出、Tailwind 映射 |
| `skills/pencil-init/SKILL.md` | 薄壳 |
| `skills/pencil-map/SKILL.md` | 薄壳 |
| `skills/pencil-sync/SKILL.md` | 薄壳 |
| `skills/pencil-assets/SKILL.md` | 薄壳 |

**已存在，不改：** `docs/superpowers/specs/2026-10-01-pencil-bridge-design.md`、`docs/reference/pencil-write-api-manual.md`、`.gitignore`。

**关于文档类任务的"代码"约定：** 本项目的交付物大半是 markdown 文本，其权威内容已在 spec 里逐节批准。因此计划中对这类任务给出的是**逐字 frontmatter + 精确章节清单 + 每节对应的 spec 章节号 + 必须出现的硬事实**，而不是把 spec 全文再抄一遍 —— 抄一遍会制造第二份真源（违反 DRY）。脚本类任务则给出**完整可运行代码**。

---

## Task 1: 仓库骨架与五个技能的最小 frontmatter

先把结构立起来，后续任务才能被 `bin/check` 校验。

**Files:**
- Create: `README.md`
- Create: `skills/pencil-bridge/SKILL.md`（最小版，内容在 Task 5 填充）
- Create: `skills/pencil-init/SKILL.md`（最小版）
- Create: `skills/pencil-map/SKILL.md`（最小版）
- Create: `skills/pencil-sync/SKILL.md`（最小版）
- Create: `skills/pencil-assets/SKILL.md`（最小版）

**Interfaces:**
- Produces: 五个技能目录，各自含一个带合法 frontmatter 的 `SKILL.md`。Task 2 的 `bin/check` 与 Task 3/4 的 `bin/link` 都依赖这五个目录存在。

- [ ] **Step 1: 写下五个 frontmatter 的逐字内容**

`skills/pencil-bridge/SKILL.md`：

```markdown
---
name: pencil-bridge
description: 通过 pencil MCP 连接 Pen.app 的设计稿，把设计同步到代码、提取素材、或把代码改动反写回设计稿。当用户提到设计稿、pen 文件、Pen.app、设计同步、设计变量、图标、提取素材时使用本技能；它会引导你选用 /pencil-init、/pencil-map、/pencil-sync、/pencil-assets 中的一条。
metadata:
  version: "1.0.0"
  suite: pencil-bridge
---

# pencil-bridge

（正文见 Task 5）
```

`skills/pencil-init/SKILL.md`：

```markdown
---
name: pencil-init
description: 检查并补齐 pencil MCP 到各 harness 的连接。当用户说「连不上 pencil」「pencil MCP 没反应」「配置一下 Pen 连接」「检查设计稿连接」时使用。默认只读诊断，任何写入前必须先询问用户。
metadata:
  version: "1.0.0"
  suite: pencil-bridge
---

# /pencil-init（Codex: $pencil-init）

（正文见 Task 13）
```

`skills/pencil-map/SKILL.md`：

```markdown
---
name: pencil-map
description: 为当前项目建立或更新设计稿到代码页面的映射表 .pencil-bridge/design-map.yaml。当用户说「建映射」「关联设计稿和页面」「这个页面在哪个设计稿里」「初始化设计映射」时使用。
metadata:
  version: "1.0.0"
  suite: pencil-bridge
---

# /pencil-map（Codex: $pencil-map）

（正文见 Task 13）
```

`skills/pencil-sync/SKILL.md`：

```markdown
---
name: pencil-sync
description: 按设计稿修改项目页面的样式（正向），或把代码里的样式改动反写回设计稿（反向）。当用户说「按设计改样式」「设计稿更新了同步一下」「把这个颜色写回设计稿」「反写」时使用。
metadata:
  version: "1.0.0"
  suite: pencil-bridge
---

# /pencil-sync（Codex: $pencil-sync）

（正文见 Task 13）
```

`skills/pencil-assets/SKILL.md`：

```markdown
---
name: pencil-assets
description: 从设计稿提取素材：位图、矢量 path、图标引用、设计变量 token。当用户说「导出图标」「提取素材」「把设计变量导出成 CSS/Dart/colors.xml」「导出 SVG」时使用。
metadata:
  version: "1.0.0"
  suite: pencil-bridge
---

# /pencil-assets（Codex: $pencil-assets）

（正文见 Task 13）
```

- [ ] **Step 2: 写 `README.md`**

必须包含这五节，每节内容按下述要点写（对着 spec §1 / §4.1 / §5 / §4.5 写）：

1. **这是什么** —— 一句话 + 四条命令的职责表（从 spec §5 的表抄）。
2. **安装** —— `git clone` 到 `~/Project/pencil-bridge` → `bin/link` → 重启/新开 harness 会话。
3. **四条命令怎么用** —— 每条的典型口令，并**同时写出 Codex 写法**（`$pencil-init` 等），说明 Codex 用 `$` 而非 `/`（spec §4.5）。
4. **前置条件** —— Pen.app 必须运行；目标 `.pen` 必须已打开（未打开会**静默读错文档**，spec §3.2）。
5. **安全边界** —— 只读诊断默认、反写有补偿备份、不读凭据文件。

- [ ] **Step 3: 验证五个目录与文件就位**

Run:
```bash
cd /Users/howard/Project/pencil-bridge && ls -1 skills/*/SKILL.md && ls -1 README.md
```
Expected: 六行输出，五个 `SKILL.md` 路径加 `README.md`，无报错。

- [ ] **Step 4: 提交**

```bash
cd /Users/howard/Project/pencil-bridge
git add README.md skills/
git commit -m "feat: 仓库骨架与五个技能的 frontmatter"
```

---

## Task 2: `bin/check` 结构校验脚本

**Files:**
- Create: `bin/check`
- Create: `tests/check.test.sh`

**Interfaces:**
- Consumes: Task 1 的五个 `skills/*/SKILL.md`。
- Produces: `bin/check` 可执行文件，退出码 0 = 全部通过、1 = 有失败项；逐项打印 `ok: <name>` 或 `FAIL: <原因>` 到 stderr。可用环境变量 `PENCIL_BRIDGE_SKILLS_DIR` 覆盖被检查的 `skills/` 目录（测试要用）。

- [ ] **Step 1: 写失败的测试 `tests/check.test.sh`**

```bash
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
```

- [ ] **Step 2: 运行测试确认它失败**

Run:
```bash
cd /Users/howard/Project/pencil-bridge && bash tests/check.test.sh
```
Expected: FAIL —— 因为 `bin/check` 还不存在（`bash: bin/check: No such file or directory`，各 case 拿到退出码 127）。

- [ ] **Step 3: 写 `bin/check`**

```bash
#!/usr/bin/env bash
# bin/check —— pencil-bridge 技能包结构校验（零依赖）
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="${PENCIL_BRIDGE_SKILLS_DIR:-$REPO_ROOT/skills}"

FAILED=0
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; }
ok()   { printf 'ok:   %s\n' "$1"; }

NAME_RE='^[a-z0-9]+(-[a-z0-9]+)*$'
REFS=(mcp-toolbox document-routing write-safety design-map assets-extraction
      init-and-mcp stack-flutter stack-kotlin stack-web)

# 复刻 DSH 的 frontmatter 读取：只看首个 --- ... --- 块
fm_field() { # $1=file $2=key
  awk -v key="$2" '
    NR==1 && $0!="---" { exit }
    NR==1 { next }
    /^---[[:space:]]*$/ { exit }
    { if (match($0, "^" key "[[:space:]]*:")) {
        sub("^" key "[[:space:]]*:[[:space:]]*", ""); print; exit } }
  ' "$1"
}

# 键是否出现在 frontmatter 内。DSH 只读 frontmatter，正文提及同名键不算问题。
fm_has_key() { # $1=file $2=key
  awk -v key="$2" '
    NR==1 && $0!="---" { exit 1 }
    NR==1 { next }
    /^---[[:space:]]*$/ { exit }
    $0 ~ "^" key "[[:space:]]*:" { found=1; exit }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

[ -d "$SKILLS_DIR" ] || { echo "FAIL: skills 目录不存在: $SKILLS_DIR" >&2; exit 1; }

shopt -s nullglob
for dir in "$SKILLS_DIR"/*/; do
  name="$(basename "$dir")"
  skill_md="$dir/SKILL.md"

  if [ ! -f "$skill_md" ]; then fail "$name: 缺 SKILL.md"; continue; fi

  fm_name="$(fm_field "$skill_md" name || true)"
  fm_desc="$(fm_field "$skill_md" description || true)"

  [ -n "$fm_name" ] || fail "$name: frontmatter 缺 name"
  [ -n "$fm_desc" ] || fail "$name: frontmatter 缺 description"

  if [ -n "$fm_name" ]; then
    [[ "$fm_name" =~ $NAME_RE ]] || fail "$name: name '$fm_name' 不合 kebab-case"
    [ "$fm_name" = "$name" ] || fail "$name: 目录名与 frontmatter name '$fm_name' 不一致"
    case "$fm_name" in _*) fail "$name: 禁止 _ 前缀技能名";; esac
  fi

  for legacy in disableModelInvocation modelInvocable userInvocable; do
    if fm_has_key "$skill_md" "$legacy"; then
      fail "$name: 含 legacy 键 $legacy（DSH 会丢弃整个技能）"
    fi
  done

  for banned in allowed-tools argument-hint; do
    if fm_has_key "$skill_md" "$banned"; then
      fail "$name: 使用 $banned（只在 Claude 生效，破坏三 harness 一致性）"
    fi
  done

  if grep -qE '/Users/[A-Za-z0-9._-]+/Project/pencil-bridge' "$skill_md"; then
    fail "$name: 出现绝对路径引用（仓库克隆到别处即失效）"
  fi

  ok "$name"
done

for r in "${REFS[@]}"; do
  [ -f "$SKILLS_DIR/pencil-bridge/references/$r.md" ] \
    || fail "缺 reference: references/$r.md"
done

for cmd in pencil-init pencil-map pencil-sync pencil-assets; do
  f="$SKILLS_DIR/$cmd/SKILL.md"
  [ -f "$f" ] || continue
  while read -r ref; do
    [ -z "$ref" ] && continue
    [ -f "$SKILLS_DIR/pencil-bridge/references/$ref" ] \
      || fail "$cmd 引用了不存在的 reference: $ref"
  done < <(grep -oE '\.\./pencil-bridge/references/[a-z0-9-]+\.md' "$f" \
             | sed 's#.*/##' | sort -u)
done

if [ "$FAILED" -eq 0 ]; then echo "全部通过。"; else echo "存在失败项。" >&2; fi
exit "$FAILED"
```

- [ ] **Step 4: 让脚本可执行并重跑测试**

Run:
```bash
cd /Users/howard/Project/pencil-bridge && chmod +x bin/check && bash tests/check.test.sh
```
Expected: PASS —— `通过 6 项，失败 0 项。`

- [ ] **Step 5: 在真仓库上跑一次（此时应当失败，因为 references 还没写）**

Run:
```bash
cd /Users/howard/Project/pencil-bridge && bash bin/check; echo "退出码=$?"
```
Expected: 退出码 1，输出 9 条 `FAIL: 缺 reference: …`。**这是预期的** —— 后续任务会逐个补齐。

- [ ] **Step 6: 提交**

```bash
cd /Users/howard/Project/pencil-bridge
git add bin/check tests/check.test.sh
git commit -m "feat: bin/check 结构校验脚本与测试"
```

---

## Task 3: `bin/link` 的软链分支

**Files:**
- Create: `bin/link`
- Create: `tests/link.test.sh`

**Interfaces:**
- Consumes: Task 1 的五个技能目录。
- Produces: `bin/link` 可执行文件。支持 `--dry-run`、`--only agents|claude|codex`、`--help`。读 `${HOME}` 定位三个技能根，从脚本自身位置推出仓库根。Task 4 在同一个文件里加复制分支。

- [ ] **Step 1: 写失败的测试 `tests/link.test.sh`**

测试用**临时 `$HOME`**，绝不碰真实家目录。

```bash
#!/usr/bin/env bash
# tests/link.test.sh —— 在隔离的临时 $HOME 里验证 bin/link
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
export HOME="$TMP_HOME"

PASS=0; FAIL=0
assert() { # $1=描述，其余为要执行的命令
  local desc="$1"; shift
  if "$@"; then echo "  ok:   $desc"; PASS=$((PASS+1))
  else echo "  FAIL: $desc"; FAIL=$((FAIL+1)); fi
}

# 预置障碍：一个指向错误目标的旧软链 + 一个同名真实目录
mkdir -p "$HOME/.agents/skills"
ln -s /nonexistent "$HOME/.agents/skills/pencil-bridge"
mkdir -p "$HOME/.agents/skills/pencil-map"
touch "$HOME/.agents/skills/pencil-map/STALE"

# 预置障碍：Codex 侧一个同名真实目录（副本分支要能重置它）
mkdir -p "$HOME/.codex/skills/pencil-init"
touch "$HOME/.codex/skills/pencil-init/STALE"

# --- dry-run 不得落盘 ---
bash "$REPO_ROOT/bin/link" --dry-run >/dev/null
assert "dry-run 后旧软链仍在（未落盘）" [ -L "$HOME/.agents/skills/pencil-bridge" ]
assert "dry-run 后真实目录仍在" [ -d "$HOME/.agents/skills/pencil-map" ]

# --- 真跑 ---
bash "$REPO_ROOT/bin/link" >/dev/null

for n in pencil-bridge pencil-init pencil-map pencil-sync pencil-assets; do
  assert "agents/$n 是软链" [ -L "$HOME/.agents/skills/$n" ]
  assert "agents/$n 指向真源" \
    [ "$(readlink "$HOME/.agents/skills/$n")" = "$REPO_ROOT/skills/$n" ]
  assert "claude/$n 是软链" [ -L "$HOME/.claude/skills/$n" ]
  assert "claude/$n 指向真源" \
    [ "$(readlink "$HOME/.claude/skills/$n")" = "$REPO_ROOT/skills/$n" ]
done

assert "旧错误软链已改指真源" [ -L "$HOME/.agents/skills/pencil-bridge" ]
assert "同名真实目录已被替换（STALE 消失）" [ ! -e "$HOME/.agents/skills/pencil-map/STALE" ]

# --- 幂等：再跑一次不应报错，且软链依然正确 ---
bash "$REPO_ROOT/bin/link" >/dev/null
assert "第二次运行后软链仍正确" \
  [ "$(readlink "$HOME/.agents/skills/pencil-sync")" = "$REPO_ROOT/skills/pencil-sync" ]

# --- --only 只动指定 harness ---
rm -rf "$HOME/.claude/skills/pencil-assets"
bash "$REPO_ROOT/bin/link" --only agents >/dev/null
assert "--only agents 不会重建 Claude 侧" [ ! -e "$HOME/.claude/skills/pencil-assets" ]

# --- 源技能缺失时直接失败，不造悬空软链 ---
MISSING_REPO="$TMP_HOME/missing-repo"
mkdir -p "$MISSING_REPO/bin" "$MISSING_REPO/skills/pencil-bridge"
cp "$REPO_ROOT/bin/link" "$MISSING_REPO/bin/link"
assert "源技能缺失时报错退出" \
  bash -c '! bash "$1/bin/link" >/dev/null 2>&1' _ "$MISSING_REPO"

echo
echo "通过 $PASS 项，失败 $FAIL 项。"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: 运行测试确认它失败**

Run:
```bash
cd /Users/howard/Project/pencil-bridge && bash tests/link.test.sh
```
Expected: FAIL —— `bin/link` 尚不存在，多个断言失败。

- [ ] **Step 3: 写 `bin/link`（先只实现软链分支，复制分支留 TODO 占位会在 Step 4 被真实实现替换）**

```bash
#!/usr/bin/env bash
# bin/link —— 把 skills/ 下的技能扇出到三个 harness 的技能根
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SRC="$REPO_ROOT/skills"

SKILL_NAMES=(pencil-bridge pencil-init pencil-map pencil-sync pencil-assets)

DRY_RUN=0
TARGETS=()

usage() {
  cat <<'EOF'
用法: bin/link [--dry-run] [--only agents|claude|codex] [--help]

  --dry-run          只打印将要做的事，不落盘
  --only <harness>   只处理一个：agents | claude | codex
  --help             显示本帮助

扇出方式:
  ~/.agents/skills/<name>   目录软链   (DSH，已证实跟随软链)
  ~/.claude/skills/<name>   目录软链   (Claude Code，已证实)
  ~/.codex/skills/<name>    复制副本   (Codex，是否跟随软链未证实，不赌)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --only) shift; [ $# -gt 0 ] || { echo "--only 需要参数" >&2; exit 2; }; TARGETS+=("$1") ;;
    --help|-h) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# 源技能必须齐全：否则软链分支会造出悬空软链（宿主静默忽略），复制分支会中途崩掉
for n in "${SKILL_NAMES[@]}"; do
  [ -d "$SKILLS_SRC/$n" ] || { echo "缺源技能目录: $SKILLS_SRC/$n" >&2; exit 1; }
done

want() {
  [ ${#TARGETS[@]} -eq 0 ] && return 0
  local t; for t in "${TARGETS[@]}"; do [ "$t" = "$1" ] && return 0; done
  return 1
}

run() { if [ "$DRY_RUN" -eq 1 ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }

link_one() { # $1=root $2=name
  local root="$1" name="$2" src="$SKILLS_SRC/$2" dst="$1/$2"
  run mkdir -p "$root"
  if [ -L "$dst" ]; then
    if [ "$(readlink "$dst")" = "$src" ]; then
      echo "  = 已是最新: $dst"; return 0
    fi
    echo "  ~ 重建软链: $dst"; run rm -f "$dst"
  elif [ -e "$dst" ]; then
    echo "  ! 同名非软链已存在，替换为软链: $dst"; run rm -rf "$dst"
  else
    echo "  + 新建软链: $dst"
  fi
  run ln -s "$src" "$dst"
}

copy_one() { # $1=root $2=name
  local root="$1" name="$2" src="$SKILLS_SRC/$2" dst="$1/$2"
  run mkdir -p "$root"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    echo "  ~ 重置副本: $dst"; run rm -rf "$dst"
  else
    echo "  + 新建副本: $dst"
  fi
  run cp -R "$src" "$dst"
}

echo "仓库: $REPO_ROOT"
echo "技能: ${SKILL_NAMES[*]}"
echo

if want agents; then
  echo "→ DSH: ${HOME}/.agents/skills (软链)"
  for n in "${SKILL_NAMES[@]}"; do link_one "${HOME}/.agents/skills" "$n"; done
  echo
fi

if want claude; then
  echo "→ Claude Code: ${HOME}/.claude/skills (软链)"
  for n in "${SKILL_NAMES[@]}"; do link_one "${HOME}/.claude/skills" "$n"; done
  echo
fi

if want codex; then
  echo "→ Codex CLI: ${HOME}/.codex/skills (复制)"
  for n in "${SKILL_NAMES[@]}"; do copy_one "${HOME}/.codex/skills" "$n"; done
  echo
fi

echo "完成。"
```

- [ ] **Step 4: 让脚本可执行并重跑测试**

Run:
```bash
cd /Users/howard/Project/pencil-bridge && chmod +x bin/link && bash tests/link.test.sh
```
Expected: PASS —— `通过 25 项，失败 0 项。`（数量随实现微调，关键是 `失败 0 项`）

- [ ] **Step 5: 提交**

```bash
cd /Users/howard/Project/pencil-bridge
git add bin/link tests/link.test.sh
git commit -m "feat: bin/link 扇出脚本（软链 + 复制双分支）"
```

---

## Task 4: 复制分支的同步语义与 `--dry-run` 验收

Task 3 的 `copy_one` 已经写了复制逻辑，这里补上真正重要的性质：**副本必须先删后拷**，且 `bin/link` 重跑后副本内容与真源逐字节一致。

**Files:**
- Modify: `tests/link.test.sh`（追加断言）
- Modify: `bin/link`（若 Step 2 的断言暴露问题）

**Interfaces:**
- Consumes: Task 3 的 `bin/link` 与 `copy_one`。
- Produces: 有测试保障的复制分支，Task 14 的真机安装可以直接依赖它。

- [ ] **Step 1: 追加复制语义的断言**

在 `tests/link.test.sh` 的 `echo` 汇总行**之前**插入：

```bash
# --- 复制分支的同步语义 ---
for n in pencil-bridge pencil-init pencil-map pencil-sync pencil-assets; do
  assert "codex/$n 存在" [ -e "$HOME/.codex/skills/$n" ]
  assert "codex/$n 不是软链（必须是真实副本）" [ ! -L "$HOME/.codex/skills/$n" ]
done
assert "codex 副本的 SKILL.md 与真源一致" \
  diff -q "$REPO_ROOT/skills/pencil-bridge/SKILL.md" \
          "$HOME/.codex/skills/pencil-bridge/SKILL.md"
assert "预置的 STALE 已被副本重置清掉" [ ! -e "$HOME/.codex/skills/pencil-init/STALE" ]

# 改真源 → 重跑 → 副本必须跟上（证明是"重置"而非"合并"）
echo "# 临时改动" >> "$REPO_ROOT/skills/pencil-assets/SKILL.md"
bash "$REPO_ROOT/bin/link" --only codex >/dev/null
assert "重跑后副本跟上了真源改动" \
  diff -q "$REPO_ROOT/skills/pencil-assets/SKILL.md" \
          "$HOME/.codex/skills/pencil-assets/SKILL.md"
git -C "$REPO_ROOT" checkout -- skills/pencil-assets/SKILL.md

# 反向：副本里多出的文件，重跑后必须消失（证明"先删后拷"）
touch "$HOME/.codex/skills/pencil-map/GARBAGE"
bash "$REPO_ROOT/bin/link" --only codex >/dev/null
assert "副本中的多余文件被清除" [ ! -e "$HOME/.codex/skills/pencil-map/GARBAGE" ]
```

- [ ] **Step 2: 运行测试，确认复制语义成立**

Run:
```bash
cd /Users/howard/Project/pencil-bridge && bash tests/link.test.sh
```
Expected: PASS，`失败 0 项。`

如果 `副本中的多余文件被清除` 失败，说明 `copy_one` 漏了 `rm -rf` —— 回到 `bin/link` 的 `copy_one` 确认删除分支覆盖 `[ -e "$dst" ] || [ -L "$dst" ]` 两种情况。

- [ ] **Step 3: 提交**

```bash
cd /Users/howard/Project/pencil-bridge
git add bin/link tests/link.test.sh
git commit -m "test: 补齐 bin/link 复制分支的同步语义断言"
```

---

## Task 5: 主 bundle `pencil-bridge/SKILL.md`

把 Task 1 的占位正文换成真内容。这是 AI 进入整个技能套件的入口。

**Files:**
- Modify: `skills/pencil-bridge/SKILL.md`

**Interfaces:**
- Consumes: 无。
- Produces: 主 bundle 总纲。Task 6–12 的每个 reference 都会被这里引用一次，Task 13 的四个薄壳都指回这里。

- [ ] **Step 1: 按下面的骨架写正文**

保留 Task 1 的 frontmatter 不动，把 `（正文见 Task 5）` 替换成：

```markdown
## When to Use This Skill

用户提到设计稿 / `.pen` / Pen.app / 设计同步 / 设计变量 / 提取图标素材时进入。
**先判断该用哪条命令**，不要自己临场拼流程：

| 用户想做什么 | 用哪条 | Codex 里写 |
|---|---|---|
| 连不上、检查配置 | `/pencil-init` | `$pencil-init` |
| 建立/更新设计与页面的映射 | `/pencil-map` | `$pencil-map` |
| 按设计改代码，或把代码改动写回设计 | `/pencil-sync` | `$pencil-sync` |
| 导出位图/矢量/图标引用/变量 token | `/pencil-assets` | `$pencil-assets` |

用户没指明时，按这个顺序问：项目里有 `.pencil-bridge/design-map.yaml` 吗？没有 → `/pencil-map`；有 → 看意图选 sync 或 assets。

## Critical Rules

1. **每次 `execute` 必须传 `filePath`**（`file://` 绝对 URI）。不传就会命中「最后聚焦的文档」兜底分支，**且不报错**。
2. **`get_app_state` 绝不能用来判断写入目标** —— 它跟随用户焦点，永远不可信。
3. **写前必读哨兵**：确认连的是目标 `.pen`。哨兵不符 → **立即停机，不重试**。
4. **提醒用户不要关掉目标 `.pen`**。未打开的文档会静默回退到焦点文档。
5. **`Update` 绝不带 `type`**；**不传 `children`**（要改结构用 `Replace`）。
6. **`SetVariables` 禁止 `replace: true`** —— 它会删掉未列出的变量并清空 themed 值。
7. **不假设写操作已落盘** —— 收尾必须提示用户保存。
8. **不读凭据文件**（清单见 `references/write-safety.md`）。
9. **图标取不到矢量源码** —— 只能产出「库名 + 图标名」引用。
10. **禁止无 visitor 全量读**：`Get("document", {depth:0})` 会直接报错。

## 栈探测

在需要栈相关约定时（`/pencil-map` 建映射、`/pencil-assets` 出 token），按文件判定：

| 命中文件 | 栈 | 加载 |
|---|---|---|
| `pubspec.yaml` | Flutter | `references/stack-flutter.md` |
| `build.gradle` / `build.gradle.kts` / `AndroidManifest.xml` | Kotlin/Android | `references/stack-kotlin.md` |
| `package.json` | Web | `references/stack-web.md` |

命中多个 = 多栈项目，`design-map.yaml` 用 `stacks` 列表，各栈分别加载。

## Workflow

1. 读 `references/document-routing.md`，跑**会话启动检查单**（Pen 在跑？design-map 存在？哨兵命中？）。
2. 按上面的路由表进入对应命令。
3. 任何需要文档上下文的**读**操作也要带 `filePath`（本技能不解决焦点漂移问题，只能绕开）。
4. 涉及写入时，**先读 `references/write-safety.md` 并逐条执行**。

## Common Mistakes to Avoid

| 错误 | 后果 | 正确做法 |
|---|---|---|
| 用 `get_app_state` 确认「现在连的是哪个文档」 | 读到用户焦点所在的**别的项目**的稿子 | 用 `filePath` + 哨兵 |
| 写 `Get("document", {depth:0})` 想「先看全貌」 | 直接报错，浪费一轮 | 用 visitor 收集需要的字段 |
| 以为 `Get(visitor)` 会返回匹配节点 | 拿到一整个 `false` 数组 | visitor 内部用局部数组 `push` |
| 在 `Update` 里带 `type` | 走整节点替换路径，行为不可预期 | 只给要改的属性 |
| 用 `Delete` 隐藏一个组件实例的后代 | 直接抛 `Cannot delete descendants of instances!` | 改为 `enabled: false` |
| 以为图标能导出 SVG | Pen.app 不提供图标源码，`Export` 无 svg 格式 | 输出库名 + 图标名引用 |
| 用 `strokeWidth` 原值写进 viewBox | 描边粗细差一个比例 | 见 `references/assets-extraction.md`（换算**待实证**） |
| 写完就宣布完成 | 可能根本没落盘 | 提示用户保存 |

## Resources

- `references/mcp-toolbox.md` —— 5 个工具、`execute` API 全貌、visitor 写法、`Print` 通道
- `references/document-routing.md` —— `filePath`、静默回退、哨兵、启动检查单
- `references/write-safety.md` —— 写操作安全规程全文
- `references/design-map.md` —— `.pencil-bridge/design-map.yaml` 协议
- `references/assets-extraction.md` —— 四类素材的取法与坑
- `references/init-and-mcp.md` —— 逐 harness 的 MCP 配置细节
- `references/stack-flutter.md` / `stack-kotlin.md` / `stack-web.md` —— 分栈约定
```

- [ ] **Step 2: 校验通过**

Run:
```bash
cd /Users/howard/Project/pencil-bridge && bash bin/check 2>&1 | grep -E '^(ok|FAIL): pencil-bridge$'
```
Expected: `ok:   pencil-bridge`

- [ ] **Step 3: 提交**

```bash
cd /Users/howard/Project/pencil-bridge
git add skills/pencil-bridge/SKILL.md
git commit -m "docs: 主 bundle SKILL.md 总纲与命令路由"
```

---

## Task 6: `references/mcp-toolbox.md`

**Files:**
- Create: `skills/pencil-bridge/references/mcp-toolbox.md`

**Interfaces:**
- Consumes: 无。
- Produces: 全套 API 参考。Task 8/9/10/11/12 与四个薄壳都会引用它。

- [ ] **Step 1: 写文件**

必须包含这五节，内容来源如下（**逐字复制关键签名与报错原文，不要改写**）：

1. **5 个工具** —— `browser` / `execute` / `get_app_state` / `get_style` / `read_skill`，各自的用途；**明确写出**旧文档里的 `pencil_batch_get` / `pencil_get_screenshot` / `pencil_get_variables` **不存在，不得引用**。来源：spec §3.1。
2. **`execute` API 全貌** —— 把 spec §3.1 的 js 代码块**逐字**搬过来（`Insert` … `Export` 全部签名），再加 `GetOptions` / `ExportOptions` 说明，以及「每次 execute 独立作用域，跨调用只能靠不带声明的赋值」「失败要用 `editId` + `edits` 修补重跑，不能同时给 `input`」。
3. **visitor 正确写法** —— 把 spec §3.2 的 visitor 代码块与「返回的是每个节点上 visitor 的返回值数组，长度 = 遍历节点总数」这条**逐字**搬来，并附上**反面写法**（`Get(n => n.type === "path")` 会得到一整个 `false` 数组）。
4. **`Print` 是唯一输出通道** —— 不 `Print` 就拿不到任何数据；`GetVariables()` 也必须 `Print(GetVariables())` 才看得到。
5. **根别名与路径语法** —— `document` / `root` / `#document` / `#root`；`/` **只用于组件实例嵌套** `instanceId/childId`；普通层级不能 `/` 拼、**不支持索引**；name 可当 path 段但仅在其全局唯一时安全，多命中报 `Found multiple descendants named 'X'`。来源：`docs/reference/pencil-write-api-manual.md` 第 3 节。

- [ ] **Step 2: 提交**

```bash
cd /Users/howard/Project/pencil-bridge
git add skills/pencil-bridge/references/mcp-toolbox.md
git commit -m "docs: reference · mcp-toolbox"
```

---

## Task 7: `references/document-routing.md`

这个文件是「多项目不窜」的全部依据，写错等于整个套件失效。

**Files:**
- Create: `skills/pencil-bridge/references/document-routing.md`

**Interfaces:**
- Consumes: 无。
- Produces: 哨兵范式与会话启动检查单。四个薄壳全部引用它。

- [ ] **Step 1: 写文件**

必须包含：

1. **三探针实测表** —— 逐字抄 spec §3.2 的表（三个探针 × `filePath` / 焦点 / 实际读到）。
2. **路由结论** —— `filePath` 有效且按文档路由、**不改 `lastFocusedResource`**；目标文档未打开或路径不可解析时**静默回退到「最后聚焦的文档」且不报错**（最危险的失败模式）；三级查找顺序（URI 直命中 → 设备比对 → `lastFocusedResource` 兜底）。
3. **哪些工具没有 `filePath`** —— `get_app_state` / `read_skill` / `get_style`（**三个**），永远命中兜底分支。另注：`browser` 的 schema **声明了** `filePath` 且列在 `required` 里（2026-10-01 stdio `tools/list` 实测），但它**是否参与文档路由未经实测** —— 如实写成「未验证」，不要断言。
4. **无法切换活动文档** —— MCP 没有 open/switch/activate 工具；要打开只能 `open -a Pen <path>`（在既有实例里打开）。
5. **只读哨兵范式** —— 逐字抄 spec §3.2 的哨兵代码块，外加基线值：`yuexiaoshi.pen` 顶层 136、`hanzi_write.pen` 顶层 183。
6. **失败原文** —— `Failed to access file "<path>". A file needs to be open in the editor to perform this action.`
7. **会话启动检查单** —— 逐字抄 spec §10.1 的四个复选框，并写明「哨兵不符 → 停机报告，不重试」。

- [ ] **Step 2: 提交**

```bash
cd /Users/howard/Project/pencil-bridge
git add skills/pencil-bridge/references/document-routing.md
git commit -m "docs: reference · document-routing"
```

---

## Task 8: `references/write-safety.md`

**Files:**
- Create: `skills/pencil-bridge/references/write-safety.md`

**Interfaces:**
- Consumes: 无。
- Produces: 反写安全规程。`/pencil-sync` 的反向模式必须逐条执行它。

- [ ] **Step 1: 写文件**

必须包含：

1. **spec §11 的 12 条规程逐字搬入**（写前补偿备份、一次 execute 一个逻辑单元、Update 不带 type、数组整组替换、不传 children、删除优先 `enabled:false`、变量只用 merge、Generate 的 asset url 同调用内应用、Copy 后代一次做完、写后回读、收尾提示保存、回滚不可行时如实报告）。
2. **为什么不能用文件拷贝做备份** —— 磁盘 `.pen` 可能落后于 app 内存，文件拷贝 ≠ 状态快照；备份走 `Get(<nodeIds>,{depth})` 落 `.pencil-bridge/backups/<ISO8601>.json`。
3. **写操作语义速查表** —— 从 spec §3.5 抄成表格：`Update` 是 partial merge、`Replace` 全量替换并返回新 id、`Move` 的 index 仅非负 number 生效、`Delete` 级联删且对实例后代抛错、`Copy` 的 reusable 变 ref。
4. **undo 语义** —— 一次 `execute` = 一个撤销块；失败整次原子回滚，`Print` 与截图都不返回。
5. **未证实项** —— 写操作是否立即持久化到磁盘 **[未证实]**，提交路径只到 `sceneGraph.commitBlock`。
6. **凭据禁读清单** —— 逐字抄 spec §3.7 的七条。

- [ ] **Step 2: 提交**

```bash
cd /Users/howard/Project/pencil-bridge
git add skills/pencil-bridge/references/write-safety.md
git commit -m "docs: reference · write-safety"
```

---

## Task 9: `references/design-map.md`

**Files:**
- Create: `skills/pencil-bridge/references/design-map.md`

**Interfaces:**
- Consumes: 无。
- Produces: design-map 协议。`/pencil-map` 与 `/pencil-sync` 都依赖它。

- [ ] **Step 1: 写文件**

必须包含：

1. **文件位置与项目根定义** —— `<projectRoot>/.pencil-bridge/design-map.yaml`；项目根 = 含 `.git` 的最近祖先，无则回落 cwd（**取 projectRoot 而非 cwd**，因为命令可能在子目录被调用）。来源：spec §7.1。
2. **完整 schema 逐字搬入** —— spec §7.2 的 yaml 代码块（`version` / `design.file` / `design.sentinel` / `project.root` / `project.stack` 与 `stacks` 列表 / `pages[].design.node|id` / `pages[].code.file|selector` / `pages[].tokens`）。
3. **建立流程八步逐字搬入** —— spec §7.3（探测栈 → 定位设计文件 → 建哨兵 → 提取设计结构 → 扫描代码页面 → 自动配对 + **用户确认后才写** → 导入既有清单 → 支持用户主动输入模式）。
4. **重跑语义** —— 已存在条目**原地更新**、不重建文件、用户手工添加的字段保留。来源：spec §7.4。
5. **哨兵怎么选** —— 该项目**独有**、可稳定读到的顶层节点名，1–3 个。

- [ ] **Step 2: 提交**

```bash
cd /Users/howard/Project/pencil-bridge
git add skills/pencil-bridge/references/design-map.md
git commit -m "docs: reference · design-map 协议"
```

---

## Task 10: `references/assets-extraction.md`

**Files:**
- Create: `skills/pencil-bridge/references/assets-extraction.md`

**Interfaces:**
- Consumes: 无。
- Produces: 四类素材取法。`/pencil-assets` 依赖它。

- [ ] **Step 1: 写文件**

必须包含：

1. **四类产物的取法表** —— 逐字抄 spec §9 的表（位图 / 矢量 / 图标引用 / 变量 token，含「关键约束」列）。
2. **位图的路径解析** —— image fill 的 `url` 是**相对 `.pen` 所在目录**的磁盘相对路径；解析成绝对路径后**直接拷磁盘文件，不需要 MCP 传字节**；保留原扩展名。附实例：`assets/hanzi-design-v1/bg_character_of_day.png` → `<pen目录>/…`（1,679,293 B 真实 PNG）。
3. **矢量的字段与坑** —— `viewBox` **只在 `includePathGeometry: true` 时才随 `geometry` 返回**；`fill:"#00000000"` 是**全透明**，落成 `fill="none"`；`strokeWidth` 是**节点像素坐标下的值**，不能直接写进 viewBox 坐标系 —— 附样本 `width:72, height:72, viewBox:[0,0,24,24], strokeWidth:6`，**换算规则标为待实证，不得当定论用**。
4. **变量引用的落法** —— `stroke` / `fill` 是 `"$ink"` 这类变量引用时，**默认落成 `stroke="currentColor"`**，提供开关可强制 resolve 成实际色值；此默认值以实现时的开关暴露，**不写死**。
5. **三栈 token 输出格式** —— spec §9.2：web 出 CSS 自定义属性（多维主题按 `[data-theme]` / `prefers-color-scheme` 分组）、flutter 出 Dart 常量类、kotlin 出 `colors.xml`（必要时 `dimens.xml` / `styles.xml`）。
6. **提取边界** —— 不导出 `icon` 节点的矢量（Pen.app 无源码、`Export` 无 svg 格式）；不导出 `html-tailwind` / `html-css`（那是整页重建，属别的技能领域）。
7. **产物落地** —— `<projectRoot>/.pencil-bridge/assets/<timestamp>/`，摘要里列出每个文件的**来源节点 id**。

- [ ] **Step 2: 提交**

```bash
cd /Users/howard/Project/pencil-bridge
git add skills/pencil-bridge/references/assets-extraction.md
git commit -m "docs: reference · assets-extraction"
```

---

## Task 11: `references/init-and-mcp.md`

这是最长的一个 reference，`/pencil-init` 的全部行为都靠它。

**Files:**
- Create: `skills/pencil-bridge/references/init-and-mcp.md`

**Interfaces:**
- Consumes: 无。
- Produces: 逐 harness 的配置细节。Task 13 的 `pencil-init` 薄壳只指向它。

- [ ] **Step 1: 写文件**

必须包含这八节：

1. **定位：补齐 + 校验，不是从零配置** —— 抄 spec §6.1 的现状表（Codex ✅ / OpenCode ✅ / VS Code ✅ / DSH ⚠️ 两份 / 其余 ❌）。**Codex CLI 在 0.154.0 上已配**，不要盲目重写。
2. **前置硬门禁** —— `pgrep -f "/Applications/Pen.app/Contents/MacOS/Pen"` 必须在跑；二进制用 `fs.accessSync(bin, X_OK)` 检查存在且可执行；不存在时按 `getMcpBinaryName()` 架构矩阵算出**应然文件名**再报错。
3. **连通性验证配方** —— spawn `command + args`，依次发 `initialize` / `notifications/initialized` / `tools/list`；成功判据 `result.serverInfo.name === "pencil"` 且 `tools/list` 返回 5 个工具；**最强信号**是 stderr 出现 `[TransportClient] connected to /Users/howard/.pencil/socket/pencil-desktop.sock`；三种失败分流（stderr 无 connected / `command` ENOENT / 握手成功但 harness 看不到工具 = 未重启 harness）。
4. **DSH 特例（重复注册风险）** —— 两套机制并存：`cordis.patch.yml` 受管块里的 `panel-mcp-pencil`、`mcp_connector.json` 的 `tables.connections."json-pencil"`；第 0 步必须**两处都 grep `pencil`**，任一命中就不写第二处，两处都有则让用户选一处；**绝不修改** `# >>> dsh-skill-mcp-panel:mcp:begin` 与 `# <<< …:end` 之间内容（面板重写会静默抹掉块内手写内容），要加就在**标记之外**追加独立 `- insert:` 条目；`cordis.yml`（合成产物）不要手改；`mcp_connector.json` 是 373 KB 版本化领域存储，建议交给 GUI 或插件 API。
5. **写入铁律** —— **禁止整文件序列化写回**（Pen.app 官方 installer 就是这么干的，会丢掉 `~/.codex/config.toml` 全部注释与键序、把 99,958 B 的 `~/.claude.json` 整体重排，**本设计不复刻**）；改为**文本级定点定位容器**，在容器起始 `{` 后插入渲染好的片段，缩进**逐字对齐该文件现有条目**。
6. **容器键名四种形态表** —— 逐字抄 spec §6.5 的表（`mcpServers` / `servers`(VS Code) / `mcp`(OpenCode) / `mcp_servers`(Codex)），并写明 OpenCode 的 `command` 是 `[exe, ...args]` 数组、`type: "local"`、`enabled: true`。
7. **三个会毒死严格解析器的文件** —— `~/.config/opencode/opencode.json` 第 164 行有**尾部逗号**（`JSON.parse` 直接抛 `Expecting property name enclosed in double quotes`）；`~/.continue/config.json` 含 `//` 注释；`~/.gemini/antigravity/mcp_config.json` 是 **0 字节**，必须当 `{}` 处理。另外 **Claude Code 要写两处**：`~/.claude.json` 的连接定义 **加上** `~/.claude/settings.json` 的 `permissions.allow` 必须含 `"mcp__pencil"`（去重）。原子性：同目录 temp + `rename` + 锁文件；写前备份 `<file>.pencil-init.bak.<ISO8601>`，同一次运行内不覆盖已有备份；幂等靠「容器键 + 名字」定位。
8. **探测与生效** —— **探测已装 harness 不能靠 `command -v`**（本机 `dsh`/`claude`/`codex`/`opencode`/`gemini`/`cursor-agent` 全部找不到，皆 GUI 形态），只能靠**配置文件是否存在**；抄 spec §6.6 的生效条件表，并**对除 DSH 外的每一行如实标注「未验证」**；`--agent` 值按 harness 填（`claudeCodeCLI` / `codexCLI` / `openCodeCLI` / `copilotIDE` / `geminiCLI`），**DSH 侧保持与现状一致（不加 `--agent`）**。

- [ ] **Step 2: 提交**

```bash
cd /Users/howard/Project/pencil-bridge
git add skills/pencil-bridge/references/init-and-mcp.md
git commit -m "docs: reference · init-and-mcp"
```

---

## Task 12: 三个分栈 reference

**Files:**
- Create: `skills/pencil-bridge/references/stack-flutter.md`
- Create: `skills/pencil-bridge/references/stack-kotlin.md`
- Create: `skills/pencil-bridge/references/stack-web.md`

**Interfaces:**
- Consumes: Task 10 定义的 token 输出格式约定。
- Produces: 三份按需加载的栈约定。

- [ ] **Step 1: 写 `stack-flutter.md`**

必须包含：**项目识别**（`pubspec.yaml`，注意 `client/` 与 `admin/` 这类单仓多栈布局）；**页面定位约定**（`lib/pages/` 之类，用 `class XxxPage` 作 selector 锚点，与 `design-map.yaml` 的 `pages[].code.selector` 对应）；**样式改动落点**（颜色/间距/圆角/字号/字重/布局方向分别改哪里；Flutter 里 `ThemeData`、`Color`、`EdgeInsets`、`BorderRadius`、`TextStyle` 的对应）；**Dart token 常量类输出格式**（`class YxsTokens { static const primary = Color(0xFF...); }`）；**变量引用的映射**（`"$yxs-primary"` 如何落成 Dart 常量名 —— 去掉 `$`、`-` 转驼峰）；**不改结构不改文案**这条边界。

- [ ] **Step 2: 写 `stack-kotlin.md`**

必须包含：**项目识别**（`build.gradle` / `build.gradle.kts` / `AndroidManifest.xml`）；**页面定位**（XML 布局 vs Jetpack Compose 两条路径，selector 锚点怎么写）；**样式改动落点**（`colors.xml` / `dimens.xml` / `styles.xml` / Compose 的 `MaterialTheme`）；**`colors.xml` 输出格式**（`<color name="yxs_primary">#...</color>`，名字规则与 Dart 侧一致）；**资源目录约定**（`res/values/`、`res/values-night/` 对应暗色主题）；**不改结构不改文案**。

- [ ] **Step 3: 写 `stack-web.md`**

必须包含：**项目识别**（`package.json`，注意区分纯静态 HTML 与构建型项目 —— 工作目录 `/Users/howard/Documents/PCData` 里就是几个散装 `*-index.html`）；**页面定位**（CSS 选择器与组件文件）；**样式改动落点**（CSS 自定义属性、内联样式、Tailwind 工具类）；**CSS 变量输出格式**（`:root { --yxs-primary: ...; }`，多维主题按 `[data-theme="dark"]` 或 `@media (prefers-color-scheme: dark)` 分组）；**Tailwind 映射约定**（若项目有 Tailwind，说明设计变量如何落到 `theme.extend`，没有则说明不引入）；**不改结构不改文案**。

- [ ] **Step 4: 校验并提交**

Run:
```bash
cd /Users/howard/Project/pencil-bridge && bash bin/check 2>&1 | tail -3
```
Expected: `全部通过。`

```bash
git add skills/pencil-bridge/references/stack-*.md
git commit -m "docs: 三个分栈 reference（flutter / kotlin / web）"
```

---

## Task 13: 四个薄命令 SKILL.md

薄壳只做三件事：声明触发场景、用相对路径指向主 bundle 的对应 reference、声明该命令的输入输出契约。

**Files:**
- Modify: `skills/pencil-init/SKILL.md`
- Modify: `skills/pencil-map/SKILL.md`
- Modify: `skills/pencil-sync/SKILL.md`
- Modify: `skills/pencil-assets/SKILL.md`

**Interfaces:**
- Consumes: Task 6–12 的全部 reference。
- Produces: 四个可被 `/name`（DSH、Claude）与 `$name`（Codex）触发的技能。

- [ ] **Step 1: 写 `pencil-init/SKILL.md` 正文**

每个薄壳都保留 Task 1 的 frontmatter，把 `（正文见 Task 13）` 换成如下结构（以 init 为例，其余三条同构）：

```markdown
## 何时使用

连不上 pencil、刚装好 Pen.app、换了机器、或想确认配置状态时。

## 先读这些

- `../pencil-bridge/references/init-and-mcp.md`（**本命令的全部细节都在这里**）
- `../pencil-bridge/references/document-routing.md`（若要顺带验证文档连通）

## 输入

无参数。用户可能附带说明「只检查不修改」。

## 流程

1. **只读诊断**（默认行为，永远先做）：Pen.app 是否在跑 → MCP 二进制是否存在且可执行 → 各 harness 的注册状态 → socket 连通性。
2. **报告**：逐项给出「现状 / 判定 / 建议」，并如实标注哪些结论是「未验证」的。
3. **写入**：只有在用户明确要求时才进入写配置流程，且**逐条**执行 `init-and-mcp.md` 的写入铁律（定点插入、不整文件重写、写前备份、幂等）。

## 输出契约

一张诊断表 + 明确结论。若发现 DSH 上 pencil 已被注册（两处机制任一命中），**报告并停止**，不要写第二处。

## 铁律

- 默认只读。任何写入前必须询问。
- 探测已装 harness **不能靠 `command -v`**，只能靠配置文件是否存在。
- **绝不触碰** `dsh-skill-mcp-panel` 的受管标记块。
```

- [ ] **Step 2: 写 `pencil-map/SKILL.md` 正文**

同样结构，要点：先读 `design-map.md` + `document-routing.md`（跑启动检查单）；**探测项目栈**（命中多个记为多栈）；**定位设计文件**；**建哨兵**；提取设计结构；扫描代码页面；**给出候选配对表 → 用户确认后才写文件**；支持导入既有清单（如 yuexiaoshi 的 `docs/design-review/manifest.json`）；支持用户**主动输入节点名与页面名**的模式；重跑时原地更新、保留用户手加字段。输出契约：`<projectRoot>/.pencil-bridge/design-map.yaml`。

- [ ] **Step 3: 写 `pencil-sync/SKILL.md` 正文**

要点：先读 `design-map.md` + `document-routing.md` + `write-safety.md`（**反向模式必读**）+ 对应栈文件。**正向**（设计→代码）：校验文档身份 → 拉节点树 `Get(<id>, {depth, resolveVariables:true})` → 产出差异清单 → **直接改，改完给 diff 摘要**（不做事前确认清单）→ 同步范围限颜色/间距/圆角/字号/字重/布局方向，**不改结构不改文案**。**反向**（代码→设计）：逐条走 `write-safety.md`，用**节点 id** 定位而非名字，写后回读，收尾提示保存，回滚不可行时如实报告。输出契约：改动文件清单 + diff 摘要（正向），或备份文件路径 + 回读结果（反向）。

- [ ] **Step 4: 写 `pencil-assets/SKILL.md` 正文**

要点：先读 `assets-extraction.md` + `document-routing.md` + 对应栈文件。四类产物（位图/矢量/图标引用/变量 token）按用户指定或全出。产物落 `<projectRoot>/.pencil-bridge/assets/<timestamp>/`，摘要里列出**每个文件的来源节点 id**。边界：不导出 icon 矢量、不导出 html-tailwind/html-css。

- [ ] **Step 5: 校验引用有效并提交**

Run:
```bash
cd /Users/howard/Project/pencil-bridge && bash bin/check
```
Expected: `全部通过。`（`bin/check` 会逐个验证每个薄壳引用的 reference 真实存在）

```bash
git add skills/pencil-*/SKILL.md
git commit -m "feat: 四条薄命令 SKILL.md"
```

---

## Task 14: 真机安装与三 harness 可见性验证

前面的测试都在临时 `$HOME` 里跑。这一步装到真机 —— 会写入 `~/.agents/skills`、`~/.claude/skills`、`~/.codex/skills`。

**Files:**
- 无新建。会写到真机家目录。

**Interfaces:**
- Consumes: Task 3/4 的 `bin/link`。
- Produces: 三 harness 可见的技能包。Task 15 的验收依赖它。

- [ ] **Step 1: 记录安装前状态（便于回滚）**

Run:
```bash
for n in pencil-bridge pencil-init pencil-map pencil-sync pencil-assets; do
  for r in ~/.agents/skills ~/.claude/skills ~/.codex/skills; do
    if [ -e "$r/$n" ] || [ -L "$r/$n" ]; then echo "已存在: $r/$n"; fi
  done
done
echo "（无输出 = 五个技能名在三处都不存在，安装是干净的）"
```

- [ ] **Step 2: 先 dry-run 看清将要做什么**

Run:
```bash
cd /Users/howard/Project/pencil-bridge && bash bin/link --dry-run
```
Expected: 打印 15 条动作（5 技能 × 3 根），**不做任何落盘**。

- [ ] **Step 3: 真跑**

Run:
```bash
cd /Users/howard/Project/pencil-bridge && bash bin/link
```

- [ ] **Step 4: 验证三种形态确实不同**

Run:
```bash
echo "--- DSH 侧（应为软链）---"
ls -l ~/.agents/skills/pencil-bridge
echo "--- Claude 侧（应为软链）---"
ls -l ~/.claude/skills/pencil-bridge
echo "--- Codex 侧（应为真实目录，非软链）---"
ls -ld ~/.codex/skills/pencil-bridge
readlink ~/.codex/skills/pencil-bridge && echo "❌ 不该是软链" || echo "✅ 不是软链"
echo "--- Codex 副本内容一致性 ---"
diff -rq ~/Project/pencil-bridge/skills ~/.codex/skills --exclude=.system | head
echo "（无输出 = 完全一致；注意 .system 是 Codex 自带的，要排除）"
```
Expected: 前两处是软链；Codex 侧是真实目录且 `readlink` 失败；`diff -rq` 无差异输出。

- [ ] **Step 5: 验证薄壳的相对路径在软链下仍能解析**

这是最容易出错的一环 —— 软链会让 `..` 的解析基准变得微妙。

Run:
```bash
cd ~/.agents/skills/pencil-map && cat ../pencil-bridge/references/document-routing.md | head -3
echo "--- 从真源侧也要能解析 ---"
cd ~/Project/pencil-bridge/skills/pencil-map && cat ../pencil-bridge/references/document-routing.md | head -3
```
Expected: 两条命令都打印出 `document-routing.md` 的开头。任一失败说明 `bin/link` 漏了主 bundle 的扇出。

- [ ] **Step 6: 提交（若有因安装暴露的修复）**

```bash
cd /Users/howard/Project/pencil-bridge
git status --short
git add -A && git commit -m "fix: 真机安装暴露的问题" || echo "无需提交"
```

---

## Task 15: spec §14 验收标准逐条实测

**Files:**
- 无新建。可能需临时改动 yuexiaoshi / hanzi_write 项目（**测完必须还原**）。

**Interfaces:**
- Consumes: Task 14 安装好的技能包、Task 1–13 的全部内容。
- Produces: 验收结论。这是整个计划的终态。

- [ ] **Step 1: 前置条件核对**

Run:
```bash
pgrep -f "/Applications/Pen.app/Contents/MacOS/Pen" >/dev/null && echo "✅ Pen.app 在跑" || echo "❌ Pen.app 未运行"
ls -l /Applications/Pen.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-arm64
echo "--- 当前打开的文档 ---"
cat ~/Library/Application\ Support/Pen/recent-documents.json | head -c 400
```
Expected: Pen.app 在跑、二进制存在且可执行。

- [ ] **Step 2: 验收 1 —— `/pencil-map` 在 yuexiaoshi 生成映射**

在 DSH 里切到 `/Users/howard/Project/yuexiaoshi` 会话，输入 `/pencil-map`。检查：
- `<projectRoot>/.pencil-bridge/design-map.yaml` 被创建（**且在用户确认之后**）
- `design.sentinel` 是该项目独有的顶层节点名
- 若导入了 `docs/design-review/manifest.json`，原文件**未被改动**

- [ ] **Step 3: 验收 2 —— 双文档并行不窜**

同时打开 yuexiaoshi.pen 与 hanzi_write.pen。在 yuexiaoshi 项目跑 `/pencil-sync`（或让 AI 只跑哨兵读取）：
- 记录第一次读到的哨兵值与顶层计数
- **把焦点切到 hanzi_write 窗口**，再跑一次
- 两次结果必须**完全相同**（yuexiaoshi 顶层 136）

Run（辅助核对）:
```bash
echo "yuexiaoshi 顶层应为 136；hanzi_write 顶层应为 183"
```

- [ ] **Step 4: 验收 3 —— 指向未打开的 .pen 必须停机**

把 yuexiaoshi 项目 `design-map.yaml` 的 `design.file` 临时改成一个**未打开**的 `.pen` 路径，跑 `/pencil-sync`。期望：命令**停机并报告**，**不静默改错文档**。测完还原该字段。

- [ ] **Step 5: 验收 4 —— `E5QUX` 的矢量与图标**

在 hanzi_write 项目对 `E5QUX` 跑 `/pencil-assets`。期望：
- 导出 7 个 `path` 节点的 SVG（每个含正确 `viewBox` 与 `fill="none"`）
- 列出 34 个 `icon` 节点的**库名 + 图标名**引用

Run（辅助核对）:
```bash
echo "E5QUX 直方图应为 {frame:60, text:18, icon:34, path:7}"
echo "7 个 path 的 name 应为: icon_tmpl_trace icon_game_huarongdao icon_character_of_day"
echo "                        icon_type_poetry icon_type_idiom icon_type_xiehouyu icon_membership"
```

- [ ] **Step 6: 验收 5 —— `/pencil-init` 只读报告**

在 DSH 里跑 `/pencil-init`。期望报告：Pen.app 状态、二进制存在性、**DSH 上 pencil 的两处注册**（`cordis.patch.yml` 受管块 + `mcp_connector.json` 的 `json-pencil`），并**不写入任何配置**。

- [ ] **Step 7: 验收 6 —— 反写与回滚**

反写一次面板样式（在 hanzi_write 或 yuexiaoshi 的一个**安全子节点**上）：
- 检查 `backups/<ISO8601>.json` 已生成
- 用备份里的原值回滚一次，确认能改回去
- 确认收尾**提示了用户保存**

- [ ] **Step 8: 记录验收结果**

把六条验收的实测结论（通过/失败 + 证据）追加到 spec 的 §14 之后，或写入 `docs/reference/acceptance-2026-10-01.md`。

```bash
cd /Users/howard/Project/pencil-bridge
git add -A
git commit -m "docs: spec §14 验收标准实测结果"
```

---

## 自审记录

**1. Spec coverage** —— 逐节对照：

| spec 节 | 落在哪个任务 |
|---|---|
| §1 Goal / §2 Non-goals | Global Constraints + Task 5 |
| §3.1 MCP 接口面 | Task 1 frontmatter、Task 6 |
| §3.2 文档路由 | Task 7（哨兵/回退）、Task 5（Critical Rules） |
| §3.3 节点模型 | Task 6（visitor/根别名）、Task 10（path/icon/image） |
| §3.4 变量 | Task 8（replace 禁用）、Task 10（token 输出） |
| §3.5 写操作语义 | Task 8（速查表 + undo + 未证实项） |
| §3.6 进程模型 | Task 7（无法切换文档）、Task 11（门禁） |
| §3.7 无版本控制 + 凭据清单 | Task 8（备份理由 + 凭据清单） |
| §4.1 目录结构 | File Structure + Task 1 |
| §4.2 主 bundle + 薄命令 | Architecture + Task 13 |
| §4.3 扇出机制 | Task 3、Task 4、Task 14 |
| §4.4 frontmatter 铁律 | Global Constraints + Task 2（`bin/check` 强制） |
| §4.5 Codex 触发差异 | Task 1（每个 frontmatter 下写双写法）、Task 5、Task 13 |
| §5 四条命令 | Task 5（路由表）、Task 13（四个薄壳） |
| §6 `/pencil-init` | Task 11 + Task 13 |
| §7 `/pencil-map` | Task 9 + Task 13 |
| §8 `/pencil-sync` | Task 8 + Task 13 |
| §9 `/pencil-assets` | Task 10 + Task 12 + Task 13 |
| §10 多项目隔离 | Task 7 + Task 5 |
| §11 写操作安全规程 | Task 8 |
| §12 references 组织 | File Structure + Task 6–12 |
| §13 未证实项 | 分散标注：Task 8（落盘）、Task 10（strokeWidth）、Task 11（生效条件标「未验证」）、Global Constraints（Codex 复制已裁决） |
| §14 验收标准 | Task 15（六条逐条） |

无遗漏。

**2. Placeholder scan** —— 已检查：无 TBD / TODO / 「稍后实现」；`bin/link` 与 `bin/check` 给出完整可运行代码；文档类任务给出逐字 frontmatter、精确章节清单、来源 spec 节号与必须出现的硬事实（这是有意为之 —— 见 File Structure 末尾的「关于文档类任务的『代码』约定」，逐字重抄 spec 会制造第二份真源）。

**3. Type consistency** —— 已核对：
- `bin/check` 的环境变量 `PENCIL_BRIDGE_SKILLS_DIR` 在测试与实现中**同名**。
- 五个技能名 `pencil-bridge` / `pencil-init` / `pencil-map` / `pencil-sync` / `pencil-assets` 在 `bin/link`、`bin/check`、测试、File Structure 中**完全一致**。
- 9 个 reference 文件名在 `bin/check` 的 `REFS` 数组、File Structure、Task 5 的 Resources 列表、Task 6–12 中**完全一致**。
- 相对路径形态统一为 `../pencil-bridge/references/<file>.md`（`bin/check` 的正则即按此写）。

**4. Script executability verification** —— 把计划里两个脚本与两套测试**逐字提取到 `/tmp` 实跑**（不是纸面审查），抓到并修掉三处真缺陷：

| # | 缺陷 | 后果 | 修法 |
|---|---|---|---|
| 1 | `tests/check.test.sh` 的 `mk()` 只接受 3 个参数，`BAD2`/`BAD3` 却传了 4 个 | legacy 键与 `allowed-tools` **从未被注入**，用例名不副实 | 重写为 `mk_full()` 造完整基线（5 技能 + 9 reference）+ `inject_fm()` 定点注入 |
| 2 | `BAD3`/`BAD4` 基线不完整（缺 `pencil-bridge/SKILL.md`） | 退出码虽为 1，却是因为「缺 SKILL.md」而非被测行为 —— **假阳性** | 同上：每个反例只在完整基线上注入**单一**缺陷 |
| 3 | `bin/check` 用整文件 `grep` 检测 legacy/banned 键 | 正文里出现 `allowed-tools:` 字样即**误报**（DSH 实际只读 frontmatter） | 新增 `fm_has_key()`（awk，只在前 1 个 frontmatter 块内查找） |

另外把 `check_case` 强化为**同时断言退出码与输出中的具体原因**（第 4 个参数 `needle`），从机制上堵死假阳性。

顺带加固：`bin/link` 增加源技能齐全性前置校验 —— 否则软链分支会造**悬空软链**、宿主静默忽略，复制分支则在中途崩溃，两种失败都不报清楚原因。

实测结果：`tests/check.test.sh` **9/9 通过**、`tests/link.test.sh` **27/27 通过**；修正后**再次从计划文件本身提取**并重跑，同样 9/9 与 27/27 —— 计划中给出的代码是可执行且已实际执行的。

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-10-01-pencil-bridge-implementation.md`. Two execution options:**

**1. Subagent-Driven (recommended)** —— 每个任务派一个全新 subagent，任务之间我来 review，迭代快、上下文干净

**2. Inline Execution** —— 在当前会话里按 executing-plans 批量执行，中间设检查点

**Which approach?**
