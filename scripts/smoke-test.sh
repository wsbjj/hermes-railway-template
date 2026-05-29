#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN=python3
  else
    PYTHON_BIN=python
  fi
fi

new_case_dir() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/bin" "$tmp/home" "$tmp/workspace"
  cat > "$tmp/bin/hermes" <<'SH'
#!/usr/bin/env bash
echo "fake hermes $*"
SH
  chmod +x "$tmp/bin/hermes"
  printf '%s\n' "$tmp"
}

run_success() {
  local name="$1"
  shift
  local tmp
  tmp="$(new_case_dir)"

  PATH="$tmp/bin:$PATH" \
    HERMES_HOME="$tmp/home/.hermes" \
    HOME="$tmp/home" \
    TERMINAL_CWD="$tmp/workspace" \
    STATUS_PAGE_ENABLED=false \
    "$@" "$ROOT_DIR/scripts/entrypoint.sh" > "$tmp/out.txt" 2>&1

  grep -q "Starting Hermes gateway" "$tmp/out.txt"
  grep -q "fake hermes gateway" "$tmp/out.txt"
  echo "$name OK"
}

run_failure() {
  local name="$1"
  local expected="$2"
  shift 2
  local tmp
  tmp="$(new_case_dir)"

  set +e
  PATH="$tmp/bin:$PATH" \
    HERMES_HOME="$tmp/home/.hermes" \
    HOME="$tmp/home" \
    TERMINAL_CWD="$tmp/workspace" \
    STATUS_PAGE_ENABLED=false \
    "$@" "$ROOT_DIR/scripts/entrypoint.sh" > "$tmp/out.txt" 2>&1
  local code=$?
  set -e

  if [[ "$code" -eq 0 ]]; then
    echo "$name expected failure but succeeded" >&2
    cat "$tmp/out.txt" >&2
    exit 1
  fi

  grep -q "$expected" "$tmp/out.txt"
  echo "$name OK"
}

run_config_case() {
  local name="$1"
  shift
  local tmp
  tmp="$(new_case_dir)"

  PATH="$tmp/bin:$PATH" \
    HERMES_HOME="$tmp/home/.hermes" \
    HOME="$tmp/home" \
    TERMINAL_CWD="$tmp/workspace" \
    STATUS_PAGE_ENABLED=false \
    "$@" "$ROOT_DIR/scripts/entrypoint.sh" > "$tmp/out.txt" 2>&1

  grep -q "^model:" "$tmp/home/.hermes/config.yaml"
  grep -q "provider: custom" "$tmp/home/.hermes/config.yaml"
  grep -q "default: infini-test-model" "$tmp/home/.hermes/config.yaml"
  grep -q "base_url: https://cloud.infini-ai.com/maas/v1" "$tmp/home/.hermes/config.yaml"
  echo "$name OK"
}

run_status_page_case() {
  local tmp port
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/home/.hermes" "$tmp/workspace"
  cat > "$tmp/home/.hermes/config.yaml" <<'YAML'
model:
  default: infini-test-model
  provider: custom
  base_url: https://cloud.infini-ai.com/maas/v1
terminal:
  cwd: /data/workspace
YAML

  port="$("$PYTHON_BIN" - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"

  PORT="$port" \
    HERMES_HOME="$tmp/home/.hermes" \
    HOME="$tmp/home" \
    TERMINAL_CWD="$tmp/workspace" \
    HERMES_INFERENCE_PROVIDER=custom \
    HERMES_MODEL=infini-test-model \
    OPENAI_BASE_URL=https://cloud.infini-ai.com/maas/v1 \
    OPENAI_API_KEY=super-secret-test-key \
    QQ_APP_ID=app-id \
    QQ_CLIENT_SECRET=secret \
    QQ_ALLOWED_USERS=openid_a \
    "$PYTHON_BIN" "$ROOT_DIR/scripts/status_server.py" > "$tmp/status.out" 2>&1 &
  local pid=$!

  trap 'kill "$pid" 2>/dev/null || true' RETURN

  for _ in $(seq 1 50); do
    if "$PYTHON_BIN" - "$port" <<'PY' >/dev/null 2>&1
import sys
import urllib.request

urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/healthz", timeout=0.2).read()
PY
    then
      break
    fi
    sleep 0.1
  done

  "$PYTHON_BIN" - "$port" <<'PY'
import json
import sys
import urllib.request

port = sys.argv[1]
base = f"http://127.0.0.1:{port}"

health = urllib.request.urlopen(f"{base}/healthz", timeout=2).read().decode("utf-8").strip()
assert health == "ok", health

ready = json.loads(urllib.request.urlopen(f"{base}/readyz", timeout=2).read().decode("utf-8"))
assert ready["status"] == "ok", ready
assert ready["model"]["provider"] == "custom", ready
assert ready["model"]["default"] == "infini-test-model", ready
assert ready["platforms"]["qqbot"] is True, ready

page = urllib.request.urlopen(base, timeout=2).read().decode("utf-8")
assert "Hermes Railway" in page, page
assert "super-secret-test-key" not in page, page
assert "openid_a" not in page, page
PY

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  trap - RETURN
  echo "status page OK"
}

