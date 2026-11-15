# Runners

See every GitHub Actions run that is still going — running, queued, waiting for approval, or pending on a concurrency group — across all repositories of a user or organization, down to the job, the runner that picked it up, and the step it is on.

`RunnersKit` is the library; `runners` is its command-line front-end.

```
velocityzen · 3 active runs in 2 of 83 repositories · 10:37:13

velocityzen/fp-swift-service
  ○ CI #56  Measure the shutdown timeout benchmark on a clock that never races
    queued 30m 46s · main · push · @velocityzen · 7/12 jobs done
    https://github.com/velocityzen/fp-swift-service/actions/runs/43728004875
    ● Test macOS              6m 19s         GitHub Actions 1000003184 → Test with a one-thread concurrency pool
    ● Test iOS Simulator      6m 34s         GitHub Actions 1000003182 → Test on the iOS Simulator
    ○ Test watchOS Simulator  queued 29m 58s xcode-27

API quota 3,597/5,000 · resets 10:46
```

`●` running · `○` queued/pending · `◇` waiting · `✗` failed · `⊘` cancelled. Jobs that passed are counted, not listed (`--all-jobs` lists them).

## Install

```bash
swift build -c release
```

```bash
cp .build/release/runners /usr/local/bin/
```

Requires Swift 6.4 and macOS 27.

## Use

```bash
runners                          # repositories you own
runners my-org                   # an organization (or any user)
runners -r my-org/api -r my-org/web
runners my-org --watch           # redraw every 15s (-i to change)
runners my-org --json            # machine-readable snapshot
```

Options: `-s/--status` to pick which run statuses to look for (default `in_progress`, `queued`, `waiting`, `pending`), `--no-jobs` to skip job details, `--forks` to include forks, `-c/--concurrency` (default 16), `--api-url` for GitHub Enterprise. `runners --help` has the rest.

### Token

The first of: `GH_TOKEN`, `GITHUB_TOKEN`, or the token of a signed-in [GitHub CLI](https://cli.github.com) (`gh auth token`). Private repositories need the classic `repo` scope, or a fine-grained token with Actions (read) on them.

For GitHub Enterprise, pass `--api-url https://ghe.example.com/api/v3` or set `GITHUB_API_URL`.

## How it works, and what it costs

GitHub has no account-wide "active runs" endpoint, so `runners`:

1. lists the owner's repositories, dropping archived, disabled and (unless `--forks`) forked ones;
2. skips repositories without workflows (`/actions/workflows`);
3. asks each remaining repository for its runs in each status (`/actions/runs?status=…`);
4. fetches the jobs of every run it found (`/runs/{id}/jobs?filter=latest`).

A first look at 83 repositories, 19 with workflows, takes about 170 requests of the 5,000/hour quota. In `--watch` mode every request carries the previous `ETag`; GitHub answers unchanged resources with `304 Not Modified`, which does not count against the quota, so later refreshes cost only what changed. Transient failures (network, 5xx, secondary rate limit) are retried with backoff, honoring `Retry-After`.

## Library

```swift
import RunnersKit

let monitor = ActionsMonitor(client: GitHubClient(token: token))
let snapshot = await monitor.snapshot(StatusQuery(target: .owner("my-org")))   // Result<StatusSnapshot, GitHubError>

switch snapshot {
case .success(let snapshot):
    for group in snapshot.byRepository {
        print(group.repository.fullName, group.runs.map(\.run.status))
    }
case .failure(let error):
    print(error.localizedDescription)
}
```

`TextReport` renders a snapshot the way the CLI does; `snapshot.json()` encodes it. The network sits behind `HTTPTransport`, so tests and other hosts can supply their own.

## Develop

```bash
swift test
```

The design notes in `docs/` cover the runner APIs of other CI providers.
