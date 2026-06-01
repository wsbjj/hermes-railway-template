# Status Terminal And I18n Design

## Goal

Add a password-protected full shell terminal to the Hermes Railway status page and add a Chinese/English language toggle for the status UI.

## Scope

- The terminal runs arbitrary shell commands inside the Railway container.
- The terminal is disabled unless `HERMES_DASHBOARD_PROXY_PASSWORD` or `HERMES_DASHBOARD_PASSWORD` is configured.
- When terminal support is enabled, the status page, `/readyz`, `/terminal`, and terminal command API require the same Basic Auth credentials used by the Dashboard proxy.
- `/healthz` remains public for health checks.
- The language toggle is client-side and covers visible status-page labels, helper text, links, terminal labels, and terminal status messages.

## Architecture

`scripts/status_server.py` remains the single HTTP server. It will render the status page with a terminal panel and localized strings embedded in a small script. It will expose `POST /api/terminal/run`, parse JSON `{ "command": "..." }`, and execute the command using `subprocess.run(..., shell=True)` in the configured workspace.

The command runner will:

- Use `TERMINAL_CWD` or `/data/workspace`.
- Create the workspace if needed.
- Use `TERMINAL_TIMEOUT`, defaulting to `180`.
- Return JSON containing `stdout`, `stderr`, `exit_code`, `duration_seconds`, and `cwd`.
- Return a timeout response with exit code `124` if the command exceeds the limit.
- Never add environment variables, tokens, or secrets to the status payload.

## Security

This is intentionally a full shell. It can read files in the container, including Hermes config and runtime secret files. Because of that, terminal endpoints must fail closed:

- If no proxy password is configured, `/terminal` and `/api/terminal/run` return `404`.
- If a password is configured, those paths require Basic Auth.
- If `STATUS_TERMINAL_ENABLED=false`, terminal paths return `404` even if a password exists.
- Terminal output is returned only to the authenticated browser session.

## UI

The page will stay a compact operations panel, not a marketing page. The terminal will be a full-width panel below deployment status cards with a dark output area, command input, run button, and short metadata row. The language toggle will sit in the header as a compact segmented button.

## Testing

Update `scripts/smoke-test.sh` to verify:

- Status terminal is hidden when no password is configured.
- Status terminal appears after authenticated access when a password is configured.
- Unauthenticated `/api/terminal/run` returns `401`.
- Authenticated `/api/terminal/run` executes in `TERMINAL_CWD` and returns stdout, stderr, exit code, and cwd.
- `STATUS_TERMINAL_ENABLED=false` hides terminal routes even with a password.
- Existing Dashboard proxy auth behavior remains intact.
- Local smoke tests work on macOS Bash 3.2 by avoiding unsupported `wait -n` during tests.
