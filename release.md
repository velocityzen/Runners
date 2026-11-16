Watch mode keeps your runs on screen when the connection drops.

## 🐛 Fixes

- **Offline in `--watch`**: when a refresh fails, for example because the Wi-Fi dropped, `runners` no longer replaces the screen with just the error. The last runs stay on screen as they were when they were fetched, with the error and when it last tried again beneath them. The next refresh that works brings the screen back to normal.

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
