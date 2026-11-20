# REVIEW.md — example Rails API

Project-specific review knowledge for the `staff-reviewer` agent (and humans).
The generic agent reads this file; everything project-specific lives here.

Stack: Rails, Pundit, Sidekiq (+ sidekiq-cron), Postgres, active_model_serializers, Pagy.
Consumers: webapp, Android and iOS apps — API changes break real clients.

## Read first
- `CLAUDE.md`, `docs/ai/architecture-guidelines.md`, `docs/ai/style-guide.md`, `docs/ai/tdd-guide.md`.
- Domain or integration changes: also `docs/ai/business-rules.md` and `docs/ai/integration-map.md`.

## Gate
`.review-gate.sh` at the repo root configures `review-gate`. Tests run inside the app container
(`app-web-1`, override with `REVIEW_GATE_CONTAINER`), which mounts ONE checkout: run the
gate from that checkout or use `--skip-tests`. `REVIEW_GATE_SKIP_SPEC_CHECK=1` disables the
spec-per-file check (framework upgrades only).

## Architecture / layering
- Flow: controller -> command -> use_case -> service -> adapter -> model (see CLAUDE.md).
- No business logic in controllers; it belongs in commands/use_cases.
- No external calls (HTTP, `PaymentGateway::`, `Stripe::`, other client namespaces) from controllers or models.
- Pundit authorization on every action that touches user data; one policy per resource.
- Pagination (Pagy) on every endpoint that returns a list; no `User.all` without scope.
- Slow work goes to Sidekiq jobs.
- Money is always integer cents — never float.
- `rescue StandardError` only with logging + re-raise or specific handling.
- Soft delete via `acts_as_paranoid` on critical data.

## API contract
- Never remove or rename a serializer field or route on v1/v2.
- New fields and routes are documented in `docs/ai/integration-map.md` (the gate enforces this for
  `config/routes.rb` and `app/serializers/`).
- When a field is touched, grep the sibling checkouts for usages:
  e.g. `../webapp`, `../android-app`, `../ios-app`.

## Rails idioms
Scopes over class methods returning arrays, `find_each` for batches, strong params, no callbacks that
hide side effects. Do not flag style the repo's own code does not follow.

## Performance and data
- N+1: use `includes`/`preload`.
- Missing indexes for new queries; no unbounded queries.
- Migrations safe on large tables: no table-locking changes without a plan, reversible, never mix data
  changes with schema changes. `db/schema.rb` and `db/migrate/` change together (gate-enforced).

## Tests
RSpec. Cover the error path, freeze time, minimal factories, no over-mocking of the unit under test.

## Upgrades (Gemfile or framework defaults change)
New deprecation warnings (the gate counts them), gem compatibility with the target version, config
silently changed by `load_defaults`, behavior changes listed in the official Rails upgrade guide.

## Sensitive paths — extra scrutiny, always a human approver
| Path | Why |
|---|---|
| `app/adapters/**` touching payments | money movement, webhooks, idempotency, cents |
| auth: `app/policies/**`, authentication/session/token code, Devise/JWT config | authz gaps, IDOR |
| `config/routes.rb`, `app/serializers/**` | public contract for API clients |
| `db/migrate/**`, `db/schema.rb` | locking, irreversible data loss |
| `bitbucket-pipelines.yml`, `Dockerfile`, `config/credentials*`, `.review-gate.sh` | CI/deploy and the gate itself |

For these: require a passing test of the failure path, check idempotency/retries, and never approve
on the agent's word alone — say "needs human sign-off" in the report.
