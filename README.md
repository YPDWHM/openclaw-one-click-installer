# OpenClaw Windows One-Click Installer

This repo packages a fuller Windows setup flow for OpenClaw beginners.

What it covers:

- installs OpenClaw through the official Windows installer
- writes `~/.openclaw/openclaw.json` and `~/.openclaw/.env`
- asks for model URL / API key during install unless the user skips
- lets the user choose channels such as Feishu, QQ Bot, Telegram, Discord, Slack, LINE, and WhatsApp
- lets the user choose recommended skills and add custom skill slugs
- preinstalls selected channel plugins when needed
- generates helper `.bat` launchers and an install summary
- includes a PDF usage manual

Quick start:

1. Double-click `install-openclaw.bat`
2. Follow the wizard
3. Read `docs/OpenClaw-Windows-Installer-Guide.pdf`

Preset config mode:

1. Copy `installer-config.example.json`
2. Rename it to `installer-config.local.json`
3. Fill in your provider, keys, URLs, channels, and skills
4. Double-click `install-openclaw.bat`
