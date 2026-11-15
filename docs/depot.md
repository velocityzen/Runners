# Depot — GitHub Actions runners API

Checked 2026-11-15. Depot's API is **Connect RPC**. Every call is a plain HTTP `POST` with a JSON body, so `URLSession` works and you don't need gRPC.

## Base & protocol

```
POST https://api.depot.dev/<proto.package>.<Service>/<Method>
Authorization: Bearer <DEPOT_TOKEN>
Content-Type: application/json
Connect-Protocol-Version: 1
```

- Request/response bodies are proto3 JSON (lowerCamelCase field names; int64 values may come back as strings).
- Errors: non-2xx HTTP with a JSON body `{ "code": "permission_denied" | "unauthenticated" | "not_found" | ..., "message": "..." }`.

## Auth

| Token | Where | Notes |
|---|---|---|
| Organization token | Depot dashboard → Organization Settings → **API Tokens** → Create token | Recommended. Scoped to one org. |
| User token | `depot login` or user settings | If the user is in several orgs, also send `X-Depot-Org: <org-id>`. |
| OIDC / job tokens | inside CI only | Not relevant for a desktop monitor. |

Gotcha: `ProjectService/ListProjects` refuses org tokens (403 `permission_denied`). Use `ListGithubActionsJobs` as the connection/health check instead.

## Runners: there is no "list runners" call

Depot runners are ephemeral EC2/macOS machines started per job from a standby pool, matched on the label you request (`depot-ubuntu-24.04`, `depot-macos-26`, …). They register in the GitHub **default runner group**. So for "what runners exist right now", use GitHub's `GET /orgs/{org}/actions/runners` and filter by the `depot-` label prefix (see `github-actions.md`).

Depot's own API is **job-centric**.

## GitHub Actions jobs on Depot runners: `depot.core.v1.GithubActionsService`

| RPC | Purpose |
|---|---|
| `/depot.core.v1.GithubActionsService/ListGithubActionsJobs` | Jobs that ran on Depot (filter by repo, status, conclusion, runner label, time window; cursor pagination). Defaults to the last 24 h. |
| `/depot.core.v1.GithubActionsService/GetGithubActionsJob` | One job by GitHub job ID. |
| `/depot.core.v1.GithubActionsService/SearchGithubActionsLogs` | Search log lines. |
| `/depot.core.v1.GithubActionsService/GetGithubActionsLogContext` | Lines around a log match. |
| `/depot.core.v1.GithubActionsService/ListGithubActionsJobRuns` | Past runs of a job (flakiness). |
| `/depot.core.v1.GithubActionsService/GetGithubActionsTestResultsSummary` | Test results. |

The service also covers analytics, runner-size recommendations, job termination and GitHub App installations.

**The request/response field names are NOT on Depot's public docs pages.** The contract is in `github.com/depot/proto` (`depot/core/v1/…`, added in depot/proto PR #41). Known from third-party clients and `depot jobs`:

- Filters: `repo` (`owner/name`), `status`, conclusion, runner label, free-text query, RFC 3339 time window (max 90 days; client used `startAt`/`endAt`), page token.
- Job data: job/workflow name, status, conclusion, runner label, execution duration, queue time, billable time, lifecycle timestamps, requested CPU/memory, GitHub job URL.

Before coding the Swift model, read the `.proto` in depot/proto, or capture a real response:

```bash
depot jobs --repo acme/api --output json      # same RPC, shows real field names
```

```bash
curl -sS -X POST https://api.depot.dev/depot.core.v1.GithubActionsService/ListGithubActionsJobs \
  -H "Authorization: Bearer $DEPOT_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Connect-Protocol-Version: 1" \
  -d '{}'
```

## Depot CI (separate product, documented)

If you also use **Depot CI** (Depot's own workflow runner, not GitHub-hosted), its API is fully documented: `depot.ci.v1.CIService`.

| RPC | Request | Response |
|---|---|---|
| `ListRuns` | `status[]` (default `["running","queued"]`), `pageSize` ≤ 100 (default 50), `pageToken`, `repo`, `sha`, `trigger`, `pr` | `runs[] {runId, repo, trigger, sha, ref, headSha, status, createdAt}`, `nextPageToken` |
| `GetRunStatus` | `runId` | run → `workflows[]` → `jobs[]` → `attempts[]` with statuses |
| `ListWorkflows` | `pageSize` ≤ 200, filters | includes `jobCounts {total, queued, waiting, running, finished, failed, cancelled, skipped}` |
| `GetJob` | `jobId` | `jobStatus`, `jobConclusion`, timestamps (`jobCreatedAt`, `jobDispatchedAt`, `jobStartedAt`, `jobFinishedAt`), `runsOn {labels[], image, cpus, memoryGb, size}` |
| `GetRunMetrics` / `GetJobMetrics` | `runId` / `jobId` | CPU & memory summaries |

Statuses:
- run/workflow/attempt: `queued, running, finished, failed, cancelled` (+ `waiting` for attempts)
- job: `queued, waiting, running, finished, failed, cancelled, skipped` (`waiting` = blocked on a concurrency group)
- conclusion: `success, failure, cancelled, skipped, timed_out`

## Runner labels (for attributing GitHub runners)

`depot-ubuntu-24.04`, `depot-ubuntu-24.04-<cpus>`, `depot-ubuntu-24.04-arm`, `depot-windows-latest`, `depot-macos-latest` (now macOS 26), `depot-macos-26`, `depot-macos-15`, `depot-macos-14`.

## Sources

- https://depot.dev/docs/api/overview
- https://depot.dev/docs/api/authentication
- https://depot.dev/docs/api/ci/reference
- https://depot.dev/docs/github-actions/overview
- https://depot.dev/docs/github-actions/runner-types
- https://depot.dev/docs/github-actions/troubleshooting (default runner group)
- https://github.com/depot/sdk-node (service list incl. `depot.core.v1.GithubActionsService`)
- https://github.com/depot/proto/pull/41 (GithubActionsService contract)
- https://github.com/depot/cli (`depot jobs`)
- https://github.com/PostHog/depot-mcp (RPC names in use)
