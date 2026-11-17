Watch mode waits the full interval between refreshes, and a missing GitHub token says why.

## 🐛 Fixes

- **`--interval` in `--watch`**: the interval used to count from the start of one refresh to the start of the next. A refresh slower than the interval, with many repositories or a slow connection, was followed by the next one at once, and `runners` read the API back to back. It now waits the whole interval after each refresh finishes, however long the refresh took, as the `--interval` help says.

## 🔧 Improvements

- **Clearer errors when there is no token**: when neither `GH_TOKEN` nor `GITHUB_TOKEN` is set and `runners` can't borrow a token from the GitHub CLI, the error now says why, then how to fix it:
  - Without `gh`: "No API token: `gh` is not installed or not on PATH; set GH_TOKEN or GITHUB_TOKEN, or run `gh auth login`".
  - When `gh` isn't signed in to your host, the error now includes gh's own reason, such as "no oauth token found for ghe.example.com". Before, it said only that `gh auth token` exited with 1.

## 🧩 RunnersKit

- **`CLIToken`**: a provider can borrow the token of any signed-in CLI with `CLIToken("forge", ["auth", "token"], hint: "set FORGE_TOKEN").token()`, as GitHub does with `gh auth token`. A failure comes back as `tokenUnavailable` with the reason, then your hint. RunnersKit now depends on swift-subprocess 1.0.2.
- **`RunsMonitor.watch`** waits `interval` after each snapshot finishes, instead of counting from when it started.
