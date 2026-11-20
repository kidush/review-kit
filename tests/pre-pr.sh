#!/usr/bin/env bash
# Offline tests for the pre-pr skill and the plugin packaging (no model calls, no network).
# Covers: install.sh (fresh, idempotent, never clobbers), the Pi reviewer snippet in SKILL.md run
# against a stub pi, prompt drift between the Claude Code and Pi reviewer prompts, the bin/
# symlink the plugin puts on PATH, and `claude plugin validate --strict` when claude is installed.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SKILL="$ROOT/skills/pre-pr/SKILL.md"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FAILED=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'BAD   %s\n' "$1"; shift; for l in "$@"; do printf '        %s\n' "$l"; done; FAILED=1; }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

# ---------- install.sh ----------
inst() { BIN_DIR="$W/h/bin" AGENT_DIR="$W/h/agents" SKILL_DIR="$W/h/agents-skills" \
  CLAUDE_SKILL_DIR="$W/h/claude-skills" "$ROOT/install.sh"; }
out=$(inst 2>&1); rc=$?
check "install: exits 0" test "$rc" = 0
check "install: skill copied" cmp -s "$SKILL" "$W/h/agents-skills/pre-pr/SKILL.md"
check "install: claude skill link" test "$(readlink "$W/h/claude-skills/pre-pr")" = "$W/h/agents-skills/pre-pr"
check "install: gate executable" test -x "$W/h/bin/review-gate"
out=$(inst 2>&1)
if grep -qE '^(installed|updated|linked) ' <<<"$out"; then bad "install: second run changes nothing" "$out"; else ok "install: second run changes nothing"; fi
rm -rf "$W/h"; mkdir -p "$W/h/claude-skills/pre-pr"; echo mine > "$W/h/claude-skills/pre-pr/SKILL.md"
mkdir -p "$W/other"; mkdir -p "$W/h/agents-skills"; ln -s "$W/other" "$W/h/agents-skills/pre-pr"
out=$(inst 2>&1); rc=$?
check "install: exits 0 with existing paths" test "$rc" = 0
check "install: keeps an existing claude skill dir" grep -qx mine "$W/h/claude-skills/pre-pr/SKILL.md"
check "install: keeps an existing skill symlink" test "$(readlink "$W/h/agents-skills/pre-pr")" = "$W/other"
check "install: nothing written through the symlink" test ! -e "$W/other/SKILL.md"
if [ "$(grep -c '^skipped ' <<<"$out")" = 2 ]; then ok "install: reports both skips"; else bad "install: reports both skips" "$out"; fi

# ---------- Pi snippet against a stub pi ----------
mkdir -p "$W/stub"
cat > "$W/stub/pi" <<'EOF'
#!/usr/bin/env bash
# Stub: records its arguments, prints the prompt (last argument), exits FAKE_PI_EXIT.
printf '%s\n' "$@" > "$(mktemp "$FAKE_PI_LOG/call.XXXXXX")"
printf 'REVIEW OF: %s\n' "${@: -1}"
echo "stub stderr" >&2
exit "${FAKE_PI_EXIT:-0}"
EOF
chmod +x "$W/stub/pi"
awk '/^```bash$/{f=1;next} /^```$/{f=0} f' "$SKILL" | sed 's|^base=origin/main.*|base="origin/release 1"|' > "$W/snippet.sh"
check "pi: snippet extracted" grep -q 'pi --print' "$W/snippet.sh"
check "pi: snippet parses" bash -n "$W/snippet.sh"
pi_run() { mkdir -p "$W/log$1"; (cd "$W" && PATH="$W/stub:$PATH" TMPDIR="$W" FAKE_PI_LOG="$W/log$1" FAKE_PI_EXIT="$2" bash "$W/snippet.sh" 2>&1); }
out=$(pi_run ok 0)
reports=$(sed -n 's/^Reports: //p' <<<"$out")
check "pi: reports folder under TMPDIR" test -d "$reports" -a "${reports#"$W"/}" != "$reports"
check "pi: both exit 0" test "$(grep -c 'exit: 0$' <<<"$out")" = 2
check "pi: two processes started" test "$(ls "$W/logok" | wc -l | tr -d ' ')" = 2
check "pi: both reports written" test -s "$reports/reviewer-1.txt" -a -s "$reports/reviewer-2.txt"
check "pi: stderr kept apart" grep -q 'stub stderr' "$reports/reviewer-1.err"
check "pi: base with a space reaches the prompt" grep -q 'git diff origin/release 1\.\.\.HEAD' "$reports/reviewer-1.txt"
for f in --print --no-session --no-extensions --no-mcp --no-skills --no-prompt-templates; do
  check "pi: passes $f" grep -qx -- "$f" "$(ls "$W"/logok/* | head -1)"
