# OpenClaw Windows 安装与卸载说明

这套工具不是只包一层官方 `install.ps1`，而是把新手最容易卡住的步骤串成一个完整向导：

- Node.js 和 OpenClaw 安装
- 模型 API Key / Base URL / 模型 ID
- Feishu、QQ Bot、Telegram、Discord、Slack、LINE、WhatsApp 渠道配置
- 推荐 Skills 选择安装
- 安装后自动生成摘要和辅助脚本
- 新增一键卸载向导，统一清理服务、配置、工作目录和 CLI

## 最快使用方法

### 安装

1. 双击 `install-openclaw.bat`
2. 在向导里选择模型提供商
3. 填写 API Key、Base URL、模型 ID 等信息
4. 勾选要配置的渠道
5. 只填写已勾选渠道所需的凭据
6. 选择要安装的 Skills
7. 安装结束后查看同目录 PDF 手册

### 卸载

1. 双击 `uninstall-openclaw.bat`
2. 选择是否先备份
3. 选择是否删除网关服务、`~/.openclaw`、工作目录、全局 CLI、安装器生成文件
4. 卸载结束后查看 `outputs/openclaw-uninstall-summary.txt`

## API Key 去哪获取

| 提供商 | 控制台地址 |
|--------|-----------|
| OpenAI | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |
| OpenRouter | [openrouter.ai/keys](https://openrouter.ai/keys) |
| Moonshot | [platform.moonshot.cn/console/api-keys](https://platform.moonshot.cn/console/api-keys) |
| 自定义兼容 | 从你的提供商控制台获取 |

## 渠道凭据去哪获取

每个渠道的详细步骤请参考 PDF 手册第 4 节，这里先给入口：

- Feishu： [open.feishu.cn/app](https://open.feishu.cn/app)
- QQ Bot： [q.qq.com](https://q.qq.com/)
- Telegram：在 Telegram 搜索 `@BotFather`
- Discord： [discord.com/developers/applications](https://discord.com/developers/applications)
- Slack： [api.slack.com/apps](https://api.slack.com/apps)
- LINE： [developers.line.biz/console](https://developers.line.biz/console/)
- WhatsApp：无需预置 token，安装后扫码登录

## 预设配置安装

1. 复制 `installer-config.example.json`
2. 改名为 `installer-config.local.json`
3. 预先填好模型、渠道、Skills
4. 再双击 `install-openclaw.bat`

## 卸载说明

- 卸载向导会优先调用 `openclaw uninstall`
- 如果你勾选了删除 CLI，会继续执行 `npm rm -g openclaw`
- 如果工作目录不在 `~/.openclaw` 下面，默认不会直接勾选删除
- 如果检测不到 `openclaw.cmd`，脚本会退回手动清理当前已知目录

## 最终交付给用户时，优先看

- `docs/OpenClaw-Windows-Installer-Guide.pdf`
- `docs/OpenClaw-Windows-Installer-Guide.html`
