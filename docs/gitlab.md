# GitLab — runners API

Checked 2026-11-15. GitLab has its own runner system: `gitlab-runner` agents pick up jobs by **tags**, not `runs-on` labels. Plain REST v4, works the same on gitlab.com and self-managed.

## Base & auth

```
https://gitlab.com/api/v4            # or https://<your-host>/api/v4
PRIVATE-TOKEN: <token>               # or: Authorization: Bearer <token>
```

| Token | Scope | Notes |
|---|---|---|
| Personal access token | `read_api` for runners/jobs reads; `manage_runner` where the docs require it (`GET /runners/:id`, group runners) | Simplest for a desktop app |
| Group / project access token | same scopes | Bot user, good for one group/project |
| OAuth2 (PKCE) | `read_api` | If you ship the app to other people |

Role requirements (runners API):
- `GET /runners`: Owner of the group namespace for group runners; Security Manager / Maintainer / Owner for project runners
- `GET /runners/all`: Administrator or Auditor (self-managed only, in practice)
- `GET /projects/:id/runners`: Maintainer or Auditor on the project
- `GET /groups/:id/runners`: Owner/Auditor (or custom role with `admin_runners`) + `manage_runner` token scope

## Runners

| Endpoint | What |
|---|---|
| `GET /runners` | Runners you own/manage |
| `GET /runners/all` | All runners on the instance (admin) |
| `GET /projects/:id/runners` | Runners usable by a project, incl. group + allowed instance runners |
| `GET /groups/:id/runners` | Runners for a group and ancestors |
| `GET /runners/:id` | Details |
| `GET /runners/:id/managers` | The actual machines (runner managers) behind one runner |
| `GET /runners/:id/jobs?status=running` | Jobs on a runner |

Filters on list endpoints: `type` (`instance_type`, `group_type`, `project_type`), `status` (`online`, `offline`, `stale`, `never_contacted`), `paused` (bool), `tag_list` (comma-separated), `version_prefix`. Requesting `offline` may also return `stale` runners. `scope` is deprecated.

Runner list item: `id, uuid, description, paused, is_shared, runner_type, online, status, job_execution_status`. `active` and `ip_address` are deprecated (`ip_address` returns `""`).

Details add: `contacted_at, tag_list, access_level, maximum_timeout, maintenance_note, projects, token_expires_at`.

Managers (`/managers`): `id, system_id, version, revision, platform, architecture, created_at, contacted_at, ip_address, status, job_execution_status`. This endpoint has its own per-user rate limit.

Status model for the UI:
- reachability: `status` = `online | offline | stale | never_contacted`, plus `paused`
- busy: `job_execution_status` (running vs idle)
- one "runner" can be N machines: look at `/managers` for per-machine status

## Jobs (queue / status)

| Endpoint | What |
|---|---|
| `GET /projects/:id/jobs?scope[]=pending&scope[]=running` | Queued + running jobs, newest first |
| `GET /projects/:id/pipelines/:pipeline_id/jobs` | Jobs of a pipeline |
| `GET /projects/:id/jobs/:job_id` | One job |

`scope` takes one status or an array: `created, pending, running, failed, success, canceled, skipped, waiting_for_resource, manual`, among others. Without `scope` you get every job. Use `--globoff` with curl for the `[]` (in Swift, `URLQueryItem(name: "scope[]", value: "pending")`, repeated).

Job fields to use: `id, status, stage, name, ref, created_at, started_at, finished_at, duration, queued_duration, tag_list, web_url, pipeline{id,status}, runner{id, description, is_shared, runner_type, online, status}, runner_manager{system_id, version, platform, architecture, contacted_at}`. `runner`/`runner_manager` are `null` until a runner picks the job up. `queued_duration` is in seconds (float).

Gaps:
- No instance/group-wide "list pending jobs" REST endpoint. Iterate projects, or use `GET /runners/:id/jobs` per runner. GitLab issue #554251 asks for a tag-filtered pending-jobs API; still open.
- Webhook alternative: project/group **Job events** hook (`object_kind: "build"`, `build_status`, `runner`, `build_queued_duration`).

## Pagination & rate limits

- Offset pagination: `page`, `per_page` (default 20, max 100). Response headers: `X-Page`, `X-Next-Page`, `X-Total`, `X-Total-Pages`, `Link`.
- Keyset pagination (preferred for jobs lists): `pagination=keyset&order_by=id&sort=desc`, then follow `Link: rel="next"`. Keyset responses omit `X-Total`/`X-Total-Pages`.
- gitlab.com rate limits: `RateLimit-Remaining`, `RateLimit-Reset` headers. Back off on 429.

## Example

```bash
curl -sS --globoff -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/projects/$(printf %s 'group/project' | jq -sRr @uri)/jobs?scope[]=pending&scope[]=running&per_page=100"
```

Project IDs can be numeric or the URL-encoded path (`group%2Fproject`). When you build that in Swift, encode `/` yourself. `URLComponents` won't do it in a path.

## Sources

- https://docs.gitlab.com/api/runners/
- https://docs.gitlab.com/api/jobs
- https://gitlab.com/gitlab-org/gitlab/-/issues/554251
- https://gitlab.com/gitlab-org/gitlab/-/issues/351010
