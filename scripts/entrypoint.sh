#!/usr/bin/env bash
set -euo pipefail

export HERMES_HOME="${HERMES_HOME:-/data/.hermes}"
export HOME="${HOME:-/data}"
export TZ="${TZ:-Asia/Shanghai}"
export HERMES_TIMEZONE="${HERMES_TIMEZONE:-$TZ}"
LEGACY_MESSAGING_CWD="${MESSAGING_CWD:-/data/workspace}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-}"

if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN=python3
  else
    PYTHON_BIN=python
  fi
fi

INIT_MARKER="${HERMES_HOME}/.initialized"
ENV_FILE="${HERMES_HOME}/.env"
CONFIG_FILE="${HERMES_HOME}/config.yaml"
DEFAULT_TERMINAL_CWD="${TERMINAL_CWD:-${LEGACY_MESSAGING_CWD}}"
STATUS_PAGE_PID=""
DASHBOARD_PID=""
GATEWAY_PID=""

mkdir -p "${HERMES_HOME}" "${HERMES_HOME}/logs" "${HERMES_HOME}/sessions" "${HERMES_HOME}/cron" "${HERMES_HOME}/pairing" "${DEFAULT_TERMINAL_CWD}"

is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup() {
  local code=$?
  trap - EXIT

  if [[ -n "${GATEWAY_PID:-}" ]]; then
    kill "$GATEWAY_PID" 2>/dev/null || true
  fi

  if [[ -n "${STATUS_PAGE_PID:-}" ]]; then
    kill "$STATUS_PAGE_PID" 2>/dev/null || true
  fi

  if [[ -n "${DASHBOARD_PID:-}" ]]; then
    kill "$DASHBOARD_PID" 2>/dev/null || true
  fi

  if [[ -n "${GATEWAY_PID:-}" ]]; then
    wait "$GATEWAY_PID" 2>/dev/null || true
  fi
  if [[ -n "${STATUS_PAGE_PID:-}" ]]; then
    wait "$STATUS_PAGE_PID" 2>/dev/null || true
  fi
  if [[ -n "${DASHBOARD_PID:-}" ]]; then
    wait "$DASHBOARD_PID" 2>/dev/null || true
  fi
  exit "$code"
}

wait_for_first_exit() {
  local pid status

  while true; do
    for pid in "$@"; do
      if ! kill -0 "$pid" 2>/dev/null; then
        status=0
        wait "$pid" 2>/dev/null || status=$?
        return "$status"
      fi
    done
    sleep 1
  done
}

dashboard_enabled() {
  is_true "${HERMES_DASHBOARD:-false}"
}

status_page_enabled() {
  is_true "${STATUS_PAGE_ENABLED:-true}"
}

dashboard_proxy_enabled() {
  dashboard_enabled && status_page_enabled
}

gateway_enabled() {
  is_true "${HERMES_GATEWAY_ENABLED:-true}"
}

dashboard_proxy_password() {
  printf '%s' "${HERMES_DASHBOARD_PROXY_PASSWORD:-${HERMES_DASHBOARD_PASSWORD:-}}"
}

dashboard_insecure_enabled() {
  if [[ "${HERMES_DASHBOARD_INSECURE+x}" == "x" ]]; then
    is_true "${HERMES_DASHBOARD_INSECURE}"
    return
  fi

  dashboard_proxy_enabled
}

validate_dashboard_proxy_security() {
  if ! dashboard_proxy_enabled; then
    return 0
  fi

  if [[ -z "$(dashboard_proxy_password)" ]]; then
    echo "[bootstrap] ERROR: HERMES_DASHBOARD=1 with the public status proxy requires HERMES_DASHBOARD_PROXY_PASSWORD (or HERMES_DASHBOARD_PASSWORD) to protect /, /readyz, /sessions, and Dashboard paths." >&2
    exit 1
  fi
}

