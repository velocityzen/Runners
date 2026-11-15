# Namespace — GitHub Actions runners API

Checked 2026-11-15. Namespace's API is defined in protobuf (`buf.build/namespace/cloud`) and served over gRPC **and Connect**. Unary calls are plain `POST` + JSON, so `URLSession` is enough. Streaming calls (`WaitInstance`, `StreamInstanceLogs`) need Connect streaming framing; avoid them or implement the envelope yourself.

## Endpoints

| Host | Serves |
|---|---|
| `https://{region}.compute.namespaceapis.com` (`us`, `eu`) | Instances (runner VMs), commands, volumes, usage, observability |
| `https://global.namespaceapis.com` | Registry, vault, images, **GitHub integration** (runner profiles), egress, caches |
| `https://iam.namespaceapis.com` | Tenants, tokens, membership |
| `https://{region}.storage.namespaceapis.com` | Artifacts |

GitHub runner services: the `profiles.proto` comment says `global.namespaceapis.com:443`. Namespace's own Go SDK and the Pulumi provider use `https://private-api.global.namespaceapis.com` for the GitHub runner services (`ProfileService`, `JobsService`). Try `global` first and fall back to `private-api.global`.

## Request shape

```
POST https://<host>/<proto.package>.<Service>/<Method>
Authorization: Bearer <tenant token>
Content-Type: application/json
Connect-Protocol-Version: 1
```

proto3 JSON rules matter in Swift `Codable`:
- field names are lowerCamelCase (`maxEntries`, `paginationCursor`)
- `int64` is a **string** in JSON (`"maxEntries": "10"`)
- `bytes` is **base64** (`paginationCursor`)
- `google.protobuf.Timestamp` is an RFC 3339 string
- `google.protobuf.Empty` request = `{}`

## Auth

| Method | How |
|---|---|
| Revokable token (desktop app) | `nsc token create --name monitor --expires_in 365d --grant '{"resource_type":"github/runner-profile","resource_id":"*","actions":["list","get"]}' --grant '{"resource_type":"instance","resource_id":"*","actions":["list","get"]}' --output token`. Default lifetime 24 h, max 365 d. Needs workspace admin (or `--user` to bind the token to your own permissions; only `--user` tokens can use `--no_expiry`). |
| Dev token | `nsc login` then `nsc auth generate-dev-token` (short-lived) |
| OIDC federation (CI) | `TokenService.IssueTenantTokenWithOIDC` on `iam.namespaceapis.com`, returns `bearer_token` |
| Inside a Namespace runner | read `bearer_token` from JSON at `$NSC_TOKEN_FILE` or `/var/run/nsc/token.json` |

Permissions are `resource_type` + `actions`. Relevant ones:
- `github/runner-profile`: `list`, `get` (also create/update/delete)
- `instance`: `list`, `get`, `wait`, …
- `instance/notification`: `list` (recent lifecycle events)
- `instance/o11y/metrics`: `get`; `instance/o11y/oom`: `list`; `instance/o11y/logs`: `get`

## Runners = runner profiles + instances

On Namespace, "a runner" is a **runner profile** (`runs-on: namespace-profile-<tag>`) that spawns ephemeral **instances** per job.

### List runner profiles: `namespace.cloud.github.v1beta.ProfileService/ListProfiles`

```bash
curl -sS -X POST https://global.namespaceapis.com/namespace.cloud.github.v1beta.ProfileService/ListProfiles \
  -H "Authorization: Bearer $NSC_TOKEN" -H "Content-Type: application/json" \
  -H "Connect-Protocol-Version: 1" -d '{}'
```

Response `profiles[]` (`RunnerProfileWithStatus`):
- `profileId`: stable ID
- `spec` (`RunnerProfileSpec`): `tag` (the alias used in `namespace-profile-<tag>`), `instanceShape` (CPU/memory/arch, `compute.v1beta.InstanceShape`), `os` (e.g. `ubuntu-24.04`, macOS images)
- `status` (`RunnerProfileStatus`): `customRunnerImage[]` build status

Other RPCs: `CreateProfile`, `UpdateProfile`, `DeleteProfile`, `RebuildProfileImage`.

### Jobs: `namespace.cloud.github.v1beta.JobsService`

| RPC | Purpose |
|---|---|
| `ListJobs` | GitHub Actions jobs that ran on Namespace runners |
| `DescribeJob` | One job, incl. the instance it ran on and its runner profile |

`ListJobsRequest` (from the proto):
- `paginationCursor` (bytes/base64), from the previous response
- `maxEntries` (int64 → string)
- `timeRange` (`TimestampRange`, on `created_at`)
- conclusion filter (`success`, `failure`, `cancelled`, completed jobs only)
- also repository, sender login, and a "not finished" flag (`HasNotFinished` in the Go SDK = pending + running)

The CLI equivalent shows the shape: `nsc github job list -o json --repository owner/repo --running --since 24h`. Run it once to capture the real JSON before writing models.

Known issue (Nov 2026): a runner *workload* token got `Unauthenticated`/`PermissionDenied` on `ListJobs` (namespacelabs/foundation#2105). Use a tenant/revokable token with explicit grants, not a workload token.

### Instances: `namespace.cloud.compute.v1beta.ComputeService`

```bash
curl -sS -X POST https://us.compute.namespaceapis.com/namespace.cloud.compute.v1beta.ComputeService/ListInstances \
  -H "Authorization: Bearer $NSC_TOKEN" -H "Content-Type: application/json" \
  -H "Connect-Protocol-Version: 1" -d '{"maxEntries":"10"}'
```

Response: `instances[]`, `paginationCursor`. Call each region you use (`us`, `eu`). `ComputeService` has 18 RPCs in total (describe, destroy, …). `ObservabilityService` and `UsageService` sit on the same host.

## Labels

`namespace-profile-<tag>`, e.g. `namespace-profile-default`, `namespace-profile-mac`, conda-forge style `namespace-profile-6cpu-on-osx-arm64`. Profiles also register as GitHub self-hosted runners, so the GitHub API sees them too.

## Sources

- https://namespace.so/docs/reference/api
- https://namespace.so/docs/security/permissions
- https://namespace.so/docs/reference/cli/token-create
- https://namespace.so/docs/reference/cli/github-job-list
- https://buf.build/namespace/cloud/docs (packages; `namespace.cloud.github.v1beta` JobsService/ProfileService)
- https://buf.build/namespace/cloud/raw/main/-/proto/namespace/cloud/github/v1beta/profiles.proto
- https://github.com/pulumi-labs/pulumi-namespace (endpoint for GitHub runner services)
- https://github.com/namespacelabs/foundation/issues/2105
