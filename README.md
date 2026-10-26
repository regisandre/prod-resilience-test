# prod-resilience-test

A skill for AI coding agents, and a runbook for human engineers, to run a complete, production-safe resilience test of
a live SaaS: test how it fails, fix the gaps, deploy the fixes, prove them in production and leave the docs true to
what production does.

It works for any stack with a web front end, an API, a database (managed SQL, SQLite, Postgres or serverless SQL),
background jobs, a payment provider, an auth library with OAuth providers and magic links, an edge/CDN with a WAF,
optionally self-hosted servers running containers, and a status page or uptime monitor.

## What it covers

| #  | Phase                                                                                            |
| -- | ------------------------------------------------------------------------------------------------ |
| 0  | Survives a reboot or upgrade: restart policies, boot units, health checks, start order           |
| 1  | Map the stack: components, critical path, external calls, single points of failure, backups     |
| 2  | External calls: timeouts, bounded retries, fallbacks, including calls hidden inside libraries   |
| 3  | Database: query time limits, keyset pagination, indexes, typed rows checked in CI               |
| 4  | Database down mid-request: clean 503 with `retry-after`, no half-written state, idempotent money |
| 5  | Observability: deep health endpoint, outside monitor, post-deploy check, tracing, error tracking |
| 6  | Load test until it breaks: stepped concurrency, first bottleneck, headroom over today's traffic |
| 7  | Kill switches: one per risky feature, no deploy needed, fail open, UI notice, one live flip     |
| 8  | Deploys and rollback: zero downtime, one-command rollback, edge rules exported, HTTPS and TLS   |
| 9  | Disaster recovery: restore script with `check` and `apply`, drill in a scratch root, rebuild gaps |
| 10 | Incident runbook: the first ten minutes, levers from a switch to a full restore                 |
| 11 | Docs versus code: every runbook checked against production                                       |
| 12 | Gate, deploy, verify every public surface, watch CI, report                                      |

The safety contract comes first: every action is classed (read-only, reversible write, irreversible write), and an
authorisation ladder is climbed one rung at a time, from read-only inspection up to deploys, git operations and
spending. Destructive experiments run locally or on staging only.

## Files

```
SKILL.md                      the method, the safety rules and the phase list
references/safety.md          the safety contract and the authorisation ladder
references/phases.md          every phase in full: discovery, change, test, production proof, exit criteria
references/checklists.md      one checklist per phase
references/pitfalls.md        traps met in real runs: symptom, cause, fix
references/report-template.md the final report and the docs to update
scripts/restore.sh            restore skeleton: check (changes nothing) and apply (refuses to overwrite)
scripts/loadtest.sh           stepped load test with its own server on a random port
scripts/signed-request.sh     HMAC-signed request that keeps the secret out of the process arguments
```

Every script prints its usage with `--help` and supports `--dry-run`.

## Install

For an agent that reads skills from a directory (a `SKILL.md` with YAML frontmatter), clone this repository into it:

```sh
git clone https://github.com/regisandre/prod-resilience-test <skills-directory>/prod-resilience-test
```

Use the agent's user-level skills directory to have it in every project, or the project's own skills directory to
share it with the team through the repository.

Then ask for a "resilience test", a "chaos test", a "production readiness" review, a "restore drill", a "kill switch",
or "load test until it breaks".

A human can follow `SKILL.md`, then `references/phases.md` phase by phase, ticking `references/checklists.md`.

## Script requirements

`bash`, `curl`, `jq`, `python3`. Per script: `age`, `sqlite3`, `pg_restore`, `docker` and the `aws` CLI (any
S3-compatible store) for `restore.sh`; [oha](https://github.com/hatoo/oha) for `loadtest.sh`.

## License

[MIT](LICENSE)
