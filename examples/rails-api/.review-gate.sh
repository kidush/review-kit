# shellcheck shell=bash
# Example review-gate config for a Rails API (Pundit, Sidekiq, RSpec in Docker).
# Copy to the repo root as .review-gate.sh and adapt. Sourced by review-gate.
# shellcheck disable=SC2034,SC2015  # vars read by review-gate; pass/fail return 0

BASE="origin/master"
ADDED_PATHS=(app lib config)
DEBUG_PATTERNS='binding\.pry|byebug|debugger|^\+\s*(puts|pp|p) '

# Spec-per-file: every changed app file under a tested layer has a changed spec.
SRC_PATTERN='^app/(controllers|models|commands|use_cases|services|adapters|policies|queries|serializers|jobs|validators)/.*\.rb$'
SKIP_TEST_CHECK_VAR="REVIEW_GATE_SKIP_SPEC_CHECK"
TEST_CHECK_NAME="spec-per-file check"
TEST_CHECK_LABEL="changed app files have changed specs"
TEST_CHECK_FAIL_LABEL="app files changed with no matching changed spec (add spec incl. error path)"
test_pattern_for() {
  local base; base="$(basename "$1" .rb)"
  printf '^spec/.*%s.*_spec\\.rb$|^spec/.*%s_spec\\.rb$' "${base%_controller}" "$base"
}

# Tests run inside a running app container that mounts ONE checkout.
TEST_NAME="rspec"
TEST_CMD="bundle exec rspec"
TEST_CMD_TARGETED="bundle exec rspec"
TEST_FILE_PATTERN='^spec/.*_spec\.rb$'
TEST_DEFAULT_TARGET="spec/"
TEST_SUMMARY_REGEX='^[0-9]+ examples?,'
DEPRECATION_REGEX='DEPRECATION WARNING'
TEST_CONTAINER="${REVIEW_GATE_CONTAINER:-app-web-1}"
TEST_CONTAINER_WORKDIR="/var/www/app"
TEST_CONTAINER_ENV=(RAILS_ENV=test)
TEST_CONTAINER_HINT="docker compose up -d"

# Client namespaces that must only be called from adapters (extend per project).
EXTERNAL_CALL_PATTERN="${EXTERNAL_CALL_PATTERN:-PaymentGateway::|Stripe::}"

project_checks() {
  # Forbidden patterns (see CLAUDE.md / REVIEW.md), on added lines under app/ lib/ config/
  local rules=() f
  echo "$ADDED" | grep -qE 'rescue StandardError' && rules+=("rescue StandardError (needs log + re-raise or specific handling; review manually)")
  echo "$ADDED" | grep -qE '\bUser\.all\b' && rules+=("User.all without scope/pagination")
  echo "$ADDED" | grep -qE '\.to_f\b.*(price|amount|value|cents)|(price|amount|value)\w*\.to_f' && rules+=("float used for money (use integer cents)")
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    added_lines "$f" | grep -qE "Net::HTTP|HTTParty|Faraday|RestClient|Adapters?::|${EXTERNAL_CALL_PATTERN}" \
      && rules+=("external call in $f (controllers/models must not call adapters)")
  done < <(changed_matching '^app/(controllers|models)/.*\.rb$')
  [ ${#rules[@]} -eq 0 ] && pass "no forbidden patterns" || fail "forbidden patterns" "${rules[@]}"

  # Schema change needs a migration, and vice versa
  local schema=0 mig=0
  changed '^db/schema\.rb$' && schema=1
  changed '^db/migrate/' && mig=1
  [ "$schema" = "$mig" ] && pass "schema.rb and migrations consistent" || fail "db/schema.rb and db/migrate/ must change together" "schema.rb=$schema migrations=$mig"

  # Contract changes must update docs/ai/integration-map.md
  if changed '^(config/routes\.rb|app/serializers/)'; then
    changed '^docs/ai/integration-map\.md$' && pass "integration-map updated with contract change" \
      || fail "routes/serializers changed but docs/ai/integration-map.md did not (new fields and routes must be documented)"
  fi
}
