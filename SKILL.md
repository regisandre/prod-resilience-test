---
name: prod-resilience-test
description: Run a complete, production-safe resilience test of a live SaaS end to end, fix what it finds, deploy the fixes and leave the docs true to production. Use when asked for a "resilience test", "chaos test", "production readiness" review, "what happens if the database goes down", a "disaster recovery drill" or "restore drill", to add or test a "kill switch", or to "load test until it breaks". Works for any stack - web front end, API, database (managed SQL, SQLite, Postgres, serverless SQL), background jobs, payment provider, auth library with OAuth and magic links, edge/CDN with a WAF, optional self-hosted servers running containers, and a status page.
---

# Production resilience test

> Status: generic method, no product-specific content.
> Last checked: 2026-10-26

This skill tests how a live SaaS fails, fixes the gaps, deploys the fixes and proves them in production.
A human engineer can follow it by hand as a runbook. An agent follows it step by step.

The test must never be the cause of an outage. Read the safety contract before anything else.

## Files

| File                            | Read it when                                                                  |
| ------------------------------- | ----------------------------------------------------------------------------- |
| `references/safety.md`          | Always, first. The safety contract and the authorisation ladder.              |
| `references/phases.md`          | At the start of each phase: goal, discovery, change, test, proof, exit.       |
| `references/checklists.md`      | During each phase. Copy the checklist into the task and tick it.              |
| `references/pitfalls.md`        | When something behaves oddly. Symptom, cause, fix.                            |
| `references/report-template.md` | At the end. The final report and the list of docs to update.                  |
| `scripts/restore.sh`            | Phase 9. Restore skeleton with `check` and `apply` modes.                     |
| `scripts/loadtest.sh`           | Phase 6. Stepped load test wrapper around a load generator.                   |
| `scripts/signed-request.sh`     | Any phase that calls a signed internal endpoint (HMAC over timestamp + body). |

Every script prints its usage with `--help` and supports `--dry-run`.

## Placeholders

Use these everywhere. Never write a real product, domain, host, account or person into a shared doc.

| Placeholder       | Meaning                                 |
| ----------------- | --------------------------------------- |
| `<app>`           | The product name                        |
| `<prod-domain>`   | Public site domain                      |
| `<api-host>`      | API host                                |
| `<node-host>`     | A self-hosted server (SSH target)       |
| `<db-name>`       | Production database name                |
| `<backup-bucket>` | Object storage bucket for backups       |
| `<registry>`      | Container registry                      |
| `<worker-name>`   | Edge worker or serverless function name |
| `<owner>`         | The person who authorises (the user)    |
| `<status-page>`   | Public status page URL                  |

## The safety contract (non-negotiable)

Full text and the ladder: `references/safety.md`. The short form:

1. Production never breaks because of the test.
2. Class every action before running it: **read-only**, **reversible write**, **irreversible write**. Read-only first, always.
3. Climb the authorisation ladder one rung at a time. Ask `<owner>` once per rung with the question tool. Never assume a rung.
   1. Read-only inspection of prod.
   2. Local or staging experiments.
   3. Reversible prod writes (flip a kill switch and back, change a setting and back).
   4. Deploys to prod.
   5. Git commit, push, merge, tag, release.
   6. Anything that costs money (a throwaway server, a paid plan, a paid API tier).

   A go-ahead on the work is never a go-ahead on git or on spending. Each git operation needs its own explicit word.

4. Never print, log or write a secret. Never `cat` an env or secret file. Read secrets on the server inside the command that uses them, then `unset`. Generate a test key for the test and revoke it at the end.
5. Destructive experiments (kill the database, fill a disk, cut the network) run locally or on staging only. The only destructive test allowed in prod is a reboot, with explicit approval, at a quiet time, after checking every container's restart policy.
6. Before every prod change, record the rollback target: previous version id, previous image digest, a `.before-<change>` copy of each file replaced. Write it in the report before the change.
7. Never apply a database migration by hand in an admin console. Write the migration file in the repo with a real timestamp (`date +%Y%m%d%H%M%S`, never a padded `000000`) and let the normal pipeline or the documented deploy command apply it.
8. Do not touch other projects or tenants that share the account, the server or the database.
9. At most two parallel sub-agents. Create one task per phase at the start. Update each task as it passes.

