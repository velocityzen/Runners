# Codeberg — runners API (Forgejo Actions + Woodpecker CI)

Checked 2026-11-15. Codeberg runs **Forgejo** and offers two CI systems with separate APIs:

1. **Forgejo Actions**: GitHub-Actions-like, built into codeberg.org. Hosted runners are limited (see codeberg.org/actions/meta). Normally you **bring your own runner** (`forgejo-runner`) and register it to your user, org or repo.
2. **Woodpecker CI** at `ci.codeberg.org`: hosted CI, access by request (criteria in Codeberg-e.V./requests). Separate server, separate token.

Monitor both if the user uses both.

---

## 1. Forgejo Actions (codeberg.org)

### Base & auth

```
https://codeberg.org/api/v1
Authorization: token <PAT>        # Forgejo also accepts "Bearer <PAT>"
Accept: application/json
```

- Token: codeberg.org → Settings → Applications → Generate token. Forgejo has only **personal** access tokens (no org tokens).
- Scopes are coarse (read vs read/write per area). There's no runner-only scope. Reading runners needs the token user to be admin of the repo/org. On Codeberg you can't use the `/admin/...` scope.
- Swagger UI: `https://codeberg.org/api/swagger`. Codeberg tracks Forgejo v15 (`codeberg-15` branch). The runner HTTP API (list/register/delete, `runners/jobs`) needs Forgejo ≥ 15.0 and Forgejo Runner ≥ 12.8.

### Runner endpoints

The same set exists in every scope. A scope also sees the active jobs of the scopes under it.

| Scope | Prefix |
|---|---|
| User | `/user/actions/runners` |
| Org | `/orgs/{org}/actions/runners` |
| Repo | `/repos/{owner}/{repo}/actions/runners` |
| Admin (self-hosted Forgejo only) | `/admin/actions/runners` |

| Method + path (under a prefix) | What |
|---|---|
| `GET …/actions/runners` | Runners visible here (incl. inherited). `?visible=false` = only this scope |
| `GET …/actions/runners/{runner_id}` | One runner |
| `GET …/actions/runners/jobs` | **Active jobs** (waiting for a runner or running). `?labels=ubuntu-latest` filters by `runs-on` |
| `POST …/actions/runners` `{ "name": "...", "ephemeral": true }` | Register (returns `{id, uuid, token}`) |
| `DELETE …/actions/runners/{runner_id}` | Delete (soft) |

Runner status (from Forgejo's runner model; mirrors the UI):
- `offline`: no contact for more than ~1 min
- `idle`: online, no recent task activity
- `active`: online and recently working

Gitea-compatible list responses look like `{ total_count, runners: [{ id, name, os, architecture, busy, status, labels, disabled, ... }] }`. Forgejo 15's exact shape isn't in the docs I could read, so check it against `/api/swagger` or one real call before modelling it.

Active-job item (`runners/jobs`): `id, attempt, handle, repo_id, owner_id, name, needs, runs_on[], task_id, status`. `status: "waiting"` = queued. `task_id: 0` means no runner has it yet.

### Runs (status per repo)

| Endpoint | What |
|---|---|
| `GET /repos/{owner}/{repo}/actions/runs?status=…` | Workflow runs (GitHub-style response: `workflow_runs[]`, `total_count`) |
| `GET /repos/{owner}/{repo}/actions/runs/{run_id}` | One run |
| `GET /repos/{owner}/{repo}/actions/tasks` | Recent tasks (job executions) |

Pagination: `page`, `limit` (Forgejo-style; check `X-Total-Count`).

```bash
curl -sS -H "Authorization: token $CODEBERG_TOKEN" \
  "https://codeberg.org/api/v1/user/actions/runners/jobs"
```

---

## 2. Woodpecker CI (ci.codeberg.org)

### Base & auth

```
https://ci.codeberg.org/api
Authorization: Bearer <Woodpecker PAT>
```

Token: log in to ci.codeberg.org with your Codeberg account → user icon (top right) → personal profile page → personal access token. This is **not** your Codeberg/Forgejo token.

Swagger 2.0 spec: every Woodpecker server serves one; the reference copy is at woodpecker-ci.org/api.

### Endpoints

| Method + path | What | Notes |
|---|---|---|
| `GET /user` | Who am I | quick auth check |
| `GET /user/repos` | Your repos on the server | get `repo_id`s |
| `GET /repos/{repo_id}/pipelines?page=&perPage=` | Pipelines of a repo | default 50 per page |
| `GET /repos/{repo_id}/pipelines/{number}` | One pipeline incl. workflows/steps | |
| `GET /queue/info` | Global queue | likely admin-only on a shared instance |
| `GET /agents`, `GET /agents/{id}`, `GET /agents/{id}/tasks` | Global agents | admin on a shared instance |
| `GET /orgs/{org_id}/agents` | **Your own org agents** (bring-your-own agents) | org admin |

The swagger doesn't flag the agent and queue endpoints as admin-only. Woodpecker's server code does restrict global agents/queue to admins, so on Codeberg's shared instance you'll likely see only your own pipelines and your org agents. Verify with your token.

Agent object: `id, name, backend, platform, capacity, version, custom_labels{}, filters, last_contact, last_work, no_schedule, org_id, owner_id, created, updated`. Treat `last_contact` (unix seconds) older than ~1 min as offline. `last_work` shows recent activity.

Queue info (if allowed): `paused`, `pending[]`, `running[]`, `waiting_on_deps[]`, `stats {worker_count, pending_count, running_count, waiting_on_deps_count}`. Each task: `id, pipeline_id, pipeline_number, repo_id, name, labels, agent_id, agent_name, created, dependencies, dep_status, run_on`.

Pipeline status values: `pending, running, success, failure, killed, error, blocked, declined, skipped, created`.

```bash
curl -sS -H "Authorization: Bearer $WOODPECKER_TOKEN" \
  "https://ci.codeberg.org/api/repos/$REPO_ID/pipelines?perPage=20"
```

## Sources

- https://docs.codeberg.org/ci
- https://docs.codeberg.org/ci/actions/
- https://codeberg.org/actions/meta
- https://aahlenst-dev.pages.dev/blog/autoscaling-forgejo-runner (Forgejo 15 runner HTTP API, scopes, `runners/jobs`)
- https://forgejo.org/2026-04-release-v15-0/#simplified-runner-registration
- https://codeberg.org/mvdkleijn/forgejo-sdk/issues/148
- https://codeberg.org/Codeberg-Infrastructure/forgejo/pulls/138 (Codeberg on v15)
- Forgejo `models/actions/runner.go` (runner status offline/idle/active)
- https://woodpecker-ci.org/api (Woodpecker REST API / swagger)
- https://pkg.go.dev/go.woodpecker-ci.org/woodpecker/server/api (auth header, PAT)
