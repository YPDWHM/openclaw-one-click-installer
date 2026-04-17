# 🐾 OpenClaw Windows 一键安装包

> 面向不熟悉命令行的 Windows 用户，把 OpenClaw 的安装、模型配置、渠道接入、Skills 安装，以及一键卸载整理成一套可直接双击使用的流程。

## ✨ 功能亮点

- 🚀 **一键安装** — 双击 `install-openclaw.bat`，自动搞定 Node.js + OpenClaw CLI
- 🤖 **多模型支持** — OpenAI / OpenRouter / Moonshot / 自定义兼容提供商
- 🔑 **API Key 自动验证** — 填完 Key 立即测试连通性，不用猜对不对
- 💬 **7 大渠道** — 飞书、QQ、Telegram、Discord、Slack、LINE、WhatsApp 一站式配置
- 🧩 **Skills 选装** — 内置推荐列表 + 支持手动输入自定义 slug
- 🪞 **npm 镜像加速** — 国内用户可选淘宝镜像，安装速度提升数倍
- 🌐 **网络提示** — 向导会提醒哪些提供商需要科学上网，哪些国内直连
- 🗑️ **一键卸载** — 双击 `uninstall-openclaw.bat`，干净卸载不留残余
- 📝 **中英双语向导** — 所有提示中文为主、英文术语括号标注

## 📦 安装流程一览

```
双击 install-openclaw.bat
  → 选择 npm 镜像源（默认 / 淘宝加速）
  → 自动安装 Node.js + OpenClaw CLI
  → 选择模型提供商 / 填写 API Key → 自动验证
  → 选择渠道 / 填写凭据
  → 选择安装 Skills
  → 生成配置文件 + 辅助脚本
  → 启动网关 🎉
```

## 🚀 快速开始

### 安装

1. 双击 `install-openclaw.bat`
2. 按向导完成模型、渠道、Skills 配置
3. 安装完成后阅读 [`docs/OpenClaw-Windows-Installer-Guide.pdf`](docs/OpenClaw-Windows-Installer-Guide.pdf)

### 卸载

1. 双击 `uninstall-openclaw.bat`
2. 按向导选择是否创建备份，以及要删除哪些内容
3. 卸载完成后查看 `outputs/openclaw-uninstall-summary.txt`

### 预设配置安装（高级）

1. 复制 `installer-config.example.json` 为 `installer-config.local.json`
2. 预先填好模型、渠道、Skills、npm 镜像等配置
3. 双击 `install-openclaw.bat` 自动安装

## 🔑 API Key 获取

