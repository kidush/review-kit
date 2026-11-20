#!/usr/bin/env bash
# Container test mode of review-gate with examples/rails-api config, using the fake docker in tests/fakebin.
# Covers: container not mounting this checkout, mounted elsewhere, mounted here (pass), mounted here (failing tests).
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KIT="$ROOT/review-gate"; CFG="$ROOT/examples/rails-api/.review-gate.sh"; FAKE="$ROOT/tests/fakebin"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cd "$W"; git init -q -b master; git config user.email t@t; git config user.name t
mkdir -p app/models spec/models; echo "class User; end" > app/models/user.rb
git add -A; git commit -qm base; git update-ref refs/remotes/origin/master HEAD; git checkout -qb feature
echo "describe User" > spec/models/user_spec.rb; echo "class User; def z; end; end" > app/models/user.rb; git add -A; git commit -qm t
FAILED=0
# mount fails want_exit
while read -r label mount fails want; do
  [ "$mount" = none ] && mount=""; [ "$mount" = here ] && mount="$W"
  for flag in "" "--full"; do
    out=$(PATH="$FAKE:$PATH" FAKE_MOUNT="$mount" FAKE_FAILS=$fails "$KIT" --config "$CFG" $flag 2>&1); rc=$?
    r=OK; [ "$rc" = "$want" ] || { r="BAD(want $want)"; FAILED=1; }
    printf '%-14s %-6s exit=%s %s  [%s]\n' "$label" "${flag:-diff}" "$rc" "$r" "$(grep -E '^(PASS|FAIL|SKIP|INFO) ' <<<"$out" | grep -iE 'rspec|container|deprec' | cut -c1-70 | paste -sd'|')"
    [ "$r" = OK ] || echo "$out"
  done
done <<'LIST'
not-mounted none 0 1
elsewhere /elsewhere 0 1
mounted here 0 0
failing here 1 1
LIST
[ "$FAILED" = 0 ] && echo "ALL OK" || { echo "FAILURES"; exit 1; }
