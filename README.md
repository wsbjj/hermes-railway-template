# Hermes Agent Railway 自用部署版

这个仓库用于把 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 部署到 Railway。当前用法不是发布 Railway Marketplace 模板，而是你自己在 Railway 里选择 GitHub 仓库 `wsbjj/hermes-railway-template` 部署。

请不要点旧的 Railway Template 页面部署。自用部署入口是：

```text
Railway Dashboard -> New Project -> Deploy from GitHub repo -> wsbjj/hermes-railway-template
```

## 这个仓库做什么

- 用 Dockerfile 在 Railway 构建指定版本的 Hermes Agent。
- 用 Railway Volume 持久化 Hermes 状态，固定挂载到 `/data`。
- 首次启动时自动创建 `/data/.hermes/config.yaml` 和 `/data/.hermes/.env`。
- 支持 Telegram、Discord、Slack、QQ Bot、企业微信 WeCom、企业微信回调、个人微信 Weixin。
- 重点适配你的场景：QQ Bot / 微信 + 无问芯穹 / MiniMax / 自定义 OpenAI 兼容接口。

## 快速部署

1. 打开 Railway Dashboard。
2. 点击 `New Project`。
3. 选择 `Deploy from GitHub repo`。
4. 选择仓库 `wsbjj/hermes-railway-template`。
5. 服务创建后，添加一个 Volume。
6. Volume 挂载路径填写：

```text
/data
```

7. 进入服务的 `Variables`，按下面的配置方案填写变量。
8. 等待构建和启动完成。
9. 看 Railway Logs，正常会出现：

```text
[bootstrap] Starting Hermes gateway...
```

## 推荐配置：QQ Bot + 无问芯穹

这是最符合你当前需求的一组变量。

```env
HERMES_GIT_REF=v2026.5.29
HERMES_HOME=/data/.hermes
HOME=/data

HERMES_INFERENCE_PROVIDER=custom
HERMES_MODEL=你的无问芯穹模型ID
OPENAI_BASE_URL=https://cloud.infini-ai.com/maas/v1
OPENAI_API_KEY=你的无问芯穹APIKey

QQ_APP_ID=你的QQ机器人AppID
QQ_CLIENT_SECRET=你的QQ机器人ClientSecret
QQ_ALLOWED_USERS=允许访问的openid_a,允许访问的openid_b
```

说明：

- `HERMES_MODEL` 必须填无问芯穹控制台里真实可用的模型 ID。
- `OPENAI_BASE_URL` 不要漏掉 `/maas/v1`。
- `QQ_ALLOWED_USERS` 用英文逗号分隔，不要写成 JSON 数组。
- 如果暂时不知道 openid，可以先排查日志或用 Hermes 的配对机制，但长期建议配置 allowlist。

## 备选配置：QQ Bot + MiniMax 国际版

```env
HERMES_GIT_REF=v2026.5.29
HERMES_HOME=/data/.hermes
HOME=/data

HERMES_INFERENCE_PROVIDER=minimax
HERMES_MODEL=MiniMax-M2.7
MINIMAX_API_KEY=你的MiniMax国际版Key

QQ_APP_ID=你的QQ机器人AppID
QQ_CLIENT_SECRET=你的QQ机器人ClientSecret
QQ_ALLOWED_USERS=允许访问的openid_a,允许访问的openid_b
```

## 备选配置：QQ Bot + MiniMax 中国区

```env
HERMES_GIT_REF=v2026.5.29
HERMES_HOME=/data/.hermes
HOME=/data

HERMES_INFERENCE_PROVIDER=minimax-cn
HERMES_MODEL=MiniMax-M2.7
MINIMAX_CN_API_KEY=你的MiniMax中国区Key

QQ_APP_ID=你的QQ机器人AppID
QQ_CLIENT_SECRET=你的QQ机器人ClientSecret
QQ_ALLOWED_USERS=允许访问的openid_a,允许访问的openid_b
```

## 备选配置：企业微信 WeCom + 无问芯穹

企业微信 WeCom 比个人微信更适合放在 Railway 上长期运行。

```env
HERMES_GIT_REF=v2026.5.29
HERMES_HOME=/data/.hermes
HOME=/data

HERMES_INFERENCE_PROVIDER=custom
HERMES_MODEL=你的无问芯穹模型ID
OPENAI_BASE_URL=https://cloud.infini-ai.com/maas/v1
OPENAI_API_KEY=你的无问芯穹APIKey

WECOM_BOT_ID=你的企业微信BotID
WECOM_SECRET=你的企业微信Secret
WECOM_ALLOWED_USERS=user_id_1,user_id_2
```

