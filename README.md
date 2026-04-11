# OpenClaw Windows 一键安装包

> 面向不熟悉命令行的 Windows 用户，把 OpenClaw 的安装、模型配置、渠道接入、Skills 安装一次搞定。

## 功能概览

```
双击运行 ➜ 安装 Node.js + CLI ➜ 选择模型 / 填 API Key ➜ 自动验证 Key
    ➜ 选择渠道 / 填凭据 ➜ 安装 Skills ➜ 生成配置 ➜ 启动网关 ✓
```

- 调用 OpenClaw 官方安装脚本，自动处理 Node.js 和 CLI
- 支持 OpenAI / OpenRouter / Moonshot / 自定义兼容提供商
- 填写 API Key 后自动验证连通性
- 可选接入 7 个渠道：飞书、QQ Bot、Telegram、Discord、Slack、LINE、WhatsApp
- 向导全程中英双语提示，每个凭据输入前告诉你去哪获取
- 安装后生成辅助 `.bat` 脚本和安装摘要

## 快速开始

### 方式 A：交互式向导

1. 双击 `install-openclaw.bat`
2. 按向导提示操作（选模型 → 填 Key → 选渠道 → 选 Skills）
3. 安装完成后阅读 `docs/OpenClaw-Windows-Installer-Guide.pdf`

### 方式 B：预设配置

1. 复制 `installer-config.example.json` 为 `installer-config.local.json`
2. 预先填好模型、渠道、Skills 配置
3. 双击 `install-openclaw.bat` 自动安装

## API Key 获取

| 提供商 | 控制台地址 |
|--------|-----------|
| OpenAI | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |
| OpenRouter | [openrouter.ai/keys](https://openrouter.ai/keys) |
| Moonshot | [platform.moonshot.cn](https://platform.moonshot.cn/console/api-keys) |
| 自定义兼容 | 从你的提供商控制台获取 |

## 支持的渠道

| 渠道 | 需要什么 | 去哪获取 |
|------|---------|---------|
| 飞书 / Lark | App ID + App Secret | [open.feishu.cn](https://open.feishu.cn/app) |
| QQ Bot | AppID + AppSecret | [q.qq.com](https://q.qq.com/) |
| Telegram | Bot Token | Telegram 内搜索 @BotFather |
| Discord | Bot Token | [discord.com/developers](https://discord.com/developers/applications) |
| Slack | Bot Token + App Token 或 Signing Secret | [api.slack.com/apps](https://api.slack.com/apps) |
| LINE | Channel Access Token + Secret | [developers.line.biz](https://developers.line.biz/console/) |
| WhatsApp | 无需 token，安装后扫码 | 安装器自动拉起 |

详细的分步获取指南请参考 [PDF 手册](docs/OpenClaw-Windows-Installer-Guide.pdf) 第 4 节。

## 项目结构

```
openclawinstall/
├── install-openclaw.bat              # 入口：双击运行
├── install-openclaw.ps1              # 主安装脚本（向导 + 配置 + 安装逻辑）
├── installer-config.example.json     # 预设配置示例
├── docs/
│   ├── OpenClaw-Windows-Installer-Guide.html   # 完整中文说明书（图文版）
│   ├── OpenClaw-Windows-Installer-Guide.pdf    # PDF 版说明书
│   ├── Windows安装教学.md                       # 快速入门指南
│   └── export-manual-pdf.ps1                   # PDF 生成脚本
├── LICENSE
└── README.md
```

安装完成后还会生成：
- `~/.openclaw/openclaw.json` — 主配置
- `~/.openclaw/.env` — API Key 和密钥
- `outputs/openclaw-install-summary.txt` — 安装摘要
- `launchers/*.bat` — 辅助脚本（仪表盘、重启网关、查看日志等）

## 常见问题

**双击没反应？** 右键用 PowerShell 运行，或执行：
```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install-openclaw.ps1
```

**安装完找不到 openclaw？** 关掉终端重新打开，再试 `openclaw --version`。

**API Key 验证失败？** 不影响安装，可以之后在 `~/.openclaw/.env` 中修改。

## 安全提醒

不要把 `.env`、API Key、AppSecret、Bot Token 上传到公开仓库。`installer-config.local.json` 和 `installer-config.generated.json` 已在 `.gitignore` 中排除。

## License

MIT