dashboard_internal_port() {
  local public_port="${PORT:-${STATUS_PAGE_PORT:-8080}}"
  local internal_port="${HERMES_DASHBOARD_INTERNAL_PORT:-${HERMES_DASHBOARD_PORT:-9119}}"

  if [[ "$internal_port" == "$public_port" ]]; then
    if [[ -n "${HERMES_DASHBOARD_INTERNAL_PORT:-}${HERMES_DASHBOARD_PORT:-}" ]]; then
      echo "[bootstrap] ERROR: Dashboard internal port ${internal_port} conflicts with public status port ${public_port}; set HERMES_DASHBOARD_INTERNAL_PORT to a different value." >&2
      exit 1
    fi
    internal_port=9120
  fi

  printf '%s' "$internal_port"
}

start_status_page() {
  if ! status_page_enabled; then
    echo "[bootstrap] Status page disabled."
    return 0
  fi

  echo "[bootstrap] Starting status page on ${STATUS_PAGE_HOST:-0.0.0.0}:${PORT:-${STATUS_PAGE_PORT:-8080}}"
  "$PYTHON_BIN" "${STATUS_SERVER_PATH:-${SCRIPT_DIR}/status_server.py}" &
  STATUS_PAGE_PID=$!
  sleep 0.2
  if ! kill -0 "$STATUS_PAGE_PID" 2>/dev/null; then
    echo "[bootstrap] ERROR: Status page failed to start." >&2
    wait "$STATUS_PAGE_PID" 2>/dev/null || true
    exit 1
  fi
}

start_dashboard() {
  if ! dashboard_enabled; then
    return 0
  fi

  local host="${HERMES_DASHBOARD_HOST:-0.0.0.0}"
  local port="${PORT:-${HERMES_DASHBOARD_PORT:-9119}}"

  if dashboard_proxy_enabled; then
    host="${HERMES_DASHBOARD_INTERNAL_HOST:-127.0.0.1}"
    port="$(dashboard_internal_port)"

    local upstream_host="$host"
    if [[ "$upstream_host" == "0.0.0.0" || "$upstream_host" == "::" ]]; then
      upstream_host="127.0.0.1"
    fi
    export HERMES_DASHBOARD_UPSTREAM_URL="http://${upstream_host}:${port}"
  fi

  local args=(dashboard --host "$host" --port "$port" --no-open)

  if is_true "${HERMES_DASHBOARD_TUI:-true}"; then
    args+=(--tui)
  fi

  if dashboard_insecure_enabled; then
    args+=(--insecure)
  fi

  if is_true "${HERMES_DASHBOARD_SKIP_BUILD:-true}"; then
    args+=(--skip-build)
  fi

  echo "[bootstrap] Starting Hermes dashboard on ${host}:${port}"
  hermes "${args[@]}" &
  DASHBOARD_PID=$!
  sleep 0.5
  if ! kill -0 "$DASHBOARD_PID" 2>/dev/null; then
    echo "[bootstrap] ERROR: Hermes dashboard failed to start." >&2
    wait "$DASHBOARD_PID" 2>/dev/null || true
    exit 1
  fi
}

