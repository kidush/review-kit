---
name: pre-pr
description: Review loop to run before opening or updating a pull request, in any repository. Runs simplify once (Claude Code only), then each round runs review-gate and two independent clean-context reviewers, fixes the verified findings, and repeats until a round is clean or 3 rounds pass. Use before creating a PR, when asked to run pre-pr or the pre-PR checks, or when a require-pre-pr hook blocks a PR.
argument-hint: "[base ref]"
---

# Pre-PR review loop

## Base

- **Claude Code:** the base is `$ARGUMENTS`.
- **Pi:** the base is the text after `/skill:pre-pr` (Pi does not substitute `$ARGUMENTS`; it appends the arguments as a separate message).
- **No base given:** use the `Base:` line that the first gate run prints. The gate takes `BASE` from the project's `.review-gate.sh`, else guesses `origin/HEAD`, `origin/main` or `origin/master`.

Use the same literal ref in every command and reviewer prompt below.

## Gate

Use the first of these that exists:

1. `./bin/review-gate` in the repository.
2. `review-gate` on PATH. `install.sh` and the review-kit plugin both put it there.
3. `review-gate` in the review-kit root, two folders above this skill's folder.

If none exists, stop and tell the user to run review-kit's `install.sh`. A missing gate is never a pass.

Gate exit codes:

- **0:** every check passed.
- **1:** a check failed. Fix the `FAIL` lines.
- **2:** usage or setup error, for example a bad base. Stop and report it.

The gate does not fix anything itself. Project rules live in `.review-gate.sh`; without that file, only the generic checks run.

## Before the loop

1. **Scope.** Run `git fetch origin`, then `git diff <base>...HEAD --name-only`. Commit any uncommitted changes first, because the reviewers review commits only. If nothing changed, stop and say so.
2. **Goal.** Write down what the change is meant to do, in a few lines: the ticket, or the PR description you plan to use. It replaces `<goal>` in the reviewer prompt, so the reviewers check the diff against it and report behaviour changes it does not mention, such as an undisclosed revert.
3. **Counterparts.** List the services on the other side of a contract this diff touches (an API it calls, a client that calls it, a queue consumer), with the path of their local checkout. `REVIEW.md` may list them. `<counterparts>` in the reviewer prompt becomes one sentence per service: "This change talks to <service> at <path>: read the other side of each contract it touches." Ask the user for a path you cannot find. With no counterpart, `<counterparts>` is empty.
4. **Simplify (Claude Code only).** Invoke the `simplify` skill on the changes since `<base>`, and commit its changes on their own (`Simplify <area>`). Run it once only: a later run would change code the reviewers already checked. In Pi, skip this step and say so in the report, because Pi has no `simplify` skill.

## Loop

Run at most **3 rounds**. Each round:

1. **Gate.** Run `<gate> --base <base>`. Fix every `FAIL` line.
2. **Tests.** If the gate shows tests as `SKIP` because `TEST_CMD` is not configured, run the tests that the project's `CLAUDE.md`, `AGENTS.md` or README documents for the changed code. If none are documented, write "tests not run" in the report. Never claim tests passed. New behaviour without a test is a finding.
3. **Review.** Launch the reviewers below. Do not give them your own opinion of the change.
4. **Verify.** Drop any finding you cannot confirm by reading the code it depends on. A finding must name the concrete input or state that breaks.
5. **Fix.** Fix every `blocker` and `should-fix` finding. Add a regression test when a test can show the bug. Leave `nit` findings for the report.
6. **Commit** the fixes, with a message that says what the review caught.

A round is **clean** when all of these hold:

- the gate exits 0;
- the tests pass, or are reported as not run;
- the reviewers return no verified `blocker` or `should-fix` finding;
- so the round ends with no new commit.

Stop at the first clean round.

## Reviewers

Each round, start **two new reviewers** with the same prompt below. Each one starts with a clean context: it gets only the prompt, not this conversation, the other reviewer's findings, or earlier rounds' findings. Merge their findings and drop duplicates. Keep the prompt short: on past PRs it caught as many known bugs as long checklists. The goal and the counterparts are the exception: on a benchmark PR, a review that read the counterparts and checked the change against its description found 4 of 4 known bugs in both runs, against 1.5-2 without (see `docs/benchmarks.md`).

