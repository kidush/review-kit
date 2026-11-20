# review-kit

A shared pre-PR review kit:

- **`review-gate`** — a deterministic bash gate (whitespace/conflicts, debug leftovers, hardcoded secrets,
  "changed source needs a changed test", tests, plus project rules). Exit `0` pass, `1` a check failed, `2` usage/setup error.
- **`agents/staff-reviewer.md`** — a read-only Claude Code subagent with fresh context: runs the gate, then
  reviews the diff (incl. a dedicated security pass) using the project's `CLAUDE.md` + `REVIEW.md`.
- **`skills/pre-pr`** - the pre-PR review loop: simplify once, then per round the gate, two independent
  clean-context reviewers (plus `staff-reviewer` when installed), verified fixes, at most 3 rounds. Works in
  Claude Code and in Pi (two `pi --print` reviewer processes instead of subagents).
- **`hooks/require-pre-pr.sh`** - an optional Claude Code hook that blocks `gh pr create` until `pre-pr`
  recorded a pass for the current commit.
- **Per-project config**: `.review-gate.sh` (checks) and `REVIEW.md` (review knowledge, including the
  counterpart services and their local checkout paths) in each repo.
- **CI wrappers** for GitHub Actions and Bitbucket Pipelines.

## How it maps to the article's review layers

| Layer (article) | This kit |
|---|---|
| Pre-PR verification by the author agent | `review-gate` run locally / by the coding agent |
| Second agent with fresh context | `staff-reviewer` subagent |
| Security review | Security pass inside `staff-reviewer` (not a separate blocking CI job yet) |
| CI | `review-gate --skip-tests` in GitHub/Bitbucket PR pipelines |
| Risk-scaled human approval | "Sensitive paths" in `REVIEW.md` → agent flags "needs human sign-off" |
| Fix recurring issues at the source | add a rule to `project_checks()` or a line to `REVIEW.md` |
| Converging loop | `pre-pr` skill: gate + fresh reviewers per round, fix verified findings, stop at a clean round or after 3 |

## Install

Pick one of the two. Both together give two copies of the agent and the skill.

**Claude Code plugin** (any machine, updates with the repo):

```
/plugin marketplace add kidush/review-kit
/plugin install review-kit@review-kit
```

The plugin provides `review-kit:staff-reviewer`, `review-kit:pre-pr`, and puts `review-gate` on PATH
and the `require-pre-pr` hook script on PATH (from `bin/`), but does not turn the hook on (see "Require the
review before a PR"). It does not install anything for Pi or for plain shell use outside Claude Code.

**`install.sh`** (Claude Code, Pi and the shell):

```bash
./install.sh   # idempotent; never overwrites a path it did not create
```

| What | Where | Override |
|---|---|---|
| `review-gate` | `~/.local/bin` | `BIN_DIR` |
| `require-pre-pr` hook | `~/.local/bin` | `BIN_DIR` |
| `staff-reviewer` agent | `~/.claude/agents` | `AGENT_DIR` |
| `pre-pr` skill (Pi reads it here) | `~/.agents/skills/pre-pr` | `SKILL_DIR` |
| link for Claude Code | `~/.claude/skills/pre-pr` -> the folder above | `CLAUDE_SKILL_DIR` |

A project-level `.claude/skills/pre-pr` overrides the installed one, so delete project copies you want to
replace. The skill reads the base, the test command and the rules from the project (`.review-gate.sh`,
`CLAUDE.md`, `REVIEW.md`), so it holds no project details itself.

## Per-project setup

1. Add `.review-gate.sh` at the repo root (optional — without it the generic checks run and the
   test-per-file check and tests are reported as `SKIP`):

```bash
BASE="origin/main"
SRC_PATTERN='^src/.*\.py$'              # files that need a changed test
SRC_EXCLUDE_PATTERN='(^|/)test_[^/]*\.py$'
test_pattern_for() { printf '^tests/.*test_%s\\.py$' "$(basename "$1" .py)"; }  # ERE matched on changed files
TEST_CMD="pytest -q"                     # full suite
TEST_CMD_TARGETED="pytest -q"            # + changed test files
TEST_FILE_PATTERN='^tests/.*\.py$'
# TEST_CONTAINER=app-1; TEST_CONTAINER_WORKDIR=/app; TEST_CONTAINER_ENV=(ENV=test)  # docker exec mode
# DEBUG_PATTERNS=...  SECRET_PATTERN=...  ADDED_PATHS=(src)  SKIP_TEST_CHECK_VAR=...
project_checks() {                       # project rules; helpers: pass fail skip info changed changed_matching added_lines
  echo "$ADDED" | grep -q 'eval(' && fail "eval in added code" || pass "no eval"
}
# run_tests() { ... }                    # optional: replaces the built-in test step entirely
```

   Variables available to `project_checks`: `CHANGED` (changed files incl. uncommitted, untracked excluded),
   `ADDED` (added lines in `ADDED_PATHS`), `MERGE_BASE`, `BASE`, `ROOT`, `FULL`, `SKIP_TESTS`.
2. Add `REVIEW.md` with the project's layering, contract rules, perf notes and sensitive paths.
3. Run `review-gate` (flags: `--base <ref>`, `--full`, `--skip-tests`, `--config <file>`), or ask Claude Code
   to "use the staff-reviewer agent".

## Require the review before a PR

`pre-pr` writes `<git dir>/pre-pr-passed` with the commit it passed. `hooks/require-pre-pr.sh` is a
PreToolUse hook that blocks `gh pr create` and `gh pr new` until that file holds the current `HEAD`. It
needs `jq`. Enable it per project, so it only gates repos that use the loop:

1. Copy `hooks/require-pre-pr.sh` to `.claude/hooks/` in the repo, so teammates get it without the kit.
2. Add it to the repo's `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/require-pre-pr.sh" }] }
    ]
  }
}
```

For one person only, point a user or local settings file at `~/.local/bin/require-pre-pr` (from
`install.sh`) instead. With the plugin only, use step 1: the plugin's folder moves with each update.

What it does, so the blocks make sense:

- The PR command runs as its own command, or right after one `cd <absolute path> &&`, so the hook checks
  the checkout the PR comes from. Anything else before it (`git push &&`, a relative `cd`, a subshell) is
  blocked, and so is a second PR command in the same call.
- It runs only `git rev-parse`, with fsmonitor off: no repository fsmonitor command or filter runs before
  the user approves the call.
- A command that only mentions the PR command is blocked: a commit message, a heredoc PR body, or another
  gh command's text such as `gh issue create --title "pr new button"`. The message points to `--body-file`.
  A PR command longer than 16 KB is blocked unread; other long commands pass.
- With no usable directory to check, it blocks.
- It catches an agent that forgot the review. It is not a gate against a deliberate bypass: `gh api`, a gh
  alias or writing the marker by hand get past it. `--head <other-branch>` is checked against the local
  `HEAD`.

`tests/require-pre-pr.sh` covers these cases offline.

## Adopting in an existing project

1. `./install.sh`.
2. Copy `examples/rails-api/.review-gate.sh` and `examples/rails-api/REVIEW.md` to the repo root and adapt
   them (base branch, layers, forbidden patterns, test container, sensitive paths).
3. If the project already has its own gate script, replace it with a 2-line wrapper (keeps the documented
   command working): `#!/usr/bin/env bash` / `exec review-gate "$@"`.
