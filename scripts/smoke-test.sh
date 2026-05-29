#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
    "$@" "$ROOT_DIR/scripts/entrypoint.sh" > "$tmp/out.txt" 2>&1

  grep -q "^model:" "$tmp/home/.hermes/config.yaml"
  grep -q "provider: custom" "$tmp/home/.hermes/config.yaml"
  grep -q "default: infini-test-model" "$tmp/home/.hermes/config.yaml"
  grep -q "base_url: https://cloud.infini-ai.com/maas/v1" "$tmp/home/.hermes/config.yaml"
  echo "$name OK"
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
