FROM node:22-bookworm-slim AS node


FROM python:3.11-slim-bookworm AS builder

ARG HERMES_GIT_REF=v2026.5.29

COPY --from=node /usr/local /usr/local
ENV PATH="/usr/local/bin:${PATH}"

RUN apt-get update -o Acquire::Retries=3 \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN test -n "${HERMES_GIT_REF}" \
  && git init /opt/hermes-agent \
  && git -C /opt/hermes-agent remote add origin https://github.com/NousResearch/hermes-agent.git \
  && git -C /opt/hermes-agent fetch --depth 1 origin "${HERMES_GIT_REF}" \
  && git -C /opt/hermes-agent checkout --detach FETCH_HEAD \
  && git -C /opt/hermes-agent submodule update --init --recursive --depth 1

COPY patches/ /tmp/hermes-patches/
RUN for patch in /tmp/hermes-patches/*.patch; do git -C /opt/hermes-agent apply --unidiff-zero "$patch"; done

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

RUN pip install --no-cache-dir --upgrade pip setuptools wheel
RUN pip install --no-cache-dir websockets -e "/opt/hermes-agent[messaging,cron,cli,pty,web]"

RUN cd /opt/hermes-agent/web \
  && npm ci \
  && npm run build \
  && rm -rf node_modules /root/.npm

RUN xterm_tgz="$(npm pack --silent @xterm/xterm@5.5.0 --pack-destination /tmp)" \
  && mkdir -p /tmp/xterm-package /opt/hermes-agent/hermes_railway_static/xterm \
  && tar -xzf "/tmp/${xterm_tgz}" -C /tmp/xterm-package --strip-components=1 \
  && cp /tmp/xterm-package/lib/xterm.js /opt/hermes-agent/hermes_railway_static/xterm/xterm.js \
  && cp /tmp/xterm-package/css/xterm.css /opt/hermes-agent/hermes_railway_static/xterm/xterm.css \
  && rm -rf /tmp/xterm-package "/tmp/${xterm_tgz}" /root/.npm

RUN cd /opt/hermes-agent/ui-tui \
  && npm ci \
  && npm run build \
  && mkdir -p /opt/hermes-agent/hermes_cli/tui_dist \
  && cp dist/entry.js /opt/hermes-agent/hermes_cli/tui_dist/entry.js \
  && cp package.json /opt/hermes-agent/hermes_cli/tui_dist/package.json \
  && rm -rf node_modules /root/.npm


FROM python:3.11-slim-bookworm

COPY --from=node /usr/local /usr/local

RUN apt-get update -o Acquire::Retries=3 \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gh \
    procps \
    tzdata \
    tini \
  && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/venv/bin:/usr/local/bin:${PATH}" \
  PYTHONUNBUFFERED=1 \
  HERMES_HOME=/data/.hermes \
  HOME=/data

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /opt/hermes-agent /opt/hermes-agent

WORKDIR /app
COPY scripts/ /app/scripts/
RUN chmod +x /app/scripts/entrypoint.sh

ENTRYPOINT ["tini", "--"]
CMD ["/app/scripts/entrypoint.sh"]
