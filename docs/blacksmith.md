# Blacksmith — runners status

Checked 2026-11-15. **Blacksmith has no public REST API.** Integration is the GitHub App plus `runs-on` labels. Observability is exposed through the dashboard (app.blacksmith.sh) and the `blacksmith` CLI. The CLI talks to a private backend whose base URL and token env var aren't documented.

## Options for a Swift app

1. **GitHub API (recommended for runner status).** Blacksmith runners register as GitHub self-hosted runners with `blacksmith-*` labels. Use `GET /orgs/{org}/actions/runners` and jobs endpoints (see `github-actions.md`), filtered on the `blacksmith-` label prefix.
2. **Shell out to the CLI** (`Process`) for Blacksmith-specific data (job metrics, usage). JSON is the default output.
3. Don't call the dashboard's private endpoints. They're undocumented and cookie-session based (a third-party MCP server does this and breaks when the session expires).

## CLI auth

```bash
curl -fsSL https://get.blacksmith.sh | sh          # install; auto-updates (BLACKSMITH_DISABLE_AUTO_UPDATE=1 to stop)

blacksmith auth login                               # interactive browser OAuth, once per machine
blacksmith auth status

# org admin mints a machine token (shown once):
blacksmith org-token create --label runner-monitor

# non-interactive login with that token (token on stdin):
echo "$TOKEN" | blacksmith auth login --api-token - --non-interactive --organization <org-slug>
```

- Credentials are stored in `~/.blacksmith/credentials`.
- Tokens are org-scoped. Select the org with `--org` or `BLACKSMITH_ORG`.
- Use an org token for automation. Don't copy a human's credentials file.

## CLI commands relevant to monitoring

Output: `--format json | table | yaml` (JSON default).

| Command | Purpose |
|---|---|
| `blacksmith jobs list` | Recent job runs. Flags: `--repo`, `--workflow`, `--job-name`, `--runner-label`, `--conclusion` (`success, failure, cancelled, skipped, timed_out`), `--since` (`24h, 7d, 14d, 30d`), `--limit`, `--cursor` |
| `blacksmith jobs stats <job_id>` | Per-run CPU/memory/OOM |
| `blacksmith jobs steps <job_id>` | Steps with timestamps |
| `blacksmith jobs logs <job_id> --step … --search …` | Logs |
| `blacksmith jobs aggregate --repo … --group-by workflow,job_name --since 14d` | Cross-run aggregates |
| `blacksmith runners` | Runner SKUs and catalog metadata (what labels exist, not live machines) |
| `blacksmith usage` | Usage and cost |
| `blacksmith stickydisk` / `blacksmith cache` | Sticky disks and caches |

Swift sketch: `Process` → `/usr/bin/env blacksmith jobs list --since 24h --format json` → decode stdout. Capture one real output first; the JSON schema isn't documented.

## Service health

Status page: https://status.blacksmith.sh (components: Blacksmith Managed Runners, API, website, GitHub dependencies).

## Labels

`blacksmith-<n>vcpu-ubuntu-2404`, `blacksmith-<n>vcpu-ubuntu-2404-arm`, older `blacksmith-<n>vcpu-ubuntu-2204`. Linux-focused.

## Sources

- https://docs.blacksmith.sh/blacksmith-cli/overview
- https://docs.blacksmith.sh/blacksmith-cli/jobs
- https://docs.blacksmith.sh/llms.txt (no API pages listed)
- https://providers.apievangelist.com/providers/blacksmith-sh/ ("does not publish a general-purpose public REST API")
- https://status.blacksmith.sh