validate_platforms() {
  local count=0

  if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    count=$((count + 1))
  fi

  if [[ -n "${DISCORD_BOT_TOKEN:-}" ]]; then
    count=$((count + 1))
  fi

  if [[ -n "${SLACK_BOT_TOKEN:-}" || -n "${SLACK_APP_TOKEN:-}" ]]; then
    if [[ -z "${SLACK_BOT_TOKEN:-}" || -z "${SLACK_APP_TOKEN:-}" ]]; then
      echo "[bootstrap] ERROR: Slack requires both SLACK_BOT_TOKEN and SLACK_APP_TOKEN." >&2
      exit 1
    fi
    count=$((count + 1))
  fi

  if [[ -n "${WECOM_BOT_ID:-}" || -n "${WECOM_SECRET:-}" ]]; then
    if [[ -z "${WECOM_BOT_ID:-}" || -z "${WECOM_SECRET:-}" ]]; then
      echo "[bootstrap] ERROR: WeCom requires both WECOM_BOT_ID and WECOM_SECRET." >&2
      exit 1
    fi
    count=$((count + 1))
  fi

  if [[ -n "${WECOM_CALLBACK_CORP_ID:-}" || -n "${WECOM_CALLBACK_CORP_SECRET:-}" || -n "${WECOM_CALLBACK_AGENT_ID:-}" || -n "${WECOM_CALLBACK_TOKEN:-}" || -n "${WECOM_CALLBACK_ENCODING_AES_KEY:-}" ]]; then
    if [[ -z "${WECOM_CALLBACK_CORP_ID:-}" || -z "${WECOM_CALLBACK_CORP_SECRET:-}" || -z "${WECOM_CALLBACK_AGENT_ID:-}" || -z "${WECOM_CALLBACK_TOKEN:-}" || -z "${WECOM_CALLBACK_ENCODING_AES_KEY:-}" ]]; then
      echo "[bootstrap] ERROR: WeCom callback requires WECOM_CALLBACK_CORP_ID, WECOM_CALLBACK_CORP_SECRET, WECOM_CALLBACK_AGENT_ID, WECOM_CALLBACK_TOKEN, and WECOM_CALLBACK_ENCODING_AES_KEY." >&2
      exit 1
    fi
    count=$((count + 1))
  fi

  if [[ -n "${WEIXIN_ACCOUNT_ID:-}" || -n "${WEIXIN_TOKEN:-}" ]]; then
    if [[ -z "${WEIXIN_ACCOUNT_ID:-}" ]]; then
      echo "[bootstrap] ERROR: Weixin requires WEIXIN_ACCOUNT_ID. WEIXIN_TOKEN may be supplied directly or restored from persisted QR login state." >&2
      exit 1
    fi
    count=$((count + 1))
  fi

  if [[ -n "${QQ_APP_ID:-}" || -n "${QQ_CLIENT_SECRET:-}" ]]; then
    if [[ -z "${QQ_APP_ID:-}" || -z "${QQ_CLIENT_SECRET:-}" ]]; then
      echo "[bootstrap] ERROR: QQ Bot requires both QQ_APP_ID and QQ_CLIENT_SECRET." >&2
      exit 1
    fi
    count=$((count + 1))
  fi

  if [[ "$count" -lt 1 ]]; then
    echo "[bootstrap] ERROR: Configure at least one platform: Telegram, Discord, Slack, WeCom, Weixin, or QQ Bot." >&2
    exit 1
  fi
}

has_valid_provider_config() {
  if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
    return 0
  fi

  if has_custom_endpoint_config; then
    return 0
  fi

  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    return 0
  fi

  if [[ -n "${MINIMAX_API_KEY:-}" || -n "${MINIMAX_CN_API_KEY:-}" ]]; then
    return 0
  fi

  return 1
}

has_custom_endpoint_config() {
  if [[ -z "${CUSTOM_BASE_URL:-}${OPENAI_BASE_URL:-}" ]]; then
    return 1
  fi

  if [[ -n "${OPENAI_API_KEY:-}${CUSTOM_API_KEY:-}${INFINI_AI_API_KEY:-}" ]]; then
    return 0
  fi

  return 1
}

