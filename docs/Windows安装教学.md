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
3. 填写 URL、API Key、模型 ID
4. 勾选要接入的渠道
5. 只填写已勾选渠道所需的凭据；不想现在配就跳过
6. 选择要装的 skills
7. 安装结束后阅读同目录 PDF 手册

## 配置文件安装

1. 复制 `installer-config.example.json`
2. 改名为 `installer-config.local.json`
3. 预先填好模型、渠道、skills
4. 再双击 `install-openclaw.bat`

## 说明书入口

最终交付给用户时，优先看：

- `docs/OpenClaw-Windows-Installer-Guide.pdf`
