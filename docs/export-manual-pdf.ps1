[CmdletBinding()]
param()

# ============================================================================
# OpenClaw Windows 一键安装与卸载说明书 — PDF 生成脚本
# 需要 Python 3 和 reportlab：pip install reportlab
# 字体使用 Windows 自带的 ARIALUNI.TTF（支持中文）
# ============================================================================

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PdfPath = Join-Path $ScriptRoot "OpenClaw-Windows-Installer-Guide.pdf"
$python = Get-Command python -ErrorAction SilentlyContinue

if (-not $python) {
    throw "python not found. Please install Python 3 and run: pip install reportlab"
}

$code = @'
# -*- coding: utf-8 -*-
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle, KeepTogether
)

pdf_path = r"__PDF__"

# -- Font --
pdfmetrics.registerFont(TTFont("ZH", r"C:\Windows\Fonts\ARIALUNI.TTF"))

# -- Styles --
styles = getSampleStyleSheet()
ACCENT = colors.HexColor("#0e5a5a")
ACCENT2 = colors.HexColor("#9a3412")
MUTED = colors.HexColor("#645d52")
LINE = colors.HexColor("#d5c8b2")
BG_HEAD = colors.HexColor("#dceeed")

sTitle = ParagraphStyle("t", parent=styles["Title"], fontName="ZH",
    fontSize=24, leading=30, textColor=ACCENT)
sH1 = ParagraphStyle("h1", parent=styles["Heading1"], fontName="ZH",
    fontSize=16, leading=22, textColor=ACCENT, spaceBefore=14, spaceAfter=6)
sH2 = ParagraphStyle("h2", parent=styles["Heading2"], fontName="ZH",
    fontSize=13, leading=18, textColor=ACCENT2, spaceBefore=10, spaceAfter=4)
sBody = ParagraphStyle("b", parent=styles["BodyText"], fontName="ZH",
    fontSize=10.5, leading=16)
sTip = ParagraphStyle("tip", parent=styles["BodyText"], fontName="ZH",
    fontSize=10, leading=15, textColor=ACCENT, leftIndent=10,
    borderColor=ACCENT, borderWidth=0.5, borderPadding=4)
sWarn = ParagraphStyle("warn", parent=styles["BodyText"], fontName="ZH",
    fontSize=10, leading=15, textColor=ACCENT2, leftIndent=10,
    borderColor=ACCENT2, borderWidth=0.5, borderPadding=4)
sMuted = ParagraphStyle("muted", parent=styles["BodyText"], fontName="ZH",
    fontSize=10, leading=15, textColor=MUTED)

doc = SimpleDocTemplate(pdf_path, pagesize=A4,
    leftMargin=16*mm, rightMargin=16*mm, topMargin=16*mm, bottomMargin=14*mm)
E = []  # elements
sp = lambda h=6: Spacer(1, h)

def h1(t): E.append(Paragraph(t, sH1))
def h2(t): E.append(Paragraph(t, sH2))
def p(t): E.append(Paragraph(t, sBody))
def tip(t): E.append(Paragraph(t, sTip))
def warn(t): E.append(Paragraph(t, sWarn))
def muted(t): E.append(Paragraph(t, sMuted))

# ===== Title =====
E.append(Paragraph("OpenClaw Windows 一键安装与卸载说明书", sTitle))
E.append(sp())
p("适用对象：不会自己装 Node.js、不会配 URL / Key、希望把 OpenClaw 和常用渠道一次配好的 Windows 用户。")
muted("本安装包覆盖模型提供商、渠道配置、插件补装、skills 选择安装，并新增统一风格的一键卸载向导。")
E.append(sp(12))

# ===== 1 =====
h1("1. 这套安装包做了什么")
p("- 调用 OpenClaw 官方 Windows 安装脚本，自动处理 Node.js 和 OpenClaw CLI。")
p("- 在安装过程中按步骤提示填写模型 API Key、Base URL、模型 ID。")
p("- 填写 API Key 后自动验证连通性，确认 Key 是否可用。")
p("- 可选配置 Feishu、QQ Bot、Telegram、Discord、Slack、LINE、WhatsApp。")
p("- 只有在用户勾选了某个渠道后，才会继续询问该渠道需要的 token、secret、webhook 路径或回调 URL。")
p("- 提供推荐 skills 选择安装，并支持手动输入额外 skill slug。")
p("- 安装后生成摘要文件和几个常用的 .bat 辅助脚本。")
p("- 新增 uninstall-openclaw.bat，一键卸载服务、状态目录、工作目录、CLI 和安装器产物。")
E.append(sp())