## 备选配置：个人微信 Weixin + 无问芯穹

个人微信 Weixin / WeChat 需要扫码登录状态。第一次部署后通常要用 Railway SSH 进入容器执行一次：

```bash
hermes gateway setup
```

扫码成功后，凭据会持久化到 `/data/.hermes`。之后 Railway 重启会复用这个 Volume。

```env
HERMES_GIT_REF=v2026.5.29
HERMES_HOME=/data/.hermes
HOME=/data

HERMES_INFERENCE_PROVIDER=custom
HERMES_MODEL=你的无问芯穹模型ID
OPENAI_BASE_URL=https://cloud.infini-ai.com/maas/v1
OPENAI_API_KEY=你的无问芯穹APIKey

WEIXIN_ACCOUNT_ID=你的微信账号ID
WEIXIN_ALLOWED_USERS=wxid_a,wxid_b
```

注意：

- 个人微信依赖 iLink 扫码登录，Railway 上更容易受账号类型和消息推送限制影响。
- 普通微信群是否稳定可用取决于 iLink 是否给该账号推送群事件。
- 如果你只是想稳定用腾讯系入口，优先用企业微信 WeCom 或 QQ Bot。

## 自定义 OpenAI 兼容接口

任何兼容 `/v1/chat/completions` 的接口都可以按下面方式配置：

```env
HERMES_INFERENCE_PROVIDER=custom
HERMES_MODEL=你的模型ID
OPENAI_BASE_URL=https://你的接口域名/v1
OPENAI_API_KEY=你的APIKey
```

这个模板也兼容下面这种写法：

```env
HERMES_INFERENCE_PROVIDER=custom
HERMES_MODEL=你的模型ID
CUSTOM_BASE_URL=https://你的接口域名/v1
CUSTOM_API_KEY=你的APIKey
```

入口脚本会自动做兼容映射：

- 如果只填 `OPENAI_BASE_URL`，会同步为 `CUSTOM_BASE_URL`。
- 如果只填 `CUSTOM_BASE_URL`，会同步为 `OPENAI_BASE_URL`。
- 如果无问芯穹地址里包含 `infini-ai`，`OPENAI_API_KEY` 和 `INFINI_AI_API_KEY` 会自动互相补齐。
- 自定义端点必须有 key：`OPENAI_API_KEY`、`CUSTOM_API_KEY` 或 `INFINI_AI_API_KEY` 至少一个。

## 变量完整说明

### 构建和持久化

| 变量 | 是否必填 | 建议值 | 说明 |
| --- | --- | --- | --- |
| `HERMES_GIT_REF` | 建议填 | `v2026.5.29` | 构建时拉取 Hermes Agent 的 tag 或 commit。 |
| `HERMES_HOME` | 必填 | `/data/.hermes` | Hermes 状态目录，必须在 Railway Volume 下。 |
| `HOME` | 必填 | `/data` | 让 Hermes 和相关 CLI 把状态写到 Volume。 |
| `TERMINAL_CWD` | 可选 | `/data/workspace` | Hermes 终端工作目录，不填则默认 `/data/workspace`。 |
| `TERMINAL_TIMEOUT` | 可选 | `180` | 终端命令超时时间，单位秒。 |

### 模型提供方

| 变量 | 是否必填 | 说明 |
| --- | --- | --- |
| `HERMES_INFERENCE_PROVIDER` | 建议填 | 模型 provider。常用值：`custom`、`minimax`、`minimax-cn`、`openrouter`、`anthropic`。 |
| `HERMES_MODEL` | 建议填 | 默认模型 ID。入口脚本会在首次启动时写入 `config.yaml`。 |
| `OPENAI_BASE_URL` | 自定义端点必填 | OpenAI 兼容接口 base URL。 |
| `OPENAI_API_KEY` | 自定义端点必填 | 自定义端点 API key。 |
| `CUSTOM_BASE_URL` | 可选 | `OPENAI_BASE_URL` 的兼容别名。 |
| `CUSTOM_API_KEY` | 可选 | `OPENAI_API_KEY` 的兼容别名。 |
| `INFINI_AI_API_KEY` | 无问芯穹可用 | 无问芯穹 key。也可以直接用 `OPENAI_API_KEY`。 |
| `OPENROUTER_API_KEY` | OpenRouter 必填 | 使用 OpenRouter 时填写。 |
| `ANTHROPIC_API_KEY` | Anthropic 必填 | 使用 Anthropic API key 时填写。 |
| `MINIMAX_API_KEY` | MiniMax 国际版必填 | `HERMES_INFERENCE_PROVIDER=minimax` 时填写。 |
| `MINIMAX_CN_API_KEY` | MiniMax 中国区必填 | `HERMES_INFERENCE_PROVIDER=minimax-cn` 时填写。 |

