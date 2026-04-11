# OpenClaw Windows 安装说明

这套安装包不是只包一层 `install.ps1`，而是把新手最容易卡住的地方都串起来：

- Node.js 和 OpenClaw 安装
- 模型 API Key / Base URL / 模型 ID
- 飞书、QQ Bot、Telegram、Discord、Slack、LINE、WhatsApp 的选择安装
- 安装过程中按需填写 token、secret、webhook 路径、回调 URL
- 推荐 skills 选择安装，以及自定义 skill slug
- 安装后自动生成辅助启动脚本和安装摘要

## 最快用法

1. 双击 `install-openclaw.bat`
2. 在向导里选择模型来源
3. 填写 URL、API Key、模型 ID（向导会提示去哪获取，填完自动验证）
4. 勾选要接入的渠道
5. 只填写已勾选渠道所需的凭据；不想现在配就跳过
6. 选择要装的 skills
7. 安装结束后阅读同目录 PDF 手册

## API Key 去哪获取

| 提供商 | 控制台地址 |
|--------|-----------|
| OpenAI | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |
| OpenRouter | [openrouter.ai/keys](https://openrouter.ai/keys) |
| Moonshot | [platform.moonshot.cn/console/api-keys](https://platform.moonshot.cn/console/api-keys) |
| 自定义兼容 | 从你的提供商控制台获取 |

## 渠道凭据去哪获取

每个渠道的详细获取步骤请参考 PDF 手册第 4 节，以下是快速入口：

- 飞书: [open.feishu.cn/app](https://open.feishu.cn/app) → 创建应用 → 凭证与基本信息
- QQ Bot: [q.qq.com](https://q.qq.com/) → 应用管理 → 开发设置
- Telegram: 在 Telegram 搜索 @BotFather → /newbot
- Discord: [discord.com/developers](https://discord.com/developers/applications) → New Application → Bot
- Slack: [api.slack.com/apps](https://api.slack.com/apps) → Create New App → OAuth & Permissions
- LINE: [developers.line.biz](https://developers.line.biz/console/) → Messaging API Channel
- WhatsApp: 无需 token，安装后扫码登录

## 配置文件安装

1. 复制 `installer-config.example.json`
2. 改名为 `installer-config.local.json`
3. 预先填好模型、渠道、skills
4. 再双击 `install-openclaw.bat`

## 说明书入口

最终交付给用户时，优先看：

- `docs/OpenClaw-Windows-Installer-Guide.pdf`
