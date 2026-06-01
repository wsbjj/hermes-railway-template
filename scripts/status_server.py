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
    dashboard_link = '      <a href="/sessions">dashboard</a>\n' if dashboard_proxy_enabled() else ""

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
    h1 {{ margin: 0 0 8px; font-size: clamp(28px, 5vw, 44px); letter-spacing: 0; }}
    p {{ color: var(--muted); margin: 0; }}
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
    @media (max-width: 720px) {{ main {{ padding: 22px; }} .grid {{ grid-template-columns: 1fr; }} }}
  </style>
</head>
<body>
  <main>
    <h1>Hermes Railway</h1>
    <p>Gateway worker is running. Chat still happens through QQ Bot, WeCom, Weixin, or other configured platforms.</p>
    <div class="status"><span class="dot"></span> Online</div>
    <section class="grid" aria-label="Deployment status">
      <div class="card"><div class="label">Railway service</div><div class="value">{service_name}</div></div>
      <div class="card"><div class="label">Environment</div><div class="value">{env_name}</div></div>
      <div class="card"><div class="label">Provider</div><div class="value">{provider}</div></div>
      <div class="card"><div class="label">Model</div><div class="value">{model_name}</div></div>
      <div class="card"><div class="label">Messaging platforms</div><div class="value">{platform_text}</div></div>
      <div class="card"><div class="label">Hermes home</div><div class="value">{hermes_home}</div></div>
      <div class="card"><div class="label">Config file</div><div class="value">{storage["config_exists"]}</div></div>
      <div class="card"><div class="label">Workspace</div><div class="value">{workspace}</div></div>
    </section>
    <div class="links">
      <a href="/healthz">healthz</a>
      <a href="/readyz">readyz</a>
{dashboard_link.rstrip()}
    </div>
  </main>
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

        if self.command in {"GET", "HEAD"} and path in {"/", "/index.html"}:
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

    def proxy_dashboard(self) -> None:
        if not dashboard_proxy_password():
            self.respond(
                503,
                "text/plain; charset=utf-8",
                b"dashboard proxy password is not configured\n",
            )
            return

        if not self.has_valid_dashboard_auth():
            self.request_dashboard_auth()
            return

        if self.headers.get("Upgrade", "").lower() == "websocket":
            self.proxy_dashboard_websocket()
            return

        self.proxy_dashboard_http()

    def has_valid_dashboard_auth(self) -> bool:
        auth_header = self.headers.get("Authorization", "").strip()
        expected = "Basic " + base64.b64encode(
            f"{dashboard_proxy_username()}:{dashboard_proxy_password()}".encode("utf-8")
        ).decode("ascii")
        return hmac.compare_digest(auth_header, expected)

    def request_dashboard_auth(self) -> None:
        body = b"authentication required\n"
        self.send_response(401)
        self.send_header(
            "WWW-Authenticate",
            'Basic realm="Hermes Dashboard", charset="UTF-8"',
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
        lines = [f"{self.command} {target} {self.request_version}\r\n"]
        for key, value in self.headers.items():
            lower = key.lower()
            if lower == "authorization":
                continue
            # Rewrite Host so the dashboard's Host validation accepts the
            # upgrade request; the original public host is preserved below.
            if lower == "host":
                continue
            lines.append(f"{key}: {value}\r\n")
        if upstream_host:
            lines.append(f"Host: {upstream_host}\r\n")
            lines.append(f"X-Forwarded-Host: {self.headers.get('Host', '')}\r\n")
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