normalize_openai_base_url_value() {
  local value="$1"

  if [[ "$value" =~ ^https?://[^/]+/?$ ]]; then
    printf '%s/v1' "${value%/}"
  else
    printf '%s' "$value"
  fi
}

normalize_provider_env() {
  if [[ -n "${OPENAI_BASE_URL:-}" ]]; then
    local normalized_openai_base_url
    normalized_openai_base_url="$(normalize_openai_base_url_value "${OPENAI_BASE_URL}")"
    if [[ "$normalized_openai_base_url" != "$OPENAI_BASE_URL" ]]; then
      export OPENAI_BASE_URL="$normalized_openai_base_url"
      echo "[bootstrap] Normalized bare custom base URL to ${OPENAI_BASE_URL}"
    fi
  fi

  if [[ -n "${CUSTOM_BASE_URL:-}" ]]; then
    local normalized_custom_base_url
    normalized_custom_base_url="$(normalize_openai_base_url_value "${CUSTOM_BASE_URL}")"
    if [[ "$normalized_custom_base_url" != "$CUSTOM_BASE_URL" ]]; then
      export CUSTOM_BASE_URL="$normalized_custom_base_url"
      echo "[bootstrap] Normalized bare custom base URL to ${CUSTOM_BASE_URL}"
    fi
  fi

  if [[ -z "${CUSTOM_BASE_URL:-}" && -n "${OPENAI_BASE_URL:-}" ]]; then
    export CUSTOM_BASE_URL="${OPENAI_BASE_URL}"
  fi

  if [[ -z "${OPENAI_BASE_URL:-}" && -n "${CUSTOM_BASE_URL:-}" ]]; then
    export OPENAI_BASE_URL="${CUSTOM_BASE_URL}"
  fi

  if [[ -z "${OPENAI_API_KEY:-}" && -n "${CUSTOM_API_KEY:-}" ]]; then
    export OPENAI_API_KEY="${CUSTOM_API_KEY}"
  fi

  if [[ -n "${OPENAI_API_KEY:-}" && -z "${INFINI_AI_API_KEY:-}" ]]; then
    case "${CUSTOM_BASE_URL:-}${OPENAI_BASE_URL:-}" in
      *infini-ai*) export INFINI_AI_API_KEY="${OPENAI_API_KEY}" ;;
    esac
  fi

  if [[ -n "${INFINI_AI_API_KEY:-}" && -z "${OPENAI_API_KEY:-}" ]]; then
    case "${CUSTOM_BASE_URL:-}${OPENAI_BASE_URL:-}" in
      *infini-ai*) export OPENAI_API_KEY="${INFINI_AI_API_KEY}" ;;
    esac
  fi
}

sync_tui_runtime_env() {
  local provider="${HERMES_INFERENCE_PROVIDER:-}"
  local model="${HERMES_MODEL:-${MODEL_NAME:-}}"

  if [[ -z "$provider" && -n "${CUSTOM_BASE_URL:-}${OPENAI_BASE_URL:-}" ]]; then
    provider="custom"
  fi

  if [[ -z "${HERMES_TUI_PROVIDER:-}" && -n "$provider" ]]; then
    export HERMES_TUI_PROVIDER="$provider"
  fi

  if [[ -z "${HERMES_INFERENCE_MODEL:-}" && -n "$model" ]]; then
    export HERMES_INFERENCE_MODEL="$model"
  fi
}

append_if_set() {
  local key="$1"
  local val="${!key:-}"
  if [[ -n "$val" ]]; then
    printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE"
  fi
}

read_env_value() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  grep -E "^${key}=" "$file" | head -n 1 | cut -d '=' -f 2-
}

config_has_terminal_cwd() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    return 1
  fi

  awk '
    /^terminal:[[:space:]]*$/ { in_terminal = 1; next }
    in_terminal && /^[^[:space:]]/ { in_terminal = 0 }
    in_terminal && /^[[:space:]]+cwd:[[:space:]]*/ { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' "$CONFIG_FILE"
}

config_has_terminal_section() {
  [[ -f "$CONFIG_FILE" ]] && grep -qE '^terminal:[[:space:]]*$' "$CONFIG_FILE"
}

config_has_model_section() {
  [[ -f "$CONFIG_FILE" ]] && grep -qE '^model:[[:space:]]*$' "$CONFIG_FILE"
}

model_env_configured() {
  [[ -n "${HERMES_INFERENCE_PROVIDER:-}${HERMES_MODEL:-}${MODEL_NAME:-}${CUSTOM_BASE_URL:-}${OPENAI_BASE_URL:-}" ]]
}

model_api_key_ref() {
  local base_url="${CUSTOM_BASE_URL:-${OPENAI_BASE_URL:-}}"

  if [[ -n "$base_url" && -n "${OPENAI_API_KEY:-}" ]]; then
    printf '${OPENAI_API_KEY}'
  fi
}

