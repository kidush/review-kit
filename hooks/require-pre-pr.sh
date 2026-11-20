#!/usr/bin/env bash
# PreToolUse hook: block `gh pr create` (or its alias `gh pr new`) until the pre-pr skill has passed for HEAD.
# It catches an agent that forgot the review. It is not a gate against a deliberate bypass: `gh api`, an alias or
# writing the marker without a review get past it. Where telling the checkout apart would mean parsing shell, it
# fails closed.
# Matching is deliberately loose: any gh/gh-axi word followed by `pr create|new` in the same command segment,
# quoted or not. The PR command runs as its own command, or right after one `cd <absolute path> &&`, so the hook
# checks the checkout it runs in. Anything else before it, a commit message that mentions it included, is blocked.

input=$(cat)
# Cheap pre-check without spawning a process: skip input that cannot hold `gh ... pr ... create` or `... new`.
# It runs on raw JSON, where flags, quotes and escaped line breaks can sit between the words.
precheck="gh.*pr.*(create|new)"
[[ "$input" =~ $precheck ]] || exit 0

if ! command -v jq >/dev/null; then
  echo "The require-pre-pr hook needs jq to check PR commands. Install jq." >&2
  exit 2
fi

# jq joins line continuations and makes each line its own segment: bash substitutions are quadratic on long input.
cmd=$(jq -r '.tool_input.command // empty | gsub("\\\\\n"; " ") | gsub("\n"; ";")' <<<"$input")
body_file="Put a PR body in a file and pass it with --body-file."
# Splitting a long command around the match is quadratic in bash too, so a long one is blocked unread.
if (( ${#cmd} > 16384 )); then
  echo "The command is too long to check for a PR command. $body_file" >&2
  exit 2
fi
# Flags such as `-R owner/repo`, `-Rowner/repo` or `--repo=owner/repo` may also sit between `pr` and `create`.
# A flag is one word that starts with `-`, and its value cannot, so a long run of flags matches in linear time.
pattern="(^|[^[:alnum:]_.-])['\"]?(gh|gh-axi)['\"]?[[:space:]]([^;&|]*[[:space:]])?['\"]?pr['\"]?[[:space:]]+(-[^[:space:];&|]*([[:space:]]+[^[:space:];&|-][^[:space:];&|]*)?[[:space:]]+)*['\"]?(create|new)(\$|[^[:alnum:]_-])"
[[ "$cmd" =~ $pattern ]] || exit 0
# Keep the boundary character the pattern matched before gh, so the prefix ends where the gh word starts.
prefix=${cmd%%"${BASH_REMATCH[0]}"*}${BASH_REMATCH[1]}
rest=${cmd#*"${BASH_REMATCH[0]}"}

reword="If the command only mentions opening a PR (e.g. in a commit message), reword it. $body_file"
own_command="Run gh pr create as its own command, optionally right after \`cd <absolute path> &&\`, so the hook can tell which checkout the PR comes from. $reword"

cd "$(jq -r '.cwd // empty' <<<"$input")" 2>/dev/null || cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
# The one prefix allowed before the PR command: `cd` to a literal absolute path, which no shell expansion can change.
cd_prefix='^[[:space:]]*cd[[:space:]]+("(/[^"$`\\]*)"|'\''(/[^'\'']*)'\''|(/[^][:space:];&|<>(){}$`'\''"\\]*))[[:space:]]*&&[[:space:]]*['\''"]?$'
empty_prefix='^[[:space:]]*['\''"]?$'
if [[ "$rest" =~ $pattern ]]; then
  echo "$own_command" >&2
  exit 2
elif [[ "$prefix" =~ $cd_prefix ]]; then
  dir=${BASH_REMATCH[2]}${BASH_REMATCH[3]}${BASH_REMATCH[4]}
  if ! cd "$dir" 2>/dev/null; then
    echo "$dir is not a directory, so there is no /pre-pr pass to check. $reword" >&2
    exit 2
  fi
elif ! [[ "$prefix" =~ $empty_prefix ]]; then
  echo "$own_command" >&2
  exit 2
fi

# A check runs only rev-parse, with fsmonitor off: a repository's fsmonitor command or filter would otherwise run
# before the user approves the call.
if ! { read -r head && read -r git_dir; } < <(git -c core.fsmonitor=false rev-parse HEAD --git-dir 2>/dev/null); then
  echo "$PWD is not a git checkout, so there is no /pre-pr pass to check. Open the PR from the checkout. $reword" >&2
  exit 2
fi

if [[ "$(cat "$git_dir/pre-pr-passed" 2>/dev/null)" != "$head" ]]; then
  echo "No passing /pre-pr review for ${head:0:7}. Run the pre-pr skill first. $reword" >&2
  exit 2
fi