### QQ Bot

| 变量 | 是否必填 | 说明 |
| --- | --- | --- |
| `QQ_APP_ID` | QQ 必填 | QQ Bot 应用 ID。 |
| `QQ_CLIENT_SECRET` | QQ 必填 | QQ Bot Client Secret。 |
| `QQ_ALLOWED_USERS` | 强烈建议 | 允许私聊访问的 openid，英文逗号分隔。 |
| `QQ_GROUP_ALLOWED_USERS` | 可选 | 允许群内访问的用户 openid，英文逗号分隔。 |
| `QQ_ALLOW_ALL_USERS` | 不推荐 | 设置 `true` 会放开 QQ 用户限制。 |
| `QQBOT_HOME_CHANNEL` | 可选 | Hermes home channel。 |
| `QQBOT_HOME_CHANNEL_NAME` | 可选 | home channel 展示名。 |

### 企业微信 WeCom

| 变量 | 是否必填 | 说明 |
| --- | --- | --- |
| `WECOM_BOT_ID` | WeCom 必填 | 企业微信 Bot ID。 |
| `WECOM_SECRET` | WeCom 必填 | 企业微信 Secret。 |
| `WECOM_ALLOWED_USERS` | 强烈建议 | 允许访问的企业微信用户 ID。 |
| `WECOM_ALLOW_ALL_USERS` | 不推荐 | 设置 `true` 会放开 WeCom 用户限制。 |
| `WECOM_GROUP_ALLOWED_USERS` | 可选 | 允许群聊访问的用户 ID。 |
| `WECOM_HOME_CHANNEL` | 可选 | Hermes home channel。 |

### 企业微信回调模式

如果你使用企业微信回调模式，需要 Railway 服务暴露公网域名，并在企业微信后台配置 callback path。

| 变量 | 是否必填 | 说明 |
| --- | --- | --- |
| `WECOM_CALLBACK_CORP_ID` | 必填 | 企业微信 Corp ID。 |
| `WECOM_CALLBACK_CORP_SECRET` | 必填 | 企业微信 Corp Secret。 |
| `WECOM_CALLBACK_AGENT_ID` | 必填 | 企业微信 Agent ID。 |
| `WECOM_CALLBACK_TOKEN` | 必填 | 回调 Token。 |
| `WECOM_CALLBACK_ENCODING_AES_KEY` | 必填 | 回调 EncodingAESKey。 |
| `WECOM_CALLBACK_HOST` | 可选 | 回调监听 host。 |
| `WECOM_CALLBACK_PORT` | 可选 | 回调监听端口。 |
| `WECOM_CALLBACK_ALLOWED_USERS` | 强烈建议 | 允许访问的用户 ID。 |

### 个人微信 Weixin

| 变量 | 是否必填 | 说明 |
| --- | --- | --- |
| `WEIXIN_ACCOUNT_ID` | Weixin 必填 | 微信账号 ID。 |
| `WEIXIN_TOKEN` | 可选 | 如果你已有 token 可直接填写；否则通过扫码登录持久化。 |
| `WEIXIN_ALLOWED_USERS` | 强烈建议 | 允许私聊访问的 wxid，英文逗号分隔。 |
| `WEIXIN_GROUP_ALLOWED_USERS` | 可选 | 允许群内访问的 wxid。 |
| `WEIXIN_ALLOW_ALL_USERS` | 不推荐 | 设置 `true` 会放开 Weixin 用户限制。 |

### Telegram / Discord / Slack

这些平台保留支持，但不是当前推荐主线。

| 平台 | 必填变量 | allowlist |
| --- | --- | --- |
| Telegram | `TELEGRAM_BOT_TOKEN` | `TELEGRAM_ALLOWED_USERS` |
| Discord | `DISCORD_BOT_TOKEN` | `DISCORD_ALLOWED_USERS` |
| Slack | `SLACK_BOT_TOKEN` + `SLACK_APP_TOKEN` | `SLACK_ALLOWED_USERS` |

## Allowlist 写法

所有 allowlist 都用英文逗号分隔：

```env
QQ_ALLOWED_USERS=openid_a,openid_b
WECOM_ALLOWED_USERS=user_id_1,user_id_2
WEIXIN_ALLOWED_USERS=wxid_a,wxid_b
```

不要写成：

```env
QQ_ALLOWED_USERS=["openid_a","openid_b"]
QQ_ALLOWED_USERS="openid_a","openid_b"
```

如果没有配置 allowlist，脚本会提示：

```text
Gateway defaults to deny-all; use DM pairing or set *_ALLOWED_USERS.
```

