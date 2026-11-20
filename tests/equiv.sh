#!/usr/bin/env bash
# Scenario tests for review-gate + examples/rails-api config on a synthetic Rails-like repo (--skip-tests).
# Each scenario checks the exit code. Optional: set ORIG=/path/to/another/review-gate to also compare
# PASS/FAIL/SKIP lines against that gate (e.g. a project's previous bin/review-gate).
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KIT="$ROOT/review-gate"
CFG="$ROOT/examples/rails-api/.review-gate.sh"
ORIG=${ORIG:-}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FAILED=0
norm() { grep -E '^(PASS|FAIL|SKIP|GATE)' | sort; }
scenario() { # name expected_exit setup_fn
  local name="$1" want="$2"; shift 2
  rm -rf "$W/r"; mkdir -p "$W/r"; cd "$W/r"
  git init -q -b master; git config user.email t@t; git config user.name t
  mkdir -p app/models app/controllers app/serializers app/use_cases spec/models db/migrate config docs/ai lib
  echo "class User; end" > app/models/user.rb; echo "Rails.routes" > config/routes.rb; echo s > db/schema.rb; echo m > docs/ai/integration-map.md
  git add -A; git commit -qm base; git update-ref refs/remotes/origin/master HEAD
  git checkout -qb feature
  ENVV=""
  "$@"
  git add -A; git commit -qm change >/dev/null 2>&1
  k="$(env ${ENVV:-} "$KIT" --config "$CFG" --skip-tests 2>&1)"; krc=$?
  r=OK; [ "$krc" = "$want" ] || r="BAD(want $want)"
  if [ -n "$ORIG" ]; then
    o="$(env ${ENVV:-} bash "$ORIG" --skip-tests 2>&1)"; orc=$?
    { [ "$(echo "$o" | norm)" = "$(echo "$k" | norm)" ] && [ $orc = $krc ]; } || r="$r DIFF-vs-ORIG"
  fi
  printf '%-16s exit=%s %s  [%s]\n' "$name" "$krc" "$r" "$(echo "$k" | grep -E '^FAIL|^SKIP' | cut -c7-60 | paste -sd'|')"
  [ "$r" = OK ] || { FAILED=1; echo "$k"; }
}
s_clean() { echo "class User; def a; end; end" > app/models/user.rb; echo "describe User" > spec/models/user_spec.rb; }
s_ws() { s_clean; printf 'x  \n' >> app/models/user.rb; }
s_conflict() { s_clean; printf '<<<<<<< HEAD\na\n=======\nb\n>>>>>>> x\n' > lib/c.rb; }
s_pry() { s_clean; echo "binding.pry" >> app/models/user.rb; }
s_puts() { s_clean; echo "  puts 'x'" > lib/t.rb; }
s_debug_outside() { s_clean; echo "binding.pry" > script.rb; }
s_rescue() { s_clean; echo "rescue StandardError" >> app/models/user.rb; }
s_userall() { s_clean; echo "User.all" > lib/q.rb; }
s_float() { s_clean; echo "x = price.to_f" > lib/m.rb; }
s_httpctrl() { s_clean; echo "class AController; Faraday.get; end" > app/controllers/a_controller.rb; echo t > spec/a_controller_spec.rb; }
s_gatewaymodel() { s_clean; echo "PaymentGateway::Charge.create" >> app/models/user.rb; }
s_nospec() { echo "class User; def b; end; end" > app/models/user.rb; }
s_ctrl_spec() { echo "class FooController; end" > app/controllers/foo_controller.rb; mkdir -p spec/requests; echo t > spec/requests/foo_spec.rb; }
s_skipspec() { s_nospec; ENVV="REVIEW_GATE_SKIP_SPEC_CHECK=1"; }
s_schema_only() { s_clean; echo s2 > db/schema.rb; }
s_mig_only() { s_clean; echo m > db/migrate/1_a.rb; }
s_schema_mig() { s_clean; echo s2 > db/schema.rb; echo m > db/migrate/1_a.rb; }
s_routes() { echo "Rails.routes2" > config/routes.rb; }
s_routes_doc() { s_routes; echo m2 > docs/ai/integration-map.md; }
s_serializer() { echo "class USer; end" > app/serializers/user_serializer.rb; echo t> spec/models/user_serializer_spec.rb; }
s_secret() { s_clean; echo "api_key = 'abcdefghijklmnop123'" > config/k.rb; }
s_uncommitted() { s_clean; git add -A; git commit -qm c; echo "binding.pry" >> lib/u.rb; }
s_nochange() { :; }
while read -r s want; do scenario "$s" "$want" "s_$s"; done <<'LIST'
clean 0
ws 1
conflict 1
pry 1
puts 1
debug_outside 0
rescue 1
userall 1
float 1
httpctrl 1
gatewaymodel 1
nospec 1
ctrl_spec 0
skipspec 0
schema_only 1
mig_only 1
schema_mig 0
routes 1
routes_doc 0
serializer 1
secret 1
uncommitted 1
nochange 0
LIST
[ "$FAILED" = 0 ] && echo "ALL OK" || { echo "FAILURES"; exit 1; }