# ===== 2 =====
h1("2. 使用方法")
h2("方式 A：交互式")
p("1. 双击 install-openclaw.bat")
p("2. 按向导选择模型来源")
p("3. 填写 API Key、Base URL、模型 ID 等信息（向导会提示去哪获取）")
p("4. 勾选要接入的渠道")
p("5. 为已勾选渠道填写凭据；暂时不配的可以跳过")
p("6. 勾选要安装的 skills")
h2("方式 B：预设配置")
p("1. 复制 installer-config.example.json，改名为 installer-config.local.json")
p("2. 预先填好模型、渠道、skills")
p("3. 双击 install-openclaw.bat 直接安装")
h2("方式 C：交互式卸载")
p("1. 双击 uninstall-openclaw.bat")
p("2. 按向导选择是否先创建备份")
p("3. 勾选要删除的内容：网关服务、~/.openclaw、工作目录、全局 CLI、安装器生成文件")
p("4. 完成后查看 outputs/openclaw-uninstall-summary.txt")
E.append(sp())
# PART2_PLACEHOLDER

# ===== 3 =====
h1("3. 模型配置与 API Key 获取")

model_table = Table([
    ["模式", "需要填写", "说明"],
    ["OpenAI", "apiKey, modelRef", "默认 openai/gpt-5.4"],
    ["OpenRouter", "apiKey, modelRef", "默认 openrouter/auto"],
    ["Moonshot", "apiKey, modelRef", "默认 moonshot/kimi-k2.5"],
    ["自定义兼容", "baseUrl, apiKey, providerId, customModelId", "中转站 / 自建接口 / 本地推理"],
], colWidths=[30*mm, 60*mm, 68*mm])
model_table.setStyle(TableStyle([
    ("FONTNAME", (0,0), (-1,-1), "ZH"), ("FONTSIZE", (0,0), (-1,-1), 9.5),
    ("BACKGROUND", (0,0), (-1,0), BG_HEAD),
    ("GRID", (0,0), (-1,-1), 0.5, LINE), ("VALIGN", (0,0), (-1,-1), "TOP"),
]))
E.append(model_table)
E.append(sp())

h2("3.1 去哪获取 API Key")
p("<b>OpenAI</b> — 打开 platform.openai.com/api-keys → 登录 → Create new secret key → 复制 sk-... 密钥")
p("<b>OpenRouter</b> — 打开 openrouter.ai/keys → 登录 → Create Key → 复制密钥")
p("<b>Moonshot (Kimi)</b> — 打开 platform.moonshot.cn/console/api-keys → 登录 → 新建 API Key → 复制密钥")
p("<b>自定义兼容</b> — 从你的提供商控制台获取 API Key；确认 Base URL 格式（通常以 /v1 结尾）")
tip("安装向导填写 API Key 后会自动发送测试请求验证连通性。如果验证失败也可以继续安装，之后再修正。")
E.append(sp())

# ===== 4 =====
h1("4. 渠道凭据获取指南")

h2("4.1 飞书 / Lark")
p("1. 打开 open.feishu.cn/app，登录后点击「创建企业自建应用」")
p("2. 进入应用详情页 → 凭证与基本信息 → 复制 App ID 和 App Secret")
p("3. 在「事件与回调」中开启「使用长连接接收事件」（websocket 模式）")
p("4. 在「权限管理」中添加接收消息和发送消息的权限")
tip("推荐 websocket 模式，不需要公网服务器。webhook 模式还需要 Verification Token 和 Encrypt Key。")

h2("4.2 QQ Bot")
p("1. 打开 q.qq.com，登录 QQ 开放平台")
p("2. 进入「应用管理」→ 创建机器人应用")
p("3. 在「开发设置」中复制 AppID 和 AppSecret")
tip("安装器会自动补装 @openclaw/qqbot 插件。")

