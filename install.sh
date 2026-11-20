#!/usr/bin/env bash
# Installs review-gate and the require-pre-pr hook to ~/.local/bin, the staff-reviewer agent to ~/.claude/agents, and the
# pre-pr skill to ~/.agents/skills (read by Pi) with a ~/.claude/skills symlink (read by Claude Code).
# Idempotent: re-running updates changed files and reports unchanged ones.
# Use this or the review-kit plugin, not both: both together give two copies of the agent and skill.
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
AGENT_DIR="${AGENT_DIR:-$HOME/.claude/agents}"
SKILL_DIR="${SKILL_DIR:-$HOME/.agents/skills}"
CLAUDE_SKILL_DIR="${CLAUDE_SKILL_DIR:-$HOME/.claude/skills}"

put() { # src dst mode
  local src="$1" dst="$2" mode="$3"
  mkdir -p "$(dirname "$dst")"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then echo "unchanged  $dst"
  else
    local verb=installed; [ -f "$dst" ] && verb=updated
    cp "$src" "$dst.tmp.$$" && chmod "$mode" "$dst.tmp.$$" && mv "$dst.tmp.$$" "$dst"
    echo "$verb  $dst"
  fi
}

put "$KIT/review-gate" "$BIN_DIR/review-gate" 755
put "$KIT/hooks/require-pre-pr.sh" "$BIN_DIR/require-pre-pr" 755
put "$KIT/agents/staff-reviewer.md" "$AGENT_DIR/staff-reviewer.md" 644

# link dst target: create the symlink, or leave anything else at dst alone.
link() {
  local dst="$1" target="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$target" ]; then echo "unchanged  $dst"
  elif [ -e "$dst" ] || [ -L "$dst" ]; then echo "skipped  $dst (exists and is not a link to $target; remove it to install)"
  else mkdir -p "$(dirname "$dst")" && ln -s "$target" "$dst" && echo "linked  $dst -> $target"
  fi
}
if [ -L "$SKILL_DIR/pre-pr" ]; then
  echo "skipped  $SKILL_DIR/pre-pr (is a symlink to $(readlink "$SKILL_DIR/pre-pr"); remove it to install)"
else
  put "$KIT/skills/pre-pr/SKILL.md" "$SKILL_DIR/pre-pr/SKILL.md" 644
fi
link "$CLAUDE_SKILL_DIR/pre-pr" "$SKILL_DIR/pre-pr"

case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "note: $BIN_DIR is not on PATH; add: export PATH=\"$BIN_DIR:\$PATH\"" ;; esac
echo "Per project: copy a .review-gate.sh (see examples/) and a REVIEW.md to the repo root."
echo "To block gh pr create until /pre-pr passed, see \"Require the review before a PR\" in the README."
