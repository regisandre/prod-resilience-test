# Phases in full

> Status: generic method. Commands use placeholders in angle brackets.
> Last checked: 2026-10-26

Each phase has the same sections: goal, discovery (read-only), change, test, prove in production, write down, exit criteria. Class every command (read-only, reversible write, irreversible write) before running it. See `safety.md`.

Adapt each command to the stack. A command that does not apply is skipped with a note in the report, never silently.

---

## Phase 0. Survives a reboot or upgrade

### Goal

After a host reboot, a daemon upgrade or a crash, every service comes back by itself, in the right order, healthy.

### Discovery (read-only)

```bash
# Restart policy of every container
ssh <node-host> 'docker ps -a --format "{{.Names}}" | xargs -r -I{} docker inspect -f "{{.Name}} {{.HostConfig.RestartPolicy.Name}}" {}'

# Daemon enabled at boot, live-restore set
ssh <node-host> 'systemctl is-enabled docker; docker info --format "{{.LiveRestoreEnabled}}"'

# Health checks defined and current state
ssh <node-host> 'docker ps --format "{{.Names}} {{.Status}}"'
ssh <node-host> 'docker inspect -f "{{.Name}} {{if .Config.Healthcheck}}{{.Config.Healthcheck.Test}}{{else}}none{{end}}" $(docker ps -q)'

# Start order in compose
ssh <node-host> 'grep -n -A3 "depends_on" /srv/<app>/docker-compose.yml'

# Other units that must start at boot (tunnels, agents, timers)
ssh <node-host> 'systemctl list-unit-files --state=enabled --no-pager | grep -v "@"'
ssh <node-host> 'systemctl list-timers --no-pager'

# Host uptime and pending kernel reboot
ssh <node-host> 'uptime; [ -f /var/run/reboot-required ] && echo reboot-required || echo no-reboot-pending'
```

Find how per-tenant containers are created (an API that calls the container daemon, a reconcile loop, a compose template). Ask: if all of them vanish, what recreates them, and from which stored state?

### Change

- Set `restart: unless-stopped` (or `always`) on every long-running container. One-shot jobs keep `no`.
- `systemctl enable docker` and any tunnel or agent unit.
- `live-restore: true` in `/etc/docker/daemon.json` when the daemon supports it, so a daemon restart does not stop containers. Never set it while a swarm is in use.
- Add a health check to each service that has none: an HTTP probe on its own health route, or a process check.
- Use `depends_on` with `condition: service_healthy` for start order.
- Make per-tenant containers recreate from stored state (a reconcile at boot, or restart policies on them too).

Every change to a server file: `.before-<change>` copy first.

### Test

On staging or a local VM: `sudo reboot`, then time until every container is `healthy` and the deep health endpoint answers 200.

### Prove in production (optional, rung 3, quiet time)

1. Check the reboot preconditions in `safety.md` section 5.
2. Note the time. Reboot:

   ```bash
   ssh <node-host> 'sudo systemctl reboot'
   ```

3. Poll from outside:

   ```bash
   start=$(date +%s); until curl -fsS -o /dev/null https://<api-host>/health/deep; do sleep 5; done; echo "back after $(( $(date +%s) - start )) s"
   ```

4. Check every container is up and healthy, per-tenant containers included.
5. Check the uptime monitor recorded the outage and the recovery.

### Write down

Restart policy table, boot units, the timed recovery (or "not run, why"), anything recreated by hand.

### Exit criteria

- Every long-running container has a restart policy that survives a reboot.
- The daemon and every required unit are enabled at boot.
- Recovery time is measured, or the reason for not measuring is written.

---

## Phase 1. Map the stack

### Goal

One page that lists every component, the critical path of a request, every external call, every single point of failure, and what is backed up.

### Discovery (read-only)