> Review the code change in this repo: `git diff <base>...HEAD`. The change is meant to: <goal> Read the changed files and the code they call or are called from. Review this diff for bugs and security issues, and report any behaviour change the goal does not mention. <counterparts> You are a read-only reviewer: do not modify files, fix findings, or launch other reviewers. Report only findings you confirmed by reading the code they depend on. Each finding names the file and line, a severity (`blocker`, `should-fix` or `nit`), and the concrete input or state that breaks, with the result.

**Claude Code:** launch the two reviewers as parallel subagents in one message.

**Optional third reviewer.** If the `staff-reviewer` agent is available (`staff-reviewer` from `install.sh`, or `review-kit:staff-reviewer` from the plugin), launch it in the same message. It adds the project's `CLAUDE.md` and `REVIEW.md` rules. Prompt: "Review against base `<base>` using `--skip-tests`." Do not give it earlier rounds' findings: each round is a fresh review. Map its severities: `important` is a `blocker`, `nit` stays a `nit`, and `pre-existing` goes in the report only. Its `BLOCK` verdict caused only by a gate failure you already fixed this round does not count.

### Running reviewers in Pi

Pi has no built-in agent tool. In Pi, start two independent CLI processes from the repository root, each with the prompt above. Do not replace the pair with one review, and do not invoke this skill recursively.

For each round, set `base` to the chosen ref and run both processes in one bash call. Use a fresh temporary directory for each round:

```bash
base=origin/main # Replace with the chosen base, quoted as shell data.
# The quoted heredocs keep the goal and the counterparts as plain text: backticks and $ in them never run.
goal=$(cat <<'GOAL'
Replace with the goal from Before the loop.
GOAL
)
# One line per counterpart, or nothing: This change talks to <service> at <path>: read the other side of each contract it touches.
counterparts=$(cat <<'COUNTERPARTS'
COUNTERPARTS
)
reports=$(mktemp -d "${TMPDIR:-/tmp}/pre-pr.XXXXXX")
prompt="Review the code change in this repo: git diff $base...HEAD. The change is meant to: $goal Read the changed files and the code they call or are called from. Review this diff for bugs and security issues, and report any behaviour change the goal does not mention. $counterparts You are a read-only reviewer: do not modify files, fix findings, or launch other reviewers. Report only findings you confirmed by reading the code they depend on. Each finding names the file and line, a severity (blocker, should-fix or nit), and the concrete input or state that breaks, with the result."
for n in 1 2; do
  pi --print --no-session --no-extensions --no-mcp --no-skills \
    --no-prompt-templates --tools read,bash \
    "$prompt" >"$reports/reviewer-$n.txt" 2>"$reports/reviewer-$n.err" &
  pids[$n]=$!
done
for n in 1 2; do
  status=0; wait "${pids[$n]}" || status=$?
  printf 'Reviewer %s exit: %s\n' "$n" "$status"
done
printf 'Reports: %s\n' "$reports"
```

- Read both reports and check both exit statuses before the Verify step. A failed process or a missing report is an incomplete review, never a clean round. Read stderr for failures.
- Do not edit the checkout while reviewers are running.
- `--no-session` gives each process a clean context, like the subagents above.
- The CLI uses the configured Pi model. If a particular model is required, pass an available `--model` explicitly to both commands.
- These tool restrictions are not an OS sandbox: bash can write files, so read-only behaviour also depends on the prompt.
- Delete the reports folder after the round's report is written.
- Pi loads a project's `.agents/skills` only after the user trusts the project (`/trust`). A user-level install in `~/.agents/skills` needs no trust.

## Finish

On a clean round:

1. Confirm that `git status --porcelain --untracked-files=no` prints nothing. If it prints anything, the round was not clean: commit and run another round, so no unreviewed change gets the marker.
2. Write the marker: `git rev-parse HEAD > "$(git rev-parse --git-dir)/pre-pr-passed"`. A project's `require-pre-pr` hook can check it before allowing a PR. Claude Code hooks do not run in Pi, so in Pi the marker is the only record.
3. Report: rounds run, what each round fixed, whether tests ran, skipped steps, and the remaining `nit` findings.

If round 3 is not clean, do **not** write the marker. Report the open findings and ask the user how to continue.
