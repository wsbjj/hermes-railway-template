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
if [[ "${1:-}" == "dashboard" ]]; then
  echo "fake hermes $*"
  if [[ "${FAKE_HERMES_DASHBOARD_EXIT:-}" == "1" ]]; then
    exit 1
  fi
  sleep "${FAKE_HERMES_DASHBOARD_SLEEP:-60}"
  exit 0
fi
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

run_existing_model_config_sync_case() {
  local tmp
  tmp="$(new_case_dir)"
  mkdir -p "$tmp/home/.hermes"
  cat > "$tmp/home/.hermes/config.yaml" <<'YAML'
model:
  default: glm-5.1
  provider: zai
  base_url: https://api.z.ai/api/paas/v4
terminal:
  cwd: /old/workspace
YAML

  PATH="$tmp/bin:$PATH" \
    HERMES_HOME="$tmp/home/.hermes" \
    HOME="$tmp/home" \
    TERMINAL_CWD="$tmp/workspace" \
    STATUS_PAGE_ENABLED=false \
    HERMES_INFERENCE_PROVIDER=custom \
    HERMES_MODEL=glm-5.1 \
    OPENAI_BASE_URL=https://cloud.infini-ai.com/maas/coding/v1 \
    OPENAI_API_KEY=test-key \
    QQ_APP_ID=app-id \
    QQ_CLIENT_SECRET=secret \
    QQ_ALLOWED_USERS=openid_a \
    "$ROOT_DIR/scripts/entrypoint.sh" > "$tmp/out.txt" 2>&1

  grep -q "provider: custom" "$tmp/home/.hermes/config.yaml"
  grep -q "default: glm-5.1" "$tmp/home/.hermes/config.yaml"
  grep -q "base_url: https://cloud.infini-ai.com/maas/coding/v1" "$tmp/home/.hermes/config.yaml"
  if grep -q "provider: zai" "$tmp/home/.hermes/config.yaml"; then
    echo "existing model config still points at zai" >&2
    cat "$tmp/home/.hermes/config.yaml" >&2
    exit 1
  fi
  echo "existing model config sync OK"
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

run_status_page_dashboard_proxy_case() {
  local tmp status_port upstream_port
  tmp="$(mktemp -d)"

  read -r status_port upstream_port <<< "$("$PYTHON_BIN" - <<'PY'
import socket

sockets = []
ports = []
for _ in range(2):
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    sockets.append(sock)
    ports.append(sock.getsockname()[1])
print(*ports)
for sock in sockets:
    sock.close()
PY
)"

  cat > "$tmp/upstream.py" <<'PY'
import base64
import hashlib
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EXPECTED_HOST = sys.argv[2]
EXPECTED_ORIGIN = f"http://{EXPECTED_HOST}"
EXPECTED_FORWARDED_HOST = "hermes-railway-template-dev.up.railway.app"
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class Handler(BaseHTTPRequestHandler):
    def reject(self, message):
        body = message.encode("utf-8")
        self.send_response(400)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def validate_proxy_headers(self):
        host = self.headers.get("Host", "")
        forwarded_host = self.headers.get("X-Forwarded-Host", "")
        if host != EXPECTED_HOST:
            return f"invalid host {host}"
        if forwarded_host != EXPECTED_FORWARDED_HOST:
            return f"invalid forwarded host {forwarded_host}"
        if self.headers.get("Upgrade", "").lower() == "websocket":
            origin = self.headers.get("Origin", "")
            if origin != EXPECTED_ORIGIN:
                return f"invalid origin {origin}"
        return ""

    def do_GET(self):
        error = self.validate_proxy_headers()
        if error:
            self.reject(error)
            return

        if self.headers.get("Upgrade", "").lower() == "websocket":
            key = self.headers.get("Sec-WebSocket-Key", "")
            accept = base64.b64encode(hashlib.sha1((key + WS_GUID).encode("ascii")).digest()).decode("ascii")
            self.send_response(101, "Switching Protocols")
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("Sec-WebSocket-Accept", accept)
            self.end_headers()
            return

        body = f"upstream {self.path}".encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY

  "$PYTHON_BIN" "$tmp/upstream.py" "$upstream_port" "127.0.0.1:$upstream_port" > "$tmp/upstream.out" 2>&1 &
  local upstream_pid=$!

  PORT="$status_port" \
    HERMES_DASHBOARD_UPSTREAM_URL="http://127.0.0.1:$upstream_port" \
    HERMES_DASHBOARD_PROXY_PASSWORD=secret-password \
    "$PYTHON_BIN" "$ROOT_DIR/scripts/status_server.py" > "$tmp/status.out" 2>&1 &
  local status_pid=$!

  trap 'kill "$status_pid" "$upstream_pid" 2>/dev/null || true' RETURN

  for _ in $(seq 1 50); do
    if "$PYTHON_BIN" - "$status_port" <<'PY' >/dev/null 2>&1
import sys
import urllib.request

urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/healthz", timeout=0.2).read()
PY
    then
      break
    fi
    sleep 0.1
  done

  "$PYTHON_BIN" - "$status_port" <<'PY'
import base64
import sys
import urllib.error
import urllib.request

port = sys.argv[1]
base = f"http://127.0.0.1:{port}"

health = urllib.request.urlopen(f"{base}/healthz", timeout=2).read().decode("utf-8").strip()
assert health == "ok", health

page = urllib.request.urlopen(base, timeout=2).read().decode("utf-8")
assert "/sessions" in page, page

try:
    urllib.request.urlopen(f"{base}/sessions", timeout=2)
except urllib.error.HTTPError as exc:
    assert exc.code == 401, exc.code
    assert "Basic" in exc.headers.get("WWW-Authenticate", ""), exc.headers
else:
    raise AssertionError("dashboard proxy accepted unauthenticated request")

token = base64.b64encode(b"admin:secret-password").decode("ascii")
req = urllib.request.Request(
    f"{base}/sessions?check=1",
    headers={
        "Authorization": f"Basic {token}",
        "Host": "hermes-railway-template-dev.up.railway.app",
    },
)
body = urllib.request.urlopen(req, timeout=2).read().decode("utf-8")
assert body == "upstream /sessions?check=1", body
PY

  "$PYTHON_BIN" - "$status_port" <<'PY'
import base64
import os
import socket
import sys

port = int(sys.argv[1])
key = base64.b64encode(os.urandom(16)).decode("ascii")
token = base64.b64encode(b"admin:secret-password").decode("ascii")
request = "\r\n".join(
    [
        "GET /api/pty?token=test&channel=demo HTTP/1.1",
        "Host: hermes-railway-template-dev.up.railway.app",
        "Origin: https://hermes-railway-template-dev.up.railway.app",
        "Upgrade: websocket",
        "Connection: Upgrade",
        "Sec-WebSocket-Version: 13",
        f"Sec-WebSocket-Key: {key}",
        f"Authorization: Basic {token}",
        "",
        "",
    ]
).encode("ascii")

with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
    sock.sendall(request)
    response = sock.recv(4096).decode("iso-8859-1")

assert " 101 " in response.split("\r\n", 1)[0], response
PY

  kill "$status_pid" "$upstream_pid" 2>/dev/null || true
  wait "$status_pid" "$upstream_pid" 2>/dev/null || true
  trap - RETURN
  echo "status page dashboard proxy OK"
}

