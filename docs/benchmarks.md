# Review benchmarks

What we measured while building the `pre-pr` loop, and what changed in the kit because of it. The code
under review is private, so the PRs are described rather than linked.

## Which review setup finds known bugs

**PR.** A full-stack change: a status popover in a web app, backed by an API in a second repository.

**Answer key.** An earlier review had found four bugs, and each was verified by hand:

| Key | Bug | Where you see it |
| --- | --- | --- |
| F1 | The API answers 200 with a failure message for an inactive record, so the UI reports a false success | the other repository's API |
| F2 | A 404 shows the wrong message, and the error handling is duplicated | the diff |
| F3 | One commit reverts an earlier fix, and the PR description does not say so | the diff, against the description |
| F4 | The UI query reads fields the API never sends | the other repository's API |

**Runs.** Each setup ran twice, as a single clean-context agent, on the same commit. Scores are known bugs
found out of 4. A half point is a finding that names the place but misses the cause.

| Setup | Run 1 | Run 2 | Notes |
| --- | ---: | ---: | --- |
| The repo's own PR review skill | 2 | 1 | |
| `staff-review` (before) | 2 | 1.5 | |
| `/code-review` medium | 2 | 1 | |
| `/code-review` high | 2 | 4 | |
| `staff-review`, then `/code-review` medium | 2 | 2 | |
| The Judge | 1.5 | 2.5 | 7-12.5 min |
| `staff-review` with counterparts and the PR description | **4** | **4** | 12.5-15 min |

The last setup added three things to the same short prompt:

- Read the other side of each contract the change touches, in the counterpart's local checkout. This finds
  F1 and F4.
- Check the diff against what the change claims, and report undisclosed behaviour changes. This finds F3.
- Report only findings backed by evidence, and say which checks ran.

**What changed in the kit**

- `pre-pr` now has a Goal and a Counterparts step before the loop, and both go into the reviewer prompt.
- Everything else in the prompt stayed short: long checklists caught no more of the known bugs.

**Caveats**

- This is one PR with two runs per setup.
- `/code-review` high went from 2 to 4 between its two runs, so one run says little. Repeat runs before
  comparing setups.

## Model against model on one PR

**Setup.** Claude Opus and Gemini 4 Neon reviewed the same Rails API PR in agy-bench, one run each. A
third model judged them blind, and a coordinator then checked the judge's work by hand.

**What held up**

- Neither model had a false positive.
- Both found the same core bugs: an action that always fails with a 500, a feature flag left commented
  out, and a NOT NULL column written as NULL.
- Neon found two more real bugs, and neither line was in the diff. One was an operation called by the
  change that overwrote the value the change had just set. The other was a sync job that undid a "hidden"
  flag the change added. Both need reading the code the change calls, the same pattern as F1 and F4 above.

**What did not hold up**

- The judge marked Opus as missing two findings that Opus had raised. One of them Opus had considered and
  dropped, for a stated reason.
- The judge also did not check Neon's extra findings against the code.

That is why agy-bench now scores each review against an answer key (`--answer-key`). The score comes from
a matcher that has to quote the review, not from a judge's overall impression.

**Caveats**

- This is one run.
- The sandbox had no Ruby gems and could not approve subagents. Neither model could run the tests or the
  loop's two reviewers, so this measured a single static pass, not `pre-pr`.

## Hardening the require-pre-pr hook

The hook went through four review rounds, each with two clean-context reviewers. Three lessons from that:

- **Following the shell's `cd` does not converge.**
  - Every round found a new way to make the hook check a different checkout than the one `gh` runs in: a
    later `cd`, a subshell, `pushd`, a bare `cd`, a symlink followed by `..`, and a glob in the path.
  - The fix was an allowlist instead of more parsing. The PR command runs alone, or right after one
    `cd <literal absolute path> &&`. Anything else before it is blocked.
- **A check that runs before the permission prompt must not run repository code.**
  - `git status` runs the repository's fsmonitor command and clean filters.
  - The hook now runs only `git rev-parse`, with fsmonitor off. The uncommitted-changes check moved into
    `pre-pr`, which runs after approval.
- **State the threat model, and give it to the reviewers as part of the goal.**
  - The hook catches an agent that forgot the review. It is not a gate against a deliberate bypass.
  - Without that line in the goal, every round rated another bypass variant as should-fix.

## Next

- Write an answer key for each benchmark PR. Run each setup with `--runs 3` and compare the recall ranges,
  not single scores.
- Try two different models as the loop's two reviewers. On the PR above, each model found bugs the other
  missed.
- Pick a model per role from these numbers: the reviewer, a scoped change, a mechanical fix. Use the
  cheapest model whose recall, or whose tests passing, holds up.
