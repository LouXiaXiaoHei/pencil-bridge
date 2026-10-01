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