h2("4.3 Telegram")
p("1. 在 Telegram 中搜索 @BotFather 并打开对话")
p("2. 发送 /newbot，按提示输入机器人名称和用户名")
p("3. 创建成功后复制 Bot Token（格式：123456789:ABCdefGHI...）")
tip("首次私聊机器人通常需要 pairing（配对码验证）。安装后通过 openclaw pairing list 查看。")

h2("4.4 Discord")
p("1. 打开 discord.com/developers/applications → New Application")
p("2. 左侧菜单 Bot → Reset Token → 复制 Bot Token")
p("3. 在 Bot 页面下方开启 Message Content Intent")
p("4. OAuth2 > URL Generator 中勾选 bot scope，生成邀请链接添加到服务器")
warn("必须开启 Message Content Intent，否则机器人无法读取消息内容。")
# PART3_PLACEHOLDER

h2("4.5 Slack")
p("1. 打开 api.slack.com/apps → Create New App > From scratch")
p("2. OAuth &amp; Permissions 中添加 Bot Token Scopes（至少 chat:write、app_mentions:read）")
p("3. Install to Workspace → 复制 Bot User OAuth Token（xoxb-...）")
p("<b>Socket 模式（推荐）：</b>Basic Information > App-Level Tokens → 创建 token（scope: connections:write）→ 复制 xapp-... → 开启 Socket Mode")
p("<b>HTTP 模式：</b>Basic Information > App Credentials → 复制 Signing Secret → Event Subscriptions 中填回调 URL")
tip("Socket 模式不需要公网服务器，适合本地开发和内网部署。")

h2("4.6 LINE")
p("1. 打开 developers.line.biz/console → 创建 Provider 和 Messaging API Channel")
p("2. Messaging API 标签 → Issue 生成 Channel Access Token")
p("3. Basic settings 标签 → 复制 Channel Secret")
p("4. Messaging API 标签 → Webhook URL 中填入安装摘要里生成的回调地址")
warn("LINE 必须使用 webhook 回调，需要公网可访问的 HTTPS 地址。")

h2("4.7 WhatsApp")
p("1. WhatsApp 渠道不需要预先获取 token")
p("2. 安装器会在安装完成后自动运行 openclaw channels login --channel whatsapp")
p("3. 终端会显示二维码，用手机 WhatsApp 扫码即可完成登录")
E.append(sp())

h2("4.8 策略说明")
p("安装向导中每个渠道都会让你选择「私聊策略」和「群聊策略」：")
policy_table = Table([
    ["策略", "含义", "适用场景"],
    ["pairing 配对", "用户需输入配对码才能对话", "推荐私聊，防止陌生人使用"],
    ["allowlist 白名单", "仅白名单中的用户可使用", "企业内部或特定群组"],
    ["open 开放", "所有人可直接使用", "公开服务或测试环境"],
    ["disabled 关闭", "完全关闭该功能", "不需要时选择"],
], colWidths=[35*mm, 55*mm, 68*mm])
policy_table.setStyle(TableStyle([
    ("FONTNAME", (0,0), (-1,-1), "ZH"), ("FONTSIZE", (0,0), (-1,-1), 9.5),
    ("BACKGROUND", (0,0), (-1,0), BG_HEAD),
    ("GRID", (0,0), (-1,-1), 0.5, LINE), ("VALIGN", (0,0), (-1,-1), "TOP"),
]))
E.append(policy_table)
tip("大多数情况下，私聊选 pairing、群聊选 allowlist 是最安全的默认选择。")
E.append(sp())

# ===== 5 =====
h1("5. 渠道回调 URL")
p("如果选择了 Slack HTTP、LINE 或飞书 webhook 模式，安装器会询问公网网关地址（如 https://bot.example.com）。")
p("安装摘要会自动拼出回调 URL：")
p("- Slack HTTP: https://bot.example.com/slack/events")
p("- LINE: https://bot.example.com/line/events")
p("- 飞书 webhook: https://bot.example.com/feishu/events")
E.append(sp())

