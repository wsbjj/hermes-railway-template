# Hermes Agent Railway 模板

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/hermes-railway-template?referralCode=uTN7AS&utm_medium=integration&utm_source=template&utm_campaign=generic)

把 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 部署到 Railway，作为带持久化状态的 Worker 服务运行。

这个模板只负责 Worker 运行时：初始化和配置都通过 Railway Variables 完成，容器首次启动时会自动引导 Hermes。

## 你会得到什么

- 在 Railway Worker 中运行的 Hermes gateway
- 首次启动时根据环境变量自动初始化
- 通过 Railway Volume 持久化 Hermes 状态，挂载路径为 `/data`
- 支持 Telegram、Discord、Slack、QQ Bot、个人微信 Weixin、企业微信 WeCom 等消息平台

## 工作方式

1. 在 Railway 中配置必需变量。
2. 首次启动时，入口脚本会在 `/data/.hermes` 下初始化 Hermes。
3. 后续重启会复用同一份持久化状态。
4. 容器启动 `hermes gateway`。

## Railway 部署步骤

在 Railway Template Composer 中：

1. 添加一个 Volume，并挂载到 `/data`。
2. 以 Worker 服务方式部署。
3. 配置下方列出的环境变量。

模板默认值已经写在 `railway.toml` 中：

- `HERMES_HOME=/data/.hermes`
- `HOME=/data`

Hermes 终端会话默认工作目录为 `/data/workspace`，该配置会写入 `${HERMES_HOME}/config.yaml`。

## 默认环境变量

模板默认按 Telegram + OpenRouter 场景展示。部署时可先填写这些变量：

```env
HERMES_GIT_REF="v2026.5.29"
OPENROUTER_API_KEY=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_ALLOWED_USERS=""
```

部署后也可以继续在 Railway 服务的 Variables 中新增或修改变量。
最新支持的变量和行为以 Hermes 上游文档为准：

- https://github.com/NousResearch/hermes-agent
- https://github.com/NousResearch/hermes-agent/blob/main/README.md

## 必需运行时变量

你至少需要配置一个模型提供方：

