#!/usr/bin/env bash
# tests/link.test.sh —— 在隔离的临时 $HOME 里验证 bin/link
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
DRY_HOME=""
export HOME="$TMP_HOME"

# R12（崩溃安全）：本测试会往被跟踪的真源 skills/pencil-assets/SKILL.md 追加内容。
# 先把它备份到 $TMP_HOME，并用 trap 覆盖 EXIT/INT/TERM 三条退出路径，
# 这样 Ctrl-C / timeout / SIGTERM 中断也不会把未提交的改动留在真源上
# （本脚本刻意没有 set -e，不能依赖"执行到下一行"来恢复）。
REAL_ASSETS_SKILL="$REPO_ROOT/skills/pencil-assets/SKILL.md"
ASSETS_BACKUP="$TMP_HOME/pencil-assets.SKILL.md.bak"
cp "$REAL_ASSETS_SKILL" "$ASSETS_BACKUP"

restore_real_assets() {
  [ -f "$ASSETS_BACKUP" ] && cp "$ASSETS_BACKUP" "$REAL_ASSETS_SKILL"
  return 0
}
cleanup() {
  restore_real_assets
  [ -n "$DRY_HOME" ] && rm -rf "$DRY_HOME"
  rm -rf "$TMP_HOME"
  return 0
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

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

# --- R15(a): 未知 harness 必须报错退出，不能静默假装成功 ---
for bad in foo agent agentss; do
  assert "未知 harness 报错退出（--only $bad）" \
    bash -c '! bash "$1/bin/link" --only "$2" >/dev/null 2>&1' _ "$REPO_ROOT" "$bad"
done
assert "未知 harness 退出码为 2" \
  bash -c 'bash "$1/bin/link" --only bogus >/dev/null 2>&1; [ $? -eq 2 ]' _ "$REPO_ROOT"
assert "未知 harness 把诊断打到 stderr" \
  bash -c 'bash "$1/bin/link" --only bogus 2>&1 >/dev/null | grep -q "未知 harness: bogus"' _ "$REPO_ROOT"
BOGUS_HOME="$TMP_HOME/bogus-home"
mkdir -p "$BOGUS_HOME"
HOME="$BOGUS_HOME" bash "$REPO_ROOT/bin/link" --only bogus >/dev/null 2>&1
assert "未知 harness 不创建任何技能根" \
  [ ! -e "$BOGUS_HOME/.agents/skills" -a ! -e "$BOGUS_HOME/.claude/skills" -a ! -e "$BOGUS_HOME/.codex/skills" ]

# --- R15(b): dry-run 在全新空 HOME 上必须一个根目录都不创建 ---
# （原两条 dry-run 断言只看"预置障碍仍在"，真跑同样成立；这里补上真正的鉴别力）
DRY_HOME="$(mktemp -d)"
HOME="$DRY_HOME" bash "$REPO_ROOT/bin/link" --dry-run >/dev/null 2>&1; RC_DRY=$?
assert "dry-run 退出码为 0" [ "$RC_DRY" -eq 0 ]
assert "dry-run 未创建 .agents/skills" [ ! -e "$DRY_HOME/.agents/skills" ]
assert "dry-run 未创建 .claude/skills" [ ! -e "$DRY_HOME/.claude/skills" ]
assert "dry-run 未创建 .codex/skills" [ ! -e "$DRY_HOME/.codex/skills" ]

# --- R15(c): 关键调用的退出码断言（本脚本没有 set -e，必须显式断言） ---
bash "$REPO_ROOT/bin/link" >/dev/null 2>&1; RC_FULL=$?
assert "全量运行退出码为 0" [ "$RC_FULL" -eq 0 ]
bash "$REPO_ROOT/bin/link" --only codex >/dev/null 2>&1; RC_CODEX=$?
assert "--only codex 退出码为 0" [ "$RC_CODEX" -eq 0 ]

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
echo "# 临时改动" >> "$REAL_ASSETS_SKILL"
bash "$REPO_ROOT/bin/link" --only codex >/dev/null 2>&1; RC_CODEX_SYNC=$?
assert "--only codex（真源改动后）退出码为 0" [ "$RC_CODEX_SYNC" -eq 0 ]
assert "重跑后副本跟上了真源改动" \
  diff -q "$REPO_ROOT/skills/pencil-assets/SKILL.md" \
          "$HOME/.codex/skills/pencil-assets/SKILL.md"
restore_real_assets
assert "真源 SKILL.md 已还原（与备份逐字节一致）" \
  diff -q "$ASSETS_BACKUP" "$REAL_ASSETS_SKILL"

# 反向：副本里多出的文件，重跑后必须消失（证明"先删后拷"）
touch "$HOME/.codex/skills/pencil-map/GARBAGE"
bash "$REPO_ROOT/bin/link" --only codex >/dev/null 2>&1; RC_CODEX_PURGE=$?
assert "--only codex（清除多余文件）退出码为 0" [ "$RC_CODEX_PURGE" -eq 0 ]
assert "副本中的多余文件被清除" [ ! -e "$HOME/.codex/skills/pencil-map/GARBAGE" ]

echo
echo "通过 $PASS 项，失败 $FAIL 项。"
[ "$FAIL" -eq 0 ]
