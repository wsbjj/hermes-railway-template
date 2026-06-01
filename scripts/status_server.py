#!/usr/bin/env python3
"""Tiny public status page for the Railway deployment.

The page intentionally exposes only non-sensitive state. Do not add raw
environment values for tokens, keys, user IDs, or secrets here.
"""

from __future__ import annotations

import html
import base64
import hmac
import http.client
import json
import os
import select
import socket
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit


STARTED_AT = time.time()
HERMES_HOME = Path(os.environ.get("HERMES_HOME", "/data/.hermes"))
HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
}
AUTH_REALM = "Hermes Railway"


def is_set(name: str) -> bool:
    return bool(os.environ.get(name, "").strip())


def dashboard_upstream_url() -> str:
    return os.environ.get("HERMES_DASHBOARD_UPSTREAM_URL", "").strip().rstrip("/")


def dashboard_upstream_host_header() -> str:
    """Host header the upstream dashboard expects.

    Hermes' dashboard validates the Host header against the address it bound
    to, so the proxy must present the upstream netloc (e.g. 127.0.0.1:9119)
    rather than forwarding the original public Railway hostname.
    """
    parsed = urlsplit(dashboard_upstream_url())
    return parsed.netloc


def dashboard_upstream_origin() -> str:
    parsed = urlsplit(dashboard_upstream_url())
    if parsed.scheme and parsed.netloc:
        return f"{parsed.scheme}://{parsed.netloc}"
    return ""


def dashboard_proxy_enabled() -> bool:
    return bool(dashboard_upstream_url())


def dashboard_proxy_username() -> str:
    return (
        os.environ.get("HERMES_DASHBOARD_PROXY_USER")
        or os.environ.get("HERMES_DASHBOARD_USER")
        or "admin"
    )


def dashboard_proxy_password() -> str:
    return (
        os.environ.get("HERMES_DASHBOARD_PROXY_PASSWORD")
        or os.environ.get("HERMES_DASHBOARD_PASSWORD")
        or ""
    )


def status_page_auth_enabled() -> bool:
    return bool(dashboard_proxy_password())


def env_flag_enabled(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    if value is None or not value.strip():
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def status_terminal_enabled() -> bool:
    return status_page_auth_enabled() and env_flag_enabled("STATUS_TERMINAL_ENABLED", True)


def terminal_workspace() -> Path:
    return Path(os.environ.get("TERMINAL_CWD", "/data/workspace"))


def terminal_timeout_seconds() -> float:
    raw_timeout = os.environ.get("TERMINAL_TIMEOUT", "180")
    try:
        timeout = float(raw_timeout)
    except ValueError:
        timeout = 180.0
    return max(1.0, timeout)


def terminal_output_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)


def status_page_auth_required(path: str) -> bool:
    protected_paths = {"/", "/index.html", "/readyz"}
    if status_terminal_enabled():
        protected_paths.add("/terminal")
    return status_page_auth_enabled() and path in protected_paths