- `OPENROUTER_API_KEY`
- `CUSTOM_BASE_URL` 加上该提供方对应的 API key 环境变量
- `OPENAI_BASE_URL` + `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `MINIMAX_API_KEY`
- `MINIMAX_CN_API_KEY`

你至少需要配置一个消息平台：

- Telegram：`TELEGRAM_BOT_TOKEN`
- Discord：`DISCORD_BOT_TOKEN`
- Slack：`SLACK_BOT_TOKEN` 和 `SLACK_APP_TOKEN`
- 企业微信 WeCom：`WECOM_BOT_ID` 和 `WECOM_SECRET`
- 企业微信回调模式 WeCom callback：`WECOM_CALLBACK_CORP_ID`、`WECOM_CALLBACK_CORP_SECRET`、`WECOM_CALLBACK_AGENT_ID`、`WECOM_CALLBACK_TOKEN`、`WECOM_CALLBACK_ENCODING_AES_KEY`
- 个人微信 Weixin / WeChat：`WEIXIN_ACCOUNT_ID` 加上已持久化的扫码登录状态，或 `WEIXIN_ACCOUNT_ID` + `WEIXIN_TOKEN`
- QQ Bot：`QQ_APP_ID` 和 `QQ_CLIENT_SECRET`

强烈建议配置 allowlist：

- `TELEGRAM_ALLOWED_USERS`
- `DISCORD_ALLOWED_USERS`
- `SLACK_ALLOWED_USERS`
- `WECOM_ALLOWED_USERS`
- `WECOM_CALLBACK_ALLOWED_USERS`
- `WEIXIN_ALLOWED_USERS`
- `QQ_ALLOWED_USERS`

allowlist 使用英文逗号分隔，不要加中括号或引号：

- `TELEGRAM_ALLOWED_USERS=123456789,987654321`
- `DISCORD_ALLOWED_USERS=123456789012345678,234567890123456789`
- `SLACK_ALLOWED_USERS=U01234ABCDE,U09876WXYZ`
- `QQ_ALLOWED_USERS=openid_a,openid_b`
- `WEIXIN_ALLOWED_USERS=wxid_a,wxid_b`

请使用 `123,456,789` 这种普通逗号分隔格式。
不要写成 JSON 或带引号数组，例如 `[123,456]` 或 `"123","456"`。

可选全局控制：

- `GATEWAY_ALLOW_ALL_USERS=true`（不推荐）

## 模型提供方选择

如果你同时配置了多个 provider 的 key，建议显式设置 `HERMES_INFERENCE_PROVIDER`，例如 `openrouter`，避免自动选择到不想用的 provider。

OpenAI 兼容的自定义接口建议这样配置：

```env
HERMES_INFERENCE_PROVIDER=custom
CUSTOM_BASE_URL=https://your-openai-compatible-endpoint/v1
```

模板会在启动时把旧写法 `OPENAI_BASE_URL` 映射到 `CUSTOM_BASE_URL`。如果你使用无问芯穹 / InfiniAI（`cloud.infini-ai.com`），建议设置 `INFINI_AI_API_KEY`；如果只设置了 `OPENAI_API_KEY`，模板会为了兼容性自动复制到 `INFINI_AI_API_KEY`。

无问芯穹示例：

```env
HERMES_INFERENCE_PROVIDER=custom
CUSTOM_BASE_URL=https://cloud.infini-ai.com/maas/v1
INFINI_AI_API_KEY=your-key
```

MiniMax 国际版示例：

```env
HERMES_INFERENCE_PROVIDER=minimax
MINIMAX_API_KEY=your-key
```

MiniMax 中国区示例：

```env
HERMES_INFERENCE_PROVIDER=minimax-cn
MINIMAX_CN_API_KEY=your-key
```

## Railway 上使用 QQ Bot / 微信

Hermes 支持 QQ Bot、个人微信 Weixin / WeChat、企业微信 WeCom，但它们的部署方式不一样：

- QQ Bot 使用腾讯官方 QQ Bot API v2，通过 WebSocket 连接。你需要在 `q.qq.com` 注册应用、开启所需 intents，然后在 Railway Variables 中设置 `QQ_APP_ID` 和 `QQ_CLIENT_SECRET`。
- 企业微信 WeCom 通常是 Railway 上更稳的腾讯系聊天入口，因为它使用 AI Bot WebSocket，不需要公网回调地址。设置 `WECOM_BOT_ID` 和 `WECOM_SECRET` 即可。
- 企业微信回调模式需要公网 callback URL。如果在 Railway 上使用，需要给服务暴露公网域名，并在企业微信后台配置 callback path。
- 个人微信 Weixin / WeChat 使用 iLink 扫码登录。需要通过 Railway SSH 运行一次 `hermes gateway setup`，扫码后把凭据持久化到 `/data/.hermes`，之后保留 `WEIXIN_ACCOUNT_ID`。普通微信群是否可用取决于 iLink 是否向该账号类型推送群事件，私聊更可靠。

QQ Bot + 无问芯穹示例：

```env
HERMES_INFERENCE_PROVIDER=custom
CUSTOM_BASE_URL=https://cloud.infini-ai.com/maas/v1
INFINI_AI_API_KEY=your-key

QQ_APP_ID=your-qq-app-id
QQ_CLIENT_SECRET=your-qq-client-secret
QQ_ALLOWED_USERS=openid_a,openid_b
```

QQ Bot + MiniMax 示例：

```env
HERMES_INFERENCE_PROVIDER=minimax
MINIMAX_API_KEY=your-key

QQ_APP_ID=your-qq-app-id
QQ_CLIENT_SECRET=your-qq-client-secret
QQ_ALLOWED_USERS=openid_a,openid_b
```

企业微信 WeCom 示例：

```env
HERMES_INFERENCE_PROVIDER=custom
CUSTOM_BASE_URL=https://cloud.infini-ai.com/maas/v1
INFINI_AI_API_KEY=your-key

WECOM_BOT_ID=your-bot-id
WECOM_SECRET=your-secret
WECOM_ALLOWED_USERS=user_id_1,user_id_2
```

个人微信 Weixin 示例：

```env
HERMES_INFERENCE_PROVIDER=custom
CUSTOM_BASE_URL=https://cloud.infini-ai.com/maas/v1
INFINI_AI_API_KEY=your-key

