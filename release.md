Watch mode tells your terminal only what changed.

## 🔧 Improvements

- **Quieter terminal status in `--watch`**: `runners` used to send every record on every refresh: the overall status, each repository and each run. It now sends a record only when it changes, so a refresh where nothing changed sends nothing. While the connection is down, the error is sent once rather than on every retry. Records still go when their runs leave the screen, and Ctrl-C still clears them.