write_model_config() {
  local provider="${HERMES_INFERENCE_PROVIDER:-}"
  local model="${HERMES_MODEL:-${MODEL_NAME:-}}"
  local base_url="${CUSTOM_BASE_URL:-${OPENAI_BASE_URL:-}}"
  local api_key_ref=""

  if [[ -z "$provider" && -n "$base_url" ]]; then
    provider="custom"
  fi

  if [[ -z "${provider}${model}${base_url}" ]]; then
    return 0
  fi

  echo "model:"
  if [[ -n "$model" ]]; then
    echo "  default: ${model}"
  fi
  if [[ -n "$provider" ]]; then
    echo "  provider: ${provider}"
  fi
  if [[ -n "$base_url" ]]; then
    echo "  base_url: ${base_url}"
  fi
  api_key_ref="$(model_api_key_ref)"
  if [[ -n "$api_key_ref" ]]; then
    echo "  api_key: ${api_key_ref}"
  fi
}

sync_model_config_from_env() {
  if [[ ! -f "$CONFIG_FILE" ]] || ! config_has_model_section || ! model_env_configured; then
    return 0
  fi

  echo "[bootstrap] Syncing model config from Railway variables"
  "$PYTHON_BIN" - "$CONFIG_FILE" <<'PY'
import os
import re
import sys
from pathlib import Path


path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="ignore")
lines = text.splitlines()

updates = {}
model = os.environ.get("HERMES_MODEL") or os.environ.get("MODEL_NAME") or ""
provider = os.environ.get("HERMES_INFERENCE_PROVIDER") or ""
base_url = os.environ.get("CUSTOM_BASE_URL") or os.environ.get("OPENAI_BASE_URL") or ""
api_key_ref = "${OPENAI_API_KEY}" if base_url and os.environ.get("OPENAI_API_KEY") else ""

if base_url and not provider:
    provider = "custom"

if model:
    updates["default"] = model
if provider:
    updates["provider"] = provider
if base_url:
    updates["base_url"] = base_url
if api_key_ref:
    updates["api_key"] = api_key_ref

if not updates:
    sys.exit(0)

start = next((i for i, line in enumerate(lines) if re.match(r"^model:\s*(#.*)?$", line)), None)
if start is None:
    sys.exit(0)

end = len(lines)
for i in range(start + 1, len(lines)):
    if re.match(r"^[^\s#][^:]*:", lines[i]):
        end = i
        break

block = lines[start + 1 : end]
indent = "  "
for line in block:
    match = re.match(r"^([ \t]+)[A-Za-z0-9_-]+:", line)
    if match:
        indent = match.group(1)
        break


def yaml_scalar(value: str) -> str:
    if re.match(r"^\$\{[A-Za-z_][A-Za-z0-9_]*\}$", value):
        return value
    if re.match(r"^[A-Za-z0-9._:/@?&=+,%~-]+$", value):
        return value
    return "'" + value.replace("'", "''") + "'"


seen = set()
new_block = []
drop_stale_secret_keys = bool(base_url or provider)
for line in block:
    match = re.match(r"^([ \t]+)([A-Za-z0-9_-]+):(.*)$", line)
    if match and match.group(2) in updates:
        key = match.group(2)
        new_block.append(f"{match.group(1)}{key}: {yaml_scalar(updates[key])}")
        seen.add(key)
        continue
    if drop_stale_secret_keys and match and match.group(2) in {"api", "api_key"}:
        continue
    new_block.append(line)

for key in ("default", "provider", "base_url", "api_key"):
    if key in updates and key not in seen:
        new_block.append(f"{indent}{key}: {yaml_scalar(updates[key])}")

path.write_text("\n".join(lines[: start + 1] + new_block + lines[end:]) + "\n", encoding="utf-8")
PY
}

create_default_config() {
  echo "[bootstrap] Creating ${CONFIG_FILE}"
  {
    write_model_config
    cat <<EOF
terminal:
  backend: ${TERMINAL_ENV:-${TERMINAL_BACKEND:-local}}
  cwd: $1
  timeout: ${TERMINAL_TIMEOUT:-180}
compression:
  enabled: true
  threshold: 0.85
EOF
  } > "$CONFIG_FILE"
}