4. If the repo has its own `.claude/agents/staff-reviewer.md`, delete it (a project-level agent overrides the
   user-level one), or replace it with the generic agent if teammates don't run `install.sh`.
5. Run `review-gate --skip-tests` and `review-gate` (tests on) on a branch and check the output.
6. Add the CI step (below).

## CI

**GitHub**: in the kit repo (e.g. `kidush/review-kit`), put `ci/github/pr-check.yml` at
`.github/workflows/pr-check.yml`, then in each project add `ci/github/caller-example.yml` as a workflow.
Inputs: `base`, `setup`, `skip-tests` (default true), `kit-repo`, `kit-ref`.

**Bitbucket**: see `ci/bitbucket/bitbucket-pipelines.snippet.yml` — a parallel "Review gate" step in the
`pull-requests` pipeline that fetches `origin/master` and runs with `--skip-tests` (the existing test step still runs the suite).

## Tests and benchmarks

**Offline tests** (no model calls):

```bash
tests/equiv.sh           # review-gate scenarios on a synthetic Rails-like repo
tests/container-mode.sh  # review-gate docker exec mode, with a fake docker
tests/require-pre-pr.sh  # the hook: which commands it blocks, no repository code run, speed
tests/pre-pr.sh          # install.sh, the Pi snippet against a stub pi, prompt drift, plugin validate,
                         # and the eval fixtures (each builds, passes its tests and the gate, bug is real)
```

**Benchmarks** (`evals/`, run with `claude plugin eval`; these call the model and cost money):

| Case | What it measures |
|---|---|
| `review-idor` | finds a missing ownership check, at blocking severity |
| `review-float-money` | finds a float returned for an amount in cents |
| `review-sql-injection` | finds SQL built from input with an f-string |
| `review-clean-control` | a correct change: no blocking finding, no BLOCK verdict |
| `pre-pr-trigger` | "run the pre-PR checks" loads the `pre-pr` skill |

Each reviewer case builds a small invoicing repo (`evals/_lib/base-repo.sh`) with one change on `feature`.
The gate and the repo's own tests pass, so only review can find the bug. By default every case also runs
without the plugin, so the report shows what the kit adds.

What the evals measure: whether the reviewers find the planted bug at blocking severity, whether they
block a correct change, and whether the skill triggers. What they cannot measure: the gate and a real
`git diff`. The eval sandbox masks the `git` binary, so the scaffold writes the change to `CHANGE.diff` and
the prompt tells the reviewer to read it there. The gate is deterministic and is covered by the offline
tests instead.

```bash
claude plugin eval . --scaffold --no-publish --runs 1 --max-cost-usd 10 --allow-tools Agent Skill
```

`--scaffold` runs the case scripts, which build the repos. `pre-pr-trigger` stops after 2 turns on purpose,
so its runs end with "Reached maximum number of turns"; only the skill call is graded. Add `--case review-idor` for one case,
`--ablation none` to skip the no-plugin arm, or `--runs 3` for steadier numbers. `aggregate-result.json`
in the results folder has score, cost, duration and turns for every run.

## Still missing

- A **blocking security review in CI** (e.g. an AI security review job whose failure blocks merge);
  today the security pass only runs inside the local agent.
- **Risk tiers / CODEOWNERS**: require a human approver for sensitive paths (payments, auth, migrations,
  CI config) via CODEOWNERS (GitHub) or default reviewers / merge checks (Bitbucket).
- A benchmark runner with real git, so the gate and `git diff` run inside the benchmark too.
  [agy-bench](https://github.com/kidush/agy-bench) runs reviews of real PRs in throwaway worktrees and
  scores them against an answer key (`--answer-key`, `--runs`); see `docs/benchmarks.md`.
- Benchmark cases for the full `pre-pr` loop (fix rounds, marker). Today the evals cover the reviewers and
  the skill trigger only, because a full loop costs several reviewer runs per case.