# ===== 6 =====
h1("6. Skills 选择安装")
skill_table = Table([
    ["Slug", "作用"],
    ["files", "文件查找、整理和清理"],
    ["calendar-planner", "日程安排"],
    ["pg", "PostgreSQL 相关"],
    ["open", "快速打开文件和链接"],
    ["docker-skill", "Docker 操作"],
    ["skill-shell", "给第三方 skill 配安全 shell"],
    ["find-skills-for-clawhub", "辅助查找 ClawHub 上的 skill"],
    ["openclaw-master-skills", "大而全的技能包，谨慎安装"],
], colWidths=[55*mm, 103*mm])
skill_table.setStyle(TableStyle([
    ("FONTNAME", (0,0), (-1,-1), "ZH"), ("FONTSIZE", (0,0), (-1,-1), 9.5),
    ("BACKGROUND", (0,0), (-1,0), BG_HEAD),
    ("GRID", (0,0), (-1,-1), 0.5, LINE), ("VALIGN", (0,0), (-1,-1), "TOP"),
]))
E.append(skill_table)
E.append(sp())
# PART4_PLACEHOLDER

# ===== 7 =====
h1("7. 安装完成后会生成什么")
p("- ~/.openclaw/openclaw.json — 主配置文件")
p("- ~/.openclaw/.env — API Key 和密钥存储")
p("- outputs/openclaw-install-summary.txt — 安装摘要（含回调 URL、状态汇总）")
p("- outputs/openclaw-uninstall-summary.txt — 卸载摘要")
p("- launchers/*.bat — 辅助脚本（仪表盘、重启网关、查看日志、卸载入口等）")
E.append(sp())

# ===== 8 =====
h1("8. 卸载时会做什么")
p("- 可选先运行 openclaw backup create 创建备份。")
p("- 优先调用 openclaw uninstall，按勾选内容卸载服务、状态目录和工作目录。")
p("- 如果勾选删除 CLI，会继续执行 npm rm -g openclaw。")
p("- 如果检测不到 openclaw.cmd，会退回到手动清理模式，删除当前安装器能确定的本地文件。")
tip("如果当前工作目录不在 ~/.openclaw 下，卸载向导默认不会直接勾选删除，避免误删你自己的业务文件。")
E.append(sp())

# ===== 9 =====
h1("9. 常见问题")
h2("双击没反应")
p("右键用 PowerShell 运行，或手动执行：")
p("powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\\install-openclaw.ps1")
h2("只想走卸载流程")
p("执行 powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\\install-openclaw.ps1 -Uninstall")
h2("安装完找不到 openclaw")
p("关掉当前终端，重新开 PowerShell，再试 openclaw --version")
h2("API Key 验证失败")
p("- 检查 Key 是否复制完整（没有多余空格或截断）")
p("- 确认提供商账户有余额或有效的订阅")
p("- 自定义提供商确认 Base URL 格式正确（通常以 /v1 结尾）")
p("- 验证失败不影响安装，可以之后在 ~/.openclaw/.env 中修改")
h2("Slack / LINE / 飞书 webhook 没有收到事件")
p("- 先确认公网回调 URL 可访问")
p("- 确认平台控制台里填的路径和安装摘要里生成的一致")
p("- 再看 openclaw gateway status 和 openclaw logs --follow")
h2("WhatsApp 一直没连上")
p("重新执行 openclaw channels login --channel whatsapp")
E.append(sp())

# ===== 10 =====
h1("10. 安全建议")
p("不要把 .env、API Key、AppSecret、bot token 上传到公开仓库。打包发给别人时，仓库里只放示例配置，不放真实密钥。")
E.append(sp())

# ===== Build =====
doc.build(E)
print(pdf_path)
'@

$code = $code.Replace("__PDF__", $PdfPath)
$tempPy = Join-Path ([System.IO.Path]::GetTempPath()) "openclaw-pdf-export.py"
[System.IO.File]::WriteAllText($tempPy, $code, [System.Text.UTF8Encoding]::new($false))
try {
    & $python.Source $tempPy
    if ($LASTEXITCODE -ne 0) { throw "Python script failed with exit code $LASTEXITCODE" }
} finally {
    Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $PdfPath)) {
    throw "PDF export failed."
}

Write-Host "PDF exported to $PdfPath"