ensure_model_in_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    return 0
  fi

  if config_has_model_section; then
    sync_model_config_from_env
    return 0
  fi

  if model_env_configured; then
    {
      printf '\n'
      write_model_config
    } >> "$CONFIG_FILE"
  fi
}

ensure_terminal_cwd_in_config() {
  local cwd="$1"
  local tmp_file

  if [[ ! -f "$CONFIG_FILE" ]]; then
    create_default_config "$cwd"
    return 0
  fi

  if config_has_terminal_cwd; then
    return 0
  fi

  if config_has_terminal_section; then
    tmp_file="$(mktemp)"
    awk -v cwd="$cwd" '
      /^terminal:[[:space:]]*$/ && !inserted {
        print
        print "  cwd: " cwd
        inserted = 1
        next
      }
      { print }
    ' "$CONFIG_FILE" > "$tmp_file"
    mv "$tmp_file" "$CONFIG_FILE"
    return 0
  fi

  printf '\nterminal:\n  cwd: %s\n' "$cwd" >> "$CONFIG_FILE"
}

migrate_legacy_messaging_cwd() {
  local persisted_cwd legacy_cwd

  persisted_cwd="$(read_env_value "$ENV_FILE" "MESSAGING_CWD" || true)"
  legacy_cwd="${persisted_cwd:-${MESSAGING_CWD:-}}"

  if [[ -n "$legacy_cwd" ]]; then
    ensure_terminal_cwd_in_config "$legacy_cwd"
  elif [[ ! -f "$CONFIG_FILE" ]]; then
    create_default_config "$DEFAULT_TERMINAL_CWD"
  fi
}

normalize_provider_env
sync_tui_runtime_env

if ! has_valid_provider_config; then
  if [[ -n "${CUSTOM_BASE_URL:-}${OPENAI_BASE_URL:-}" ]]; then
    echo "[bootstrap] ERROR: Custom/OpenAI-compatible endpoints require CUSTOM_BASE_URL or OPENAI_BASE_URL plus OPENAI_API_KEY, CUSTOM_API_KEY, or INFINI_AI_API_KEY." >&2
  else
    echo "[bootstrap] ERROR: Configure a provider: OPENROUTER_API_KEY, OPENAI_BASE_URL+OPENAI_API_KEY, CUSTOM_BASE_URL+OPENAI_API_KEY, ANTHROPIC_API_KEY, MINIMAX_API_KEY, or MINIMAX_CN_API_KEY." >&2
  fi
  exit 1
fi

if gateway_enabled; then
  validate_platforms
elif ! dashboard_enabled; then
  echo "[bootstrap] ERROR: HERMES_GATEWAY_ENABLED=false requires HERMES_DASHBOARD=1 so the container still has a foreground service." >&2
  exit 1
fi

migrate_legacy_messaging_cwd

ensure_model_in_config

echo "[bootstrap] Writing runtime env to ${ENV_FILE}"
{
  echo "# Managed by entrypoint.sh"
  echo "HERMES_HOME=${HERMES_HOME}"
  echo "TZ=${TZ}"
  echo "HERMES_TIMEZONE=${HERMES_TIMEZONE}"
  echo "PATH=${PATH}"
} > "$ENV_FILE"

