# WarpBuild — runners API

Checked 2026-11-15. WarpBuild has the most complete public REST API of the bunch: plain JSON over HTTPS, with real runner and runner-instance endpoints.

## Base

```
https://api.warpbuild.com/api/v1
Authorization: Bearer wkey-xxxxxxxx
Accept: application/json
```

## Auth

Dashboard → **API Keys** → Generate API Key. Pick scopes: `CI` (required for runners/jobs), plus `Cache` / `Helios` if needed. The key is shown once and can be renamed/rescoped later. Format `wkey-…`. OpenAPI security scheme name: `JWTKeyAuth` (same Bearer header).

## Endpoints

### Runner sets: the configured runners (what `runs-on` labels map to)

| Endpoint | Notes |
|---|---|
| `GET /runners` | All runner sets in the org. Query: `labels[]`, `active`, `ids[]`, `image`, `provider_id`. Not paginated. |
| `GET /runners/{id}` | One runner set. |
| `GET /runner_pool?runner_set_id=` | Warm pools: `items[] {id, runner_set_id, provider, size, created_at, updated_at}` |
| `GET /stacks?kind=ec2` | BYOC stacks |

Runner set object: `id, name, organization_id, provider_id, stock_runner_id, active (bool), labels[], configuration { image, sku, capacity_type, byoc_sku {arch, instance_types[], network_tier, role_arn, ...}, storage {disk_type, iops, size, throughput, tier, ...} }, meta, created_at, updated_at`.

### Runner instances: the live machines (status check)

`GET /runner_instance`

| Query | Meaning |
|---|---|
| `status[]` | `init_triggered, init_complete, polling, suspending, suspended, allocating, allocated, running, completed, purging, purged` |
| `labels[]` | filter by labels |
| `job_id` | the GitHub job ID |
| `created` | `>2026-11-01T00:00:00Z` or range `a..b` |
| `stack_kind_ids[]` | BYOC stacks |
| `search` | id, status, labels, provider alias, job_id (exact) |
| `include_cloud_runners` | include WarpBuild cloud runners |
| `page`, `per_page` | default 1 / 20 |

Response: `{ page, per_page, next_page, total_items, total_pages, runner_instances: [...] }`.

Useful instance fields:
- `id`, `status`, `labels`, `runner_set_id`, `last_job_processed_id`
- `last_job_processed_meta`: `vcs_org`, `vcs_repo`, `vcs_workflow_name`, `vcs_job_name`, `vcs_ref`, `vcs_head_ref`, `vcs_start_time`, `vcs_end_time`
- timestamps: `created_at`, `allocation_requested_at`, `allocated_at`, `running_started_at`, `suspended_at`, `purged_at`, `first_polled_at`, `last_polled_at`, `updated_at`
- `configuration.sku`: `arch`, `cores`, `memory`, `os`, `display_name`
- `purged_reason`

Lifecycle as an "is it busy" mapping (my reading of the states, not documented):
- idle/warm: `init_*`, `polling`, `suspended`
- starting: `allocating`, `allocated`
- busy: `running`
- gone: `completed`, `purging`, `purged`

Queue time ≈ `running_started_at − allocation_requested_at`.

### Usage

`GET /runners/usage?start_date=&end_date=` returns `daywise[] {date, runtime_seconds}`, `runnerwise[] {runner_id, runtime_seconds}`, `total_job_count`.
`GET /reports/billing/ci?start_date=…&end_date=…` (add `&format=csv` for per-job CSV).

### Example

```bash
curl -sS 'https://api.warpbuild.com/api/v1/runner_instance?status=running&status=allocating&per_page=100' \
  -H 'Accept: application/json' -H "Authorization: Bearer $WARPBUILD_API_KEY"
```

Array query params repeat the key (`status=a&status=b`). `URLComponents` with multiple `URLQueryItem`s of the same name does this.

## Labels

`warp-ubuntu-latest-x64-4x`, `warp-ubuntu-latest-arm64-4x`, macOS e.g. `warp-macos-15-arm64-6x` (check `GET /runners` for your org's exact labels).

## Sources

- https://warpbuild.com/docs/api
- https://warpbuild.com/docs/ci/api-keys
- https://warpbuild.com/docs/ci/api-keys/automation
- https://warpbuild.com/docs/api/runners/ListRunners
- https://warpbuild.com/docs/api/runners/GetRunner
- https://warpbuild.com/docs/api/runners/ListRunnerInstances
- https://warpbuild.com/docs/api/runners/ListRunnerPools
- https://warpbuild.com/docs/api/runners/GetRunnersUsage
