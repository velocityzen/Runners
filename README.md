# Runners

See every CI run that is still going — running, queued, waiting for approval, or pending — across all repositories of a user, organization or GitLab group, down to the job, the runner that picked it up, and the step it is on. Works with GitHub Actions and GitLab CI.

`RunnersKit` is the library; `runners` is its command-line front-end.

```
velocityzen on GitHub · 3 active runs in 2 of 83 repositories · 10:37:13

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

Each [release](https://github.com/velocityzen/Runners/releases) has a build for Apple silicon. It needs macOS 27.

```bash
curl -fsSLO https://github.com/velocityzen/Runners/releases/latest/download/runners-macos-arm64.tar.gz
```

```bash
curl -fsSL https://github.com/velocityzen/Runners/releases/latest/download/runners-macos-arm64.tar.gz.sha256 | shasum -a 256 -c -
```

```bash
tar -xzf runners-macos-arm64.tar.gz && mv runners /usr/local/bin/
```

The binary is not notarized. `curl` doesn't mark it as downloaded, so it runs as is; one downloaded with a browser needs `xattr -d com.apple.quarantine runners` first. `runners --version` says which release it is.

Or build it with Swift 6.4, on macOS 27 or Linux (a build of your own says `dev`):

```bash
swift build -c release
```

```bash
cp .build/release/runners /usr/local/bin/
```

## Use

```bash
runners                          # repositories you own
runners my-org                   # an organization (or any user)
runners -r my-org/api -r my-org/web
runners my-org --watch           # redraw every 15s (-i to change)
runners my-org --json            # machine-readable snapshot
runners -p gitlab my-group       # a GitLab group, subgroups included (or a user)
runners -p gitlab -r my-group/sub/project
```

Options: `-s/--status` to pick which run statuses to show (default `running`, `queued`, `waiting`, `pending`), `--no-jobs` to skip job details, `--forks` to include forks, `-c/--concurrency` (default 16), `--api-url` for GitHub Enterprise or self-managed GitLab, `--config` for a settings file. Flags that switch something on have a `--no-` form to override the config. `runners --help` has the rest.

With `--watch`, a run that finishes stays on screen with how it ended (`✓ success in 3m 12s, 2m ago`, `✗ failure …`, `⊘ cancelled …`) until a newer run of the same workflow on the same branch takes its place, or you stop watching. A run that is re-run shows as active again.

Statuses mean the same on both services: **queued** waits for a runner; **pending** waits on something else first (a concurrency group, earlier stages, a resource); **waiting** waits for a person or a timer (an approval, a manual job, a delay).

### Terminal status

`runners` reports what it is doing to the terminal with the [Program Status Protocol](https://www.superlogical.com/rex/docs/build/program-status) (OSC 7501), through [ProgramStatus](https://github.com/velocityzen/ProgramStatus). A terminal that knows the protocol shows it; others ignore it. Reports go to the controlling terminal, so `--json` and pipes stay clean.

- A check is **working** while it runs, then **done** with a summary, or **error**.
- With `--watch`, the root record is **idle** with no active runs, **working** with some, **blocked** while one waits for approval, and **error** when a refresh fails. Each repository on screen gets a record titled with its name, and each run one beneath it, with its jobs' progress. A finished run's record keeps how it ended: **done** when it passed, **error** when it failed or timed out, **idle** when cancelled. A repository whose runs have all finished is **error** if one failed, otherwise **done**. Records go when their runs leave the screen.
- Ctrl-C clears those records, leaves the root **idle**, and exits with 130.

`--no-program-status`, or `program_status=false`, turns it off.

### Tokens

- **GitHub:** the first of `GH_TOKEN`, `GITHUB_TOKEN`, or the token of a signed-in [GitHub CLI](https://cli.github.com) (`gh auth token`). Private repositories need the classic `repo` scope, or a fine-grained token with Actions (read). For GitHub Enterprise, pass `--api-url https://ghe.example.com/api/v3` or set `GITHUB_API_URL`.
- **GitLab:** `GITLAB_TOKEN` (or `GITLAB_ACCESS_TOKEN`), a personal access token with `read_api`. For a self-managed instance set `GITLAB_HOST` (as `glab` does), `CI_API_V4_URL`, or pass `--api-url https://gitlab.example.com/api/v4`.

Any of these can also live in a `.env` or `.runners` file (below).

### Configuration

Every option has a setting. The first place that sets one wins:

