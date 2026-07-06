# Deploy and Host Hermes Agent with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/soothing-eagerness?utm_medium=integration&utm_source=template&utm_campaign=generic)

把 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 部署到 Railway 的一键模板。当前模板默认使用 `Hermes Agent v0.18.0 / v2026.7.1`，适合把 Hermes 作为长期在线的聊天机器人、Web Dashboard 或轻量工作台运行。

## About Hosting Hermes Agent

这个模板使用 Dockerfile 从指定 Hermes Agent tag 构建镜像，在 Railway 上运行 gateway、Dashboard 代理和状态页。模板会把 `/data/.hermes` 作为 Hermes home，建议挂载 Railway Volume 到 `/data`，这样配置、会话、技能和工作区不会在重启后丢失。模型配置通过 Railway Variables 注入，支持自定义 OpenAI 兼容接口、OpenRouter、Anthropic 和 MiniMax。

核心能力：

- Railway 一键部署，使用 Dockerfile 构建 Hermes Agent。
- 持久化 `/data/.hermes`，重启后保留 Hermes 配置、会话和运行时数据。
- 内置 Web Dashboard 代理、登录页和状态页。
- 预构建 Hermes Web UI、TUI 和浏览器终端依赖，减少冷启动时的构建工作。
- 支持 QQ Bot、企业微信 WeCom、个人微信 Weixin、Telegram、Discord、Slack 等 Hermes gateway 平台。

## Why Deploy Hermes Agent on Railway?

Railway 适合托管这类需要长期在线、需要公网入口、又需要少量持久化数据的 agent 服务。使用本模板后，你不需要手动维护服务器、systemd、反向代理和 TLS。Railway 负责构建、部署、日志、域名、环境变量和 Volume，Hermes 负责模型调用、消息平台接入和 Dashboard 交互。

## Common Use Cases

- 部署 QQ、微信、Telegram、Discord 或 Slack 上的长期在线 AI 助手。
- 给团队内部使用一个带登录保护的 Hermes Web Dashboard。
- 在 Railway 上测试自定义 OpenAI 兼容模型接口。
- 为个人自动化、消息转发、工具调用和轻量任务执行提供远程运行环境。
- 使用持久化 Volume 保留 Hermes 会话、技能和工作区。

## Dependencies for Hermes Agent Hosting

模板会在镜像内安装 Hermes Agent、Python 运行环境、Node.js 构建依赖、Hermes Web UI、TUI 和浏览器终端静态资源。运行时主要依赖 Railway 的 Variables、公网域名和 Volume。

### Deployment Dependencies

- Railway workspace 和一个 Railway service。
- GitHub 仓库访问权限，用于从 `wsbjj/hermes-railway-template` 构建。
- 一个模型 provider key，例如 OpenAI 兼容接口、OpenRouter、Anthropic 或 MiniMax。
- 至少一个消息平台凭据，或者开启 Dashboard-only 模式。
- 推荐挂载 Railway Volume 到 `/data`。

## 快速部署

1. 点击上方 **Deploy on Railway**。
2. 选择 workspace，创建项目。
3. 在 Railway Variables 里填入模型和消息平台变量。
4. 绑定持久化 Volume 到 `/data`。
5. 部署完成后打开 Railway 提供的公网域名。

Railway Variables 里不要给值加引号。直接填：

```env
OPENAI_API_KEY=sk-xxx
```

不要填：

```env
OPENAI_API_KEY="sk-xxx"
```

## 最小可用配置

下面是 QQ Bot + 自定义 OpenAI 兼容接口的最小配置。把 `OPENAI_BASE_URL` 换成你的接口地址，`HERMES_MODEL` 换成真实模型 ID。

```env
HERMES_GIT_REF=v2026.7.1
HERMES_HOME=/data/.hermes
HOME=/data

HERMES_INFERENCE_PROVIDER=custom
HERMES_MODEL=your-model-id
OPENAI_BASE_URL=https://your-openai-compatible-endpoint/v1
OPENAI_API_KEY=your-api-key

QQ_APP_ID=your-qq-app-id
QQ_CLIENT_SECRET=your-qq-client-secret
QQ_ALLOWED_USERS=openid_a,openid_b

HERMES_DASHBOARD=1
HERMES_DASHBOARD_PROXY_PASSWORD=change-this-password
```

自定义接口如果只填裸域名，例如 `https://cmdme.cn`，入口脚本会自动归一化为 `https://cmdme.cn/v1`。

## 模型配置

### 自定义 OpenAI 兼容接口

推荐用于 GLM、自建转发服务、聚合 API 或其他 OpenAI-compatible endpoint。

```env
HERMES_INFERENCE_PROVIDER=custom
HERMES_MODEL=glm-5.2
OPENAI_BASE_URL=https://cmdme.cn/v1
OPENAI_API_KEY=your-api-key
```

也可以使用 `CUSTOM_BASE_URL` 和 `CUSTOM_API_KEY`：

