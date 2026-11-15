# Ubicloud — runners API

Checked 2026-11-15. Ubicloud has a public REST API (OpenAPI 3, "Clover API"), but its GitHub section covers **installations, repositories and cache** only. **There's no endpoint to list runners or their status.** For runner status, use the GitHub API with the `ubicloud-` label prefix (see `github-actions.md`).

## Base & auth

```
https://api.ubicloud.com
Authorization: Bearer <personal access token>
```

Token: Ubicloud console → your project → **Tokens** → Create Token → copy.

## Pagination & errors

- List endpoints are cursor-based: `order_column` (`id`, or `name` where names are unique), `start_after`, `page_size` (1–1000, default 1000).
- List response: `{ "items": [...], "count": <total> }`.
- Status codes: 200, 204, 400 invalid, 401 not authenticated, 403 unauthorized, 404, 409 bad state, **419 invalid token**, 500. DELETE returns 204 even when the resource doesn't exist.

## Endpoints useful for a runner monitor

| Endpoint | Purpose |
|---|---|
| `GET /project` | Your projects (`id` like `pjkkmx0f2vke4h36nk9cm8v8q0`) |
| `GET /project/{project_id}/github` | GitHub installations: `{count, items[{id, name}]}` |
| `GET /project/{project_id}/github/{installation_id_or_name}` | Installation details |
| `GET /project/{project_id}/github/{installation}/repository` | Repos using Ubicloud runners |
| `GET /project/{project_id}/github/{installation}/repository/{repo}` | Repo details |
| `GET .../repository/{repo}/cache` | Cache entries (and DELETE) |
| `GET https://api.ubicloud.com/ips-v4` | Ubicloud egress IPv4 ranges (no auth) |

The full path list is in the OpenAPI spec at `https://www.ubicloud.com/docs/api-reference/openapi.yml`. Generate Swift types with swift-openapi-generator if you want typed models.

```bash
curl -sS https://api.ubicloud.com/project/$PROJECT_ID/github \
  -H "Authorization: Bearer $UBICLOUD_TOKEN"
```

## Runner status

The console's **GitHub Runners** page (and the GitHub Actions tab) is the only Ubicloud-side view. Programmatically:
- live runners: `GET /orgs/{org}/actions/runners`, filter labels starting with `ubicloud`
- jobs: GitHub workflow jobs API, `labels` contains `ubicloud-*`

## Labels

`ubicloud` (2 vCPU x64 Ubuntu 22.04), `ubicloud-standard-{2,4,8,16,30}`, `ubicloud-standard-4-ubuntu-2404`, arm variants `ubicloud-standard-{n}-arm`. Full list: `github.com/ubicloud/ubicloud/blob/main/config/github_runner_labels.yml`. Linux only. Premium runners are on by default and fall back to standard when the premium fleet is busy.

## Sources

- https://ubicloud.com/docs/api-reference/overview
- https://www.ubicloud.com/docs/api-reference/project/list-all-projects
- https://www.ubicloud.com/docs/api-reference/github/list-all-github-installations
- https://www.ubicloud.com/docs/api-reference/github/list-repositories-for-a-github-installation
- https://www.ubicloud.com/docs/llms.txt
- https://ubicloud.com/docs/github-actions-integration/quickstart
- https://ubicloud.com/docs/github-actions-integration/runner-types