1. the command line
2. environment variables
3. `.env` in the working directory
4. `.runners` in the working directory, or the file given with `--config`
5. `~/.runners`

`.runners` holds `key=value` lines named as in the code. Lists are comma-separated, `#` starts a comment line, and values may be quoted. Environment variables and `.env` use the same names in capitals, with `RUNNERS_` in front of the runner settings:

```ini
# .runners
provider=gitlab
owner=my-group
status=running, queued
jobs=false
gitlab.host=gitlab.example.com
```

| `.runners` | Environment, `.env` | Default |
|---|---|---|
| `provider` | `RUNNERS_PROVIDER` | `github`; or `gitlab` |
| `owner` | `RUNNERS_OWNER` | the token's user |
| `repos` | `RUNNERS_REPOS` | all of the owner's; `a/b, c/d` |
| `status` | `RUNNERS_STATUS` | `running, queued, waiting, pending` |
| `jobs` | `RUNNERS_JOBS` | `true` |
| `all_jobs` | `RUNNERS_ALL_JOBS` | `false` |
| `forks` | `RUNNERS_FORKS` | `false` |
| `concurrency` | `RUNNERS_CONCURRENCY` | `16`; 1–32 |
| `interval` | `RUNNERS_INTERVAL` | `15` seconds; at least 5 |
| `color` | `RUNNERS_COLOR` | on a terminal, unless `NO_COLOR` is set |
| `program_status` | `RUNNERS_PROGRAM_STATUS` | `true` |
| `cache` | `RUNNERS_CACHE` | `true` |
| `github.token` | `GH_TOKEN`, `GITHUB_TOKEN` | `gh auth token` |
| `github.api_url` | `GITHUB_API_URL` | `https://api.github.com` |
| `gitlab.token` | `GITLAB_TOKEN`, `GITLAB_ACCESS_TOKEN` | |
| `gitlab.host` | `GITLAB_HOST`, `CI_API_V4_URL` | `gitlab.com` |

Only these names work in `.runners`: an environment name such as `GITHUB_TOKEN`, or a typo, is an error that lists the valid settings.

`owner` and `repos` go together: the first source that sets either one decides both, so a project's `.runners` with `owner=` replaces `repos=` from `~/.runners`. A value that doesn't parse is an error that names the setting, not something silently skipped. Keep tokens in `~/.runners` or a git-ignored `.env`, not in a `.runners` you commit.

## How it works, and what it costs

Neither service has an account-wide "active runs" endpoint.

On **GitHub**, `runners`:

1. lists the owner's repositories, dropping archived, disabled and (unless `--forks`) forked ones;
2. skips repositories without workflows (`/actions/workflows`);
3. asks each remaining repository for its runs in each status (`/actions/runs?status=…`);
4. fetches the jobs of every run it found (`/runs/{id}/jobs?filter=latest`).

A first look at 84 repositories, 19 with workflows, takes 163 requests of the 5,000/hour quota. Every request after that carries the `ETag` of the last answer; GitHub answers unchanged resources with `304 Not Modified`, which does not count against the quota, so later checks cost only what changed: about two requests per active run. The answers are kept in `~/Library/Caches/runners/responses.json` (`~/.cache/runners/` on Linux), readable by you only, so this holds across runs too, not just within a watch. `--no-cache`, or `cache=false`, keeps them in memory only.

`--watch` also reads the repositories and which have workflows (steps 1–2) only every five minutes, so a refresh in between is 77 requests instead of 163, nearly all of them free. A repository that gets its first workflow shows within five minutes. When a run drops out of the active ones, the watch reads it once more (`/actions/runs/{id}`, plus its jobs) to learn how it ended.

On **GitLab**, `runners`:

1. lists the namespace's projects (a group's include its subgroups'), dropping archived ones, ones with CI/CD turned off and (unless `--forks`) forks;
2. asks each project once for its unfinished jobs (`/jobs?scope[]=created&scope[]=pending&scope[]=running…`), which point to its unfinished pipelines;
3. reads each of those pipelines and its jobs.

That is one request per project plus two per running pipeline (`--watch` lists the projects every five minutes), and in `--watch` mode two more for each pipeline when it finishes, to learn how it ended. `manual` jobs are not asked for: optional ones stay `manual` in finished pipelines forever. So a pipeline blocked only by a manual job, with nothing after it, does not show.

On both, transient failures (network, 5xx, throttling) are retried with backoff, honoring `Retry-After`.

## Library

