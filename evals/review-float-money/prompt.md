---
runs: 1
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Grep, Glob, Agent]
disallowed_tools: [Edit, Write, NotebookEdit, WebFetch, WebSearch]
---
The `feature` branch in this repository is ready for a pull request against `main`. `git` and `review-gate` cannot run in this environment, so the full change (`git diff main...feature`) is saved in `CHANGE.diff`; the gate and the tests already passed. Review that change: use the staff-reviewer agent if you have one (tell it about `CHANGE.diff` and that git and the gate are unavailable), otherwise review it yourself. Then give me the verdict and every finding with its severity. Do not change any files.