def run_terminal_command(command: str) -> dict[str, Any]:
    cwd = terminal_workspace()
    timeout = terminal_timeout_seconds()
    start = time.monotonic()
    cwd.mkdir(parents=True, exist_ok=True)

    try:
        completed = subprocess.run(
            command,
            shell=True,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        duration = round(time.monotonic() - start, 3)
        stdout = terminal_output_text(exc.stdout)
        stderr = terminal_output_text(exc.stderr)
        return {
            "command": command,
            "cwd": str(cwd),
            "exit_code": 124,
            "stdout": stdout,
            "stderr": f"{stderr}\ncommand timed out after {timeout:g}s".lstrip(),
            "duration_seconds": duration,
            "timed_out": True,
        }

    duration = round(time.monotonic() - start, 3)
    return {
        "command": command,
        "cwd": str(cwd),
        "exit_code": completed.returncode,
        "stdout": terminal_output_text(completed.stdout),
        "stderr": terminal_output_text(completed.stderr),
        "duration_seconds": duration,
        "timed_out": False,
    }


def read_model_config() -> dict[str, str]:
    config_path = HERMES_HOME / "config.yaml"
    model: dict[str, str] = {}
    if not config_path.exists():
        return model

    in_model = False
    for raw_line in config_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw_line.rstrip()
        if line == "model:":
            in_model = True
            continue
        if in_model and line and not line.startswith((" ", "\t")):
            break
        if not in_model or ":" not in line:
            continue

        key, value = line.strip().split(":", 1)
        value = value.strip().strip("'\"")
        if key in {"provider", "default", "base_url"} and value:
            model[key] = value

    return model


def platform_state() -> dict[str, bool]:
    return {
        "telegram": is_set("TELEGRAM_BOT_TOKEN"),
        "discord": is_set("DISCORD_BOT_TOKEN"),
        "slack": is_set("SLACK_BOT_TOKEN") and is_set("SLACK_APP_TOKEN"),
        "qqbot": is_set("QQ_APP_ID") and is_set("QQ_CLIENT_SECRET"),
        "wecom": is_set("WECOM_BOT_ID") and is_set("WECOM_SECRET"),
        "wecom_callback": all(
            is_set(name)
            for name in (
                "WECOM_CALLBACK_CORP_ID",
                "WECOM_CALLBACK_CORP_SECRET",
                "WECOM_CALLBACK_AGENT_ID",
                "WECOM_CALLBACK_TOKEN",
                "WECOM_CALLBACK_ENCODING_AES_KEY",
            )
        ),
        "weixin": is_set("WEIXIN_ACCOUNT_ID"),
    }


def status_payload() -> dict[str, Any]:
    model_config = read_model_config()
    provider = os.environ.get("HERMES_INFERENCE_PROVIDER") or model_config.get("provider") or ""
    model_name = (
        os.environ.get("HERMES_MODEL")
        or os.environ.get("MODEL_NAME")
        or model_config.get("default")
        or ""
    )
    base_url_configured = bool(
        os.environ.get("OPENAI_BASE_URL")
        or os.environ.get("CUSTOM_BASE_URL")
        or model_config.get("base_url")
    )

    return {
        "status": "ok",
        "service": "hermes-railway-template",
        "uptime_seconds": round(time.time() - STARTED_AT, 1),
        "railway": {
            "environment": os.environ.get("RAILWAY_ENVIRONMENT_NAME", ""),
            "service": os.environ.get("RAILWAY_SERVICE_NAME", ""),
            "deployment": os.environ.get("RAILWAY_DEPLOYMENT_ID", ""),
        },
        "model": {
            "provider": provider,
            "default": model_name,
            "base_url_configured": base_url_configured,
        },
        "platforms": platform_state(),
        "storage": {
            "hermes_home": str(HERMES_HOME),
            "home_exists": HERMES_HOME.exists(),
            "config_exists": (HERMES_HOME / "config.yaml").exists(),
            "env_exists": (HERMES_HOME / ".env").exists(),
            "workspace": os.environ.get("TERMINAL_CWD", "/data/workspace"),
        },
    }


def enabled_platform_labels(platforms: dict[str, bool]) -> str:
    labels = [name for name, enabled in platforms.items() if enabled]
    return ", ".join(labels) if labels else "none"


def render_html(payload: dict[str, Any]) -> bytes:
    model = payload["model"]
    storage = payload["storage"]
    railway = payload["railway"]
    platforms = payload["platforms"]

    provider = html.escape(model["provider"] or "not configured")
    model_name = html.escape(model["default"] or "not configured")
    env_name = html.escape(railway["environment"] or "unknown")
    service_name = html.escape(railway["service"] or payload["service"])
    hermes_home = html.escape(storage["hermes_home"])
    workspace = html.escape(storage["workspace"])
    platform_text = html.escape(enabled_platform_labels(platforms))
    config_exists = html.escape(str(storage["config_exists"]))
    dashboard_link = (
        '      <a href="/sessions" data-i18n="links.dashboard">dashboard</a>\n'
        if dashboard_proxy_enabled()
        else ""
    )
    terminal_link = (
        '      <a href="/terminal" data-i18n="links.terminal">terminal</a>\n'
        if status_terminal_enabled()
        else ""
    )
    terminal_panel = ""
    if status_terminal_enabled():
        terminal_panel = f"""
    <section class="terminal" id="terminal-panel" aria-label="Terminal">
      <div class="section-head">
        <div>
          <h2 data-i18n="terminal.title">Terminal</h2>
          <p data-i18n="terminal.description">Run shell commands inside the Hermes Railway container.</p>
        </div>
        <span class="terminal-badge" data-i18n="terminal.protected">Password protected</span>
      </div>
      <form id="terminal-form" class="terminal-form">
        <label class="sr-only" for="terminal-command" data-i18n="terminal.commandLabel">Command</label>
        <input id="terminal-command" name="command" type="text" autocomplete="off" spellcheck="false" value="hermes --help">
        <button type="submit" data-i18n="terminal.run">Run</button>
      </form>
      <pre id="terminal-output" class="terminal-output" aria-live="polite" data-terminal-placeholder="terminal.placeholder" data-placeholder-visible="true">Command output will appear here.</pre>
      <div class="terminal-meta">
        <span data-i18n="terminal.cwdLabel">cwd</span>
        <code>{workspace}</code>
      </div>
    </section>
"""
    translations = {
        "en": {
            "intro": "Gateway worker is running. Chat still happens through QQ Bot, WeCom, Weixin, or other configured platforms.",
            "status.online": "Online",
            "labels.service": "Railway service",
            "labels.environment": "Environment",
            "labels.provider": "Provider",
            "labels.model": "Model",
            "labels.platforms": "Messaging platforms",
            "labels.home": "Hermes home",
            "labels.config": "Config file",
            "labels.workspace": "Workspace",
            "links.dashboard": "dashboard",
            "links.terminal": "terminal",
            "terminal.title": "Terminal",
            "terminal.description": "Run shell commands inside the Hermes Railway container.",
            "terminal.protected": "Password protected",
            "terminal.commandLabel": "Command",
            "terminal.run": "Run",
            "terminal.running": "Running...",
            "terminal.placeholder": "Command output will appear here.",
            "terminal.cwdLabel": "cwd",
            "terminal.authError": "Authentication required. Refresh the page and sign in again.",
            "terminal.requestError": "Command request failed.",
        },
        "zh": {
            "intro": "网关服务正在运行。聊天仍然通过 QQ Bot、企业微信、微信或其他已配置平台进行。",
            "status.online": "在线",
            "labels.service": "Railway 服务",
            "labels.environment": "环境",
            "labels.provider": "模型提供方",
            "labels.model": "模型",
            "labels.platforms": "消息平台",
            "labels.home": "Hermes 目录",
            "labels.config": "配置文件",
            "labels.workspace": "工作目录",
            "links.dashboard": "控制台",
            "links.terminal": "终端",
            "terminal.title": "终端",
            "terminal.description": "在 Hermes Railway 容器内执行 shell 命令。",
            "terminal.protected": "密码保护",
            "terminal.commandLabel": "命令",
            "terminal.run": "运行",
            "terminal.running": "正在运行...",
            "terminal.placeholder": "命令输出会显示在这里。",
            "terminal.cwdLabel": "工作目录",
            "terminal.authError": "需要重新登录。请刷新页面并输入密码。",
            "terminal.requestError": "命令请求失败。",
        },
    }
    translations_json = json.dumps(translations, ensure_ascii=False)

    html_text = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Hermes Railway Status</title>
  <style>
    :root {{
      color-scheme: light;
      --bg: #f7f8fa;
      --panel: #ffffff;
      --text: #172033;
      --muted: #667085;
      --line: #d8dee8;
      --ok: #16a34a;
      --accent: #2563eb;
      --terminal-bg: #111827;
      --terminal-text: #d1fae5;
      --terminal-muted: #9ca3af;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      min-height: 100vh;
      background: var(--bg);
      color: var(--text);
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.5;
    }}
    main {{
      width: min(960px, calc(100vw - 32px));
      margin: 0 auto;
      padding: 48px 0;
    }}
    .topbar {{
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 20px;
      margin-bottom: 8px;
    }}
    h1 {{ margin: 0 0 8px; font-size: clamp(28px, 5vw, 44px); letter-spacing: 0; }}
    h2 {{ margin: 0 0 4px; font-size: 20px; letter-spacing: 0; }}
    p {{ color: var(--muted); margin: 0; }}
    .language-toggle {{
      display: inline-flex;
      gap: 4px;
      padding: 4px;
      border: 1px solid var(--line);
      border-radius: 999px;
      background: var(--panel);
    }}
    .language-toggle button {{
      border: 0;
      border-radius: 999px;
      background: transparent;
      color: var(--muted);
      cursor: pointer;
      font-weight: 700;
      padding: 6px 10px;
    }}
    .language-toggle button.active {{
      background: var(--text);
      color: #fff;
    }}
    .status {{
      display: inline-flex;
      align-items: center;
      gap: 10px;
      margin: 24px 0;
      padding: 10px 14px;
      border: 1px solid rgba(22, 163, 74, 0.28);
      border-radius: 999px;
      color: var(--ok);
      background: rgba(22, 163, 74, 0.08);
      font-weight: 700;
    }}
    .dot {{ width: 10px; height: 10px; border-radius: 50%; background: var(--ok); }}
    .grid {{ display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }}
    .card {{ padding: 18px; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); }}
    .label {{ color: var(--muted); font-size: 13px; }}
    .value {{ margin-top: 6px; font-weight: 700; overflow-wrap: anywhere; }}
    .links {{ display: flex; gap: 12px; margin-top: 24px; flex-wrap: wrap; }}
    a {{ color: var(--text); text-decoration: none; border-bottom: 1px solid var(--accent); }}
    .section-head {{
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 16px;
      margin-bottom: 16px;
    }}
    .terminal {{
      margin-top: 26px;
      padding: 18px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
    }}
    .terminal-badge {{
      white-space: nowrap;
      color: var(--accent);
      background: rgba(37, 99, 235, 0.08);
      border: 1px solid rgba(37, 99, 235, 0.18);
      border-radius: 999px;
      font-size: 12px;
      font-weight: 800;
      padding: 6px 10px;
    }}
    .terminal-form {{
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 10px;
      margin-bottom: 12px;
    }}
    .terminal-form input {{
      width: 100%;
      border: 1px solid var(--line);
      border-radius: 8px;
      color: var(--text);
      font: 600 14px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      padding: 12px;
    }}
    .terminal-form button {{
      border: 0;
      border-radius: 8px;
      background: var(--accent);
      color: #fff;
      cursor: pointer;
      font-weight: 800;
      min-width: 84px;
      padding: 0 16px;
    }}
    .terminal-form button:disabled {{ cursor: wait; opacity: 0.68; }}
    .terminal-output {{
      min-height: 260px;
      max-height: 520px;
      overflow: auto;
      margin: 0;
      padding: 16px;
      border-radius: 8px;
      background: var(--terminal-bg);
      color: var(--terminal-text);
      font: 13px/1.55 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      white-space: pre-wrap;
      overflow-wrap: anywhere;
    }}
    .terminal-meta {{
      display: flex;
      gap: 8px;
      align-items: center;
      color: var(--muted);
      font-size: 13px;
      margin-top: 10px;
      overflow-wrap: anywhere;
    }}
    .terminal-meta code {{ color: var(--text); font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }}
    .sr-only {{
      position: absolute;
      width: 1px;
      height: 1px;
      padding: 0;
      margin: -1px;
      overflow: hidden;
      clip: rect(0, 0, 0, 0);
      white-space: nowrap;
      border: 0;
    }}
    @media (max-width: 720px) {{
      main {{ padding: 22px; }}
      .topbar, .section-head {{ flex-direction: column; }}
      .grid {{ grid-template-columns: 1fr; }}
      .terminal-form {{ grid-template-columns: 1fr; }}
      .terminal-form button {{ min-height: 44px; }}
    }}
  </style>