```bash
# Repo layout and deploy targets
git ls-files | grep -E '(wrangler|vercel|fly|netlify|docker-compose|Dockerfile|serverless|terraform|\.github/workflows)' 
# Outbound hosts the code calls
git grep -nE 'https?://[a-z0-9.-]+' -- '*.ts' '*.js' '*.py' '*.go' '*.rs' | grep -vE 'localhost|example\.(com|org)' | sed -E 's#.*(https?://[^/"'"'"' ]+).*#\1#' | sort | uniq -c | sort -rn
# Env variable names (names only, never values)
git grep -nhoE '(process\.env|env)\.[A-Z0-9_]+' | sort -u
# DNS and edge
dig +short <prod-domain>; dig +short <api-host>
curl -sI https://<prod-domain> | grep -iE '^(server|cf-|x-vercel|via|x-served-by)'
# Containers and volumes on each server
ssh <node-host> 'docker ps --format "{{.Names}} {{.Image}}"; docker volume ls --format "{{.Name}}"'
# Scheduled jobs
git grep -nE 'cron|schedule' -- '*.toml' '*.yml' '*.yaml' '*.json'
```

### Change

None. Mapping only.

### Write down

Create or update `docs/architecture/stack-map.md`:

- Component table: name, where it runs, what it stores, owner of the account, how it is deployed.
- Critical path of one authenticated API request: edge, WAF, worker or server, auth check, database, external calls, response.
- External calls table: target, caller, purpose, timeout today, retry today, fallback today. Fill the last three in phase 2.
- Single points of failure: one database, one server, one region, one account, one person with access.
- Backup table: what, where, how often, encrypted with what, retention, last restore tested. Mark "not backed up" in bold where true.

### Exit criteria

- Every component in the repo and in prod is on the map.
- Every single point of failure is named, with "accepted" or "to fix" next to it.

---

## Phase 2. External calls

### Goal

No outbound call can hang a request. Each one has a timeout, a bounded retry when it is safe, and a fallback or a clean error.

### Discovery (read-only)

```bash
# Direct calls
git grep -nE '\b(fetch|axios|got|request|http\.(get|post)|urlopen|reqwest)\b' -- ':!**/test/**'
# Timeouts already present
git grep -nE 'AbortSignal\.timeout|timeout:|signal:|Duration|deadline|ctx, cancel' -- ':!**/test/**'
# Library calls that hide a network call
git grep -nE '(oauth|socialProviders|captcha|sendEmail|mailer|llm|completion|payment|checkout|charge)' -- ':!**/test/**'
```

For each third-party library on the critical path, read its source in `node_modules` (or the vendored path) for the installed version. Look for its own timeout before claiming a gap.

```bash
grep -rnE 'timeout|AbortSignal|signal' node_modules/<library>/dist | head -40
```

### Change

For each call, in this order of preference:

1. **Timeout** on the call itself: `AbortSignal.timeout(<ms>)`, client `timeout` option, context deadline. Pick it from the p99 of the dependency plus margin, not from habit.
2. **Retry**, only for idempotent calls (GET, or a write with an idempotency key). At most 2 retries, exponential backoff with jitter, and a total budget under the caller's own timeout.
3. **Fallback** when a degraded answer is acceptable: a cached value, a default, a queue for later. Otherwise a **clean error**: 503 with `retry-after`, in the shape the caller reads.
4. **When a library offers no hook** (OAuth token or profile fetch, a captcha client): bound the whole entry point with a time limit and answer a clean 503 on expiry.

Specific calls to cover:

| Call                          | Typical rule                                                                |
| ----------------------------- | --------------------------------------------------------------------------- |
| OAuth token and profile fetch | Bound the callback route; on expiry redirect to sign-in with an error code  |
| Captcha verification          | Short timeout; decide fail-open or fail-closed per route and write it down  |
| Email sending                 | Timeout; queue or log on failure; never fail the user action for a receipt  |
| LLM or ML API                 | Timeout; retry only if the request is idempotent; clean error to the caller |
| Payment provider              | Timeout; idempotency key on every write; retry with the same key            |
| Webhooks out                  | Timeout; retry from a queue with backoff; dead-letter after N tries         |

### Test

One table-driven test per rule. Stub the dependency to hang (a promise that never resolves, or a delay past the timeout). Assert the caller answers within the bound, with the expected status and body, and that a non-idempotent call was sent once.

### Prove in production

A request through each bounded path still answers 200 in normal time. Log lines show the timeout values loaded (if logged). No new errors in error tracking for 30 minutes after deploy.

### Write down

Fill the timeout, retry and fallback columns of the external calls table in the stack map. Add the source URLs read for each library.

### Exit criteria

