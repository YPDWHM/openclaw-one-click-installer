# OpenClaw Windows 一键安装包

面向不熟悉命令行的 Windows 用户，把 OpenClaw 的安装、模型配置、渠道接入、Skills 安装，以及现在新增的一键卸载整理成一套可直接双击使用的流程。

## 功能概览

```text
双击运行安装器 -> 安装 Node.js + OpenClaw -> 选择模型 / 填 API Key -> 自动验证 Key
-> 选择渠道 / 填渠道凭据 -> 安装 Skills -> 生成配置 -> 启动网关

双击运行卸载器 -> 选择是否备份 -> 卸载网关服务 / 状态目录 / 工作目录 / CLI
-> 清理安装器生成的辅助脚本与摘要 -> 生成卸载摘要
```

- 调用 OpenClaw 官方 Windows 安装脚本，自动处理 Node.js 和 CLI。
- 支持 OpenAI、OpenRouter、Moonshot、自定义 OpenAI 兼容提供商。
- 填写 API Key 后自动做连通性验证。
- 支持 Feishu / QQ Bot / Telegram / Discord / Slack / LINE / WhatsApp。
- 安装完成后会生成配置文件、摘要文件和常用 `.bat` 辅助脚本。
- 新增独立 `uninstall-openclaw.bat`，并在 `launchers/` 中同步生成卸载入口。

## 快速开始

### 安装

1. 双击 `install-openclaw.bat`
2. 按向导完成模型、渠道、Skills 配置
3. 安装完成后阅读 `docs/OpenClaw-Windows-Installer-Guide.pdf`

### 卸载

1. 双击 `uninstall-openclaw.bat`
2. 按向导选择是否创建备份，以及是否删除网关服务、`~/.openclaw`、工作目录、全局 CLI、安装器生成文件
3. 卸载完成后查看 `outputs/openclaw-uninstall-summary.txt`

### 预设配置安装

1. 复制 `installer-config.example.json` 为 `installer-config.local.json`
2. 预先填好模型、渠道、Skills
3. 双击 `install-openclaw.bat` 自动安装

## API Key 获取

| 提供商 | 控制台地址 |
|--------|-----------|
| OpenAI | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |
| OpenRouter | [openrouter.ai/keys](https://openrouter.ai/keys) |
| Moonshot | [platform.moonshot.cn/console/api-keys](https://platform.moonshot.cn/console/api-keys) |
| 自定义兼容 | 从你的提供商控制台获取 |

## 支持的渠道

| 渠道 | 需要什么 | 去哪获取 |
|------|---------|---------|
| Feishu / Lark | App ID + App Secret | [open.feishu.cn](https://open.feishu.cn/app) |
| QQ Bot | AppID + AppSecret | [q.qq.com](https://q.qq.com/) |
| Telegram | Bot Token | Telegram 内搜索 `@BotFather` |
| Discord | Bot Token | [discord.com/developers](https://discord.com/developers/applications) |
| Slack | Bot Token + App Token 或 Signing Secret | [api.slack.com/apps](https://api.slack.com/apps) |
| LINE | Channel Access Token + Secret | [developers.line.biz](https://developers.line.biz/console/) |
| WhatsApp | 无需预置 token，安装后扫码 | 安装器自动拉起 |

详细步骤请看 [PDF 手册](docs/OpenClaw-Windows-Installer-Guide.pdf)。

## 卸载会做什么

卸载向导会尽量复用安装器现有的交互风格，并按你勾选的内容执行：

- 可选先运行 `openclaw backup create`
- 调用 `openclaw uninstall` 卸载网关服务、状态目录、工作目录
- 额外执行 `npm rm -g openclaw` 卸载全局 CLI
- 清理当前安装包生成的 `launchers/`、`installer-config.generated.json`、安装摘要
- 生成 `outputs/openclaw-uninstall-summary.txt`

如果检测不到 `openclaw.cmd`，卸载器会退回到手动清理模式，继续删除当前包能确定的本地文件和目录。

## 项目结构

```text
openclawinstall/
├── install-openclaw.bat
├── uninstall-openclaw.bat
├── install-openclaw.ps1
├── installer-config.example.json
├── docs/
│   ├── OpenClaw-Windows-Installer-Guide.html
│   ├── OpenClaw-Windows-Installer-Guide.pdf
│   ├── Windows安装教学.md
│   └── export-manual-pdf.ps1
├── LICENSE
└── README.md
```

安装后还会生成：

- `~/.openclaw/openclaw.json`：主配置
- `~/.openclaw/.env`：API Key 和密钥
- `outputs/openclaw-install-summary.txt`：安装摘要
- `outputs/openclaw-uninstall-summary.txt`：卸载摘要
- `launchers/*.bat`：辅助脚本

## 常见问题

**双击没反应？** 右键用 PowerShell 运行，或执行：

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install-openclaw.ps1
```

**只想走卸载流程？** 执行：

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install-openclaw.ps1 -Uninstall
```

**安装完找不到 `openclaw`？** 关闭终端重新打开，再试 `openclaw --version`。

**API Key 验证失败？** 不影响安装，可以稍后手动修改 `~/.openclaw/.env`。

**自定义工作目录会被自动删除吗？** 交互式卸载里会单独确认；如果工作目录不在 `~/.openclaw` 下，默认不会直接勾选删除。

## 安全提醒

不要把 `.env`、API Key、App Secret、Bot Token 上传到公开仓库。`installer-config.local.json` 和 `installer-config.generated.json` 都应视作敏感文件。

## License

MIT