</head>
<body>
  <main>
    <div class="topbar">
      <div>
        <h1>Hermes Railway</h1>
        <p data-i18n="intro">Gateway worker is running. Chat still happens through QQ Bot, WeCom, Weixin, or other configured platforms.</p>
      </div>
      <div class="language-toggle" aria-label="Language">
        <button type="button" data-language-toggle="en" class="active">EN</button>
        <button type="button" data-language-toggle="zh">中文</button>
      </div>
    </div>
    <div class="status"><span class="dot"></span> <span data-i18n="status.online">Online</span></div>
    <section class="grid" aria-label="Deployment status">
      <div class="card"><div class="label" data-i18n="labels.service">Railway service</div><div class="value">{service_name}</div></div>
      <div class="card"><div class="label" data-i18n="labels.environment">Environment</div><div class="value">{env_name}</div></div>
      <div class="card"><div class="label" data-i18n="labels.provider">Provider</div><div class="value">{provider}</div></div>
      <div class="card"><div class="label" data-i18n="labels.model">Model</div><div class="value">{model_name}</div></div>
      <div class="card"><div class="label" data-i18n="labels.platforms">Messaging platforms</div><div class="value">{platform_text}</div></div>
      <div class="card"><div class="label" data-i18n="labels.home">Hermes home</div><div class="value">{hermes_home}</div></div>
      <div class="card"><div class="label" data-i18n="labels.config">Config file</div><div class="value">{config_exists}</div></div>
      <div class="card"><div class="label" data-i18n="labels.workspace">Workspace</div><div class="value">{workspace}</div></div>
    </section>
{terminal_panel.rstrip()}
    <div class="links">
      <a href="/healthz">healthz</a>
      <a href="/readyz">readyz</a>
{dashboard_link.rstrip()}
{terminal_link.rstrip()}
    </div>
  </main>
  <script>
    const translations = {translations_json};
    const fallbackLanguage = "en";

    function translate(key, language) {{
      const dict = translations[language] || translations[fallbackLanguage];
      return dict[key] || translations[fallbackLanguage][key] || key;
    }}

    function applyLanguage(language) {{
      const selected = translations[language] ? language : fallbackLanguage;
      document.documentElement.lang = selected === "zh" ? "zh-CN" : "en";
      document.querySelectorAll("[data-i18n]").forEach((node) => {{
        node.textContent = translate(node.dataset.i18n, selected);
      }});
      const terminalOutput = document.getElementById("terminal-output");
      if (terminalOutput && terminalOutput.dataset.placeholderVisible === "true") {{
        terminalOutput.textContent = translate(terminalOutput.dataset.terminalPlaceholder, selected);
      }}
      document.querySelectorAll("[data-language-toggle]").forEach((button) => {{
        button.classList.toggle("active", button.dataset.languageToggle === selected);
      }});
      window.localStorage.setItem("hermes-status-language", selected);
    }}

    function formatTerminalResult(result) {{
      const lines = ["$ " + result.command, ""];
      if (result.stdout) {{
        lines.push(result.stdout.trimEnd());
      }}
      if (result.stderr) {{
        lines.push("", "[stderr]", result.stderr.trimEnd());
      }}
      lines.push(
        "",
        "Exit code: " + result.exit_code +
          " | Duration: " + result.duration_seconds + "s" +
          " | CWD: " + result.cwd
      );
      return lines.join("\\n");
    }}

    function terminalApiUrl() {{
      const url = new URL("/api/terminal/run", window.location.href);
      url.username = "";
      url.password = "";
      return url.toString();
    }}

    const initialLanguage = window.localStorage.getItem("hermes-status-language") || fallbackLanguage;
    applyLanguage(initialLanguage);

    document.querySelectorAll("[data-language-toggle]").forEach((button) => {{
      button.addEventListener("click", () => applyLanguage(button.dataset.languageToggle));
    }});

    const terminalForm = document.getElementById("terminal-form");
    if (terminalForm) {{
      const commandInput = document.getElementById("terminal-command");
      const output = document.getElementById("terminal-output");
      const runButton = terminalForm.querySelector("button[type='submit']");

      terminalForm.addEventListener("submit", async (event) => {{
        event.preventDefault();
        const language = document.documentElement.lang === "zh-CN" ? "zh" : "en";
        const command = commandInput.value.trim();
        if (!command) {{
          commandInput.focus();
          return;
        }}

        runButton.disabled = true;
        output.dataset.placeholderVisible = "false";
        runButton.textContent = translate("terminal.running", language);
        output.textContent = "$ " + command + "\\n\\n" + translate("terminal.running", language);

        try {{
          const response = await fetch(terminalApiUrl(), {{
            method: "POST",
            headers: {{"Content-Type": "application/json"}},
            body: JSON.stringify({{command}})
          }});
          if (response.status === 401) {{
            output.textContent = translate("terminal.authError", language);
            return;
          }}
          if (!response.ok) {{
            output.textContent = translate("terminal.requestError", language) + " (" + response.status + ")";
            return;
          }}
          output.textContent = formatTerminalResult(await response.json());
        }} catch (error) {{
          output.textContent = translate("terminal.requestError", language) + "\\n" + error;
        }} finally {{
          runButton.disabled = false;
          runButton.textContent = translate("terminal.run", language);
        }}
      }});
    }}
  </script>
