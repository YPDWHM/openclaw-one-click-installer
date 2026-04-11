# OpenClaw Windows 傻瓜式安装包

这个目录是一套面向 Windows 新手的 OpenClaw 安装包装层。

它做的事情：

- 调官方 `install.ps1`，自动安装 Node.js 和 OpenClaw
- 自动写入 `~/.openclaw/openclaw.json`
- 自动写入 `~/.openclaw/.env`
- 可选配置飞书 / QQ Bot
- 可选批量安装 skills
- 可选安装并启动 Gateway 服务

最简单的用法：

1. 双击 `install-openclaw.bat`
2. 跟着提示输入模型、Key、飞书或 QQ 信息
3. 等脚本自动完成安装与启动

预设配置安装：

1. 复制 `installer-config.example.json`
2. 重命名为 `installer-config.local.json`
3. 把其中的 Key、URL、AppID、AppSecret 改成你自己的
4. 双击 `install-openclaw.bat`

详细说明见 `docs/Windows安装教学.md`。