If a rule and a request conflict, stop and ask `<owner>`.

## Method rules

- **Research before fixing or planning.** Search the library's GitHub issues (open and closed) with the exact error. Read the docs for the installed version, not the latest. Read the changelog between the installed and the target version. Cite the URLs in the report. Say so when the search contradicts the first intuition, or when it finds nothing.
- **Check the source before claiming a gap.** A library may already have the timeout you think is missing.
- **Test-driven for business logic.** Write the failing test first. Watch it fail for the right reason. Then fix. One rule per test, cases in a table, each assertion named after its case. On a money path, break the code once, watch the test fail, restore it. No tests for UI rendering.
- **Measure before and after** every performance change with the same kit, at least two runs each. Report the noise between runs. Cap the secondary load (for example reads at a fixed rate) so a change does not only shift CPU from one path to another.
- **Prove in production** with an observable check: status code, header, response body, log line, metric. Reading the code is not proof.
- **Keep the docs true to production.** Every runbook step must match what prod does today. Each internal doc starts with `> Status:` and `> Last checked: YYYY-MM-DD`. Never reference an internal doc path from code.
- **Plain writing.** Short sentences, active voice, imperative for steps. No em dash or en dash: use `-` or `|`. Straight quotes. `...` not the ellipsis character.

## Start of the run

1. Read `references/safety.md`.
2. Ask `<owner>` for rung 1 (read-only prod) and rung 2 (local/staging). Ask the other rungs only when a phase needs them.
3. Create one task per phase (0 to 12). Copy each phase checklist from `references/checklists.md` into its task.
4. Open the report file from `references/report-template.md`. Fill it as you go, not at the end.
5. Record the starting git state of every repository involved: branch, last commit, dirty or clean.

## Phases

Detail for each phase: `references/phases.md`. Checklists: `references/checklists.md`.

| #   | Phase                          | Where it runs                   | Highest rung needed |
| --- | ------------------------------ | ------------------------------- | ------------------- |
| 0   | Survives a reboot or upgrade   | prod read-only, optional reboot | 1, reboot needs 3   |
| 1   | Map the stack                  | prod read-only, repo            | 1                   |
| 2   | External calls                 | repo, local                     | 2                   |
| 3   | Database queries               | repo, local                     | 2                   |
| 4   | Database down mid-request      | local or staging only           | 2                   |
| 5   | Observability                  | repo, prod read-only            | 1, then 4 to ship   |
| 6   | Load test until it breaks      | local or staging only           | 2                   |
| 7   | Kill switches                  | repo, local, one prod flip      | 3                   |
| 8   | Deploys, rollback, edge config | repo, prod read-only            | 1, then 4           |
| 9   | Disaster recovery              | scratch root on the server      | 3, spend needs 6    |
| 10  | Incident runbook               | docs                            | none                |
| 11  | Docs versus code               | docs, repo                      | none                |
| 12  | Gate, deploy, verify, report   | repo, prod                      | 4 and 5             |

### 0. Survives a reboot or upgrade

Check that every container comes back without a human. Restart policy of each container, daemon enabled at boot, `live-restore`, health checks, start order, how per-tenant containers are recreated. A real timed reboot only with explicit approval at a quiet time.

### 1. Map the stack

List every component, the critical path of one request, every external call, every single point of failure, and what is backed up and what is not. Write it down before changing anything.

### 2. External calls

Every outbound call has a timeout, a bounded retry (idempotent calls only) and a fallback or a clean error. Include calls inside third-party libraries: OAuth token and profile fetches, captcha verification, email sending, LLM or ML APIs, the payment provider. When a library has no hook, bound the whole entry point with a time limit and a clean 503.

### 3. Database queries

A time limit on every query. Keyset (cursor) pagination instead of OFFSET on growing lists. Indexes checked with EXPLAIN. Typed rows generated from the migrations, with a CI check that fails when a migration lands without regenerated types.

