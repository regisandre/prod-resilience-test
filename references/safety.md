# Safety contract and authorisation ladder

> Status: generic, applies to every run of the skill.
> Last checked: 2026-10-26

Read this file before the first command of a run. If a request conflicts with a rule here, stop and ask `<owner>`.

## 1. The prime rule

Production never breaks because of the test. When unsure whether an action is safe, treat it as unsafe and ask.

## 2. Class every action

Write the class next to each action in the task or the report before running it.

| Class              | Examples                                                                                     | Rule                                           |
| ------------------ | -------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| Read-only          | `GET` a health endpoint, `docker inspect`, `EXPLAIN`, list a bucket, read a dashboard        | Rung 1. Always first.                          |
| Reversible write   | Flip a kill switch and back, change a config setting and back, create then delete a test key | Rung 3 in prod. Record the way back first.     |
| Irreversible write | Delete data, rotate a secret that clients use, overwrite a backup, send mail to users        | Avoid in prod. If unavoidable, ask separately. |

A write you believe is reversible but have never reversed is irreversible until proven otherwise. Reverse it once on staging first.

## 3. The authorisation ladder

Ask `<owner>` once per rung, with the agent's question tool (never as free text buried in a long answer). Record each answer with its date in the report. Never assume a rung from the rung below.

| Rung | Covers                                                                                 | Ask example                                                                     |
| ---- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 1    | Read-only inspection of prod: HTTP GETs, SSH read commands, dashboards, logs           | "May I inspect prod read-only (GETs, docker inspect, logs, no writes)?"         |
| 2    | Local or staging experiments, including destructive ones                               | "May I run destructive experiments locally / on staging?"                       |
| 3    | Reversible prod writes: kill switch flips, settings, a scratch directory on the server | "May I flip the `<feature>` switch off for 2 minutes in prod, then back on?"    |
| 4    | Deploys to prod                                                                        | "May I deploy `<component>` version `<id>` to prod? Rollback: `<previous id>`." |
| 5    | Git: commit, push, merge, tag, release                                                 | Ask per operation. "Commit" does not cover "push".                              |
| 6    | Anything that costs money                                                              | "May I spend about `<amount>` on `<item>` for `<duration>`?"                    |

Rules of the ladder:

- A go-ahead on the work ("go", "do it all", an approved plan) is never a go-ahead on rung 5 or rung 6.
- Rung 5 covers one operation. A second push needs a second explicit word.
- Rung 3 covers the action named in the question. Another switch, another setting: ask again.
- A reboot in prod is a rung 3 action with its own question, asked at a quiet time.
- Approval in one session does not carry to the next.

## 4. Secrets

- Never print, log, paste or write a secret. Not in the chat, not in the report, not in a commit, not in a shell history line.
- Never `cat`, `less`, `grep` or open an env file or secret file to look at it. To check that a variable exists, test its presence only:

  ```bash
  ssh <node-host> 'set -a; . /srv/<app>/.env; set +a; [ -n "${<VAR_NAME>:-}" ] && echo present || echo missing; unset <VAR_NAME>'
  ```

- Use a secret inside the command that needs it, on the machine that holds it, then `unset` it.
- Generate a dedicated test key for the test (lowest scopes that work), note its id (never its value), revoke it at the end, and check the revocation with a 401.
- Redact tokens in any output you keep: replace with `<redacted>`.
- Run a secret scan on every staged diff before a commit:

  ```bash
  gitleaks protect --staged --redact --no-banner
  ```

## 5. Destructive experiments

| Experiment                      | Where                                                           |
| ------------------------------- | --------------------------------------------------------------- |
| Stop or kill the database       | Local or staging only                                           |
| Fill a disk                     | Local or staging only                                           |
| Cut the network to a dependency | Local or staging only                                           |
| Load test until errors          | Local or staging only                                           |
| Kill a container                | Local or staging only                                           |
| Reboot the host                 | Prod allowed, rung 3 question, quiet time, after phase 0 checks |

Before a prod reboot:

1. Every container has restart policy `always` or `unless-stopped`.
2. The container daemon is enabled at boot.
3. A recent backup exists and its header is valid (phase 9).
4. The status page or uptime monitor is watching, so the downtime is measured from outside.
5. `<owner>` said yes to this reboot, today.

## 6. Rollback target before every prod change

Before the change, write in the report:

- the previous version id (worker version, release tag, deployment id);
- the previous image digest (`docker inspect -f '{{index .RepoDigests 0}}' <container>`), or the image id if it has no digest;
- the path of a `.before-<change>` copy of every file replaced on a server;
- the exact command that rolls back.

```bash
ssh <node-host> 'cp -a /srv/<app>/docker-compose.yml /srv/<app>/docker-compose.yml.before-<change>'
```

No rollback target, no change.

## 7. Database migrations

- Never apply a migration by hand through an admin console, an SQL editor or an MCP tool.
- Write the migration file in the repo. Name it with the real clock: `$(date +%Y%m%d%H%M%S)_<description>.sql`. Never pad the time with zeros.
- A committed migration is never edited. Fix it with a new migration.
- The normal pipeline or the documented deploy command applies it. After it runs, read the migration history table once to confirm the version landed.

## 8. Neighbours

Do not touch other projects, tenants, workers, databases, buckets or containers that share the account or the server. Filter every command to `<app>` resources (name prefix, label, project id). If a command cannot be filtered, it is not read-only for this run.

## 9. Agents and tasks

- At most two sub-agents run at the same time. Queue the rest.
- Brief each sub-agent with these safety rules. A sub-agent inherits no rung: it gets only the rungs written in its brief.
- Create one task per phase at the start. Update each task when a checklist item passes.

## 10. Stop conditions

Stop at once, restore the rollback target and tell `<owner>` when:

- the deep health endpoint answers anything but 200 after a change;
- the status page or uptime monitor reports down;
- an error rate rises in error tracking after a change;
- a command touched a resource outside `<app>`;
- a secret appeared in any output.