for key in \
  OPENROUTER_API_KEY CUSTOM_BASE_URL CUSTOM_API_KEY OPENAI_API_KEY OPENAI_BASE_URL INFINI_AI_API_KEY ANTHROPIC_API_KEY MINIMAX_API_KEY MINIMAX_BASE_URL MINIMAX_CN_API_KEY MINIMAX_CN_BASE_URL HERMES_MODEL MODEL_NAME HERMES_INFERENCE_PROVIDER HERMES_INFERENCE_MODEL HERMES_TUI_PROVIDER HERMES_PORTAL_BASE_URL NOUS_INFERENCE_BASE_URL HERMES_NOUS_MIN_KEY_TTL_SECONDS HERMES_DUMP_REQUESTS \
  STATUS_PAGE_ENABLED STATUS_PAGE_HOST STATUS_PAGE_PORT PORT HERMES_DASHBOARD HERMES_DASHBOARD_HOST HERMES_DASHBOARD_PORT HERMES_DASHBOARD_TUI HERMES_DASHBOARD_INSECURE HERMES_DASHBOARD_SKIP_BUILD HERMES_DASHBOARD_PUBLIC_URL HERMES_DASHBOARD_OAUTH_CLIENT_ID HERMES_DASHBOARD_PORTAL_URL HERMES_WEB_DIST HERMES_GATEWAY_ENABLED HERMES_DASHBOARD_SESSION_SECONDS HERMES_DASHBOARD_SESSION_SECRET \
  TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_USERS TELEGRAM_ALLOW_ALL_USERS TELEGRAM_HOME_CHANNEL TELEGRAM_HOME_CHANNEL_NAME \
  DISCORD_BOT_TOKEN DISCORD_ALLOWED_USERS DISCORD_ALLOW_ALL_USERS DISCORD_HOME_CHANNEL DISCORD_HOME_CHANNEL_NAME DISCORD_REQUIRE_MENTION DISCORD_FREE_RESPONSE_CHANNELS \
  SLACK_BOT_TOKEN SLACK_APP_TOKEN SLACK_ALLOWED_USERS SLACK_ALLOW_ALL_USERS SLACK_HOME_CHANNEL SLACK_HOME_CHANNEL_NAME WHATSAPP_ENABLED WHATSAPP_ALLOWED_USERS \
  WECOM_BOT_ID WECOM_SECRET WECOM_WEBSOCKET_URL WECOM_ALLOWED_USERS WECOM_ALLOW_ALL_USERS WECOM_DM_POLICY WECOM_GROUP_POLICY WECOM_GROUP_ALLOWED_USERS WECOM_HOME_CHANNEL WECOM_HOME_CHANNEL_NAME WECOM_HOME_CHANNEL_THREAD_ID \
  WECOM_CALLBACK_CORP_ID WECOM_CALLBACK_CORP_SECRET WECOM_CALLBACK_AGENT_ID WECOM_CALLBACK_TOKEN WECOM_CALLBACK_ENCODING_AES_KEY WECOM_CALLBACK_HOST WECOM_CALLBACK_PORT WECOM_CALLBACK_ALLOWED_USERS WECOM_CALLBACK_ALLOW_ALL_USERS \
  WEIXIN_ACCOUNT_ID WEIXIN_TOKEN WEIXIN_BASE_URL WEIXIN_CDN_BASE_URL WEIXIN_DM_POLICY WEIXIN_GROUP_POLICY WEIXIN_ALLOWED_USERS WEIXIN_GROUP_ALLOWED_USERS WEIXIN_ALLOW_ALL_USERS WEIXIN_SPLIT_MULTILINE_MESSAGES WEIXIN_HOME_CHANNEL WEIXIN_HOME_CHANNEL_NAME WEIXIN_HOME_CHANNEL_THREAD_ID \
  QQ_APP_ID QQ_CLIENT_SECRET QQ_ALLOWED_USERS QQ_GROUP_ALLOWED_USERS QQ_ALLOW_ALL_USERS QQ_PORTAL_HOST QQ_STT_API_KEY QQ_STT_BASE_URL QQ_STT_MODEL QQBOT_HOME_CHANNEL QQBOT_HOME_CHANNEL_NAME QQBOT_HOME_CHANNEL_THREAD_ID \
  GATEWAY_ALLOW_ALL_USERS \
  FIRECRAWL_API_KEY NOUS_API_KEY BROWSERBASE_API_KEY BROWSERBASE_PROJECT_ID BROWSERBASE_PROXIES BROWSERBASE_ADVANCED_STEALTH BROWSER_SESSION_TIMEOUT BROWSER_INACTIVITY_TIMEOUT FAL_KEY ELEVENLABS_API_KEY VOICE_TOOLS_OPENAI_KEY \
  TINKER_API_KEY WANDB_API_KEY RL_API_URL GITHUB_TOKEN \
  TERMINAL_ENV TERMINAL_BACKEND TERMINAL_DOCKER_IMAGE TERMINAL_SINGULARITY_IMAGE TERMINAL_MODAL_IMAGE TERMINAL_CWD TERMINAL_TIMEOUT TERMINAL_LIFETIME_SECONDS TERMINAL_CONTAINER_CPU TERMINAL_CONTAINER_MEMORY TERMINAL_CONTAINER_DISK TERMINAL_CONTAINER_PERSISTENT TERMINAL_SANDBOX_DIR TERMINAL_SSH_HOST TERMINAL_SSH_USER TERMINAL_SSH_PORT TERMINAL_SSH_KEY SUDO_PASSWORD \
  WEB_TOOLS_DEBUG VISION_TOOLS_DEBUG MOA_TOOLS_DEBUG IMAGE_TOOLS_DEBUG CONTEXT_COMPRESSION_ENABLED CONTEXT_COMPRESSION_THRESHOLD CONTEXT_COMPRESSION_MODEL HERMES_MAX_ITERATIONS HERMES_TOOL_PROGRESS HERMES_TOOL_PROGRESS_MODE