### 4. Database down mid-request (local or staging only)

Every entry answers a clean 503 with `retry-after` in the shape its caller reads. Never a 500 with a stack trace. No half-written state. Every money write is idempotent on retry, and the payment provider's idempotency key is stable across retries.

### 5. Observability

A deep health endpoint that checks each dependency and renders one real page. Each check timed. 503 when one fails. Watched from outside every few minutes. Checked by the deploy pipeline after each switch. Request tracing sampled. Error tracking wired.

### 6. Load test until it breaks (local or staging only)

Steps of concurrency. Record requests per second, p50, p99, error rate per step. Find the first bottleneck (a global lock, a single DB connection, a pool size). Fix it if cheap. Re-measure. State what it means for today's traffic.

### 7. Kill switches

One switch per risky feature: sign-up, trial or demo endpoint, contact form, exports, new payments, agent or MCP API, expensive model calls. Stored where a change needs no deploy. Cached a few seconds. Fails open when the store cannot be read. A switched-off feature answers 503 with `retry-after` before any other work. The UI shows a notice and disables the button. The sign-up switch covers every way an account is created (password, magic link, each OAuth provider) and never locks out existing users. Then flip one low-risk switch in prod, verify the API answer, the UI notice and the timing, and turn it back on.

### 8. Deploys and rollback

Zero-downtime switch, post-switch check, one-command rollback, frozen lockfile, a documented laptop deploy identical to CI. Export the edge provider's WAF, rate-limit and configuration rules into a doc. Check that plain HTTP redirects to HTTPS at the edge, minimum TLS is 1.2, and HSTS is sent.

### 9. Disaster recovery

Cold standby at zero cost unless `<owner>` approves spending. A restore script with a `check` mode (decrypt, list, integrity check of every database, timed, plaintext shredded on exit, changes nothing) and an `apply` mode (refuses to overwrite, restores with each image's owner uid:gid). Drill it on the live server into a scratch root with prefixed volumes and a throwaway encryption key, then remove everything it made. Time the download of the real latest backup and check its header. List what a rebuild still lacks.

### 10. Incident runbook

The first ten minutes: what alerts, one command per component, the levers from a kill switch to a full restore. Add the lessons of one real public postmortem read end to end.

### 11. Docs versus code

Check every runbook and decision record against the code and prod. Delete stale plans. Ask `<owner>` with the question tool for a changelog entry: multi-select of the user-visible changes.

### 12. Gate, deploy, verify, report

Typecheck, lint, all tests, generated-file checks, secret scan of the staged diff. Deploy (rung 4). Verify every public surface: site, docs, API, auth, agent endpoint, status page, sitemap. Commit and push only on explicit words (rung 5). Watch CI on the pushed commit, fix it if red. Update the file-integrity baseline after planned changes, once every changed file is explained. Write the report.

## When something goes wrong during the test

1. Stop the experiment. Do not run the next step.
2. Restore the rollback target recorded for that change.
3. Check the deep health endpoint and the status page.
4. Tell `<owner>` at once: what ran, what broke, what was restored, the evidence.
5. Write it in the report under "Incidents during the test".

## Common traps

Read `references/pitfalls.md` before phases 6, 8, 9 and 12. The most costly ones:

- A partial build deployed: the front-end package's own build skips the docs merge, headers and sitemap, so `/docs` 404s in prod. Build from the repository root. Check `/docs` after every deploy.
- A benchmark that hits an orphan server from a previous run. Random port per run. Kill by the run's own PID. Check the server log for bind errors.
- An env file that overrides the compose file. Change the env variable, not only the compose image.
- Images only in a local registry on the server. They die with the server.
- Restored files owned by root. `chown` per volume to the uid:gid each image runs as.

## End of the run

1. Revoke every test key. Remove every scratch volume, scratch directory and throwaway encryption key.
2. Confirm every kill switch flipped during the test is back on.
3. Fill the report from `references/report-template.md`, in `<owner>`'s language.
4. List the git state of every repository: pushed or not, and why.
5. Pull requests in English, no attribution footer.
