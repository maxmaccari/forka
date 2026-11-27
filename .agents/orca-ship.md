# Orca Ship hooks

Hooks for the `orca-ship` pipeline.

## after worktree
Install Playwright for the e2e tests (`mix test.e2e`) in this worktree: run
`npm --prefix assets ci --include=dev`, then
`npm --prefix assets exec -- playwright install chromium`.
`assets/node_modules` is not tracked, so every worktree needs the first command.
Chromium is cached per machine, so the second only downloads on a machine's first run.