```swift
import RunnersKit

let monitor = RunsMonitor(service: GitHubService(token: token))      // or GitLabService(token:)
let snapshot = await monitor.snapshot(StatusQuery(target: .owner("my-org")))   // Result<StatusSnapshot, RunnersError>

switch snapshot {
case .success(let snapshot):
    for group in snapshot.byRepository {
        print(group.repository.fullName, group.runs.map(\.run.status))
    }
case .failure(let error):
    print(error.localizedDescription)
}
```

To keep watching, read `watch`, an async sequence built on fp-swift's `withRepeat`. It takes a snapshot when you ask for the next one, at most once per `interval`; a failure is an element, not the end, and cancelling your task finishes it. A run that finishes is read once more through `CIService.latest` and stays in later snapshots with its conclusion, until a newer run of the same workflow on the same branch replaces it; `snapshot.activeRuns` and `snapshot.finishedRuns` tell them apart. The repositories are read again every `rescan` (five minutes by default), or after a failure:

```swift
for await snapshot in monitor.watch(query, every: .seconds(15)) {
    // Result<StatusSnapshot, RunnersError>
}
```

`TextReport` renders a snapshot the way the CLI does; `snapshot.json()` encodes it. The network sits behind `HTTPTransport`, so tests and other hosts can supply their own. `ConditionalTransport` adds `ETag`s from an `ETagCache`; `ETagCache.load(from:)` and `save(to:)` keep one in a file between runs.

### Layout

- `Domain/` — the shared types every service maps onto: `Owner`, `Repository`, `Run`, `Job`, `RunStatus`, `Conclusion`, `RateLimit`, `RunnersError`; and `Provider`, the protocol a service describes itself with.
- `Monitor/` — `CIService`, the protocol a service implements, and `RunsMonitor`, which drives one.
- `Services/<Service>/` — one folder per service: its `Provider`, its `CIService`, its wire types and endpoints, and the mapping from its responses to the domain types. `Services/Providers.swift` lists the built-in ones.
- `HTTP/` — the shared REST client: auth headers, `Link` pagination, retries, `ETag` caching.
- `Report/` — the terminal rendering.

The CLI's `Sources/runners/Config/` merges the command line, environment, `.env` and `.runners` files into `Settings`. It knows providers only through the `Provider` protocol: the `provider` setting picks one by `id`, and each provider's settings join the ones `.runners` files take.

To add a service, add `Services/<Service>/` with a type conforming to `CIService` and one conforming to `Provider`, then list the provider in `Providers.builtIn`. The provider gives:

- `id`, `name` and `repositoryTerm`: what the command line, config and reports call it;
- `tokenSettings` and `apiURLSettings`: the settings it reads, most preferred first. `.setting("forge.token")` is `forge.token` in `.runners` and `FORGE_TOKEN` in the environment; `.environment("ci.token")` is another tool's variable, read from the environment only;
- `defaultAPIURL`, and `apiURL(_:from:)` when a setting holds something other than a URL, such as a host;
- `fallbackToken(apiURL:)`, for when no token is set;
- `service(token:apiURL:transport:)`, which builds its `CIService`.

## Develop

```bash
swift test
```

Formatting and lint rules are in `.swift-format`, shared with fp-swift:

```bash
swift format format --in-place --recursive Sources Tests Package.swift
```

```bash
swift format lint --strict --recursive Sources Tests Package.swift
```

The design notes in `docs/` cover the runner APIs of other CI providers.

### CI and releases

`.github/workflows/ci.yml` runs on pushes to `main` and on pull requests: swift-format in strict lint mode, then the build and tests on macOS 27 (GitHub's `xcode-27` image) and on Linux, x86_64 and arm64, in the `swift:6.4` container. [zizmor](https://zizmor.sh) audits the workflows first whenever `.github` changes.

To release, write the notes in `release.md` at the root of the repository, commit it, then tag that commit with the version and push the tag:

```bash
git tag 0.1.0
```

```bash
git push origin 0.1.0
```

`.github/workflows/release.yml` then tests the tagged commit, builds `runners` for Apple silicon with the tag as its `--version` (without a leading `v`), and publishes a GitHub release titled with the tag, with `release.md` as its notes and `runners-macos-arm64.tar.gz` and its `.sha256` attached. A tag with a suffix, such as `1.2.0-beta.1`, makes a pre-release.

Once the release is out, the workflow removes `release.md` from `main` in a commit of its own, so pull before writing the next notes. It leaves the file alone if `main` already has different notes in it. A tag whose commit has no `release.md`, or only blank lines in it, releases nothing.
