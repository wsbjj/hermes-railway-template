# Hermes Agent Railway 部署版

这个仓库用于把 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 部署到 Railway。

现在有两种部署方式：

1. **一键部署（推荐）**：直接用下面的 Railway 模板，点一下就能创建项目、Volume 和环境变量。
2. **从 GitHub 仓库部署**：在 Railway 里手动选择 GitHub 仓库 `wsbjj/hermes-railway-template`，适合需要改源码或绑定自己分支的场景。

## 一键部署（Railway 模板）

点击下面的按钮，用模板直接部署：

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/DOx7Ru?referralCode=vX8D8t&utm_medium=integration&utm_source=template&utm_campaign=generic)

模板地址：

```text
https://railway.com/deploy/DOx7Ru?referralCode=vX8D8t&utm_medium=integration&utm_source=template&utm_campaign=generic
```

一键部署流程：

1. 点击上面的 `Deploy on Railway` 按钮，登录 Railway。
2. 模板会自动创建服务，并预设好需要的变量占位。
3. 按下面的[配置方案](#推荐配置qq-bot--无问芯穹)填写自己的模型 key 和机器人凭据。
4. 确认服务已经挂载 Volume 到 `/data`（模板通常已经预设，如果没有请手动添加，见下一节）。
5. 点击 `Deploy`，等待构建和启动完成。
6. 打开 Railway 生成的公网链接，看到 Hermes Railway 状态页即代表部署成功。

> 提示：一键部署完成后，剩下的变量配置、状态页、Dashboard 用法和「从 GitHub 仓库部署」完全一致，可以直接参考本文后面的章节。

## 从 GitHub 仓库部署

如果你想改源码、固定自己的分支，或者不走模板，可以手动从 GitHub 仓库部署：

```text
Railway Dashboard -> New Project -> Deploy from GitHub repo -> wsbjj/hermes-railway-template
```

## 这个仓库做什么

- 用 Dockerfile 在 Railway 构建指定版本的 Hermes Agent。
- 用 Railway Volume 持久化 Hermes 状态，固定挂载到 `/data`。
- 首次启动时自动创建 `/data/.hermes/config.yaml`，每次启动都会按当前变量重写 `/data/.hermes/.env`。
- 支持 Telegram、Discord、Slack、QQ Bot、企业微信 WeCom、企业微信回调、个人微信 Weixin。
- 重点适配你的场景：QQ Bot / 微信 + 无问芯穹 / MiniMax / 自定义 OpenAI 兼容接口。
- 可选启用 Hermes 官方 Web Dashboard，让 Railway 网页也能直接聊天。

## 快速部署（手动从 GitHub 仓库）

> 如果你用上面的[一键部署模板](#一键部署railway-模板)，可以跳过这一节；模板已经帮你创建好服务和 Volume。

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
9. 打开 Railway 生成的公网链接，应该能看到 Hermes Railway 状态页。
10. 看 Railway Logs，正常会出现：

```text
[bootstrap] Starting status page on 0.0.0.0:<PORT>
[bootstrap] Starting Hermes gateway...
```

状态页只是部署健康页面，不是聊天 UI。真正聊天仍然通过 QQ Bot、WeCom、Weixin、Telegram、Discord 或 Slack 进行。

如果启用官方 Web Dashboard，Railway 链接仍会先打开轻量状态页；首次访问会进入模板自己的登录页，登录后 1 小时内可进入状态页、Dashboard 和网页终端。

## Railway dev 环境和 GitHub dev 分支

这个仓库已经有 `dev` 分支。Railway 的环境名称不会自动绑定 GitHub 分支；你需要在 Railway 的 `dev` 环境里手动选择 source branch 为 `dev`。

建议流程：

1. Railway 左上角点击 `production` 下拉。
2. 点击 `New Environment`。
3. 新环境命名为 `dev`，可以从 `production` 复制配置。
4. 进入 `dev` 环境的 `hermes-railway-template` 服务。
5. 在 `Settings` 里把 GitHub source branch 改成 `dev`。

之后：

```text
GitHub dev  -> Railway dev
GitHub main -> Railway production
```

不要让 `production` 和 `dev` 同时使用同一套 QQ Bot、WeCom 或 Weixin 凭据。两个环境同时连接同一个机器人账号，可能抢连接或重复回复。

## 推荐配置：QQ Bot + 无问芯穹

这是最符合你当前需求的一组变量。

```env
HERMES_GIT_REF=v2026.7.1
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
HERMES_GIT_REF=v2026.7.1
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
HERMES_GIT_REF=v2026.7.1
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
HERMES_GIT_REF=v2026.7.1
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
HERMES_GIT_REF=v2026.7.1
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
- 如果自定义端点只填裸域名，例如 `https://cmdme.cn`，启动脚本会自动归一化为 `https://cmdme.cn/v1`。
- 如果无问芯穹地址里包含 `infini-ai`，`OPENAI_API_KEY` 和 `INFINI_AI_API_KEY` 会自动互相补齐。
- 自定义端点会在 `config.yaml` 写入 `model.api_key: ${OPENAI_API_KEY}` 这种环境变量引用，不会把明文 key 写进 Volume 配置文件。
- 自定义端点必须有 key：`OPENAI_API_KEY`、`CUSTOM_API_KEY` 或 `INFINI_AI_API_KEY` 至少一个。

## 可复制环境变量模板

`examples/` 目录里保留了可直接复制到 Railway Variables 的模板：

- [examples/railway.qq-infini.env](examples/railway.qq-infini.env)：QQ Bot + 无问芯穹。
- [examples/railway.qq-minimax.env](examples/railway.qq-minimax.env)：QQ Bot + MiniMax 国际版。
- [examples/railway.qq-minimax-cn.env](examples/railway.qq-minimax-cn.env)：QQ Bot + MiniMax 中国区。
- [examples/railway.wecom-infini.env](examples/railway.wecom-infini.env)：企业微信 WeCom + 无问芯穹。
- [examples/railway.weixin-infini.env](examples/railway.weixin-infini.env)：个人微信 Weixin + 无问芯穹。
- [examples/railway.dev-dashboard.env](examples/railway.dev-dashboard.env)：只跑官方 Web Dashboard 的 dev 验证环境。

## 变量完整说明

### 构建和持久化

| 变量 | 是否必填 | 建议值 | 说明 |
| --- | --- | --- | --- |
| `HERMES_GIT_REF` | 建议填 | `v2026.7.1` | 构建时拉取 Hermes Agent 的 tag 或 commit。 |
| `HERMES_SOURCE_CACHE_BUST` | 更新时可填 | 时间戳，如 `202607061600` | 强制 Docker 重新执行 Hermes 源码拉取层。使用 `main` 等会移动的 ref 时，每次更新都应换一个值。 |
| `HERMES_HOME` | 建议保留 | `/data/.hermes` | Hermes 状态目录，默认在 Railway Volume 下。 |
| `HOME` | 建议保留 | `/data` | 让 Hermes 和相关 CLI 把状态写到 Volume。 |
| `TZ` | 可选 | `Asia/Shanghai` | 容器系统时区；入口脚本默认设置，Railway Variables 可覆盖。 |
| `HERMES_TIMEZONE` | 可选 | `Asia/Shanghai` | Hermes 内部时区；默认跟随 `TZ`。 |
| `TERMINAL_CWD` | 可选 | `/data/workspace` | Hermes 终端工作目录，不填则默认 `/data/workspace`。 |
| `TERMINAL_TIMEOUT` | 可选 | `180` | 兼容接口 `/api/terminal/run` 的单条命令超时时间，单位秒。 |
| `PORT` | Railway 自动注入 | 不要手动设置 | Railway 公网链接转发到的端口，状态页/前置代理会监听这个端口。 |
| `STATUS_PAGE_ENABLED` | 可选 | `true` | 是否启动轻量状态页；设置为 `false` 可关闭。 |
| `STATUS_PAGE_HOST` | 可选 | `0.0.0.0` | 状态页监听地址，Railway 上必须能绑定公网流量。 |
| `STATUS_PAGE_PORT` | 可选 | `8080` | 本地备用端口；Railway 上优先使用 `PORT`。 |
| `STATUS_TERMINAL_ENABLED` | 可选 | `true` | 是否在已加密登录的状态页显示网页终端；只有设置了 `HERMES_DASHBOARD_PROXY_PASSWORD` 或 `HERMES_DASHBOARD_PASSWORD` 才会启用。 |
| `HERMES_GATEWAY_ENABLED` | 可选 | `true` | 是否启动 QQ Bot / WeCom / Weixin 等消息网关；纯 Web Dashboard 测试环境可设为 `false`。 |
| `HERMES_DASHBOARD` | 可选 | `false` | 设置为 `1` 或 `true` 后启动 Hermes 官方 Web Dashboard。 |
| `HERMES_DASHBOARD_HOST` | 可选 | `0.0.0.0` | 关闭状态页时 Dashboard 直接监听的地址；状态页代理模式下默认改为内部 loopback。 |
| `HERMES_DASHBOARD_PORT` | 可选 | `9119` | Dashboard 端口；状态页代理模式下作为内部端口使用，公网仍走 `PORT`。 |
| `HERMES_DASHBOARD_INTERNAL_HOST` | 可选 | `127.0.0.1` | 状态页代理模式下 Dashboard 只绑定到容器内部地址。 |
| `HERMES_DASHBOARD_INTERNAL_PORT` | 可选 | `9119` | 状态页代理模式下 Dashboard 的内部端口；如果和 `PORT` 冲突会自动避让默认冲突或提示修改。 |
| `HERMES_DASHBOARD_TUI` | 可选 | `true` | 是否开启 Dashboard 的网页聊天页。 |
| `HERMES_DASHBOARD_INSECURE` | 可选 | 代理模式默认开启 | 跳过 Dashboard OAuth/code gate。状态页代理模式下默认由 `HERMES_DASHBOARD_PROXY_PASSWORD` 保护；如需额外保留官方 OAuth，可显式设置为 `false`。 |
| `HERMES_DASHBOARD_SKIP_BUILD` | 可选 | `true` | 默认使用镜像里预构建好的 Dashboard 静态资源，避免 Railway 启动时重新跑 Vite 构建。需要运行时强制重建时才设为 `false`。 |
| `HERMES_DASHBOARD_PROXY_USER` | 可选 | `admin` | 状态页登录页用户名。 |
| `HERMES_DASHBOARD_PROXY_PASSWORD` | Dashboard / 终端必填 | 随机强密码 | 状态页登录页密码；保护所有 URL，包括 `/healthz`、`/readyz`、`/terminal`、网页终端 API、`/sessions` 和所有 Dashboard 路径；也兼容 `HERMES_DASHBOARD_PASSWORD`。 |
| `HERMES_DASHBOARD_SESSION_SECONDS` | 可选 | `3600` | 登录 Cookie 有效期，默认 1 小时。 |
| `HERMES_DASHBOARD_PUBLIC_URL` | 公开 Dashboard 建议填 | Railway 公网 URL | OAuth 回调使用的公开 Dashboard 地址。 |
| `HERMES_DASHBOARD_OAUTH_CLIENT_ID` | 公开 Dashboard 建议填 | Nous Portal client id | 启用官方 OAuth gate，避免公网暴露 `.env`。 |

### 模型提供方

| 变量 | 是否必填 | 说明 |
| --- | --- | --- |
| `HERMES_INFERENCE_PROVIDER` | 建议填 | 模型 provider。常用值：`custom`、`minimax`、`minimax-cn`、`openrouter`、`anthropic`。 |
| `HERMES_MODEL` | 建议填 | 默认模型 ID。入口脚本会写入或同步到 `config.yaml`。 |
| `HERMES_INFERENCE_MODEL` | 自动同步 | Dashboard Chat 子进程使用的模型名。通常不用手动填；入口脚本会从 `HERMES_MODEL` 同步。 |
| `HERMES_TUI_PROVIDER` | 自动同步 | Dashboard Chat 子进程使用的 provider。通常不用手动填；入口脚本会从 `HERMES_INFERENCE_PROVIDER` 同步，避免 `glm-5.1` 这类模型名被 Hermes 自动识别成 `zai`。 |
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

1. 设置 `HERMES_HOME`、`HOME`、`TZ=Asia/Shanghai` 和 `HERMES_TIMEZONE=Asia/Shanghai` 默认值，并自动创建 `${HERMES_HOME}`、日志、会话、cron、pairing 和终端工作目录。
2. 归一化自定义接口变量，例如把 `OPENAI_BASE_URL` 同步为 `CUSTOM_BASE_URL`，把无问芯穹 key 同步为 `INFINI_AI_API_KEY`。
3. 同步 Dashboard Chat 子进程变量：`HERMES_TUI_PROVIDER` 来自 `HERMES_INFERENCE_PROVIDER`，`HERMES_INFERENCE_MODEL` 来自 `HERMES_MODEL`。
4. 校验模型 provider 变量。
5. 如果 `HERMES_GATEWAY_ENABLED=true`，校验至少配置了一个消息平台。
6. 首次创建 `${HERMES_HOME}/config.yaml`；如果已有配置，则按 Railway Variables 同步 `model:` 段。
7. 每次启动都把当前运行变量写入 `${HERMES_HOME}/.env`。
8. 首次启动写入初始化标记 `${HERMES_HOME}/.initialized`。
9. 如果 `HERMES_DASHBOARD=1`，启动 Hermes 官方 Web Dashboard；状态页代理模式下默认只监听容器内部 `127.0.0.1:9119`。
10. 启动轻量状态页/前置代理，监听 Railway 的 `$PORT`；如果没有启用 Dashboard，它只提供状态页。
11. 如果 `HERMES_GATEWAY_ENABLED=true`，启动 `hermes gateway`。

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

如果 `/data/.hermes/config.yaml` 已经存在并且已有 `model:` 段，只要 Railway Variables 里显式设置了 `HERMES_INFERENCE_PROVIDER`、`HERMES_MODEL`、`OPENAI_BASE_URL` 或 `CUSTOM_BASE_URL`，启动脚本会同步 `model.default`、`model.provider`、`model.base_url` 和 `model.api_key` 环境变量引用。这样重新部署后，旧 Volume 里残留的 provider 或缺失的自定义端点 key 不会继续压过 Railway Variables。

## 轻量状态页

这个仓库会默认启动一个很小的 HTTP 状态页，让 Railway 公网链接可以打开。

可访问路径：

```text
/         HTML 状态页
/healthz  返回 ok
/readyz   返回 JSON 状态
```

设置 `HERMES_DASHBOARD_PROXY_PASSWORD` 或 `HERMES_DASHBOARD_PASSWORD` 后，除 `/login` 之外的所有路径都会先要求登录，包括 `/healthz`。登录 Cookie 默认 3600 秒有效，可用 `HERMES_DASHBOARD_SESSION_SECONDS` 调整。

状态页只展示非敏感信息：

- Hermes gateway 是否在线
- Railway service / environment 名称
- 当前 provider 和模型名
- 已启用的消息平台，例如 `qqbot`、`wecom`、`weixin`
- `/data/.hermes/config.yaml` 是否存在

状态页不会显示：

- API key
- token
- secret
- allowlist 用户 ID
- QQ openid / 微信 wxid

如果不想暴露状态页，可以在 Railway Variables 中设置：

```env
STATUS_PAGE_ENABLED=false
```

启用官方 Web Dashboard 且保留状态页时，状态页会继续监听 Railway 的 `$PORT`，并把非状态页路径代理到容器内部的 Dashboard：

- `/`、`/healthz`、`/readyz`、`/sessions`、`/terminal` 和 Dashboard WebSocket 都使用同一个登录会话。
- 如果设置了 `HERMES_DASHBOARD_PROXY_PASSWORD` 或 `HERMES_DASHBOARD_PASSWORD`，状态页会显示网页终端，并用同一组登录 Cookie 保护 `/terminal`、`/api/terminal/run` 和 `/api/terminal/ws`。
- `/sessions` 和其他 Dashboard 路径不再触发浏览器密码弹窗；在登录页登录后，1 小时内直接访问。
- Dashboard 在代理模式下默认只监听 `127.0.0.1:9119`，不会直接绑定公网端口。
- 代理模式必须设置 `HERMES_DASHBOARD_PROXY_PASSWORD`；未设置时容器会 fail closed，避免误把 Dashboard 裸露到公网。
- 状态页代理模式下，Dashboard 默认跳过官方 OAuth/code gate；公网入口已经由状态页登录会话保护。如果要同时保留官方 OAuth/code，可显式设置 `HERMES_DASHBOARD_INSECURE=false`。

## 网页终端

状态页内置了一个 xterm.js + PTY 的完整 Shell 终端，打开后可以像 Linux / macOS 终端一样直接输入、回车执行、`cd` 后保留当前目录，也支持 `Ctrl+C` 和窗口 resize。它默认使用 `TERMINAL_CWD`，不填则是 `/data/workspace`；旧的 `/api/terminal/run` 单条命令接口仍保留，超时沿用 `TERMINAL_TIMEOUT`，默认 `180` 秒。

启用条件：

```env
HERMES_DASHBOARD_PROXY_USER=admin
HERMES_DASHBOARD_PROXY_PASSWORD=换成一个随机强密码
STATUS_TERMINAL_ENABLED=true
```

安全提醒：

- 这是完整 Shell，不是命令白名单。登录后可以读取容器文件，包括 `/data/.hermes/.env`、`config.yaml`、日志和工作区文件。
- 没有设置 `HERMES_DASHBOARD_PROXY_PASSWORD` 或 `HERMES_DASHBOARD_PASSWORD` 时，`/terminal`、`/api/terminal/run` 和 `/api/terminal/ws` 会返回 `404`，不会裸露在公网。
- 如果你只想保留状态页和 Dashboard，不想开启网页终端，设置 `STATUS_TERMINAL_ENABLED=false`。

状态页右上角有 `EN / 中文` 切换按钮，只影响当前浏览器里的状态页显示，不会改 Hermes 配置。

## 官方 Web Dashboard

Hermes 官方 Web Dashboard 是真正的网页 UI。启用 `--tui` 后，Dashboard 里会出现 Chat 页，可以在浏览器里直接和 Hermes 对话。

这个镜像会在 Docker build 阶段用 Node.js 22 预构建 Dashboard 前端和内嵌聊天用的 Hermes TUI。容器启动时默认传入 `--skip-build`，所以 Railway Deploy Logs 不应该再出现运行时 `npm run build`。如果你看到 Vite 提示 `Node.js 18.20.4` 不满足要求，通常说明 Railway 还没有部署到包含本修复的 `dev` 分支最新提交，或者服务没有使用根目录 Dockerfile 重新构建。

最小 dev 测试配置：

```env
HERMES_DASHBOARD=1
HERMES_DASHBOARD_TUI=1
HERMES_DASHBOARD_PROXY_USER=admin
HERMES_DASHBOARD_PROXY_PASSWORD=换成一个随机强密码
HERMES_GATEWAY_ENABLED=false
```

这组配置适合 Railway `dev` 环境短期验证网页聊天。`HERMES_GATEWAY_ENABLED=false` 表示不启动 QQ Bot / WeCom / Weixin 网关，避免 dev 环境误用 production 机器人凭据。

状态页代理模式下不需要显式设置 `HERMES_DASHBOARD_INSECURE=true`。入口脚本会默认跳过 Dashboard 官方 OAuth/code gate，公网入口由 `HERMES_DASHBOARD_PROXY_PASSWORD` 登录页和 1 小时签名 Cookie 保护。只有关闭状态页代理、直接把 Dashboard 暴露到公网端口做短期 dev 测试时，才需要手动设置 `HERMES_DASHBOARD_INSECURE=true`。

如果要同时保留 QQ Bot：

```env
HERMES_DASHBOARD=1
HERMES_DASHBOARD_TUI=1
HERMES_DASHBOARD_PROXY_USER=admin
HERMES_DASHBOARD_PROXY_PASSWORD=换成一个随机强密码
HERMES_GATEWAY_ENABLED=true

QQ_APP_ID=你的测试QQ机器人AppID
QQ_CLIENT_SECRET=你的测试QQ机器人ClientSecret
QQ_ALLOWED_USERS=你的测试openid
```

公网安全提醒：

- Dashboard 会读写 `/data/.hermes/.env`，里面可能有 API key、token、secret。
- 状态页代理模式下，除 `/login` 外所有路径都必须先通过 `HERMES_DASHBOARD_PROXY_PASSWORD` 登录，包括 `/healthz`、`/readyz`、`/sessions`、终端和所有 Dashboard 路径。
- 状态页代理模式下默认跳过官方 OAuth/code gate，避免登录状态页后 Dashboard 再要求 code；如果你显式设置 `HERMES_DASHBOARD_INSECURE=false`，Dashboard 仍会保留官方 gate。
- production 如果要公开 Dashboard，建议使用 `HERMES_DASHBOARD_OAUTH_CLIENT_ID` 和 `HERMES_DASHBOARD_PUBLIC_URL` 配置官方 OAuth。
- 如果关闭状态页代理并让 Dashboard 直接公网绑定，且没有 OAuth 又没有设置 `HERMES_DASHBOARD_INSECURE=true`，Dashboard 会拒绝启动，这是官方的 fail-closed 行为。
- `HERMES_DASHBOARD_SKIP_BUILD` 默认是 `true`。只有你明确想在容器启动时重新跑 `npm install && npm run build`，才设置为 `false`。
- Chat 页显示 `[session ended]` 时，先刷新页面再试。如果仍然马上结束，检查 Railway Logs 和 `/data/.hermes/config.yaml`，通常是模型配置不完整或当前部署还没有预构建内嵌 TUI。

## 修改模型或 provider

直接改 Railway Variables 最方便；重新部署后，入口脚本会把模型相关变量同步到持久化的 `/data/.hermes/config.yaml`。

部署后如果你要换模型，有三种方式：

1. 修改 Railway Variables，然后重新部署，让入口脚本同步 `model:` 段。
2. 在 Hermes 聊天中使用 `/model ... --global` 持久化；如果 Railway Variables 里仍设置了模型字段，下次部署会再次以 Variables 为准。
3. 通过 Railway SSH 编辑 `/data/.hermes/config.yaml`；如果只是测试环境，也可以删除该文件后重新部署，让脚本按 Variables 重建。

## 更新 Hermes 程序版本

不要在 Railway 容器里直接运行 `hermes update` 更新程序本体。Railway 运行的是已经构建好的镜像，运行中改容器文件系统既不会稳定保留，也不会触发 Web/TUI 重新构建。

推荐在本机用 Railway CLI 触发一次新的镜像构建：

```powershell
.\scripts\update-hermes-railway.ps1 -Ref main -Environment dev -Service hermes-railway-template
```

如果要固定到某个 tag 或 commit，把 `main` 换成目标 ref：

```powershell
.\scripts\update-hermes-railway.ps1 -Ref v2026.7.1 -Environment dev -Service hermes-railway-template
```

手动执行等价命令：

```powershell
railway variable set HERMES_GIT_REF=main HERMES_SOURCE_CACHE_BUST=202607061600 --service hermes-railway-template --environment dev --skip-deploys
railway deployment redeploy --from-source --yes --service hermes-railway-template --environment dev
```

说明：

- `HERMES_GIT_REF` 是构建时拉取的 Hermes Agent tag、branch 或 commit。
- `HERMES_SOURCE_CACHE_BUST` 用来让 Docker 构建缓存失效。尤其当 `HERMES_GIT_REF=main` 时，ref 名字不变但远端 commit 会变，所以每次更新都应换一个时间戳。
- `/data/.hermes` 在 Railway Volume 下，配置、凭据和会话状态会跨镜像重建保留。
- 重新部署后可以在状态页 `/readyz` 的 `image.hermes_git_ref` 和 `image.source_cache_bust` 确认当前镜像来自哪次构建。

## 本地验证

检查脚本语法：

```bash
bash -n scripts/entrypoint.sh
```

运行仓库内置烟测：

```bash
bash scripts/smoke-test.sh
```

单独检查状态页脚本：

```bash
python -m py_compile scripts/status_server.py
```

检查 Dockerfile：

```bash
docker buildx build --check .
```

本地构建镜像：

```bash
docker build --build-arg HERMES_GIT_REF=v2026.7.1 -t hermes-railway-template .
```

本地运行示例：

```bash
docker run --rm \
  -p 8080:8080 \
  -e PORT=8080 \
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

### Dashboard 启动时报 Vite / Node 版本错误

如果 Deploy Logs 里出现：

```text
You are using Node.js 18.20.4. Vite requires Node.js version 20.19+ or 22.12+.
```

说明 Dashboard 前端在容器启动阶段被重新构建了，而且运行时 Node 版本不满足 Vite 7 要求。当前 `dev` 分支的镜像已经改为：

- Docker build 阶段使用 Node.js 22 预构建 Dashboard。
- Docker build 阶段同时预构建内嵌聊天 TUI，避免第一次打开 Chat 时临时安装 npm 依赖。
- 状态页代理模式下默认启用 Dashboard insecure mode，从而放行 Dashboard 聊天 WebSocket；公网入口仍由状态页登录页和签名 Cookie 保护。
- 容器启动 `hermes dashboard` 时默认带 `--skip-build`。
- 运行时镜像也带 Node.js 22，方便你手动排查。

处理方式：

1. 确认 Railway `dev` 环境的 source branch 是 GitHub `dev`。
2. 在 Railway 里点 `Redeploy`，让它重新按最新 Dockerfile 构建。
3. 确认没有把 `HERMES_DASHBOARD_SKIP_BUILD` 设置为 `false`。
4. 如果之前的失败部署留下了缓存，优先触发一次干净重建。

### 启动时报 provider 错误

检查你至少配置了一组模型变量：

- 无问芯穹 / 自定义接口：`OPENAI_BASE_URL` + `OPENAI_API_KEY`
- MiniMax 国际版：`MINIMAX_API_KEY`
- MiniMax 中国区：`MINIMAX_CN_API_KEY`
- OpenRouter：`OPENROUTER_API_KEY`
- Anthropic：`ANTHROPIC_API_KEY`

如果 Dashboard Chat 报 `Provider 'zai' is set in config.yaml`，但 Railway Variables 和 `/data/.hermes/config.yaml` 都已经是 `provider: custom`，通常是 TUI 子进程按模型名自动识别 provider。重新部署最新版本；入口脚本会同步 `HERMES_TUI_PROVIDER=custom` 和 `HERMES_INFERENCE_MODEL=<HERMES_MODEL>` 来覆盖这个自动识别。

如果日志提示 `run hermes model to configure (api_key)` 或自定义端点返回 `INVALID_API_KEY`，但 Railway Variables 中的 `OPENAI_API_KEY` 确认正确，通常是 `/data/.hermes/config.yaml` 的 `model.api_key` 缺失。重新部署最新版本；入口脚本会写入 `api_key: ${OPENAI_API_KEY}`，让 Hermes 对 `cmdme.cn` 这类非官方自定义域名也显式使用 Railway key。

### 终端工具提示命令不存在

如果日志里出现：

```text
/usr/bin/bash: line 3: hermes: command not found
/usr/bin/bash: line 3: ps: command not found
```

重新部署最新镜像。入口脚本会把容器 `PATH` 写入 `/data/.hermes/.env`，让 Hermes 的内部终端工具也能找到 `/opt/venv/bin/hermes`；运行镜像也包含 `procps`，因此 `ps` 可用。

如果日志里出现 `Empty response (no content or reasoning)`，并且标题生成提示拿到了 `<!doctype html>`，说明 `OPENAI_BASE_URL` 指向了网页入口而不是 JSON API。自定义 OpenAI 兼容接口应使用 API base URL，例如 `https://cmdme.cn/v1`；最新入口脚本会把 `https://cmdme.cn` 这类裸域名自动补成 `/v1`。

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

### Railway 链接还是打不开

检查 Deploy Logs 中是否出现：

```text
[bootstrap] Starting status page on 0.0.0.0:<PORT>
```

如果没有，确认没有设置：

```env
STATUS_PAGE_ENABLED=false
```

如果出现 `Status page failed to start`，通常是端口变量异常或服务进程启动失败。Railway 正常会自动注入 `PORT`，一般不需要手动设置。

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

一键部署模板：

- https://railway.com/deploy/DOx7Ru?referralCode=vX8D8t&utm_medium=integration&utm_source=template&utm_campaign=generic
