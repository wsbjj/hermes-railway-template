# Status Terminal And I18n Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a password-protected full shell terminal and Chinese/English UI toggle to the Hermes Railway status page.

**Architecture:** Keep the feature inside `scripts/status_server.py`: render a terminal UI when enabled, protect terminal routes with existing Basic Auth, and execute commands through a small subprocess helper. Update `scripts/smoke-test.sh` for red-green coverage and patch `scripts/entrypoint.sh` only enough for local smoke tests to run on macOS Bash 3.2.

**Tech Stack:** Python stdlib HTTP server, Python `subprocess`, Bash smoke tests, vanilla HTML/CSS/JS.

---

### Task 1: Baseline Shell Compatibility

**Files:**
- Modify: `scripts/entrypoint.sh`
- Test: `scripts/smoke-test.sh`

- [ ] **Step 1: Verify failing baseline**

Run: `bash scripts/smoke-test.sh`

Expected: failure before feature work because `wait -n` is unavailable in macOS Bash 3.2.

- [ ] **Step 2: Replace `wait -n` with a portable wait loop**

Add a helper that waits for all started processes and returns the first non-zero status, without relying on `wait -n`.

- [ ] **Step 3: Run smoke tests**

Run: `bash scripts/smoke-test.sh`

Expected: existing smoke tests pass before terminal-specific assertions are added.

### Task 2: Terminal API Tests

**Files:**
- Modify: `scripts/smoke-test.sh`
- Modify later: `scripts/status_server.py`

- [ ] **Step 1: Add failing tests for terminal auth and execution**

Add a smoke-test case that starts `status_server.py` with `HERMES_DASHBOARD_PROXY_PASSWORD`, posts to `/api/terminal/run`, and asserts:

- unauthenticated POST returns `401`
- authenticated POST returns JSON with command output
- the command runs in `TERMINAL_CWD`
- page HTML contains the terminal panel

- [ ] **Step 2: Run the new test and verify red**

Run: `bash scripts/smoke-test.sh`

Expected: failure because `/api/terminal/run` does not exist yet.

### Task 3: Terminal Backend

**Files:**
- Modify: `scripts/status_server.py`
- Test: `scripts/smoke-test.sh`

- [ ] **Step 1: Implement terminal enablement helpers**

Add helpers for `status_terminal_enabled()`, terminal workspace, timeout, JSON request parsing, and JSON responses.

- [ ] **Step 2: Implement `POST /api/terminal/run`**

Require Basic Auth, reject missing or invalid command payloads, run the command with timeout, and return JSON.

- [ ] **Step 3: Run smoke tests**

Run: `bash scripts/smoke-test.sh`

Expected: terminal API tests pass.

### Task 4: Status Page UI And Language Toggle

**Files:**
- Modify: `scripts/status_server.py`
- Test: `scripts/smoke-test.sh`

- [ ] **Step 1: Add failing HTML assertions**

Assert authenticated status page HTML contains language toggle controls and terminal UI strings.

- [ ] **Step 2: Implement localized UI**

Render language controls, data attributes for localized text, terminal command form, output panel, and JavaScript for language switching and command submission.

- [ ] **Step 3: Run smoke tests**

Run: `bash scripts/smoke-test.sh`

Expected: HTML assertions and terminal API tests pass.

### Task 5: Documentation And Final Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document terminal settings**

Document `STATUS_TERMINAL_ENABLED`, Basic Auth requirement, full shell risk, and usage.

- [ ] **Step 2: Run full verification**

Run:

```bash
bash -n scripts/entrypoint.sh
python3 -m py_compile scripts/status_server.py
bash scripts/smoke-test.sh
```

Expected: all commands exit `0`.
