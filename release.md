`runners` now runs on Linux, and tells you which version you have.

## ✨ New

- **Linux builds**: every release now comes with static binaries for Linux on x86_64 and aarch64. They run on any distribution with nothing to install; they only need the system's CA certificates (the `ca-certificates` package, which most systems have). Without the GitHub CLI, set `GITHUB_TOKEN` or `GH_TOKEN`.
- **`runners --version`**: prints the release you're running, such as `0.3.0`. A build of your own prints `dev`.

## 🐛 Fixes

- On Linux, a build from source no longer crashes when it exits.

## 📦 Install

For Apple silicon, on macOS 27:

```bash
curl -fsSLO https://github.com/velocityzen/Runners/releases/latest/download/runners-macos-arm64.tar.gz
tar -xzf runners-macos-arm64.tar.gz && mv runners /usr/local/bin/
```

For Linux, on x86_64 or aarch64:

```bash
curl -fsSLO https://github.com/velocityzen/Runners/releases/latest/download/runners-linux-$(uname -m).tar.gz
tar -xzf runners-linux-$(uname -m).tar.gz && sudo mv runners /usr/local/bin/
```

Each archive has a `.sha256` beside it to check the download against.