run_success "QQ InfiniAI via OPENAI_BASE_URL" env \
  HERMES_INFERENCE_PROVIDER=custom \
  OPENAI_BASE_URL=https://cloud.infini-ai.com/maas/v1 \
  OPENAI_API_KEY=test-key \
  QQ_APP_ID=app-id \
  QQ_CLIENT_SECRET=secret \
  QQ_ALLOWED_USERS=openid_a

run_config_case "model config from Railway variables" env \
  HERMES_INFERENCE_PROVIDER=custom \
  HERMES_MODEL=infini-test-model \
  OPENAI_BASE_URL=https://cloud.infini-ai.com/maas/v1 \
  OPENAI_API_KEY=test-key \
  QQ_APP_ID=app-id \
  QQ_CLIENT_SECRET=secret \
  QQ_ALLOWED_USERS=openid_a

run_success "QQ InfiniAI via CUSTOM_BASE_URL" env \
  HERMES_INFERENCE_PROVIDER=custom \
  CUSTOM_BASE_URL=https://cloud.infini-ai.com/maas/v1 \
  INFINI_AI_API_KEY=test-key \
  QQ_APP_ID=app-id \
  QQ_CLIENT_SECRET=secret \
  QQ_ALLOWED_USERS=openid_a

run_success "QQ MiniMax" env \
  HERMES_INFERENCE_PROVIDER=minimax \
  MINIMAX_API_KEY=test-key \
  QQ_APP_ID=app-id \
  QQ_CLIENT_SECRET=secret \
  QQ_ALLOWED_USERS=openid_a

run_success "WeCom custom endpoint" env \
  HERMES_INFERENCE_PROVIDER=custom \
  OPENAI_BASE_URL=https://api.example.com/v1 \
  OPENAI_API_KEY=test-key \
  WECOM_BOT_ID=bot-id \
  WECOM_SECRET=secret \
  WECOM_ALLOWED_USERS=user_a

run_success "Weixin custom endpoint" env \
  HERMES_INFERENCE_PROVIDER=custom \
  OPENAI_BASE_URL=https://api.example.com/v1 \
  OPENAI_API_KEY=test-key \
  WEIXIN_ACCOUNT_ID=wxid_a \
  WEIXIN_ALLOWED_USERS=wxid_a

run_failure "custom endpoint without key" "Custom/OpenAI-compatible endpoints require" env \
  HERMES_INFERENCE_PROVIDER=custom \
  CUSTOM_BASE_URL=https://api.example.com/v1 \
  QQ_APP_ID=app-id \
  QQ_CLIENT_SECRET=secret \
  QQ_ALLOWED_USERS=openid_a

run_failure "QQ missing secret" "QQ Bot requires both QQ_APP_ID and QQ_CLIENT_SECRET" env \
  HERMES_INFERENCE_PROVIDER=minimax \
  MINIMAX_API_KEY=test-key \
  QQ_APP_ID=app-id

run_status_page_case