run_dashboard_case() {
  local name="$1"
  shift
  local tmp
  tmp="$(new_case_dir)"

  PATH="$tmp/bin:$PATH" \
    HERMES_HOME="$tmp/home/.hermes" \
    HOME="$tmp/home" \
    TERMINAL_CWD="$tmp/workspace" \
    PORT=19091 \
    HERMES_DASHBOARD=1 \
    HERMES_DASHBOARD_INSECURE=true \
    HERMES_DASHBOARD_PROXY_PASSWORD=test-password \
    "$@" "$ROOT_DIR/scripts/entrypoint.sh" > "$tmp/out.txt" 2>&1

  grep -q "Starting Hermes dashboard on 127.0.0.1:9119" "$tmp/out.txt"
  grep -q "Starting status page" "$tmp/out.txt"
  grep -q "fake hermes dashboard --host 127.0.0.1 --port 9119 --no-open --tui --insecure --skip-build" "$tmp/out.txt"
  grep -q "Starting Hermes gateway" "$tmp/out.txt"
  grep -q "fake hermes gateway" "$tmp/out.txt"
  echo "$name OK"
}

run_dashboard_password_failure_case() {
  local tmp
  tmp="$(new_case_dir)"

  set +e
  PATH="$tmp/bin:$PATH" \
    HERMES_HOME="$tmp/home/.hermes" \
    HOME="$tmp/home" \
    TERMINAL_CWD="$tmp/workspace" \
    PORT=19094 \
    HERMES_DASHBOARD=1 \
    HERMES_DASHBOARD_INSECURE=true \
    HERMES_GATEWAY_ENABLED=false \
    FAKE_HERMES_DASHBOARD_SLEEP=1 \
    HERMES_INFERENCE_PROVIDER=custom \
    OPENAI_BASE_URL=https://api.example.com/v1 \
    OPENAI_API_KEY=test-key \
    "$ROOT_DIR/scripts/entrypoint.sh" > "$tmp/out.txt" 2>&1
  local code=$?
  set -e

  if [[ "$code" -eq 0 ]]; then
    echo "Dashboard proxy without password expected failure but succeeded" >&2
    cat "$tmp/out.txt" >&2
    exit 1
  fi

  grep -q "HERMES_DASHBOARD_PROXY_PASSWORD" "$tmp/out.txt"
  echo "Dashboard proxy password required OK"
}

