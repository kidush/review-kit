#!/usr/bin/env bash
# Offline tests for hooks/require-pre-pr.sh: which commands it blocks, that it runs no repository code, and its speed.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
H="$ROOT/hooks/require-pre-pr.sh"; export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mk() { git init -q "$1"; echo one >"$1/f"; git -C "$1" add f; git -C "$1" -c user.name=t -c user.email=t@e commit -qm init; }
mark() { git -C "$1" rev-parse HEAD >"$(git -C "$1" rev-parse --absolute-git-dir)/pre-pr-passed"; }
run() { printf %s "$2" >"$T/cmd"; jq -n --rawfile c "$T/cmd" --arg d "$1" '{tool_input:{command:$c},cwd:$d}' | bash "$H" 2>"$T/err"; echo $?; }
fails=0
expect() { local want=$1 dir=$2 cmd=$3 re=${4:-}; local got; got=$(run "$dir" "$cmd")
  if [[ $got != "$want" ]] || { [[ -n $re ]] && ! grep -qE "$re" "$T/err"; }; then echo "FAIL want=$want got=$got: ${cmd:0:60} :: $(head -c 200 "$T/err")"; fails=$((fails+1)); else echo "ok $want: ${cmd:0:60}"; fi; }
mk "$T/a"; mk "$T/b"; mark "$T/a"
expect 0 "$T/a" 'git status'
expect 0 "$T/a" 'gh pr create --fill'
expect 2 "$T/b" 'gh pr create' 'No passing'
expect 0 "$T/b" "cd \"$T/a\" && gh pr create"
expect 0 "$T/b" "cd '$T/a' && gh pr create"
expect 0 "$T/b" "cd $T/a && gh pr create"
expect 2 "$T/a" "cd \"$T/b\" && gh pr create" 'No passing'
expect 2 "$T/a" "cd \"$T/nope\" && gh pr create" 'not a directory'
for c in 'git push && gh pr create' "cd $T/a && cd . && gh pr create" "(cd $T/a && true); gh pr create" "pushd $T/a && gh pr create" 'cd && gh pr create' "cd -P $T/a && gh pr create" 'cd "$PWD" && gh pr create' 'cd $(pwd) && gh pr create' 'cd - && gh pr create' 'cd . && gh pr create' "env -C $T/a gh pr create" 'GIT_DIR=x gh pr create' "{ cd $T/a; gh pr create; }" "bash -c 'gh pr create'" "if cd $T/a; then gh pr create; fi" "git commit -m 'then gh pr create'" 'gh pr create; gh pr create --repo o/r' 'gh pr view 1; cd /x && gh pr new'; do
  expect 2 "$T/a" "$c" 'as its own command'
done
expect 0 "$T/a" 'gh pr -R o/r create'
expect 2 "$T/b" 'gh pr -Ro/r create' 'No passing'
expect 2 "$T/b" 'gh pr -Ro/r --web create' 'No passing'
expect 0 "$T/a" '"gh" pr --repo=o/r create'
expect 0 "$T/a" 'gh pr view 1'
expect 0 "$T/a" 'gh pr comment 1 --body "a new test"'
echo two >"$T/a/f"; expect 0 "$T/a" 'gh pr create'
git -C "$T/a" config filter.p.clean "touch $T/filter-ran; cat"; echo 'f filter=p' >"$T/a/.gitattributes"; echo three >"$T/a/f"
git -C "$T/a" config core.fsmonitor "touch $T/fsm-ran; false"
run "$T/a" 'gh pr create' >/dev/null
[[ -e $T/filter-ran || -e $T/fsm-ran ]] && { echo "FAIL filter or fsmonitor ran"; fails=$((fails+1)); } || echo "ok no filter/fsmonitor"
s=$(date +%s%N); run "$T/a" "gh pr $(printf -- '--json %.0s' {1..24})view" >/dev/null; echo "timing $(( ($(date +%s%N)-s)/1000000 ))ms"
fast() { local cmd=$1 limit=$2 s ms; s=$(date +%s%N); run "$T/a" "$cmd" >/dev/null; ms=$(( ($(date +%s%N)-s)/1000000 ))
  if (( ms > limit )); then echo "FAIL slow ${ms}ms > ${limit}ms: ${cmd:0:40}"; fails=$((fails+1)); else echo "ok fast ${ms}ms: ${cmd:0:40}"; fi; }
nl=$'\n'
big=$(for i in $(seq 1500); do printf '  def print_line_%s; foo.new(x) \\\n' "$i"; done)
fast "cat > x.rb <<'RB'${nl}${big}${nl}RB" 300
fast "gh pr create --body \"$(printf 'word pr new x %.0s' $(seq 20000))\"" 1000
expect 2 "$T/a" "gh pr create --body \"$(printf 'word pr new x %.0s' $(seq 2000))\"" 'body-file'
expect 2 "$T/a" "gh pr create --body \"\$(cat <<'MD'${nl}Summary${nl}- hook now blocks gh pr new${nl}MD${nl})\"" 'body-file'
[ "$fails" = 0 ] && echo "ALL OK" || { echo "FAILURES: $fails"; exit 1; }