do
  append_if_set "$key"
done

if [[ ! -f "$INIT_MARKER" ]]; then
  date -u +"%Y-%m-%dT%H:%M:%SZ" > "$INIT_MARKER"
  echo "[bootstrap] First-time initialization completed."
else
  echo "[bootstrap] Existing Hermes data found. Skipping one-time init."
fi

if gateway_enabled && [[ -z "${TELEGRAM_ALLOWED_USERS:-}${DISCORD_ALLOWED_USERS:-}${SLACK_ALLOWED_USERS:-}${WECOM_ALLOWED_USERS:-}${WECOM_CALLBACK_ALLOWED_USERS:-}${WEIXIN_ALLOWED_USERS:-}${QQ_ALLOWED_USERS:-}" ]]; then
  if ! is_true "${GATEWAY_ALLOW_ALL_USERS:-}" && ! is_true "${TELEGRAM_ALLOW_ALL_USERS:-}" && ! is_true "${DISCORD_ALLOW_ALL_USERS:-}" && ! is_true "${SLACK_ALLOW_ALL_USERS:-}" && ! is_true "${WECOM_ALLOW_ALL_USERS:-}" && ! is_true "${WECOM_CALLBACK_ALLOW_ALL_USERS:-}" && ! is_true "${WEIXIN_ALLOW_ALL_USERS:-}" && ! is_true "${QQ_ALLOW_ALL_USERS:-}"; then
    echo "[bootstrap] WARNING: No allowlists configured. Gateway defaults to deny-all; use DM pairing or set *_ALLOWED_USERS." >&2
  fi
fi

trap cleanup EXIT
trap 'exit 143' TERM INT

if dashboard_enabled; then
  validate_dashboard_proxy_security
  start_dashboard
fi

if ! dashboard_enabled || dashboard_proxy_enabled; then
  start_status_page
fi

if gateway_enabled; then
  echo "[bootstrap] Starting Hermes gateway..."
  unset MESSAGING_CWD
  hermes gateway &
  GATEWAY_PID=$!
else
  echo "[bootstrap] Gateway disabled."
fi

PIDS=()
if [[ -n "${STATUS_PAGE_PID:-}" ]]; then
  PIDS+=("$STATUS_PAGE_PID")
fi
if [[ -n "${DASHBOARD_PID:-}" ]]; then
  PIDS+=("$DASHBOARD_PID")
fi
if [[ -n "${GATEWAY_PID:-}" ]]; then
  PIDS+=("$GATEWAY_PID")
fi

if [[ "${#PIDS[@]}" -eq 0 ]]; then
  echo "[bootstrap] ERROR: No foreground process started." >&2
  exit 1
fi

wait_for_first_exit "${PIDS[@]}"