run_dashboard_rebuild_case() {
  local tmp
  tmp="$(new_case_dir)"

  PATH="$tmp/bin:$PATH" \
    HERMES_HOME="$tmp/home/.hermes" \
    HOME="$tmp/home" \
    TERMINAL_CWD="$tmp/workspace" \
    PORT=19093 \
    HERMES_DASHBOARD=1 \
    HERMES_DASHBOARD_INSECURE=true \
    HERMES_DASHBOARD_PROXY_PASSWORD=test-password \
    HERMES_DASHBOARD_SKIP_BUILD=false \
    HERMES_INFERENCE_PROVIDER=custom \
    OPENAI_BASE_URL=https://api.example.com/v1 \
    OPENAI_API_KEY=test-key \
    QQ_APP_ID=app-id \
    QQ_CLIENT_SECRET=secret \
    QQ_ALLOWED_USERS=openid_a \
    "$ROOT_DIR/scripts/entrypoint.sh" > "$tmp/out.txt" 2>&1

  grep -q "Starting Hermes dashboard on 127.0.0.1:9119" "$tmp/out.txt"
  grep -q "Starting status page" "$tmp/out.txt"
  grep -q "fake hermes dashboard --host 127.0.0.1 --port 9119 --no-open --tui --insecure" "$tmp/out.txt"
  if grep -q -- "--skip-build" "$tmp/out.txt"; then
    echo "Dashboard rebuild mode unexpectedly skipped build" >&2
    cat "$tmp/out.txt" >&2
    exit 1
  fi
  echo "Dashboard rebuild opt-out OK"
}

run_dashboard_only_case() {
  local tmp
  tmp="$(new_case_dir)"

  PATH="$tmp/bin:$PATH" \
    HERMES_HOME="$tmp/home/.hermes" \
    HOME="$tmp/home" \
    TERMINAL_CWD="$tmp/workspace" \
    PORT=19092 \
    HERMES_DASHBOARD=1 \
    HERMES_DASHBOARD_INSECURE=true \
    HERMES_DASHBOARD_PROXY_PASSWORD=test-password \
    HERMES_GATEWAY_ENABLED=false \
    FAKE_HERMES_DASHBOARD_SLEEP=1 \
    HERMES_INFERENCE_PROVIDER=custom \
    OPENAI_BASE_URL=https://api.example.com/v1 \
    OPENAI_API_KEY=test-key \
    "$ROOT_DIR/scripts/entrypoint.sh" > "$tmp/out.txt" 2>&1

  grep -q "Starting Hermes dashboard on 127.0.0.1:9119" "$tmp/out.txt"
  grep -q "Starting status page" "$tmp/out.txt"
  grep -q "fake hermes dashboard --host 127.0.0.1 --port 9119 --no-open --tui --insecure --skip-build" "$tmp/out.txt"
  grep -q "Gateway disabled" "$tmp/out.txt"
  if grep -q "fake hermes gateway" "$tmp/out.txt"; then
    echo "Dashboard-only mode unexpectedly started gateway" >&2
    cat "$tmp/out.txt" >&2
    exit 1
  fi
  echo "Dashboard-only web chat OK"
}

run_dockerfile_tui_prebuild_case() {
  grep -q "ui-tui" "$ROOT_DIR/Dockerfile"
  grep -q "hermes_cli/tui_dist" "$ROOT_DIR/Dockerfile"
  grep -q "hermes-dashboard-insecure-public-ws.patch" "$ROOT_DIR/Dockerfile"
  grep -q "allow_public" "$ROOT_DIR/patches/hermes-dashboard-insecure-public-ws.patch"
  echo "Dockerfile TUI prebuild OK"
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

run_existing_model_config_sync_case

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

run_failure "gateway disabled without dashboard" "HERMES_GATEWAY_ENABLED=false requires HERMES_DASHBOARD=1" env \
  HERMES_GATEWAY_ENABLED=false \
  HERMES_INFERENCE_PROVIDER=custom \
  OPENAI_BASE_URL=https://api.example.com/v1 \
  OPENAI_API_KEY=test-key

run_status_page_case

run_status_page_dashboard_proxy_case

run_dashboard_case "Dashboard with QQ gateway" env \
  HERMES_INFERENCE_PROVIDER=custom \
  OPENAI_BASE_URL=https://api.example.com/v1 \
  OPENAI_API_KEY=test-key \
  QQ_APP_ID=app-id \
  QQ_CLIENT_SECRET=secret \
  QQ_ALLOWED_USERS=openid_a

run_dashboard_password_failure_case

run_dashboard_rebuild_case

run_dashboard_only_case

run_dockerfile_tui_prebuild_case
