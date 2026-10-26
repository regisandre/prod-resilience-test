# Checklists

> Status: one checklist per phase. Copy each into its task and tick as you go.
> Last checked: 2026-10-26

## Start

- [ ] `safety.md` read.
- [ ] Rung 1 (read-only prod) asked and answered.
- [ ] Rung 2 (local / staging) asked and answered.
- [ ] One task per phase created.
- [ ] Report file opened from the template.
- [ ] Git state of every repo recorded.

## Phase 0. Reboot

- [ ] Restart policy of every container listed.
- [ ] Every long-running container `unless-stopped` or `always`.
- [ ] Daemon and required units enabled at boot.
- [ ] `live-restore` checked (set, or reason not).
- [ ] Health check on every service.
- [ ] Start order with `service_healthy`.
- [ ] Per-tenant container recreation path known.
- [ ] `.before-<change>` copy of each edited server file.
- [ ] Reboot: timed with approval, or "not run" with reason.

## Phase 1. Map

- [ ] Component table.
- [ ] Critical path of one request.
- [ ] External calls table (targets, callers).
- [ ] Single points of failure, each "accepted" or "to fix".
- [ ] Backup table, gaps in bold.

## Phase 2. External calls

- [ ] Every direct call found.
- [ ] Every library call on the critical path found, source read for the installed version.
- [ ] Timeout on each call.
- [ ] Retry only on idempotent calls, bounded, with jitter.
- [ ] Fallback or clean 503 on each.
- [ ] Entry-point time limit where a library has no hook.
- [ ] Table-driven test hangs each dependency.
- [ ] Sources cited.

## Phase 3. Database

- [ ] Time limit on every query path.
- [ ] No OFFSET on a growing list.
- [ ] EXPLAIN on each hot query, before and after.
- [ ] Missing indexes added in a new migration with a real timestamp.
- [ ] Typed rows generated, CI fails on drift (proved once).

## Phase 4. Database down (local / staging)

- [ ] Every entry listed (routes, webhooks, jobs, tools).
- [ ] Every money write listed.
- [ ] 503 with `retry-after` in each caller's shape.
- [ ] No stack trace in any prod response.
- [ ] No half-written state (transaction or batch).
- [ ] Money writes idempotent, provider key stable.
- [ ] Money test broken once, watched fail, restored.
- [ ] Prod proof: same idempotency key twice.

## Phase 5. Observability

- [ ] Deep health checks every dependency and renders one page.
- [ ] Each check timed, 503 names the failure.
- [ ] Outside monitor every 1 to 5 min, alerts a human.
- [ ] Deploy pipeline checks deep health after the switch.
- [ ] Tracing sampled, request id header.
- [ ] Error tracking server and client, release tagged.
- [ ] Heartbeat on silent jobs.

## Phase 6. Load (local / staging)

- [ ] Today's peak rps and p99 recorded.
- [ ] Random port, own PID, bind errors checked.
- [ ] Steps run, 2 runs each, noise reported.
- [ ] Secondary load capped.
- [ ] Break point and bottleneck named.
- [ ] Cheap fix applied and re-measured, or accepted.
- [ ] Headroom statement written.

## Phase 7. Kill switches

- [ ] Risky feature list.
- [ ] Every account creation path listed.
- [ ] Store changes without deploy.
- [ ] Cache a few seconds, fail open (tested).
- [ ] 503 with `retry-after` before any other work.
- [ ] Sign-up switch in the user-create hook, every method tested.
- [ ] Existing users still sign in (tested).
- [ ] Agent / MCP write tools check their switch.
- [ ] UI notice and disabled button, every UI language.
- [ ] Operator command documented.
- [ ] Rung 3 asked for one flip.
- [ ] Prod flip: API 503, delay timed, UI notice seen, back on.

## Phase 8. Deploys and edge

- [ ] Zero-downtime switch.
- [ ] Post-switch deep health check.
- [ ] One-command rollback, timed once.
- [ ] Frozen lockfile in CI and laptop.
- [ ] Laptop deploy documented, equals CI.
- [ ] WAF, rate-limit and settings exported to the repo.
- [ ] HTTP redirects at the edge.
- [ ] TLS 1.2 minimum.
- [ ] HSTS on.

## Phase 9. Disaster recovery

- [ ] Backups listed, lifecycle known.
- [ ] Freshness alert in place.
- [ ] Restore `check` mode: decrypt, list, integrity, timed, shred on exit.
- [ ] Restore `apply` mode: refuses overwrite, chown per volume.
- [ ] Drill in scratch root, prefixed volumes, throwaway key.
- [ ] Drill cleanup verified empty.
- [ ] Real latest backup download timed, header checked, file shredded.
- [ ] Local-only images published or backed up.
- [ ] Rebuild gaps listed with decisions.

## Phase 10. Incident runbook

- [ ] What alerts.
- [ ] One command per component, each run once.
- [ ] Levers from switch to restore.
- [ ] Status page template.
- [ ] One public postmortem read, lessons and URL.

## Phase 11. Docs

- [ ] Every runbook checked against code and prod.
- [ ] Status headers current.
- [ ] Stale plans deleted, same-topic docs merged.
- [ ] Changelog multi-select asked.

## Phase 12. Gate, deploy, verify

- [ ] Gate green: typecheck, lint, tests, generated files, secret scan.
- [ ] Rollback targets in the report.
- [ ] Rung 4 asked, deploy from the root build.
- [ ] Every public surface checked (site, docs, API, auth, MCP, status page, sitemap).
- [ ] Rung 5 asked per git operation.
- [ ] CI run id resolved, watched, green.
- [ ] Integrity baseline: every entry explained, then accepted.

## End

- [ ] Test keys revoked, 401 checked.
- [ ] Scratch resources removed.
- [ ] Every switch back on.
- [ ] Report in `<owner>`'s language, sources, git state.