- Every external call in the table has a timeout, a retry rule (or "none, not idempotent") and a fallback or clean error.
- Each new bound has a test that hangs the dependency.

---

## Phase 3. Database queries

### Goal

No query can run unbounded. Growing lists page by key. Hot queries use an index. Code types match the schema.

### Discovery (read-only)

```bash
git grep -nE '\bOFFSET\b|\.offset\(' -- ':!**/test/**'
git grep -nE 'statement_timeout|busy_timeout|query_timeout|timeout' -- '*.sql' '*.ts' '*.py' '*.go'
git grep -nE 'SELECT .* FROM' -- ':!**/test/**' | wc -l
```

Run EXPLAIN on each hot query against a copy or locally with the real migrations:

```sql
-- Postgres
EXPLAIN (ANALYZE, BUFFERS) <query>;
-- SQLite / serverless SQLite
EXPLAIN QUERY PLAN <query>;
```

Look for `Seq Scan` or `SCAN <table>` on large tables, and `USE TEMP B-TREE FOR ORDER BY`.

### Change

- **Time limit**: `statement_timeout` per role or per transaction (Postgres), `busy_timeout` plus a wrapper deadline (SQLite), the client query timeout otherwise.
- **Keyset pagination**: replace `OFFSET n` with `WHERE (created_at, id) < (:c, :i) ORDER BY created_at DESC, id DESC LIMIT :n`. Return an opaque cursor.
- **Indexes**: add the index EXPLAIN asks for, in a new migration with a real timestamp. On Postgres, `CREATE INDEX CONCURRENTLY` in its own migration outside a transaction when the table is big.
- **Typed rows**: generate the row types from the migrations (a schema dump, the provider's type generator). Add a CI step that regenerates and fails on a diff.

### Test

- A table-driven pagination test: N rows, page size k, walk all pages, assert no duplicate and no gap, including rows with equal timestamps.
- A test that a slow query hits the time limit and maps to the clean error.
- The CI type check: add a column in a scratch migration without regenerating, watch CI fail, revert.

### Prove in production

The migration version is in the migration history table. One read shows the new index exists. The paged route answers with a cursor.

### Write down

Queries changed, EXPLAIN before and after, the timeout values, the CI check name.

### Exit criteria

- No `OFFSET` on a growing list.
- Every hot query plan uses an index.
- A time limit applies to every query path.
- CI fails when types and migrations drift.

---

## Phase 4. Database down mid-request (local or staging only)

### Goal

When the database disappears in the middle of a request, every entry answers a clean 503 with `retry-after`. No half-written state. Every money write is safe to retry.

### Discovery (read-only)

List every entry: HTTP routes, webhooks in, scheduled jobs, queue consumers, agent or MCP tools. List every money write: balance credit or debit, invoice line, payment record, refund, plan change.

```bash
git grep -nE '(credit|debit|balance|invoice|refund|charge|payment|subscription)' -- ':!**/test/**' | grep -iE '(insert|update|upsert)'
git grep -nE 'idempotency|Idempotency-Key|idempotencyKey' -- ':!**/test/**'
```

### Change

- One error mapping at the edge of the app: a database unavailable error (connection refused, timeout, "database is locked", pool exhausted) becomes 503 with `retry-after: <seconds>` and a body in the shape the caller reads (JSON API error, HTML page for a browser, the protocol's error for an agent tool, a non-2xx for a webhook so the sender retries).
- Never a 500 with a stack trace. Strip stack traces from every prod response.
- Wrap the auth library's entry, the agent or MCP entry and the well-known routes too: a rejected promise there must become one logged failure and a clean answer that still carries the security headers.
- Group multi-step writes in a transaction or a batch so a failure leaves nothing half done.
- Money writes: a unique key per logical operation (`<source>:<request-id>`), stored with the write, `INSERT ... ON CONFLICT DO NOTHING`, then read back. A retry returns the first result.
- Payment provider: derive its idempotency key from the logical operation, not from a random value made per attempt. The same key on every retry.
- Webhooks in: dedupe by the provider's event id before any side effect.

### Test

Locally or on staging:

```bash
# Postgres in a container
docker stop <db-container>
# SQLite file
chmod 000 <db-file>   # or point the app at a missing path
# Managed or serverless DB: stub the binding to throw in the test harness
```

In the test suite, a table of entries x failure points (before the write, between two writes, after the write but before the response). For each case assert: status 503, `retry-after` present, body shape, no partial rows, and on retry exactly one money row.

On a money path: break the idempotency (remove the `ON CONFLICT`), watch the test fail, restore.

### Prove in production

Not by killing the database. Instead:

- Send the same write twice with the same `Idempotency-Key` using a test key. Assert the second answer equals the first and the balance moved once.
- Check that a forced error route (if one exists for tests) or a malformed request gives no stack trace.

### Write down

The entry table with its 503 shape, the money writes with their idempotency key, the test names.

### Exit criteria

- Every entry answers a clean 503 with `retry-after` when the database is down.
- No half-written state in any case of the table.
- Every money write is idempotent, and the provider key is stable across retries.

---

## Phase 5. Observability

### Goal

A failure is seen within minutes, from outside, and the cause is findable.

### Discovery (read-only)

```bash
curl -s -o /dev/null -w '%{http_code} %{time_total}\n' https://<api-host>/health
curl -s https://<api-host>/health/deep
git grep -nE '(sentry|bugsnag|rollbar|honeybadger|otel|opentelemetry|trace|sampl)' -- ':!**/test/**'
grep -nE 'health' .github/workflows/*.yml
```

Check the uptime monitor's target URLs and interval. Check who gets the alert and how.

### Change

- **Deep health endpoint** (`/health/deep` or similar): checks each dependency (database read, object storage head, cache, each critical external API with a cheap call), renders one real page through the normal render path, times each check, answers 200 with the timings or 503 with the failing check named. No secret, no internal host in the body. Rate-limit it or protect it if a check is expensive.
- **Outside watch**: the uptime monitor polls the deep endpoint every 1 to 5 minutes and alerts a human.
- **Deploy check**: the pipeline calls the deep endpoint after each switch and rolls back or fails loudly on non-200.
- **Tracing**: sample request traces (1 to 10 percent) with a request id echoed in a response header.
- **Error tracking**: wired on server and client, with release tags so an error maps to a deploy.
- **Silent jobs**: a scheduled job writes a heartbeat. A separate check alerts when the heartbeat is stale (backups, billing sync, cleanup).

### Test

Unit test the health aggregator: a table of dependency states (all ok, one slow, one failing) to expected status and body.

### Prove in production

```bash
curl -s -w '\n%{http_code}\n' https://<api-host>/health/deep
curl -sI https://<api-host>/<any-route> | grep -i 'x-request-id'
```

Check the uptime monitor shows the deep endpoint green with its interval. Find one real trace and one test error in the tracking tool.

### Write down

The health checks and their timings, the monitor interval and alert route, the sampling rate.

### Exit criteria

- Deep health answers 503 naming the failing dependency.
- An outside monitor watches it and alerts a human.
- The deploy pipeline checks it after each switch.

---

## Phase 6. Load test until it breaks (local or staging only)

### Goal

Know the first bottleneck and the headroom over today's traffic.

### Discovery (read-only)

- Today's traffic: peak requests per second and p99 from the edge analytics or logs, last 30 days.
- The hot routes: top 5 by request count.
- The pool sizes, worker counts, connection limits, rate limits in config.

### Change (only after a measurement)

Typical cheap fixes: raise a pool size, remove a global lock, add an index, cache a hot read, move work off the request path. One change at a time.

### Test

Use `scripts/loadtest.sh`. Rules:

- Random port per run. Start the server, record its PID, kill only that PID. Check the server log for bind errors before trusting a number.
- Steps of concurrency, for example 1, 4, 16, 64, 128, 256. Each step 30 to 60 s.
- Record per step: requests per second, p50, p99, error rate.
- At least two runs before and two after each change, same kit, same data. Report the spread between runs.
- Cap the secondary load (for example background reads at a fixed rate) so the change does not only move CPU.
- Stop at the first step where errors pass 1 percent or p99 passes the target. That is the break point.

```bash
scripts/loadtest.sh --url http://127.0.0.1:<port>/<route> --steps 1,4,16,64,128 --duration 30 --runs 2 --out results/<label>.csv
```

### Prove in production

Not by load testing prod. State the result against today's traffic: "Break point is X req/s at p99 Y ms. Today's peak is Z req/s. Headroom is X/Z."

### Write down

Before and after table per step, the run spread, the bottleneck found, the fix, the headroom statement.

### Exit criteria

- Break point and first bottleneck are known.
- Cheap fixes applied and re-measured, or written as "accepted".

---

## Phase 7. Kill switches

### Goal

`<owner>` can turn off a risky feature in seconds without a deploy, and users see a clear notice instead of an error.

### Discovery (read-only)

List the risky features: sign-up, free trial or demo endpoint, contact form, exports, new payments or checkout, agent or MCP API, expensive model calls, file uploads. List every way an account is created: password, magic link, each OAuth provider, invitation, admin creation, API.

```bash
git grep -nE '(signUp|sign-up|createUser|socialProviders|magicLink|invite)' -- ':!**/test/**'
```

### Change

- **Store**: a table or key-value entry that can change without a deploy. One row per feature: name, off flag, reason, changed at, changed by.
- **Read**: cached a few seconds per instance (5 to 30 s). **Fail open**: if the store cannot be read, the feature stays on and the error is logged.
- **Check first**: the switched-off feature answers 503 with `retry-after` and a body naming the feature, before any other work (no captcha call, no database write, no charge).
- **Every path**: the sign-up switch sits in the one place every account creation passes (the auth library's user-create hook), so password, magic link and each OAuth provider are covered. Existing users still sign in, including by magic link and OAuth.
- **Agent or MCP tools**: each write tool declares its feature. The tool wrapper checks the switch before the tool runs.
- **UI**: a public endpoint lists the switched-off features. The page shows a notice and disables the button. Translate the notice into each UI language.
- **Operator path**: one documented command to flip a switch and to read the current state.

### Test

One table-driven test: for each feature and each entry (each sign-up method, each tool), switch off, assert 503 with the body and `retry-after`, assert no side effect happened. Plus: store unreadable, assert the feature works (fail open). Plus: existing user signs in while sign-up is off.

### Prove in production (rung 3)

Pick one low-risk switch (the contact form, for example). Ask `<owner>` for this exact flip.

```bash
# 1. State before
curl -s https://<api-host>/features
# 2. Flip off with the documented operator command
<operator-command> switch off contact --reason "resilience test"
t0=$(date +%s)
# 3. Poll until the API answers 503 (shows the cache delay)
until [ "$(curl -s -o /dev/null -w '%{http_code}' -X POST https://<api-host>/contact -H 'content-type: application/json' -d '{}')" = 503 ]; do sleep 1; done
echo "off after $(( $(date +%s) - t0 )) s"
curl -si -X POST https://<api-host>/contact -H 'content-type: application/json' -d '{}' | grep -iE '^(HTTP|retry-after)|feature'
# 4. Check the UI notice in a browser, take a screenshot
# 5. Flip back on and check it answers normally again
<operator-command> switch on contact
```

### Write down

The switch table (feature, entries covered, cache time, fail mode), the prod flip with timings, the screenshot path, the operator command.

### Exit criteria

- One switch per risky feature, covering every entry.
- Fail open proven by a test.
- One prod flip done, timed and reverted.

---

## Phase 8. Deploys, rollback and edge configuration

### Goal

A deploy never takes the site down, a bad deploy rolls back in one command, and the edge config is written down and safe.

### Discovery (read-only)

```bash
grep -nE '(deploy|rollback|frozen|--frozen-lockfile|npm ci|health)' .github/workflows/*.yml package.json
# Worker or serverless versions
<edge-cli> deployments list --name <worker-name>
# Edge security
curl -sI http://<prod-domain> | head -3
curl -sI https://<prod-domain> | grep -i strict-transport-security
for v in 1.0 1.1; do curl -s -o /dev/null -w "tls$v %{http_code}\n" --tls-max $v --tlsv$v https://<prod-domain> || echo "tls$v refused"; done
curl -s -o /dev/null -w 'tls1.2 %{http_code}\n' --tlsv1.2 --tls-max 1.2 https://<prod-domain>
```

### Change

- **Zero downtime**: versioned uploads with a traffic switch, or blue-green containers behind a proxy, or rolling restarts with health checks.
- **Post-switch check**: the pipeline calls deep health right after the switch. Non-200 rolls back.
- **One-command rollback**: documented, tested once on staging.

  ```bash
  <edge-cli> rollback <previous-version-id>
  # or, containers
  ssh <node-host> 'cd /srv/<app> && cp docker-compose.yml.before-<change> docker-compose.yml && docker compose up -d'
  ```

- **Frozen lockfile** in CI and in the laptop deploy.
- **Laptop deploy**: a documented path identical to CI (same build command from the repo root, same checks), for when CI is blocked.
- **Edge export**: export WAF rules, rate-limit rules and zone settings to JSON in the repo, with a README that says how to diff against live. Use a read-only API token with the WAF read scope.
- **HTTPS**: plain HTTP answers a redirect at the edge (an API key sent to `http://` travels in clear before any app redirect). Minimum TLS 1.2. HSTS sent on every page.

### Test

On staging: deploy a version that fails deep health, watch the pipeline roll back. Time the rollback command.

### Prove in production

```bash
curl -sI http://<prod-domain> | head -1          # expect 301 or 308
curl -sI https://<prod-domain> | grep -i strict-transport-security
curl -s -o /dev/null -w '%{http_code}\n' --tlsv1.1 --tls-max 1.1 https://<prod-domain>   # expect failure
<edge-cli> deployments list --name <worker-name> | head -5
```

### Write down

The deploy and rollback commands with their measured times, the edge export files, the HTTPS, TLS and HSTS results.

### Exit criteria

- Rollback is one command and was timed.
- The laptop deploy is documented and equals CI.
- Edge rules are exported. HTTP redirects. TLS 1.2 minimum. HSTS on.

---

## Phase 9. Disaster recovery

### Goal

From nothing but the backups and the password manager, `<app>` can be rebuilt, and the time to do it is known.

### Discovery (read-only)

```bash
# Backups present, newest first
<s3-cli> ls s3://<backup-bucket>/<prefix>/ --recursive | sort | tail -5
# Bucket lifecycle (expiry)
<s3-cli> get-bucket-lifecycle-configuration --bucket <backup-bucket>
# Images that exist only on the server
ssh <node-host> 'docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" | grep -E "^(localhost|<local-registry>)"'
# Uid:gid each image runs as
ssh <node-host> 'for c in $(docker ps --format "{{.Names}}"); do echo "$c $(docker exec $c id -u):$(docker exec $c id -g)"; done'
```

### Change

- **Restore script** (`scripts/restore.sh` skeleton):
  - `check` mode: download the latest backup, decrypt to a temp dir, list contents, run an integrity check on every database (`PRAGMA integrity_check`, `pg_restore --list`), print timings, shred the plaintext on exit with a trap. Changes nothing.
  - `apply` mode: refuses to overwrite an existing volume or directory, restores files and volumes, `chown` per volume to the uid:gid its image runs as.
- **Images**: publish every image to a remote registry, or back them up with an encrypted `docker save`, once per image id, refreshed before the bucket lifecycle expires them.
- **Freshness alert**: a scheduled check fails when the newest backup is older than the expected interval plus margin.

### Test (rung 3 on the live server, scratch root only)

```bash
# Throwaway key for the drill, never the real one
age-keygen -o /tmp/drill.key
# Make a small encrypted test backup with the drill key, then
scripts/restore.sh check --source <test-backup> --key /tmp/drill.key --dry-run
scripts/restore.sh apply --source <test-backup> --key /tmp/drill.key --root /srv/drill-<date> --volume-prefix drill_
# Clean up everything it made
docker volume ls -q | grep '^drill_' | xargs -r docker volume rm
rm -rf /srv/drill-<date>; shred -u /tmp/drill.key
```

Then with the real latest backup, check mode only, without decrypting on a laptop: time the download and check the encryption header.

```bash
time <s3-cli> cp s3://<backup-bucket>/<latest> /tmp/latest.age
head -c 64 /tmp/latest.age | head -1    # expect the age header line
shred -u /tmp/latest.age
```

### Prove in production

The drill output (timings, integrity ok), the cleanup shown empty (`docker volume ls | grep drill_` returns nothing), the freshness check green.

### Write down

Recovery time estimate per step (new server, install, download, restore, DNS), what a rebuild still lacks (images only local, models to download, secrets in the password manager, manual DNS steps), and the decision `<owner>` took on each gap.

### Exit criteria

- `check` and `apply` both ran in the drill, and the scratch root is gone.
- The real latest backup downloads and has a valid header.
- Every gap of a rebuild is listed with a decision.

---

## Phase 10. Incident runbook

### Goal

At 3 a.m., someone who did not build `<app>` can act in the first ten minutes.

### Change

Write `docs/runbooks/incident-first-ten-minutes.md`:

1. **What alerts**: the monitor, the channel, the message shape.
2. **Look**: one command per component (deep health, edge status, database, each server, the payment provider status page, the email provider status).
3. **Levers**, from smallest to largest: a kill switch, a rate limit, a rollback, scaling or restarting a service, the edge "under attack" mode, the status page notice, a full restore.
4. **Communicate**: status page update template, who to tell.
5. **After**: write a postmortem with a timeline.

Read one real public postmortem end to end (a provider outage on the same stack is best). Add a "Lessons" section with 3 to 5 lessons that apply here, with the URL.

### Exit criteria

- The runbook exists, each command was run once read-only to prove it works.
- One public postmortem cited, with lessons.

---

## Phase 11. Docs versus code

### Goal

Every doc says what prod does today.

### Discovery (read-only)

```bash
git ls-files 'docs/**' '*.md' | xargs grep -L '^> Last checked:'
git ls-files 'docs/**' | xargs grep -n '^> Last checked:' | sort -t: -k3
```

### Change

- For each runbook and decision record: run or read each step against the code and prod. When a doc and the code disagree, the code wins: fix the doc and list the gap in the report. Update `> Status:` and `> Last checked:`.
- Delete plans that were superseded or never built.
- Merge two docs on one topic into one.
- Ask `<owner>` with the question tool for a changelog entry: a multi-select of the user-visible changes from this run. Write only what was picked.

### Exit criteria

- Every internal doc has a current status header.
- No stale plan remains.
- The changelog entry is written or explicitly declined.

---

## Phase 12. Gate, deploy, verify, report

### Goal

Ship the fixes safely and prove them live.

### Steps

1. **Gate** locally:

   ```bash
   <pkg> install --frozen-lockfile
   <pkg> run typecheck
   <pkg> run lint
   <pkg> run test
   <pkg> run <generated-files-check>
   shellcheck <scripts>/*.sh
   gitleaks protect --staged --redact --no-banner
   ```

2. **Rollback targets** recorded for each component (safety section 6).
3. **Deploy** (rung 4), from the repository root build.
4. **Verify every public surface**:

   ```bash
   for u in / /docs /pricing /sitemap.xml /api/health/deep /signin; do
     printf '%s ' "$u"; curl -s -o /dev/null -w '%{http_code} %{time_total}\n' "https://<prod-domain>$u"
   done
   curl -s -o /dev/null -w 'api %{http_code}\n' -H "Authorization: Bearer $TEST_KEY" https://<api-host>/v1/<route>
   curl -s -o /dev/null -w 'mcp %{http_code}\n' https://<api-host>/mcp
   curl -s -o /dev/null -w 'status %{http_code}\n' <status-page>
   ```

5. **Commit and push** only on explicit words (rung 5, one operation each).
6. **Watch CI** on the pushed commit. Resolve the run id first, then watch:

   ```bash
   sha=$(git rev-parse HEAD)
   until id=$(gh run list --commit "$sha" --json databaseId -q '.[0].databaseId') && [ -n "$id" ]; do sleep 5; done
   gh run watch "$id" --exit-status || gh run view "$id" --log-failed | tail -50
   ```

   If red, read the log, fix the real cause locally, and ask before pushing again.

7. **File-integrity baseline**: list every flagged file, explain each (planned change, reboot rewrite, hash changed versus only inode or mtime), then accept the new baseline.
8. **Clean up**: revoke test keys (check a 401), remove scratch resources, confirm all switches are back on.
9. **Report** from `report-template.md`.

### Exit criteria

- Gate green, deploy done, every public surface 200 (or the expected code).
- CI green on the pushed commit.
- Baseline accepted with every entry explained.
- Report delivered.
