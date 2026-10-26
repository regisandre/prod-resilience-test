# Pitfalls

> Status: traps met in real resilience runs, made generic.
> Last checked: 2026-10-26

Each entry: symptom, cause, fix. Read before phases 6, 8, 9 and 12.

## 1. Partial build deployed, `/docs` answers 404

- **Symptom**: after a deploy, `https://<prod-domain>/docs` (or the sitemap, or a security header) is gone. The site itself works.
- **Cause**: the front-end package's own build ran instead of the root build. The root build merges the docs site, writes static headers and generates the sitemap. The package build skips those steps.
- **Fix**: always build from the repository root with the documented command. After every deploy, check `/docs`, `/sitemap.xml` and one security header:

  ```bash
  for u in /docs /sitemap.xml; do curl -s -o /dev/null -w "$u %{http_code}\n" https://<prod-domain>$u; done
  curl -sI https://<prod-domain> | grep -iE 'strict-transport|content-security'
  ```

## 2. Benchmark measures the wrong binary

- **Symptom**: "before" and "after" numbers are the same, or the change seems to do nothing.
- **Cause**: an orphan server from a previous run still holds the port. The new server fails to bind and exits. Both runs hit the old process.
- **Fix**: pick a random free port per run. Record the server PID at start and kill only that PID. Grep the server log for `EADDRINUSE`, `address already in use` or `bind` before trusting a number. Print the server version or commit in a response header and check it.

## 3. `wait` hangs the script

- **Symptom**: the load-test script never returns after the load generator finishes.
- **Cause**: a bare `wait` waits for every background job, including the server started in the background.
- **Fix**: `wait "$loadgen_pid"` only. Then `kill "$server_pid"`.

## 4. Windows paths from Git Bash

- **Symptom**: a native Windows tool (Python, a compiled binary) says "file not found" for `/tmp/result.json` that exists.
- **Cause**: Git Bash maps `/tmp` to a Windows path only for its own tools. Native programs get the literal `/tmp/...`.
- **Fix**: convert with `cygpath -w /tmp/result.json`, or keep the work in tools that understand the mapping (`jq`, `awk`), or write under the repo with a relative path.

## 5. Signed internal request answered 401, or a setting resets

- **Symptom**: a hand-signed request to an internal endpoint answers 401. Or it answers 200 and a setting silently goes back to its default.
- **Cause**: the timestamp unit is wrong (milliseconds versus seconds), or the body hash covers different bytes than the body sent (pretty-printed JSON, a trailing newline). For the reset: a field that the endpoint treats as required (for example a memory limit) was missing from the body, and the server wrote its default.
- **Fix**: sign the exact bytes sent (write the body to a file, hash the file, send the file). Check the unit the server expects in its source. Before a PUT, GET the current object and send it back whole with only the field you change. Use `scripts/signed-request.sh`.

## 6. Env file overrides the compose file

- **Symptom**: the image tag is bumped in `docker-compose.yml`, `docker compose up -d` runs, the old image keeps running.
- **Cause**: compose reads `image: ${APP_IMAGE:-<registry>/<app>:<tag>}` and `.env` sets `APP_IMAGE`. The env value wins.
- **Fix**: check for variable substitution in the compose file. Change the env variable (after a `.before-<change>` copy), then `docker compose up -d`. Verify with `docker inspect -f '{{.Config.Image}}' <container>`.

## 7. Images only in a local registry

- **Symptom**: the rebuild plan lists "pull images", but some images exist only on the server.
- **Cause**: images built on the server, or pushed to a registry that runs on the same server.
- **Fix**: publish them to a remote registry, or back them up: an encrypted `docker save`, once per image id, refreshed before the bucket lifecycle rule expires the object. List them in the rebuild gaps until done.

## 8. Restored files owned by root

- **Symptom**: after a restore, a service crashes with "permission denied" on its data directory.
- **Cause**: the backup container ran as root and wrote the files as root. The app image runs as another uid.
- **Fix**: record the uid:gid each image runs as (`docker exec <c> id`). In `apply` mode, `chown -R <uid>:<gid>` each volume after restore.

## 9. Edge dashboard and API traps

- **Symptom**: an export or setting change "works" but nothing changes, or an API call answers 403.
- **Cause**: the browser session is logged into another account of the edge provider. Or the API token lacks the WAF read scope. Or a dashboard internal API refuses a PATCH without its anti-CSRF token.
- **Fix**: check the account id shown in the dashboard before any action. Create a read-only token with exactly the scopes needed (zone settings read, WAF read). Change settings through the dashboard UI, not by replaying its internal calls.

## 10. Assumed missing timeout already exists

- **Symptom**: a wrapper timeout is added and a review points out the library already had one.
- **Cause**: the gap was assumed from the docs or memory, not from the installed source.
- **Fix**: read the library source for the installed version (`node_modules/<lib>/dist`) before claiming a gap. Note the file and line in the report.

## 11. CI red on a lint rule that passes locally

- **Symptom**: CI fails on lint. Local lint is green.
- **Cause**: a different linter version locally (newer or older) reports the rule differently, or the rule is configured per environment.
- **Fix**: read the CI log for the exact rule and line. Fix the code for the real rule. Pin the linter version so local equals CI.

## 12. File-integrity baseline flags planned changes

- **Symptom**: the file-integrity monitor reports many changed files after the run.
- **Cause**: your own planned changes, plus files rewritten at boot by a reboot test (resolv.conf, machine state, logs rotated).
- **Fix**: list every entry. For each, say whether the hash changed or only inode or mtime, and which planned change or boot step explains it. Accept the baseline only when every entry is explained. An unexplained entry is an incident.

## 13. Deploy pipeline blocked by CI billing or quota

- **Symptom**: CI does not start, or stops with a billing or minutes message, during the run.
- **Cause**: the CI plan quota is spent, or a payment failed.
- **Fix**: use the documented laptop deploy, which must equal CI (same root build, same checks, same frozen lockfile). Tell `<owner>` about the CI block. Never skip the gate because CI is down.

## 14. Watcher fails because the run is not registered yet

- **Symptom**: `gh run watch` (or similar) right after a push says "no run found" or watches the previous run.
- **Cause**: the CI run is created a few seconds after the push.
- **Fix**: resolve the run id for the pushed commit sha first, in a loop, then watch that id:

  ```bash
  sha=$(git rev-parse HEAD)
  until id=$(gh run list --commit "$sha" --json databaseId -q '.[0].databaseId') && [ -n "$id" ]; do sleep 5; done
  gh run watch "$id" --exit-status
  ```

## 15. Kill switch cache hides the flip

- **Symptom**: the switch is off in the store but the API still answers normally.
- **Cause**: the per-instance cache. Each instance keeps the old value for its cache time.
- **Fix**: poll until the answer changes and record the delay. It must be at most the cache time plus one request. If it is longer, the cache key or time is wrong.

## 16. Sign-up switch misses a path

- **Symptom**: sign-up is off, but a new account appears through OAuth or a magic link.
- **Cause**: the check sits on the password sign-up route only.
- **Fix**: put the check in the auth library's user-create hook, which every method passes. Test each method in one table. Test that an existing user still signs in by each method.
