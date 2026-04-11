# OpenClaw Windows 安装教学

## 一句话说明

这套目录是给 Windows 新手做的 OpenClaw 一键安装包装层。双击 `install-openclaw.bat`，脚本会先调用 OpenClaw 官方 `install.ps1` 安装 Node.js 和 OpenClaw，然后帮你把模型、飞书、QQ Bot 和 skills 配好。

## 截至 2026-04-11 的官方要点

- OpenClaw 官方 Windows 快速安装命令是 `iwr -useb https://openclaw.ai/install.ps1 | iex`
- 官方当前推荐 Node 24
- Feishu 和 QQ Bot 在当前正式版里都属于内置 / 打包插件，通常不需要额外执行 `openclaw plugins install`
- `openclaw skills install <slug>` 会装到当前工作区的 `skills/` 目录

## 两种安装方式

### 方式一：交互式

1. 双击 `install-openclaw.bat`
2. 按提示填写：
   - 模型供应商
   - API Key
   - 默认模型
   - 飞书 / QQ 信息
   - 要安装的 skills
3. 等脚本自动完成安装

### 方式二：预设配置

1. 复制 `installer-config.example.json`
2. 改名成 `installer-config.local.json`
3. 把里面的 Key、URL、AppID、AppSecret 改成你自己的
4. 双击 `install-openclaw.bat`

## 配置文件怎么填

### 内置模型供应商

`providerKind` 支持：

- `openai`
- `openrouter`
- `moonshot`

最小示例：

```json
{
  "model": {
    "providerKind": "openai",
    "modelRef": "openai/gpt-5.4",
    "apiKey": "sk-xxxx"
  }
}
```

### 自定义兼容 OpenAI 的接口

如果你要填自己的 URL，就把 `providerKind` 改成 `custom`：

```json
{
  "model": {
    "providerKind": "custom",
    "apiKey": "sk-xxxx",
    "baseUrl": "https://your-api.example.com/v1",
    "providerId": "customai",
    "customModelId": "gpt-4.1-mini",
    "customModelName": "My Custom Model",
    "customApi": "openai-completions",
    "contextWindow": 131072,
    "maxTokens": 8192,
    "requiresStringContent": false,
    "supportsTools": true
  }
}
```

### 飞书

```json
{
  "channels": {
    "feishu": {
      "enabled": true,
      "domain": "feishu",
      "accountId": "main",
      "accountName": "OpenClaw 助手",
      "appId": "cli_xxx",
      "appSecret": "xxxx"
    }
  }
}
```

国际版 Lark 把 `domain` 改成 `lark`。

### QQ Bot

```json
{
  "channels": {
    "qqbot": {
      "enabled": true,
      "appId": "123456789",
      "clientSecret": "xxxx"
    }
  }
}
```

### skills

```json
{
  "skills": {
    "slugs": [
      "calendar",
      "browser"
    ]
  }
}
```

注意：这里必须填真实存在的 skill slug。

## 安装后文件位置

- OpenClaw 配置：`%USERPROFILE%\.openclaw\openclaw.json`
- 环境变量：`%USERPROFILE%\.openclaw\.env`
- 默认工作区：`%USERPROFILE%\.openclaw\workspace`
- skills：`%USERPROFILE%\.openclaw\workspace\skills`

## 装完后怎么验

```powershell
openclaw doctor --non-interactive
openclaw gateway status
openclaw dashboard
```

## 常见问题

### 双击没反应

直接开 PowerShell，进入本目录运行：

```powershell
.\install-openclaw.ps1
```

### 装完后提示找不到 `openclaw`

关掉当前终端，重新开 PowerShell，再执行：

```powershell
openclaw --version
```

### 自定义 URL 跑不起来

优先检查：

- `baseUrl` 是否真的带 `/v1`
- `customModelId` 是否和服务端一致
- 是否需要把 `requiresStringContent` 改成 `true`
- 是否需要把 `supportsTools` 改成 `false`

## 安全提醒

2026 年 3 月出现过假 OpenClaw 安装器和 GitHub 投毒案例，所以建议只走 `openclaw.ai` 或官方 GitHub 的来源，不要直接搜陌生安装包。

## 参考链接

- [Installation](https://docs.openclaw.ai/install)
- [Getting Started](https://docs.openclaw.ai/start/getting-started)
- [Feishu](https://docs.openclaw.ai/channels/feishu)
- [QQ Bot](https://docs.openclaw.ai/channels/qqbot)
- [Skills](https://docs.openclaw.ai/tools/skills)