```env
HERMES_INFERENCE_PROVIDER=custom
HERMES_MODEL=your-model-id
CUSTOM_BASE_URL=https://your-openai-compatible-endpoint/v1
CUSTOM_API_KEY=your-api-key
```

入口脚本会把自定义接口写入 `/data/.hermes/config.yaml`：

```yaml
model:
  default: your-model-id
  provider: custom
  base_url: https://your-openai-compatible-endpoint/v1
  api_key: ${OPENAI_API_KEY}
```

密钥不会明文写入 `config.yaml`。

### OpenRouter

```env
HERMES_INFERENCE_PROVIDER=openrouter
HERMES_MODEL=openai/gpt-4.1-mini
OPENROUTER_API_KEY=your-openrouter-key
```

### Anthropic

```env
HERMES_INFERENCE_PROVIDER=anthropic
HERMES_MODEL=claude-sonnet-4-5
ANTHROPIC_API_KEY=your-anthropic-key
```

### MiniMax 国际版

```env
HERMES_INFERENCE_PROVIDER=minimax
HERMES_MODEL=MiniMax-M2.7
MINIMAX_API_KEY=your-minimax-key
```

### MiniMax 中国区

```env
HERMES_INFERENCE_PROVIDER=minimax-cn
HERMES_MODEL=MiniMax-M2.7
MINIMAX_CN_API_KEY=your-minimax-cn-key
```

## 消息平台配置

至少配置一个消息平台，或者开启 Dashboard-only 模式。

### QQ Bot

```env
QQ_APP_ID=your-qq-app-id
QQ_CLIENT_SECRET=your-qq-client-secret
QQ_ALLOWED_USERS=openid_a,openid_b
```

### 企业微信 WeCom

```env
WECOM_BOT_ID=your-wecom-bot-id
WECOM_SECRET=your-wecom-secret
WECOM_ALLOWED_USERS=user_a,user_b
```

### 个人微信 Weixin

```env
WEIXIN_ACCOUNT_ID=your-weixin-account-id
WEIXIN_ALLOWED_USERS=wxid_a,wxid_b
```

### Telegram

```env
TELEGRAM_BOT_TOKEN=your-telegram-bot-token
TELEGRAM_ALLOWED_USERS=123456789,987654321
```

### Discord

```env
DISCORD_BOT_TOKEN=your-discord-bot-token
DISCORD_ALLOWED_USERS=123456789012345678
```

### Slack

```env
SLACK_BOT_TOKEN=xoxb-xxx
SLACK_APP_TOKEN=xapp-xxx
SLACK_ALLOWED_USERS=U12345678
```

## Dashboard

默认建议开启 Dashboard，并设置登录密码：

```env
HERMES_DASHBOARD=1
HERMES_DASHBOARD_PROXY_PASSWORD=change-this-password
```

部署后访问 Railway 域名会先进入模板自带登录页。登录后可以访问 Hermes Dashboard、状态页和内置终端。

如果只想运行 Dashboard，不接消息平台：

```env
HERMES_DASHBOARD=1
HERMES_GATEWAY_ENABLED=false
HERMES_DASHBOARD_PROXY_PASSWORD=change-this-password
```

## 示例变量文件

- [examples/railway.qq-custom.env](examples/railway.qq-custom.env): QQ Bot + 自定义 OpenAI 兼容接口。
- [examples/railway.wecom-custom.env](examples/railway.wecom-custom.env): 企业微信 WeCom + 自定义 OpenAI 兼容接口。
- [examples/railway.weixin-custom.env](examples/railway.weixin-custom.env): 个人微信 Weixin + 自定义 OpenAI 兼容接口。
- [examples/railway.qq-minimax.env](examples/railway.qq-minimax.env): QQ Bot + MiniMax 国际版。
- [examples/railway.qq-minimax-cn.env](examples/railway.qq-minimax-cn.env): QQ Bot + MiniMax 中国区。
- [examples/railway.dev-dashboard.env](examples/railway.dev-dashboard.env): Dashboard 调试配置。

## 关键变量

| 变量 | 是否必填 | 说明 |
| --- | --- | --- |
| `HERMES_GIT_REF` | 建议填 | Hermes Agent tag 或 commit，当前建议 `v2026.7.1`。 |
| `HERMES_HOME` | 建议填 | Railway 上建议固定为 `/data/.hermes`。 |
| `HOME` | 建议填 | Railway 上建议固定为 `/data`。 |
| `HERMES_INFERENCE_PROVIDER` | 必填 | `custom`、`openrouter`、`anthropic`、`minimax`、`minimax-cn` 等。 |
| `HERMES_MODEL` | 必填 | 模型 ID。 |
| `OPENAI_BASE_URL` | custom 必填 | OpenAI 兼容接口 base URL。 |
| `OPENAI_API_KEY` | custom 必填 | OpenAI 兼容接口 key。 |
| `CUSTOM_BASE_URL` | custom 可选 | `OPENAI_BASE_URL` 的通用别名。 |
| `CUSTOM_API_KEY` | custom 可选 | `OPENAI_API_KEY` 的通用别名。 |
| `OPENROUTER_API_KEY` | openrouter 必填 | OpenRouter key。 |
| `ANTHROPIC_API_KEY` | anthropic 必填 | Anthropic key。 |
| `MINIMAX_API_KEY` | minimax 必填 | MiniMax 国际版 key。 |
| `MINIMAX_CN_API_KEY` | minimax-cn 必填 | MiniMax 中国区 key。 |
| `HERMES_DASHBOARD_PROXY_PASSWORD` | Dashboard 建议填 | 模板登录页密码。 |
| `HERMES_GATEWAY_ENABLED` | 可选 | 设为 `false` 可关闭消息 gateway，仅保留 Dashboard。 |
| `TERMINAL_CWD` | 可选 | Dashboard 终端默认目录，默认 `/data/workspace`。 |