| 提供商 | 控制台地址 | 网络要求 |
|--------|-----------|---------|
| 🟢 OpenAI | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) | 需要科学上网 🪜 |
| 🟠 OpenRouter | [openrouter.ai/keys](https://openrouter.ai/keys) | 需要科学上网 🪜 |
| 🌙 Moonshot | [platform.moonshot.cn/console/api-keys](https://platform.moonshot.cn/console/api-keys) | 国内直连 ✅ |
| ⚙️ 自定义兼容 | 从你的提供商控制台获取 | 取决于提供商 |

> 💡 安装向导填写 API Key 后会自动验证连通性。验证失败不影响安装，之后可以在 `~/.openclaw/.env` 中修改。

## 💬 支持的渠道

| 渠道 | 需要什么 | 去哪获取 |
|------|---------|---------|
| 🪶 Feishu / Lark | App ID + App Secret | [open.feishu.cn](https://open.feishu.cn/app) |
| 🐧 QQ Bot | AppID + AppSecret | [q.qq.com](https://q.qq.com/) |
| ✈️ Telegram | Bot Token | Telegram 内搜索 `@BotFather` |
| 🎮 Discord | Bot Token | [discord.com/developers](https://discord.com/developers/applications) |
| 💬 Slack | Bot Token + App Token 或 Signing Secret | [api.slack.com/apps](https://api.slack.com/apps) |
| 📗 LINE | Channel Access Token + Secret | [developers.line.biz](https://developers.line.biz/console/) |
| 🟢 WhatsApp | 无需预置 token，安装后扫码 | 安装器自动拉起 |

> 📖 每个渠道的详细获取步骤请看 [PDF 手册](docs/OpenClaw-Windows-Installer-Guide.pdf) 第 4 节。

## 🪞 npm 镜像加速

| 选项 | 地址 | 适用场景 |
|------|------|---------|
| 默认 | `registry.npmjs.org` | 海外用户或已有科学上网 |
| 淘宝镜像 | `registry.npmmirror.com` | 🇨🇳 国内用户推荐，无需梯子 |

安装器会在安装前自动设置 npm registry，安装完成后恢复原始源，不影响你其他项目。

预设配置安装时，在 `installer-config.local.json` 中设置：
```json
{
  "openclaw": {
    "npmMirror": "https://registry.npmmirror.com"
  }
}
```

## 🗑️ 卸载会做什么

卸载向导复用安装器的交互风格，按你勾选的内容执行：

- 📦 可选先运行 `openclaw backup create` 创建备份
- 🔌 调用 `openclaw uninstall` 卸载网关服务、状态目录、工作目录
- 🧹 执行 `npm rm -g openclaw` 卸载全局 CLI
- 🗂️ 清理 `launchers/`、`installer-config.generated.json`、安装摘要
- 📝 生成 `outputs/openclaw-uninstall-summary.txt`

> ⚠️ 如果检测不到 `openclaw.cmd`，卸载器会退回到手动清理模式。如果工作目录不在 `~/.openclaw` 下，默认不会直接勾选删除。

## 📁 项目结构

```text
openclawinstall/
├── 📄 install-openclaw.bat          # 安装入口（双击运行）
├── 📄 uninstall-openclaw.bat        # 卸载入口（双击运行）
├── ⚙️ install-openclaw.ps1          # 核心安装/卸载脚本
├── 📋 installer-config.example.json  # 预设配置模板
├── 📂 docs/
│   ├── 📖 OpenClaw-Windows-Installer-Guide.html
│   ├── 📖 OpenClaw-Windows-Installer-Guide.pdf
│   ├── 📝 Windows安装教学.md
│   └── ⚙️ export-manual-pdf.ps1
├── 📜 LICENSE
└── 📖 README.md
```

安装后还会生成：

| 文件 | 位置 | 说明 |
|------|------|------|
| `openclaw.json` | `~/.openclaw/` | 主配置文件 |
| `.env` | `~/.openclaw/` | API Key 和密钥 |
| 安装摘要 | `outputs/` | 回调 URL、状态汇总 |
| 卸载摘要 | `outputs/` | 卸载操作记录 |
| 辅助脚本 | `launchers/` | 仪表盘、重启、日志、卸载入口 |

## ❓ 常见问题

<details>
<summary>双击没反应？</summary>

右键用 PowerShell 运行，或执行：
```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install-openclaw.ps1
```
</details>

<details>
<summary>只想走卸载流程？</summary>

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install-openclaw.ps1 -Uninstall
```
</details>

<details>
<summary>安装完找不到 openclaw？</summary>

关闭终端重新打开，再试 `openclaw --version`。
</details>

<details>
<summary>API Key 验证失败？</summary>

不影响安装，可以稍后手动修改 `~/.openclaw/.env`。常见原因：
- Key 没复制完整（多了空格或被截断）
- 提供商账户没余额
- 自定义提供商的 Base URL 格式不对（通常以 `/v1` 结尾）
</details>

<details>
<summary>自定义工作目录会被自动删除吗？</summary>

交互式卸载里会单独确认。如果工作目录不在 `~/.openclaw` 下，默认不会直接勾选删除。
</details>

## 🔒 安全提醒

> 不要把 `.env`、API Key、App Secret、Bot Token 上传到公开仓库。`installer-config.local.json` 和 `installer-config.generated.json` 都应视作敏感文件。

## 📜 License

MIT