done
check "pi: tools limited to read,bash" grep -qx 'read,bash' "$(ls "$W"/logok/* | head -1)"
out=$(pi_run fail 3)
if [ "$(grep -c 'exit: 3$' <<<"$out")" = 2 ]; then ok "pi: failing reviewers report their exit code"; else bad "pi: failing reviewers report their exit code" "$out"; fi

# ---------- one reviewer prompt for both runtimes ----------
claude_prompt=$(sed -n 's/^> \(Review the code change.*\)$/\1/p' "$SKILL" | tr -d '`' | sed 's/<base>/$base/')
pi_prompt=$(sed -n 's/^prompt="\(.*\)"$/\1/p' "$SKILL")
if [ -n "$claude_prompt" ] && [ "$claude_prompt" = "$pi_prompt" ]; then ok "prompt: Claude Code and Pi prompts match"
else bad "prompt: Claude Code and Pi prompts match" "claude: $claude_prompt" "pi:     $pi_prompt"; fi

# ---------- plugin packaging ----------
check "plugin: bin/review-gate runs" bash -c '"$1" --help >/dev/null' _ "$ROOT/bin/review-gate"
check "skill: frontmatter name" grep -qx 'name: pre-pr' "$SKILL"
if command -v claude >/dev/null; then
  out=$(claude plugin validate "$ROOT" --strict 2>&1); rc=$?
  if [ "$rc" = 0 ]; then ok "plugin: validate --strict"; else bad "plugin: validate --strict" "$out"; fi
else
  echo "SKIP  plugin: validate --strict (claude not installed)"
fi

# ---------- eval fixtures: each scaffold builds, passes its tests and the gate, and the bug is real ----------
# The benchmark only measures review if the gate and tests pass and the planted bug really misbehaves.
# The eval sandbox masks git, so reviewers read the change from CHANGE.diff, which the scaffold writes.
declare -A PROOF=(
  [review-idor]="
c=store.connect(); c.execute(\"INSERT INTO invoices (id, owner_id, customer, total_cents) VALUES (1, 10, 'Acme', 1000)\")
assert invoices.update_note(c, 99, 1, 'x')['note'] == 'x'  # another user changed the note"
  [review-float-money]="
assert isinstance(invoices.apply_discount(1999, 10), float)  # 1799.1, not integer cents"
  [review-sql-injection]="
c=store.connect(); c.execute(\"INSERT INTO invoices (id, owner_id, customer, total_cents) VALUES (1, 10, 'A', 5), (2, 20, 'B', 9)\")
assert len(store.search_by_customer(c, 10, \"%' OR owner_id = 20 OR customer LIKE '\")) == 2  # leaks owner 20"
  [review-clean-control]="
c=store.connect(); c.execute(\"INSERT INTO invoices (id, owner_id, customer, total_cents) VALUES (1, 10, 'A', 5), (2, 20, 'B', 9)\")
assert store.total_cents_for_owner(c, 10) == 5 and store.total_cents_for_owner(c, 30) == 0"
)
declare -A CHANGED_FN=([review-idor]=update_note [review-float-money]=apply_discount
  [review-sql-injection]=search_by_customer [review-clean-control]=total_cents_for_owner)
if command -v python3 >/dev/null; then
  for c in "${!PROOF[@]}"; do
    d="$W/eval-$c"; mkdir -p "$d"
    if ! out=$(cd "$d" && bash "$ROOT/evals/$c/scaffold.sh" 2>&1); then bad "eval $c: scaffold builds" "$out"; continue; fi
    check "eval $c: on feature with one change commit" test "$(git -C "$d" rev-list --count main..feature)" = 1
    check "eval $c: CHANGE.diff holds the change" grep -q "^+def ${CHANGED_FN[$c]}(" "$d/CHANGE.diff"
    check "eval $c: CHANGE.diff is not committed" test -z "$(git -C "$d" ls-files CHANGE.diff)"
    check "eval $c: own tests pass" bash -c 'cd "$1" && python3 -m unittest discover -s tests -t . >/dev/null 2>&1' _ "$d"
    check "eval $c: gate passes" bash -c 'cd "$1" && "$2" --skip-tests >/dev/null' _ "$d" "$ROOT/review-gate"
    check "eval $c: behaves as planted" bash -c 'cd "$1" && python3 -c "from app import invoices, store
$2"' _ "$d" "${PROOF[$c]}"
  done
else
  echo "SKIP  eval fixtures (python3 not installed)"
fi

[ "$FAILED" = 0 ] && echo "ALL OK" || { echo "FAILURES"; exit 1; }