WEIXIN_ACCOUNT_ID=your-account-id
WEIXIN_ALLOWED_USERS=wxid_a,wxid_b
```

## 环境变量参考

完整且最新的变量列表请查看 [Hermes repository](https://github.com/NousResearch/hermes-agent)。

## 简单使用流程

部署完成后：

1. 在你配置的消息平台里和机器人发起对话，例如 Telegram、Discord、Slack、QQ Bot、WeCom 或 Weixin。
2. 如果启用了 allowlist，确认你的用户 ID 已加入对应的 `*_ALLOWED_USERS`。
3. 发送普通消息，例如 `hello`。
4. Hermes 应该会通过配置好的模型提供方回复。

首次排查建议：

- 确认 gateway 日志显示平台连接成功。
- 确认 Railway Volume 已挂载到 `/data`。
- 确认模型 provider 变量已经设置，并且 key 有效。

## 在 Railway 上更新

不要在 Railway 部署中直接运行 `hermes update`。

- `hermes update` 会修改正在运行的容器，可能导致持久化的 `/data/.hermes/config.yaml` 比下次 Railway 启动的镜像更新。
- 在 Railway 上更新 Hermes，应修改服务 Variables 中的 `HERMES_GIT_REF`，固定到指定 tag 或 commit，然后重新部署。
- Railway 会在构建阶段暴露服务变量，本模板的 Dockerfile 使用 `ARG HERMES_GIT_REF`，因此构建会被该变量固定。

推荐流程：

1. 将 `HERMES_GIT_REF` 设置为明确的上游 tag 或 commit SHA。
2. 部署或重新部署服务。
3. 如果上游引入了新的配置项，重新部署后通过 Railway SSH 运行 `hermes config migrate`。

## 手动运行 Hermes 命令

如果需要在已部署服务中手动运行 `hermes ...` 命令，例如 `hermes config`、`hermes model` 或 `hermes pairing list`，可以使用 [Railway SSH](https://docs.railway.com/cli/ssh) 连接到运行中的容器。

连接后可执行：

```bash
hermes status
hermes config
hermes model
hermes pairing list
```

## 运行时行为

入口脚本 `scripts/entrypoint.sh` 会执行这些动作：

- 校验必需的 provider 和消息平台变量
- 将运行时环境变量写入 `${HERMES_HOME}/.env`
- 如果缺少 `${HERMES_HOME}/config.yaml`，则自动创建
- 将旧的 `MESSAGING_CWD` 从 `${HERMES_HOME}/.env` 迁移到 `config.yaml`，并从持久化 env 中移除
- 写入一次性初始化标记 `${HERMES_HOME}/.initialized`
- 启动 `hermes gateway`

## 故障排查

- `401 Missing Authentication header`：通常是 provider 和 key 不匹配，或当前选择的 provider 缺少 API key。
- 机器人已连接但不回复：检查 allowlist 变量和用户 ID 是否正确。
- 重新部署后数据丢失：确认 Railway Volume 已挂载到 `/data`。
- QQ Bot 启动失败：检查 `QQ_APP_ID` 和 `QQ_CLIENT_SECRET` 是否同时设置，并确认 QQ Bot 后台 intents 已开启。
- Weixin 启动失败：检查 `WEIXIN_ACCOUNT_ID` 和 `WEIXIN_TOKEN`，或重新通过 `hermes gateway setup` 完成扫码登录。

## 构建版本固定

本模板要求显式设置 `HERMES_GIT_REF`。

Railway 服务变量在构建阶段可用，Dockerfile 中读取：

- `ARG HERMES_GIT_REF`

请在 Railway Variables 中把 `HERMES_GIT_REF` 设置为固定的上游 tag 或 commit SHA。
如果不设置，模板默认使用 `v2026.5.29`。

示例：

- `HERMES_GIT_REF=v2026.5.29`
- `HERMES_GIT_REF=4f3c2b1`

## 本地冒烟测试

```bash
docker build --build-arg HERMES_GIT_REF=v2026.5.29 -t hermes-railway-template .

docker run --rm \
  -e OPENROUTER_API_KEY=sk-or-xxx \
  -e TELEGRAM_BOT_TOKEN=123456:ABC \
  -e TELEGRAM_ALLOWED_USERS=123456789 \
  -v "$(pwd)/.tmpdata:/data" \
  hermes-railway-template
```