## 首次启动会发生什么

入口脚本 `scripts/entrypoint.sh` 会执行：

1. 校验模型 provider 变量。
2. 校验至少配置了一个消息平台。
3. 自动创建 `${HERMES_HOME}` 下的目录。
4. 首次创建 `${HERMES_HOME}/config.yaml`。
5. 把 Railway Variables 写入 `${HERMES_HOME}/.env`。
6. 写入初始化标记 `${HERMES_HOME}/.initialized`。
7. 启动 `hermes gateway`。

如果你设置了：

```env
HERMES_INFERENCE_PROVIDER=custom
HERMES_MODEL=your-model
OPENAI_BASE_URL=https://example.com/v1
```

首次启动会生成类似：

```yaml
model:
  default: your-model
  provider: custom
  base_url: https://example.com/v1
terminal:
  backend: local
  cwd: /data/workspace
  timeout: 180
compression:
  enabled: true
  threshold: 0.85
```

如果 `/data/.hermes/config.yaml` 已经存在并且已有 `model:` 段，脚本不会覆盖它。

## 修改模型或 provider

首次部署前，直接改 Railway Variables 最方便。

部署后如果你要换模型，有三种方式：

1. 在 Hermes 聊天中使用 `/model ... --global` 持久化。
2. 通过 Railway SSH 编辑 `/data/.hermes/config.yaml`。
3. 如果只是测试环境，删除 Volume 里的 `/data/.hermes/config.yaml` 后重新部署，让脚本按 Variables 重建。

不要在 Railway 里直接运行 `hermes update` 更新程序本体。更新 Hermes 版本应修改：

```env
HERMES_GIT_REF=新的tag或commit
```

然后重新部署。

## 本地验证

检查脚本语法：

```bash
bash -n scripts/entrypoint.sh
```

运行仓库内置烟测：

```bash
bash scripts/smoke-test.sh
```

检查 Dockerfile：

```bash
docker buildx build --check .
```

本地构建镜像：

```bash
docker build --build-arg HERMES_GIT_REF=v2026.5.29 -t hermes-railway-template .
```

本地运行示例：

```bash
docker run --rm \
  -e HERMES_INFERENCE_PROVIDER=custom \
  -e HERMES_MODEL=your-model \
  -e OPENAI_BASE_URL=https://cloud.infini-ai.com/maas/v1 \
  -e OPENAI_API_KEY=your-key \
  -e QQ_APP_ID=app-id \
  -e QQ_CLIENT_SECRET=secret \
  -e QQ_ALLOWED_USERS=openid_a \
  -v "$(pwd)/.tmpdata:/data" \
  hermes-railway-template
```

## 常见问题

### Railway 构建失败

先看 Build logs 的最后 30 行。常见原因：

- `HERMES_GIT_REF` 写错，GitHub 拉不到 tag 或 commit。
- Railway 没有使用 Dockerfile 构建。
- 上游 Hermes 依赖临时下载失败。

### 启动时报 provider 错误

检查你至少配置了一组模型变量：

- 无问芯穹 / 自定义接口：`OPENAI_BASE_URL` + `OPENAI_API_KEY`
- MiniMax 国际版：`MINIMAX_API_KEY`
- MiniMax 中国区：`MINIMAX_CN_API_KEY`
- OpenRouter：`OPENROUTER_API_KEY`
- Anthropic：`ANTHROPIC_API_KEY`

### QQ Bot 启动失败

检查：

- `QQ_APP_ID` 和 `QQ_CLIENT_SECRET` 是否同时填写。
- QQ Bot 后台 intents 是否开启。
- `QQ_ALLOWED_USERS` 是否是 openid，不是 QQ 号。

### 机器人已连接但不回复

优先检查 allowlist：

- QQ 用 `QQ_ALLOWED_USERS`
- 企业微信用 `WECOM_ALLOWED_USERS`
- 个人微信用 `WEIXIN_ALLOWED_USERS`

### 重新部署后数据丢失

确认 Railway Volume 挂载路径是：

```text
/data
```

不要挂到 `/app`、`/root` 或其他路径。

## 参考

- Railway Dockerfile 变量需要在 Dockerfile 中用 `ARG` 声明。
- Railway 从 GitHub 仓库部署时会自动识别根目录 Dockerfile。
- Hermes 自定义 OpenAI 兼容端点使用 `OPENAI_BASE_URL` + `OPENAI_API_KEY`，或者在 `config.yaml` 中设置 `model.base_url`。

上游文档：

- https://docs.railway.com
- https://github.com/NousResearch/hermes-agent
- https://github.com/NousResearch/hermes-agent/tree/main/website/docs
