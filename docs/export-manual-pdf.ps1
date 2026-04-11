[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PdfPath = Join-Path $ScriptRoot "OpenClaw-Windows-Installer-Guide.pdf"
$python = Get-Command python -ErrorAction SilentlyContinue

if (-not $python) {
    throw "python not found."
}

$code = @'
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

pdf_path = r"__PDF__"
pdfmetrics.registerFont(TTFont("ManualFont", r"C:\Windows\Fonts\ARIALUNI.ttf"))

styles = getSampleStyleSheet()
title = ParagraphStyle("title", parent=styles["Title"], fontName="ManualFont", fontSize=24, leading=30, textColor=colors.HexColor("#0e5a5a"))
h1 = ParagraphStyle("h1", parent=styles["Heading1"], fontName="ManualFont", fontSize=16, leading=22, textColor=colors.HexColor("#0e5a5a"), spaceBefore=10, spaceAfter=6)
body = ParagraphStyle("body", parent=styles["BodyText"], fontName="ManualFont", fontSize=10.5, leading=16)

doc = SimpleDocTemplate(pdf_path, pagesize=A4, leftMargin=16*mm, rightMargin=16*mm, topMargin=16*mm, bottomMargin=14*mm)
elements = []

elements.append(Paragraph("OpenClaw Windows Installer Guide", title))
elements.append(Spacer(1, 8))
elements.append(Paragraph("This package is meant for Windows beginners who need a guided OpenClaw install with models, channels, keys, URLs, plugins, and skills handled in one flow.", body))
elements.append(Spacer(1, 8))

sections = [
    ("What the installer covers", [
        "1. Runs the official OpenClaw Windows installer.",
        "2. Collects provider API key, Base URL, and model id during setup.",
        "3. Lets the user choose channels such as Feishu, QQ Bot, Telegram, Discord, Slack, LINE, and WhatsApp.",
        "4. Prompts only for the credentials required by the channels the user selected.",
        "5. Lets the user choose recommended skills and add custom skill slugs.",
        "6. Generates launcher bat files and an install summary."
    ]),
    ("How to use it", [
        "Interactive mode: double-click install-openclaw.bat and follow the wizard.",
        "Preset mode: copy installer-config.example.json to installer-config.local.json, prefill it, then run the installer."
    ]),
    ("Model setup", [
        "OpenAI / OpenRouter / Moonshot: fill apiKey and modelRef.",
        "Custom OpenAI-compatible endpoint: fill baseUrl, providerId, customModelId, and apiKey.",
        "Set requiresStringContent=true if your backend rejects structured content.",
        "Set supportsTools=false if your backend fails on tool calling."
    ]),
    ("Channel credentials", [
        "Feishu / Lark: App ID and App Secret. Webhook mode also needs Verification Token and Encrypt Key.",
        "QQ Bot: AppID and AppSecret.",
        "Telegram: BotFather token.",
        "Discord: Bot token.",
        "Slack: socket mode uses bot token plus app token. HTTP mode uses bot token plus signing secret.",
        "LINE: channel access token plus channel secret.",
        "WhatsApp: QR login after install."
    ]),
    ("Callback URLs", [
        "If the user selects Slack HTTP, LINE, or Feishu webhook mode, the installer also asks for a public gateway base URL.",
        "The generated install summary shows the final callback URL for those channels."
    ]),
    ("Recommended skills", [
        "Preset options include files, calendar-planner, pg, open, docker-skill, skill-shell, find-skills-for-clawhub, and openclaw-master-skills.",
        "Users can still enter extra custom skill slugs."
    ]),
    ("Generated outputs", [
        "~/.openclaw/openclaw.json",
        "~/.openclaw/.env",
        "outputs/openclaw-install-summary.txt",
        "launchers/*.bat helper files"
    ]),
    ("Troubleshooting", [
        "If double-click install does not work, run install-openclaw.ps1 in PowerShell with ExecutionPolicy Bypass.",
        "If openclaw is not found after install, close the terminal and open a new PowerShell window.",
        "If webhook channels do not receive events, verify callback URLs and run openclaw gateway status plus openclaw logs --follow.",
        "If WhatsApp is not linked, rerun openclaw channels login --channel whatsapp."
    ])
]

for heading, lines in sections:
    elements.append(Paragraph(heading, h1))
    for line in lines:
        elements.append(Paragraph(line, body))
    elements.append(Spacer(1, 4))

table = Table([
    ["Channel", "Minimum credentials"],
    ["Feishu / Lark", "App ID + App Secret"],
    ["QQ Bot", "AppID + AppSecret"],
    ["Telegram", "BotFather token"],
    ["Discord", "Bot token"],
    ["Slack", "Bot token + App token / Signing secret"],
    ["LINE", "Channel access token + Channel secret"],
    ["WhatsApp", "QR login"]
], colWidths=[48*mm, 110*mm])
table.setStyle(TableStyle([
    ("FONTNAME", (0, 0), (-1, -1), "ManualFont"),
    ("FONTSIZE", (0, 0), (-1, -1), 10),
    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#dceeed")),
    ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#b7b7b7")),
    ("VALIGN", (0, 0), (-1, -1), "TOP"),
]))
elements.append(Paragraph("Channel quick reference", h1))
elements.append(table)

doc.build(elements)
print(pdf_path)
'@

$code = $code.Replace("__PDF__", $PdfPath)
$code | & $python.Source -

if (-not (Test-Path -LiteralPath $PdfPath)) {
    throw "PDF export failed."
}

Write-Host "PDF exported to $PdfPath"
