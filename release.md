The first release of `runners`: see every CI run that is still going, across all the repositories of a user, organization or group, on GitHub Actions and GitLab CI.

## ✨ Features

- **Every active run at a glance**: running, queued, pending and waiting-for-approval runs, grouped by repository, down to each job, the runner that picked it up and the step it is on. Jobs that passed are counted; `--all-jobs` lists them too.
- **GitHub and GitLab**: github.com, GitHub Enterprise, gitlab.com and self-managed GitLab (`--api-url`, `github.api_url`, `gitlab.host`). If you are signed in with `gh`, there is no token to set up.
- **Watch mode**: `--watch` redraws every 15 seconds (`-i` to change it). A run that finishes stays on screen with how it ended, such as `✓ success in 3m 12s, 2m ago`, until a newer run of the same workflow on the same branch takes its place.
- **Status in your terminal**: terminals that support the Program Status Protocol show what `runners` is doing: working, done, blocked while a run waits for approval, or error. Ctrl-C clears it. `--no-program-status` turns it off.
- **Choose what to see**: `--status` for the run statuses, `--repo` for particular repositories, `--forks` to include forks, `--no-jobs` to skip job details.
- **Config files**: put settings in `.runners` or `~/.runners` as `key=value` lines (`owner=my-org`, `status=running, queued`), or in environment variables and `.env`. Command-line flags win, and a wrong value is an error that names the setting.
- **JSON output**: `--json` prints a snapshot for scripts.

## ⚡ Easy on your API quota

- Responses that haven't changed come back as `304 Not Modified`, which GitHub doesn't count against your quota. They are kept on disk between runs, so checking again costs next to nothing. `--no-cache` keeps them in memory only.
- In watch mode, the list of repositories is refreshed every five minutes instead of on every redraw.

## 📦 Install

For Apple silicon, on macOS 27:

```bash
curl -fsSLO https://github.com/velocityzen/Runners/releases/latest/download/runners-macos-arm64.tar.gz
tar -xzf runners-macos-arm64.tar.gz && mv runners /usr/local/bin/
```

`RunnersKit`, the Swift library behind the command, is in the same package for building your own monitors.
