# Report template

> Status: template for the final report of a resilience run.
> Last checked: 2026-10-26

Write the report in `<owner>`'s language. Keep it short. Evidence over prose: status codes, timings, tables. Never a secret, never a real token, never a key value (ids only).

Fill it during the run, not at the end.

---

```markdown
# Resilience test - <app> - <YYYY-MM-DD>

> Status: done | in progress | stopped (<why>)
> Last checked: <YYYY-MM-DD>

## Summary

- <3 to 6 lines: what was tested, what broke, what was fixed, what is still open>

## Authorisations

| Rung | Scope asked                      | Answer    | Date   |
| ---- | -------------------------------- | --------- | ------ |
| 1    | read-only prod                   | yes       | <date> |
| 2    | local / staging experiments      | yes       | <date> |
| 3    | flip `<feature>` switch off/on   | yes       | <date> |
| 4    | deploy `<component>` `<version>` | yes       | <date> |
| 5    | push `<repo>` `<sha>`            | yes       | <date> |
| 6    | spend                            | not asked |        |

## Per phase

### 0. Reboot

| Container | Restart policy | Health check | Comes back |
| --------- | -------------- | ------------ | ---------- |

Reboot: run | not run (<why>). Recovery: <N> s from outside.

### 1. Stack map

Doc: `<path>`. Single points of failure: <list, each accepted or to fix>.

### 2. External calls

| Call | Timeout before | Timeout after | Retry | Fallback | Test |
| ---- | -------------- | ------------- | ----- | -------- | ---- |

### 3. Database

| Query | Plan before | Plan after | Change |
| ----- | ----------- | ---------- | ------ |

Time limit: <value>. Types check: <CI step name>.

### 4. Database down

| Entry | Before | After (status, retry-after, body) |
| ----- | ------ | --------------------------------- |

Money writes idempotent: <list>. Prod proof: same `Idempotency-Key` twice -> <result>.

### 5. Observability

Deep health: `<url>` -> <code>, checks <list with ms>. Monitor: every <N> min, alerts <channel>.

### 6. Load

| Concurrency | rps before | p50 / p99 before | rps after | p50 / p99 after | errors |
| ----------- | ---------- | ---------------- | --------- | --------------- | ------ |

Noise between runs: <percent>. Bottleneck: <what>. Headroom: <X req/s vs today Y req/s>.

### 7. Kill switches

| Feature | Entries covered | Cache | Fail mode |
| ------- | --------------- | ----- | --------- |

Prod flip: `<feature>` off at <time>, 503 seen after <N> s, UI notice <screenshot path>, back on at <time>.

### 8. Deploy and edge

Rollback: `<command>`, <N> s. HTTP -> <code>. TLS 1.1 -> refused. HSTS: <value>. Edge export: `<path>`.

### 9. Disaster recovery

Drill: check <N> s, apply <N> s, cleanup verified. Latest backup: <size>, download <N> s, header ok.
Rebuild gaps: <list with decision>.

### 10. Incident runbook

Doc: `<path>`. Postmortem read: <URL>.

### 11. Docs

Updated: <list>. Deleted: <list>. Changelog: <entry or declined>.

### 12. Gate and deploy

Gate: typecheck, lint, <N>/<N> tests, generated files, secret scan -> green.

## Rollback targets

| Component | Before                   | After   | Rollback command |
| --------- | ------------------------ | ------- | ---------------- |
| <worker>  | version `<id>`           | `<id>`  | `<command>`      |
| <service> | digest `sha256:<...>`    | `<...>` | `<command>`      |
| <file>    | `<path>.before-<change>` |         | `cp ...`         |

## Deployed

| What | Where | Version | Verified by |
| ---- | ----- | ------- | ----------- |

## Public surfaces after deploy

| URL | Code | Time |
| --- | ---- | ---- |

## Incidents during the test

<none | what ran, what broke, what was restored, evidence>

## Still open

| Item | Why open | Decision of <owner> |
| ---- | -------- | ------------------- |

## Sources

- <URL> - <what it settled; "contradicted first guess" or "found nothing" when true>

## Git state

| Repo | Branch | Commit | Pushed | CI  | Why not pushed |
| ---- | ------ | ------ | ------ | --- | -------------- |

## Cleanup

- Test keys revoked: <ids>, 401 checked.
- Scratch volumes and dirs removed: <list>, checked empty.
- Switches back on: <list>.
- Integrity baseline accepted: <date>, <N> entries explained.
```

---

## Docs to update at the end

| Doc                                  | What to change                                               |
| ------------------------------------ | ------------------------------------------------------------ |
| Stack map                            | Components, external calls table, single points of failure   |
| Backup and restore runbook           | Script usage, drill timings, rebuild gaps                    |
| Kill switches runbook                | Switch list, operator command, cache time, fail mode         |
| Deploy and rollback runbook          | Commands, measured times, laptop path                        |
| Edge configuration doc and exports   | Fresh exports, HTTPS, TLS, HSTS state                        |
| Incident first-ten-minutes runbook   | Commands per component, levers, postmortem lessons           |
| Public API docs                      | 503 shape, `retry-after`, idempotency, pagination if changed |
| Changelog                            | Entry picked by `<owner>`                                    |
| Security or integrity baseline notes | Date and explanation of accepted entries                     |

Every touched doc gets a fresh `> Status:` and `> Last checked:` line.

## Pull requests

- Title and body in English.
- Sections: summary, changes per phase, test results, rollback, what to know before merging.
- No attribution footer, no tool signature.