</body>
</html>
"""
    return html_text.encode("utf-8")


class StatusHandler(BaseHTTPRequestHandler):
    server_version = "HermesStatus/1.0"

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        self.handle_request()

    def do_HEAD(self) -> None:  # noqa: N802 - stdlib handler API
        self.handle_request()

    def do_POST(self) -> None:  # noqa: N802 - stdlib handler API
        self.handle_request()

    def do_PUT(self) -> None:  # noqa: N802 - stdlib handler API
        self.handle_request()

    def do_PATCH(self) -> None:  # noqa: N802 - stdlib handler API
        self.handle_request()

    def do_DELETE(self) -> None:  # noqa: N802 - stdlib handler API
        self.handle_request()

    def do_OPTIONS(self) -> None:  # noqa: N802 - stdlib handler API
        self.handle_request()

    def handle_request(self) -> None:
        path = self.path.split("?", 1)[0]

        if path in {"/terminal", "/api/terminal/run"} and not status_terminal_enabled():
            self.respond(404, "text/plain; charset=utf-8", b"not found\n")
            return

        if path == "/api/terminal/run":
            self.handle_terminal_run()
            return

        if self.command in {"GET", "HEAD"} and status_page_auth_required(path):
            if not self.has_valid_proxy_auth():
                self.request_proxy_auth()
                return

        if self.command in {"GET", "HEAD"} and path in {"/", "/index.html", "/terminal"}:
            payload = status_payload()
            self.respond(200, "text/html; charset=utf-8", render_html(payload))
            return

        if self.command in {"GET", "HEAD"} and path == "/healthz":
            self.respond(200, "text/plain; charset=utf-8", b"ok\n")
            return

        if self.command in {"GET", "HEAD"} and path == "/readyz":
            payload = status_payload()
            body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
            self.respond(200, "application/json; charset=utf-8", body)
            return

        if dashboard_proxy_enabled():
            self.proxy_dashboard()
            return

        self.respond(404, "text/plain; charset=utf-8", b"not found\n")

    def respond(self, status: int, content_type: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def respond_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.respond(status, "application/json; charset=utf-8", body)

    def handle_terminal_run(self) -> None:
        if not self.has_valid_proxy_auth():
            self.request_proxy_auth()
            return

        if self.command != "POST":
            self.send_response(405)
            self.send_header("Allow", "POST")
            self.send_header("Content-Length", "0")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            return

        try:
            content_length = int(self.headers.get("Content-Length") or "0")
        except ValueError:
            self.respond_json(400, {"error": "invalid content length"})
            return

        if content_length <= 0:
            self.respond_json(400, {"error": "missing JSON body"})
            return
        if content_length > 65536:
            self.respond_json(413, {"error": "request body too large"})
            return

        raw_body = self.rfile.read(content_length)
        try:
            data = json.loads(raw_body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self.respond_json(400, {"error": "invalid JSON body"})
            return

        command = data.get("command") if isinstance(data, dict) else None
        if not isinstance(command, str) or not command.strip():
            self.respond_json(400, {"error": "command must be a non-empty string"})
            return

        try:
            result = run_terminal_command(command)
        except Exception as exc:  # noqa: BLE001 - return a safe terminal error
            self.respond_json(500, {"error": f"terminal execution failed: {exc}"})
            return

        self.respond_json(200, result)

    def proxy_dashboard(self) -> None:
        if not dashboard_proxy_password():
            self.respond(
                503,
                "text/plain; charset=utf-8",
                b"dashboard proxy password is not configured\n",
            )
            return

        if not self.has_valid_proxy_auth():
            self.request_proxy_auth()
            return

        if self.headers.get("Upgrade", "").lower() == "websocket":
            self.proxy_dashboard_websocket()
            return

        self.proxy_dashboard_http()

    def has_valid_proxy_auth(self) -> bool:
        auth_header = self.headers.get("Authorization", "").strip()
        expected = "Basic " + base64.b64encode(
            f"{dashboard_proxy_username()}:{dashboard_proxy_password()}".encode("utf-8")
        ).decode("ascii")
        return hmac.compare_digest(auth_header, expected)

    def request_proxy_auth(self) -> None:
        body = b"authentication required\n"
        self.send_response(401)
        self.send_header(
            "WWW-Authenticate",
            f'Basic realm="{AUTH_REALM}", charset="UTF-8"',
        )
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def dashboard_target(self) -> tuple[str, int, str]:
        parsed = urlsplit(dashboard_upstream_url())
        if parsed.scheme != "http" or not parsed.hostname:
            raise ValueError("HERMES_DASHBOARD_UPSTREAM_URL must be an http URL")

        base_path = parsed.path.rstrip("/")
        target = f"{base_path}{self.path}" if base_path else self.path
        return parsed.hostname, parsed.port or 80, target

    def proxy_headers(self) -> dict[str, str]:
        headers: dict[str, str] = {}
        original_host = self.headers.get("Host", "")
        for key, value in self.headers.items():
            lower = key.lower()
            if lower in HOP_BY_HOP_HEADERS or lower == "authorization":
                continue
            # Rewrite Host to the upstream netloc. The dashboard rejects any
            # Host that does not match the address it bound to.
            if lower == "host":
                continue
            headers[key] = value

        upstream_host = dashboard_upstream_host_header()
        if upstream_host:
            headers["Host"] = upstream_host

        client_host = self.client_address[0] if self.client_address else ""
        forwarded_for = self.headers.get("X-Forwarded-For", "")
        headers["X-Forwarded-For"] = (
            f"{forwarded_for}, {client_host}" if forwarded_for and client_host else client_host
        )
        headers["X-Forwarded-Host"] = original_host
        headers["X-Forwarded-Proto"] = self.headers.get("X-Forwarded-Proto", "http")
        return headers

    def proxy_dashboard_http(self) -> None:
        conn: http.client.HTTPConnection | None = None
        try:
            host, port, target = self.dashboard_target()
            content_length = int(self.headers.get("Content-Length") or "0")
            body = self.rfile.read(content_length) if content_length > 0 else None

            conn = http.client.HTTPConnection(host, port, timeout=30)
            conn.request(self.command, target, body=body, headers=self.proxy_headers())
            response = conn.getresponse()
            response_body = response.read()
        except Exception as exc:  # noqa: BLE001 - return a safe public error
            self.respond(
                502,
                "text/plain; charset=utf-8",
                f"dashboard upstream unavailable: {exc}\n".encode("utf-8"),
            )
            return
        finally:
            if conn is not None:
                conn.close()

        self.send_response(response.status, response.reason)
        for key, value in response.getheaders():
            lower = key.lower()
            if lower in HOP_BY_HOP_HEADERS or lower in {"content-length", "server", "date"}:
                continue
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(response_body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(response_body)

    def proxy_dashboard_websocket(self) -> None:
        self.close_connection = True
        upstream: socket.socket | None = None
        try:
            host, port, target = self.dashboard_target()
            upstream = socket.create_connection((host, port), timeout=30)
            upstream.sendall(self.websocket_request_bytes(target))
            self.relay_sockets(upstream)
        except Exception:
            if upstream is None:
                self.respond(502, "text/plain; charset=utf-8", b"dashboard websocket unavailable\n")
        finally:
            if upstream is not None:
                upstream.close()

    def websocket_request_bytes(self, target: str) -> bytes:
        upstream_host = dashboard_upstream_host_header()
        upstream_origin = dashboard_upstream_origin()
        original_host = self.headers.get("Host", "")
        original_origin = self.headers.get("Origin", "")
        lines = [f"{self.command} {target} {self.request_version}\r\n"]
        for key, value in self.headers.items():
            lower = key.lower()
            if lower == "authorization":
                continue
            # Rewrite Host so the dashboard's Host validation accepts the
            # upgrade request; the original public host is preserved below.
            if lower in {"host", "origin", "x-forwarded-host", "x-forwarded-proto"}:
                continue
            lines.append(f"{key}: {value}\r\n")
        if upstream_host:
            lines.append(f"Host: {upstream_host}\r\n")
            lines.append(f"X-Forwarded-Host: {original_host}\r\n")
        if upstream_origin:
            # FastAPI HTTP middleware does not run for WebSocket upgrades;
            # Hermes repeats its Host/Origin guard in the WS route.
            lines.append(f"Origin: {upstream_origin}\r\n")
        forwarded_proto = self.headers.get("X-Forwarded-Proto", "")
        if not forwarded_proto and original_origin:
            forwarded_proto = urlsplit(original_origin).scheme
        if forwarded_proto:
            lines.append(f"X-Forwarded-Proto: {forwarded_proto}\r\n")
        lines.append("\r\n")
        return "".join(lines).encode("iso-8859-1")

    def relay_sockets(self, upstream: socket.socket) -> None:
        sockets = [self.connection, upstream]
        for sock in sockets:
            sock.settimeout(None)

        while True:
            readable, _, _ = select.select(sockets, [], [], 60)
            for source in readable:
                data = source.recv(65536)
                if not data:
                    return
                target = upstream if source is self.connection else self.connection
                target.sendall(data)

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002 - stdlib name
        return


def main() -> None:
    host = os.environ.get("STATUS_PAGE_HOST", "0.0.0.0")
    port = int(os.environ.get("PORT") or os.environ.get("STATUS_PAGE_PORT") or "8080")
    httpd = ThreadingHTTPServer((host, port), StatusHandler)
    print(f"[status] Listening on {host}:{port}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
