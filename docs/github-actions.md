# GitHub Actions — runners API

Checked 2026-11-15. Plain HTTPS + JSON REST. GitHub is the common source of truth for every other provider here: Depot, Namespace, WarpBuild, Blacksmith, Ubicloud and CodeBuild runners all register with GitHub as (ephemeral) self-hosted runners and pick up jobs by `runs-on` label.

## Base

```
https://api.github.com
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2026-03-10        # version used in current docs examples
Authorization: Bearer <token>
User-Agent: <your-app-name>             # GitHub rejects requests without a User-Agent
```

GHE.com: replace `api.github.com` with `api.<SUBDOMAIN>.ghe.com`.

## Auth

| Option | Use for | Notes |
|---|---|---|
| Fine-grained PAT | personal tool, single org | Per-endpoint permissions below. |
| Classic PAT | quick start | `repo` for repo runners; `admin:org` for org self-hosted runners; `manage_runners:org` for GitHub-hosted (larger) runners. |
| GitHub App | multi-org app, best rate limits | JWT → installation token (below). |

### GitHub App flow

1. JWT, signed RS256 with the App private key (PEM):
   - `iat` = now − 60 s (clock drift)
   - `exp` = now + ≤ 600 s (10 min max)
   - `iss` = App ID (or client ID)
2. `POST /app/installations/{installation_id}/access_tokens` with `Authorization: Bearer <JWT>` → `{ "token": "...", "expires_at": "..." }`. Token lives 1 hour.
3. Use the installation token as `Authorization: Bearer <token>`.

Find installation IDs: `GET /app/installations` (JWT auth).

Swift note: CryptoKit has no RSA. On macOS use `Security` (`SecKeyCreateWithData` + `SecKeyCreateSignature(.rsaSignatureMessagePKCS1v15SHA256)`); on Linux use swift-crypto `_CryptoExtras` (`_RSA.Signing.PrivateKey(pemRepresentation:)`, PKCS#1 v1.5 + SHA-256). Strip the PEM header for `SecKey`.

## Runners

### Self-hosted runners (incl. all third-party providers)

| Endpoint | Classic scope | Fine-grained permission |
|---|---|---|
| `GET /orgs/{org}/actions/runners?per_page=100&page=1&name=` | `admin:org` | Org "Self-hosted runners" (read) |
| `GET /orgs/{org}/actions/runners/{runner_id}` | `admin:org` | Org "Self-hosted runners" (read) |
| `GET /repos/{owner}/{repo}/actions/runners` | `repo` | Repo "Administration" (read) |
| `GET /repos/{owner}/{repo}/actions/runners/{runner_id}` | `repo` | Repo "Administration" (read) |
| `GET /orgs/{org}/actions/runner-groups` / `.../runner-groups/{id}/runners` | `admin:org` | Org "Self-hosted runners" (read) |

Requires admin on the org/repo. `per_page` max 100, default 30.

```json
{
  "total_count": 2,
  "runners": [
    {
      "id": 23, "name": "linux_runner", "os": "linux",
      "status": "online", "busy": true, "ephemeral": false, "version": "2.323.0",
      "labels": [
        { "id": 5, "name": "self-hosted", "type": "read-only" },
        { "id": 11, "name": "Linux", "type": "read-only" }
      ]
    }
  ]
}
```

- `status`: `online` | `offline`. `busy`: running a job right now.
- Third-party ephemeral runners appear here only while alive (one job each), so this list is a live "who's running now" view, not an inventory. Group by label prefix (`depot-`, `blacksmith-`, `warp-`, `namespace-profile-`, `ubicloud-`, `codebuild-`) to attribute to a provider.

### GitHub-hosted *larger* runners

| Endpoint | Classic scope | Fine-grained |
|---|---|---|
| `GET /orgs/{org}/actions/hosted-runners?per_page&page` | `manage_runners:org` | Org "Administration" (read) |
| `GET /orgs/{org}/actions/hosted-runners/{hosted_runner_id}` | `manage_runners:org` | Org "Administration" (read) |
| `GET /orgs/{org}/actions/hosted-runners/limits` | — | Org "Administration" (read) |

Response items: `id, name, runner_group_id, platform, image{id,size}, machine_size_details{id,cpu_cores,memory_gb,storage_gb}, status, maximum_runners, public_ip_enabled, public_ips[], last_active_on`. Docs only show `status: "Ready"`; treat other values as opaque strings.

Note: the docs page spells the list scope `manage_runner:org` once and `manage_runners:org` elsewhere; the plural is the real one.

### Standard GitHub-hosted runners (`ubuntu-latest`, `macos-15`…)

No API lists them. Observe them through jobs (next section): `runner_name`, `runner_group_name`, `labels`.

## Status checks: runs and jobs

| Endpoint | Purpose |
|---|---|
| `GET /repos/{owner}/{repo}/actions/runs?status=queued` (or `in_progress`) | Active runs |
| `GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs?filter=latest&per_page=100` | Jobs of a run |
| `GET /repos/{owner}/{repo}/actions/runs/{run_id}/attempts/{attempt_number}/jobs` | Jobs of one attempt |
| `GET /repos/{owner}/{repo}/actions/jobs/{job_id}` | One job |

Permission: repo "Actions" (read); classic `repo` for private repos; none for public repos.

Run `status` filter values: `completed, action_required, cancelled, failure, neutral, skipped, stale, success, timed_out, in_progress, queued, requested, waiting, pending`. With `status`/`branch`/`actor`/`created`/`event`/`head_sha`/`check_suite_id` filters the endpoint returns at most 1,000 results.

Job fields you'll want: `id, run_id, status (queued|in_progress|completed|waiting|requested|pending), conclusion, created_at, started_at, completed_at, labels[], runner_id, runner_name, runner_group_id, runner_group_name, html_url`. Queue time = `started_at − created_at`.

There is no org-wide "all queued jobs" endpoint: iterate repos → runs (`status=queued|in_progress`) → jobs.

## Push instead of poll

Org/repo webhook `workflow_job` (actions: `queued`, `waiting`, `in_progress`, `completed`) carries the same job object incl. `labels` and `runner_name`. Better than polling if the app can receive webhooks (or via a relay).

## Pagination & rate limits

- Pagination via `Link` header (`rel="next"`). `per_page` ≤ 100.
- Watch `x-ratelimit-remaining`, `x-ratelimit-reset`. PATs: 5,000 req/h; App installation tokens scale higher. Use `If-None-Match` with `ETag` — 304 responses don't count against the limit.

## Sources

- https://docs.github.com/en/rest/actions/self-hosted-runners
- https://docs.github.com/en/rest/actions/hosted-runners
- https://docs.github.com/en/rest/actions/workflow-runs
- https://docs.github.com/en/rest/actions/workflow-jobs
- https://docs.github.com/en/rest/actions/self-hosted-runner-groups
- https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app