## Railway Volume

建议给服务挂载一个 Volume：

```text
Mount Path: /data
```

这样 Hermes 的配置、会话、技能、缓存和工作区会持久化。没有 Volume 时服务仍能启动，但每次重新部署都会丢失运行态数据。

## 手动从 GitHub 部署

如果不使用模板按钮，也可以手动创建 Railway 服务：

```text
Railway Dashboard -> New Project -> Deploy from GitHub repo -> wsbjj/hermes-railway-template
```

然后在 Variables 中填入上面的模型和平台配置。

## 本地验证

```powershell
bash -n scripts/entrypoint.sh scripts/smoke-test.sh
bash scripts/smoke-test.sh
python -m py_compile scripts/status_server.py
docker buildx build --check .
```

本地构建镜像：

```powershell
docker build --build-arg HERMES_GIT_REF=v2026.7.1 -t hermes-railway-template .
```

## 更新 Hermes 版本

维护者可以用脚本更新 Railway 构建参数并触发从源码重建：

```powershell
.\scripts\update-hermes-railway.ps1 -Ref v2026.7.1 -Environment dev -Service hermes-railway-template
```

脚本会设置：

```text
HERMES_GIT_REF=REF_VALUE
HERMES_SOURCE_CACHE_BUST=CACHE_BUST_VALUE
```

然后执行 Railway 的 source redeploy。手动等价命令：

```powershell
railway variable set HERMES_GIT_REF=v2026.7.1 HERMES_SOURCE_CACHE_BUST=202607061600 --service hermes-railway-template --environment dev --skip-deploys
railway deployment redeploy --from-source --yes --service hermes-railway-template --environment dev
```

## 发布 Railway 模板

维护者发布或更新 Marketplace 模板：

```powershell
railway templates publish 2e0d2a90-f128-4519-96c4-17ab7b457494 `
  --workspace "Bu Junjie's Projects" `
  --category Bots `
  --description "Deploy Hermes Agent on Railway with Dashboard and messaging bots." `
  --readme-file README.md `
  --json
```

模板链接：

```text
https://railway.com/deploy/soothing-eagerness?utm_medium=integration&utm_source=template&utm_campaign=generic
```

## 常见问题

### 自定义接口返回 `INVALID_API_KEY`

先确认 Railway Variables 中的 key 没有引号。然后确认 `OPENAI_BASE_URL` 是 API base URL，例如：

```env
OPENAI_BASE_URL=https://cmdme.cn/v1
```

最新入口脚本会把 `model.api_key` 写成 `${OPENAI_API_KEY}`，用于避免 Hermes 对非官方自定义域名时找不到 key。

### 日志提示 `run hermes model to configure (api_key)`

重新部署最新模板。入口脚本会从 Railway Variables 同步 `/data/.hermes/config.yaml` 的 `model` 配置，并写入 env 引用形式的 `api_key`。

### 裸域名接口返回 HTML

如果模型日志里出现 HTML doctype，通常是 base URL 指向了网页入口。请使用 `/v1` API 地址。裸域名会自动补 `/v1`，但带路径的地址需要你自己确认是 API endpoint。

### Dashboard 打不开或跳登录

确认已设置：

```env
HERMES_DASHBOARD=1
HERMES_DASHBOARD_PROXY_PASSWORD=change-this-password
```

未登录访问 `/readyz`、`/terminal`、Dashboard API 时会被重定向到登录页，这是预期行为。

### 没有配置消息平台

如果不想接 QQ/微信/Telegram 等平台，需要开启 Dashboard-only：

```env
HERMES_DASHBOARD=1
HERMES_GATEWAY_ENABLED=false
HERMES_DASHBOARD_PROXY_PASSWORD=change-this-password
```

否则入口脚本会要求至少配置一个消息平台。

## 相关链接

- Hermes Agent: https://github.com/NousResearch/hermes-agent
- Hermes 文档: https://github.com/NousResearch/hermes-agent/tree/main/website/docs
- Railway 模板: https://railway.com/deploy/soothing-eagerness?utm_medium=integration&utm_source=template&utm_campaign=generic
