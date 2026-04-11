[CmdletBinding()]
param(
    [string]$ConfigPath = "",
    [switch]$NonInteractive,
    [switch]$DryRun,
    [switch]$SkipOpenClawInstall,
    [switch]$SkipSkills,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HomeDir = [Environment]::GetFolderPath("UserProfile")
$OpenClawHome = Join-Path $HomeDir ".openclaw"
$OpenClawConfigPath = Join-Path $OpenClawHome "openclaw.json"
$OpenClawEnvPath = Join-Path $OpenClawHome ".env"
$PowerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

$script:ChannelCatalog = @(
    [ordered]@{ id = "feishu"; label = "Feishu / Lark"; summary = "App ID + App Secret"; pluginPackage = ""; pluginMode = "bundled" },
    [ordered]@{ id = "qqbot"; label = "QQ Bot"; summary = "AppID + AppSecret"; pluginPackage = "@openclaw/qqbot"; pluginMode = "install" },
    [ordered]@{ id = "telegram"; label = "Telegram"; summary = "BotFather token"; pluginPackage = ""; pluginMode = "builtin" },
    [ordered]@{ id = "discord"; label = "Discord"; summary = "Bot token"; pluginPackage = ""; pluginMode = "builtin" },
    [ordered]@{ id = "slack"; label = "Slack"; summary = "Socket or HTTP mode"; pluginPackage = ""; pluginMode = "builtin" },
    [ordered]@{ id = "line"; label = "LINE"; summary = "Channel access token + secret"; pluginPackage = ""; pluginMode = "bundled" },
    [ordered]@{ id = "whatsapp"; label = "WhatsApp"; summary = "QR login after install"; pluginPackage = "@openclaw/whatsapp"; pluginMode = "install" }
)

$script:SkillCatalog = @(
    [ordered]@{ slug = "files"; label = "Files"; summary = "File search and cleanup" },
    [ordered]@{ slug = "calendar-planner"; label = "Calendar Planner"; summary = "Calendar and schedule workflows" },
    [ordered]@{ slug = "pg"; label = "Postgres"; summary = "PostgreSQL inspection and queries" },
    [ordered]@{ slug = "open"; label = "Open"; summary = "Fast open file/URL helper" },
    [ordered]@{ slug = "docker-skill"; label = "Docker"; summary = "Docker-related operations" },
    [ordered]@{ slug = "skill-shell"; label = "Skill Shell"; summary = "Safer shell around third-party skills" },
    [ordered]@{ slug = "find-skills-for-clawhub"; label = "Find Skills"; summary = "Search and shortlist ClawHub skills" },
    [ordered]@{ slug = "openclaw-master-skills"; label = "Master Skills Bundle"; summary = "Large preset bundle" }
)

function Write-Section([string]$Text) { Write-Host ""; Write-Host "=== $Text ===" -ForegroundColor Cyan }
function Write-Step([string]$Text) { Write-Host "[*] $Text" -ForegroundColor Green }
function Write-WarnLine([string]$Text) { Write-Host "[!] $Text" -ForegroundColor Yellow }
function Write-DryRun([string]$Text) { Write-Host "[DRY RUN] $Text" -ForegroundColor Magenta }

function Save-Utf8Text([string]$Path, [string]$Content) {
    if ($DryRun) { Write-DryRun "Write text $Path"; return }
    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-PlainObject($InputObject) {
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string] -or $InputObject.GetType().IsPrimitive) { return $InputObject }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) { $result[[string]$key] = ConvertTo-PlainObject $InputObject[$key] }
        return $result
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = @()
        foreach ($item in $InputObject) { $items += ,(ConvertTo-PlainObject $item) }
        return $items
    }
    if ($InputObject -is [pscustomobject]) {
        $result = @{}
        foreach ($property in $InputObject.PSObject.Properties) { $result[$property.Name] = ConvertTo-PlainObject $property.Value }
        return $result
    }
    return $InputObject
}

function Merge-Hashtable([hashtable]$Base, [hashtable]$Overlay) {
    $result = @{}
    if ($Base) { foreach ($key in $Base.Keys) { $result[$key] = ConvertTo-PlainObject $Base[$key] } }
    if ($Overlay) {
        foreach ($key in $Overlay.Keys) {
            $incoming = ConvertTo-PlainObject $Overlay[$key]
            if ($result.ContainsKey($key) -and $result[$key] -is [hashtable] -and $incoming -is [hashtable]) {
                $result[$key] = Merge-Hashtable -Base $result[$key] -Overlay $incoming
            } else {
                $result[$key] = $incoming
            }
        }
    }
    return $result
}

function Load-JsonAsHashtable([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @{} }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
    return ConvertTo-PlainObject ($raw | ConvertFrom-Json)
}

function Save-JsonFile([string]$Path, [hashtable]$Data) {
    if ($DryRun) { Write-DryRun "Write JSON $Path"; return }
    $json = $Data | ConvertTo-Json -Depth 100
    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Load-EnvMap([string]$Path) {
    $result = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $result }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) { continue }
        $index = $line.IndexOf("=")
        if ($index -lt 1) { continue }
        $result[$line.Substring(0, $index).Trim()] = $line.Substring($index + 1)
    }
    return $result
}

function Save-EnvMap([string]$Path, [hashtable]$Map) {
    if ($DryRun) { Write-DryRun "Write env $Path"; return }
    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $lines = @()
    foreach ($key in ($Map.Keys | Sort-Object)) { $lines += "$key=$($Map[$key])" }
    [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Backup-FileIfExists([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $backupPath = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    if ($DryRun) { Write-DryRun "Backup $Path -> $backupPath"; return }
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    Write-Step "Backup created: $backupPath"
}

function Ensure-Directory([string]$Path) {
    if ($DryRun) { Write-DryRun "Create directory $Path"; return }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Expand-PathLike([string]$PathValue, [string]$BasePath) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $PathValue }
    $expanded = $PathValue.Replace("%USERPROFILE%", $HomeDir)
    if ($expanded -eq "~") { $expanded = $HomeDir }
    if ($expanded.StartsWith("~\")) { $expanded = Join-Path $HomeDir $expanded.Substring(2) }
    if (-not [System.IO.Path]::IsPathRooted($expanded)) { $expanded = Join-Path $BasePath $expanded }
    return [System.IO.Path]::GetFullPath($expanded)
}

function Get-ProviderSpec([string]$ProviderKind) {
    switch ($ProviderKind.ToLowerInvariant()) {
        "openai" { return @{ apiKeyEnv = "OPENAI_API_KEY"; defaultModelRef = "openai/gpt-5.4" } }
        "openrouter" { return @{ apiKeyEnv = "OPENROUTER_API_KEY"; defaultModelRef = "openrouter/auto" } }
        "moonshot" { return @{ apiKeyEnv = "MOONSHOT_API_KEY"; defaultModelRef = "moonshot/kimi-k2.5" } }
        "custom" { return @{ apiKeyEnv = "CUSTOM_OPENAI_API_KEY"; defaultModelRef = "customai/your-model-id" } }
        default { throw "Unsupported providerKind: $ProviderKind" }
    }
}

function Split-CommaList([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    return @($Text.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Read-SecretText([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally {
        if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    }
}

function Test-ApiKeyConnectivity([string]$ProviderKind, [string]$ApiKey, [string]$BaseUrl) {
    if ($DryRun) { Write-DryRun "Test API key connectivity"; return }
    if ([string]::IsNullOrWhiteSpace($ApiKey)) { return }
    $testUrl = switch ($ProviderKind.ToLowerInvariant()) {
        "openai"     { "https://api.openai.com/v1/models" }
        "openrouter" { "https://openrouter.ai/api/v1/models" }
        "moonshot"   { "https://api.moonshot.cn/v1/models" }
        "custom"     { if ([string]::IsNullOrWhiteSpace($BaseUrl)) { return } else { $BaseUrl.TrimEnd("/") + "/models" } }
        default      { return }
    }
    Write-Host "  正在验证 API Key (testing connectivity)..." -ForegroundColor Gray
    try {
        $headers = @{ "Authorization" = "Bearer $ApiKey" }
        $response = Invoke-WebRequest -UseBasicParsing -Uri $testUrl -Headers $headers -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            Write-Host "  [OK] API Key 验证成功 (API Key verified)" -ForegroundColor Green
        }
    } catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        if ($status -eq 401 -or $status -eq 403) {
            Write-WarnLine "API Key 被拒绝 (rejected) — 请检查 Key 是否正确"
        } else {
            Write-WarnLine "连接测试失败 (connection test failed): $($_.Exception.Message)"
        }
        Write-Host "  你仍然可以继续安装，稍后再修正 (you can still continue)" -ForegroundColor Gray
    }
}

function Prompt-Default([string]$Prompt, [string]$DefaultValue = "") {
    if ([string]::IsNullOrEmpty($DefaultValue)) { return (Read-Host $Prompt).Trim() }
    $value = Read-Host "$Prompt [$DefaultValue]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $DefaultValue }
    return $value.Trim()
}

function Prompt-YesNo([string]$Prompt, [bool]$DefaultValue) {
    $hint = if ($DefaultValue) { "Y/n" } else { "y/N" }
    while ($true) {
        $value = Read-Host "$Prompt [$hint]"
        if ([string]::IsNullOrWhiteSpace($value)) { return $DefaultValue }
        switch ($value.Trim().ToLowerInvariant()) {
            "y" { return $true }; "yes" { return $true }; "n" { return $false }; "no" { return $false }
        }
        Write-WarnLine "Please enter y or n."
    }
}

function Prompt-Choice([string]$Title, [array]$Options, [string]$DefaultId = "") {
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    $defaultIndex = -1
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $option = $Options[$i]
        Write-Host ("{0}. {1} - {2}" -f ($i + 1), $option.label, $option.summary)
        if ($option.id -eq $DefaultId) { $defaultIndex = $i + 1 }
    }
    while ($true) {
        $suffix = if ($defaultIndex -gt 0) { " [$defaultIndex]" } else { "" }
        $raw = Read-Host "Choose one$suffix"
        if ([string]::IsNullOrWhiteSpace($raw) -and $defaultIndex -gt 0) { return $Options[$defaultIndex - 1].id }
        if ($raw -match '^\d+$') {
            $number = [int]$raw
            if ($number -ge 1 -and $number -le $Options.Count) { return $Options[$number - 1].id }
        }
        $trimmed = $raw.Trim().ToLowerInvariant()
        foreach ($option in $Options) { if ($option.id -eq $trimmed) { return $option.id } }
        Write-WarnLine "Invalid choice."
    }
}

function Prompt-MultiSelect([string]$Title, [array]$Options) {
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $option = $Options[$i]
        Write-Host ("{0}. {1} - {2}" -f ($i + 1), $option.label, $option.summary)
    }
    Write-Host "0. None"
    Write-Host "A. All"
    while ($true) {
        $raw = Read-Host "Choose one or more (example: 1,3,5)"
        if ([string]::IsNullOrWhiteSpace($raw) -or $raw.Trim() -eq "0") { return @() }
        if ($raw.Trim().ToLowerInvariant() -eq "a") { return @($Options | ForEach-Object { $_.id }) }
        $parts = @($raw.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $selected = @()
        $valid = $true
        foreach ($part in $parts) {
            if ($part -notmatch '^\d+$') { $valid = $false; break }
            $number = [int]$part
            if ($number -lt 1 -or $number -gt $Options.Count) { $valid = $false; break }
            $selected += $Options[$number - 1].id
        }
        if ($valid) { return @($selected | Select-Object -Unique) }
        Write-WarnLine "Invalid selection."
    }
}

function Prompt-Policy([string]$Title, [string[]]$Values, [string]$DefaultValue) {
    $descriptions = @{
        "pairing"   = "配对模式 — 用户需输入配对码才能使用 (pairing code required)"
        "allowlist" = "白名单 — 仅允许白名单中的用户 (allowlist only)"
        "open"      = "开放 — 所有人可直接使用 (open to everyone)"
        "disabled"  = "关闭 — 不启用此功能 (disabled)"
    }
    $options = @()
    foreach ($value in $Values) {
        $summary = if ($descriptions.ContainsKey($value)) { $descriptions[$value] } else { $value }
        $options += [ordered]@{ id = $value; label = $value; summary = $summary }
    }
    return Prompt-Choice -Title $Title -Options $options -DefaultId $DefaultValue
}

function Get-SkillDefinition([string]$Slug) {
    return $script:SkillCatalog | Where-Object { $_.slug -eq $Slug } | Select-Object -First 1
}

function Get-ChannelDefaults() {
    return @{
        feishu = @{
            selected = $false; enabled = $false; installPlugin = $false
            domain = "feishu"; accountId = "main"; accountName = "OpenClaw Assistant"
            connectionMode = "websocket"; dmPolicy = "pairing"; groupPolicy = "allowlist"; requireMention = $true
            appId = ""; appSecret = ""; verificationToken = ""; encryptKey = ""
            webhookPath = "/feishu/events"; webhookHost = "127.0.0.1"; webhookPort = 3000
            typingIndicator = $true; resolveSenderNames = $true
        }
        qqbot = @{ selected = $false; enabled = $false; installPlugin = $true; appId = ""; clientSecret = ""; dmPolicy = "pairing" }
        telegram = @{ selected = $false; enabled = $false; installPlugin = $false; botToken = ""; dmPolicy = "pairing"; requireMention = $true }
        discord = @{ selected = $false; enabled = $false; installPlugin = $false; token = ""; dmPolicy = "pairing"; groupPolicy = "allowlist" }
        slack = @{ selected = $false; enabled = $false; installPlugin = $false; mode = "socket"; botToken = ""; appToken = ""; signingSecret = ""; dmPolicy = "pairing"; groupPolicy = "allowlist"; webhookPath = "/slack/events" }
        line = @{ selected = $false; enabled = $false; installPlugin = $false; channelAccessToken = ""; channelSecret = ""; dmPolicy = "pairing"; webhookPath = "/line/events" }
        whatsapp = @{ selected = $false; enabled = $false; installPlugin = $true; dmPolicy = "pairing"; groupPolicy = "allowlist"; runLoginAfterInstall = $true }
    }
}

function Normalize-InstallerConfig([hashtable]$InputConfig) {
    $defaults = @{
        openclaw = @{ tag = "latest"; installDaemon = $true; startGateway = $true; openDashboard = $true }
        workspace = @{ path = "%USERPROFILE%\.openclaw\workspace" }
        gateway = @{
            publicBaseUrl = ""; writeSummaryFile = $true; createHelperScripts = $true
            summaryPath = ".\outputs\openclaw-install-summary.txt"; helperDir = ".\launchers"
        }
        model = @{
            providerKind = "openai"; modelRef = ""; apiKey = ""; baseUrl = ""; providerId = "customai"
            customModelId = "your-model-id"; customModelName = "My Custom Model"; customApi = "openai-completions"
            contextWindow = 131072; maxTokens = 8192; requiresStringContent = $false; supportsTools = $true
        }
        channels = Get-ChannelDefaults
        skills = @{ presetSlugs = @(); customSlugs = @(); saveGeneratedConfig = $true }
    }
    $config = Merge-Hashtable -Base $defaults -Overlay $InputConfig
    $providerSpec = Get-ProviderSpec -ProviderKind $config.model.providerKind
    if ([string]::IsNullOrWhiteSpace([string]$config.model.modelRef)) {
        if ($config.model.providerKind -eq "custom") { $config.model.modelRef = "{0}/{1}" -f $config.model.providerId, $config.model.customModelId }
        else { $config.model.modelRef = $providerSpec.defaultModelRef }
    }
    $config.workspace.path = Expand-PathLike ([string]$config.workspace.path) $ScriptRoot
    $config.gateway.summaryPath = Expand-PathLike ([string]$config.gateway.summaryPath) $ScriptRoot
    $config.gateway.helperDir = Expand-PathLike ([string]$config.gateway.helperDir) $ScriptRoot
    return $config
}

function Configure-FeishuChannel([hashtable]$Config) {
    $channel = $Config.channels.feishu; $channel.selected = $true
    Write-Host ""
    Write-Host "  飞书凭据获取: 前往飞书开放平台 (open.feishu.cn) -> 创建应用 -> 凭证与基本信息" -ForegroundColor Gray
    if (-not (Prompt-YesNo "现在配置飞书凭据 (Configure Feishu)?" $true)) { $channel.enabled = $false; return }
    $channel.enabled = $true
    $channel.domain = Prompt-Default "飞书域名 (feishu 或 lark)" $channel.domain
    $channel.accountId = Prompt-Default "飞书账号 ID (account id)" $channel.accountId
    $channel.accountName = Prompt-Default "机器人显示名称 (bot display name)" $channel.accountName
    $channel.appId = Prompt-Default "飞书 App ID" "cli_xxx"
    $channel.appSecret = Read-SecretText "飞书 App Secret"
    $channel.connectionMode = Prompt-Choice -Title "飞书连接模式 (connection mode)" -Options @(
        [ordered]@{ id = "websocket"; label = "websocket"; summary = "推荐，无需公网回调地址 (no public webhook needed)" },
        [ordered]@{ id = "webhook"; label = "webhook"; summary = "需要 verification token 和 encrypt key" }
    ) -DefaultId $channel.connectionMode
    $channel.dmPolicy = Prompt-Policy "飞书私聊策略 (Feishu DM policy)" @("pairing", "allowlist", "open", "disabled") $channel.dmPolicy
    $channel.groupPolicy = Prompt-Policy "飞书群聊策略 (Feishu group policy)" @("allowlist", "open", "disabled") $channel.groupPolicy
    $channel.requireMention = Prompt-YesNo "群聊中是否需要 @机器人 才回复 (Require @mention)?" $channel.requireMention
    if ($channel.connectionMode -eq "webhook") {
        $channel.verificationToken = Read-SecretText "飞书 Verification Token"
        $channel.encryptKey = Read-SecretText "飞书 Encrypt Key"
        $channel.webhookPath = Prompt-Default "飞书 Webhook 路径 (webhook path)" $channel.webhookPath
        $channel.webhookHost = Prompt-Default "飞书 Webhook 主机 (webhook host)" $channel.webhookHost
        $channel.webhookPort = [int](Prompt-Default "飞书 Webhook 端口 (webhook port)" ([string]$channel.webhookPort))
    }
}

function Configure-QqBotChannel([hashtable]$Config) {
    $channel = $Config.channels.qqbot; $channel.selected = $true
    Write-Host ""
    Write-Host "  QQ Bot 凭据获取: 前往 QQ 开放平台 (q.qq.com) -> 应用管理 -> 开发设置" -ForegroundColor Gray
    $channel.installPlugin = Prompt-YesNo "现在安装 QQ Bot 插件 (Install plugin)?" $channel.installPlugin
    if (-not (Prompt-YesNo "现在配置 QQ Bot?" $true)) { $channel.enabled = $false; return }
    $channel.enabled = $true
    $channel.appId = Prompt-Default "QQ Bot AppID" ""
    $channel.clientSecret = Read-SecretText "QQ Bot AppSecret"
    $channel.dmPolicy = Prompt-Policy "QQ Bot 私聊策略 (DM policy)" @("pairing", "allowlist", "open", "disabled") $channel.dmPolicy
}

function Configure-TelegramChannel([hashtable]$Config) {
    $channel = $Config.channels.telegram; $channel.selected = $true
    Write-Host ""
    Write-Host "  Telegram 凭据获取: 在 Telegram 中搜索 @BotFather -> 发送 /newbot -> 复制 token" -ForegroundColor Gray
    if (-not (Prompt-YesNo "现在配置 Telegram?" $true)) { $channel.enabled = $false; return }
    $channel.enabled = $true
    $channel.botToken = Read-SecretText "Telegram Bot Token"
    $channel.dmPolicy = Prompt-Policy "Telegram 私聊策略 (DM policy)" @("pairing", "allowlist", "open", "disabled") $channel.dmPolicy
    $channel.requireMention = Prompt-YesNo "群聊中是否需要 @机器人 才回复 (Require @mention)?" $channel.requireMention
}

function Configure-DiscordChannel([hashtable]$Config) {
    $channel = $Config.channels.discord; $channel.selected = $true
    Write-Host ""
    Write-Host "  Discord 凭据获取: 前往 discord.com/developers -> New Application -> Bot -> Reset Token" -ForegroundColor Gray
    Write-Host "  注意: 需要在 Bot 页面开启 Message Content Intent" -ForegroundColor Yellow
    if (-not (Prompt-YesNo "现在配置 Discord?" $true)) { $channel.enabled = $false; return }
    $channel.enabled = $true
    $channel.token = Read-SecretText "Discord Bot Token"
    $channel.dmPolicy = Prompt-Policy "Discord 私聊策略 (DM policy)" @("pairing", "allowlist", "open", "disabled") $channel.dmPolicy
    $channel.groupPolicy = Prompt-Policy "Discord 服务器策略 (group policy)" @("allowlist", "open", "disabled") $channel.groupPolicy
}

function Configure-SlackChannel([hashtable]$Config) {
    $channel = $Config.channels.slack; $channel.selected = $true
    Write-Host ""
    Write-Host "  Slack 凭据获取: 前往 api.slack.com/apps -> 创建应用 -> OAuth & Permissions" -ForegroundColor Gray
    if (-not (Prompt-YesNo "现在配置 Slack?" $true)) { $channel.enabled = $false; return }
    $channel.enabled = $true
    $channel.mode = Prompt-Choice -Title "Slack 连接模式 (mode)" -Options @(
        [ordered]@{ id = "socket"; label = "socket"; summary = "需要 Bot Token + App Token，无需公网 (推荐)" },
        [ordered]@{ id = "http"; label = "http"; summary = "需要 Bot Token + Signing Secret + 回调 URL" }
    ) -DefaultId $channel.mode
    $channel.botToken = Read-SecretText "Slack Bot Token (xoxb-...)"
    if ($channel.mode -eq "socket") { $channel.appToken = Read-SecretText "Slack App Token (xapp-...)" }
    else {
        $channel.signingSecret = Read-SecretText "Slack Signing Secret"
        $channel.webhookPath = Prompt-Default "Slack Webhook 路径 (webhook path)" $channel.webhookPath
    }
    $channel.dmPolicy = Prompt-Policy "Slack 私聊策略 (DM policy)" @("pairing", "allowlist", "open", "disabled") $channel.dmPolicy
    $channel.groupPolicy = Prompt-Policy "Slack 频道策略 (channel policy)" @("allowlist", "open", "disabled") $channel.groupPolicy
}

function Configure-LineChannel([hashtable]$Config) {
    $channel = $Config.channels.line; $channel.selected = $true
    Write-Host ""
    Write-Host "  LINE 凭据获取: 前往 developers.line.biz -> 创建 Messaging API Channel" -ForegroundColor Gray
    Write-Host "  注意: LINE 必须使用 webhook 回调，需要公网 HTTPS 地址" -ForegroundColor Yellow
    if (-not (Prompt-YesNo "现在配置 LINE?" $true)) { $channel.enabled = $false; return }
    $channel.enabled = $true
    $channel.channelAccessToken = Read-SecretText "LINE Channel Access Token"
    $channel.channelSecret = Read-SecretText "LINE Channel Secret"
    $channel.dmPolicy = Prompt-Policy "LINE 私聊策略 (DM policy)" @("pairing", "allowlist", "open", "disabled") $channel.dmPolicy
    $channel.webhookPath = Prompt-Default "LINE Webhook 路径 (webhook path)" $channel.webhookPath
}

function Configure-WhatsAppChannel([hashtable]$Config) {
    $channel = $Config.channels.whatsapp; $channel.selected = $true
    Write-Host ""
    Write-Host "  WhatsApp 无需预先获取 token，安装完成后扫码登录即可" -ForegroundColor Gray
    $channel.installPlugin = Prompt-YesNo "现在安装 WhatsApp 插件 (Install plugin)?" $channel.installPlugin
    $channel.enabled = Prompt-YesNo "启用 WhatsApp 配置 (Enable WhatsApp)?" $true
    $channel.dmPolicy = Prompt-Policy "WhatsApp 私聊策略 (DM policy)" @("pairing", "allowlist", "open", "disabled") $channel.dmPolicy
    $channel.groupPolicy = Prompt-Policy "WhatsApp 群聊策略 (group policy)" @("allowlist", "open", "disabled") $channel.groupPolicy
    $channel.runLoginAfterInstall = Prompt-YesNo "安装后自动拉起 WhatsApp 扫码登录 (Run QR login)?" $channel.runLoginAfterInstall
}

function Collect-InteractiveConfig {
    Write-Section "OpenClaw Windows 安装向导 (Installer Wizard)"
    $providerKind = Prompt-Choice -Title "选择模型提供商 (Choose a model provider)" -Options @(
        [ordered]@{ id = "openai"; label = "OpenAI"; summary = "使用 OPENAI_API_KEY — 从 platform.openai.com 获取" },
        [ordered]@{ id = "openrouter"; label = "OpenRouter"; summary = "使用 OPENROUTER_API_KEY — 从 openrouter.ai/keys 获取" },
        [ordered]@{ id = "moonshot"; label = "Moonshot"; summary = "使用 MOONSHOT_API_KEY — 从 platform.moonshot.cn 获取" },
        [ordered]@{ id = "custom"; label = "自定义兼容 (Custom OpenAI-compatible)"; summary = "使用自定义 Base URL + API Key" }
    ) -DefaultId "openai"
    $config = Normalize-InstallerConfig -InputConfig @{ model = @{ providerKind = $providerKind } }
    $providerSpec = Get-ProviderSpec -ProviderKind $providerKind
    $config.openclaw.tag = Prompt-Default "OpenClaw 版本标签 (tag)" $config.openclaw.tag
    $config.workspace.path = Expand-PathLike (Prompt-Default "工作目录路径 (Workspace path)" $config.workspace.path) $ScriptRoot
    $config.openclaw.installDaemon = Prompt-YesNo "安装网关服务 (Install gateway service)?" $config.openclaw.installDaemon
    $config.openclaw.startGateway = Prompt-YesNo "配置完成后启动网关 (Start gateway)?" $config.openclaw.startGateway
    $config.openclaw.openDashboard = Prompt-YesNo "配置完成后打开仪表盘 (Open dashboard)?" $config.openclaw.openDashboard
    if ($providerKind -eq "custom") {
        $config.model.providerId = Prompt-Default "自定义提供商 ID (provider id)" $config.model.providerId
        $config.model.baseUrl = Prompt-Default "自定义 Base URL（须包含 /v1）" "https://your-api.example.com/v1"
        $config.model.customModelId = Prompt-Default "自定义模型 ID (model id)" $config.model.customModelId
        $config.model.customModelName = Prompt-Default "模型显示名称 (display name)" $config.model.customModelName
        $config.model.customApi = Prompt-Default "API 类型 (API type)" $config.model.customApi
        $config.model.contextWindow = [int](Prompt-Default "上下文窗口 tokens (Context window)" ([string]$config.model.contextWindow))
        $config.model.maxTokens = [int](Prompt-Default "最大输出 tokens (Max output)" ([string]$config.model.maxTokens))
        $config.model.requiresStringContent = Prompt-YesNo "后端是否要求纯字符串内容 (string-only content)?" $config.model.requiresStringContent
        $config.model.supportsTools = Prompt-YesNo "后端是否支持工具调用 (tool calling)?" $config.model.supportsTools
        $config.model.modelRef = "{0}/{1}" -f $config.model.providerId, $config.model.customModelId
    } else {
        $config.model.modelRef = Prompt-Default "默认模型引用 (model ref) provider/model" $providerSpec.defaultModelRef
    }
    $apiKeyHints = @{
        "openai"     = "  提示: 前往 platform.openai.com -> API Keys 页面获取"
        "openrouter" = "  提示: 前往 openrouter.ai/keys 获取"
        "moonshot"   = "  提示: 前往 platform.moonshot.cn -> API 密钥管理获取"
        "custom"     = "  提示: 从你的自定义提供商控制台获取 API Key"
    }
    if ($apiKeyHints.ContainsKey($providerKind)) { Write-Host $apiKeyHints[$providerKind] -ForegroundColor Gray }
    $config.model.apiKey = Read-SecretText "模型 API Key（填写后将自动验证）"
    Test-ApiKeyConnectivity -ProviderKind $providerKind -ApiKey $config.model.apiKey -BaseUrl ([string]$config.model.baseUrl)
    $selectedChannels = Prompt-MultiSelect -Title "选择要配置的渠道 (Choose channels)" -Options $script:ChannelCatalog
    foreach ($channelId in $selectedChannels) {
        switch ($channelId) {
            "feishu" { Configure-FeishuChannel -Config $config }
            "qqbot" { Configure-QqBotChannel -Config $config }
            "telegram" { Configure-TelegramChannel -Config $config }
            "discord" { Configure-DiscordChannel -Config $config }
            "slack" { Configure-SlackChannel -Config $config }
            "line" { Configure-LineChannel -Config $config }
            "whatsapp" { Configure-WhatsAppChannel -Config $config }
        }
    }
    $needsPublicBaseUrl = $false
    if ($config.channels.feishu.enabled -and $config.channels.feishu.connectionMode -eq "webhook") { $needsPublicBaseUrl = $true }
    if ($config.channels.slack.enabled -and $config.channels.slack.mode -eq "http") { $needsPublicBaseUrl = $true }
    if ($config.channels.line.enabled) { $needsPublicBaseUrl = $true }
    if ($needsPublicBaseUrl) { $config.gateway.publicBaseUrl = Prompt-Default "公网网关地址 (Public gateway base URL) https://..." "" }
    $config.skills.presetSlugs = @(
        Prompt-MultiSelect -Title "选择要安装的推荐技能 (Choose recommended skills)" -Options ($script:SkillCatalog | ForEach-Object {
            [ordered]@{ id = $_.slug; label = $_.label; summary = $_.summary }
        })
    )
    $config.skills.customSlugs = Split-CommaList (Prompt-Default "额外技能 slug（逗号分隔，可选）(Custom skill slugs)" "")
    $config.gateway.writeSummaryFile = Prompt-YesNo "生成安装摘要文件 (Write install summary)?" $config.gateway.writeSummaryFile
    $config.gateway.createHelperScripts = Prompt-YesNo "生成辅助启动脚本 (Create helper .bat files)?" $config.gateway.createHelperScripts
    $config.skills.saveGeneratedConfig = Prompt-YesNo "保存生成的配置文件 (Save generated config)?" $config.skills.saveGeneratedConfig
    return $config
}

function Validate-InstallerConfig([hashtable]$Config) {
    if ([string]::IsNullOrWhiteSpace([string]$Config.openclaw.tag)) { throw "openclaw.tag cannot be empty." }
    if ([string]::IsNullOrWhiteSpace([string]$Config.workspace.path)) { throw "workspace.path cannot be empty." }
    if ([string]::IsNullOrWhiteSpace([string]$Config.model.providerKind)) { throw "model.providerKind cannot be empty." }
    if ([string]::IsNullOrWhiteSpace([string]$Config.model.apiKey)) { throw "model.apiKey cannot be empty." }
    if ([string]::IsNullOrWhiteSpace([string]$Config.model.modelRef)) { throw "model.modelRef cannot be empty." }
    if ($Config.model.providerKind -eq "custom" -and [string]::IsNullOrWhiteSpace([string]$Config.model.baseUrl)) { throw "model.baseUrl cannot be empty in custom mode." }
    if ($Config.channels.feishu.enabled -and ([string]::IsNullOrWhiteSpace([string]$Config.channels.feishu.appId) -or [string]::IsNullOrWhiteSpace([string]$Config.channels.feishu.appSecret))) { throw "Feishu appId/appSecret cannot be empty when enabled." }
    if ($Config.channels.qqbot.enabled -and ([string]::IsNullOrWhiteSpace([string]$Config.channels.qqbot.appId) -or [string]::IsNullOrWhiteSpace([string]$Config.channels.qqbot.clientSecret))) { throw "QQ Bot AppID/AppSecret cannot be empty when enabled." }
    if ($Config.channels.telegram.enabled -and [string]::IsNullOrWhiteSpace([string]$Config.channels.telegram.botToken)) { throw "Telegram bot token cannot be empty when enabled." }
    if ($Config.channels.discord.enabled -and [string]::IsNullOrWhiteSpace([string]$Config.channels.discord.token)) { throw "Discord bot token cannot be empty when enabled." }
    if ($Config.channels.slack.enabled) {
        if ([string]::IsNullOrWhiteSpace([string]$Config.channels.slack.botToken)) { throw "Slack bot token cannot be empty when enabled." }
        if ($Config.channels.slack.mode -eq "socket" -and [string]::IsNullOrWhiteSpace([string]$Config.channels.slack.appToken)) { throw "Slack socket mode requires appToken." }
        if ($Config.channels.slack.mode -eq "http" -and [string]::IsNullOrWhiteSpace([string]$Config.channels.slack.signingSecret)) { throw "Slack HTTP mode requires signingSecret." }
    }
    if ($Config.channels.line.enabled -and ([string]::IsNullOrWhiteSpace([string]$Config.channels.line.channelAccessToken) -or [string]::IsNullOrWhiteSpace([string]$Config.channels.line.channelSecret))) { throw "LINE token/secret cannot be empty when enabled." }
}

function Invoke-ExternalCommand([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory = "", [switch]$AllowFailure) {
    $quotedArgs = $Arguments | ForEach-Object { if ($_ -match "\s") { '"' + $_ + '"' } else { $_ } }
    $display = $FilePath + " " + ($quotedArgs -join " ")
    if ($DryRun) { Write-DryRun $display; return }
    if ($WorkingDirectory) { Push-Location $WorkingDirectory }
    try {
        & $FilePath @Arguments
        $exitCode = $LASTEXITCODE
    } finally {
        if ($WorkingDirectory) { Pop-Location }
    }
    if (($null -ne $exitCode) -and $exitCode -ne 0 -and -not $AllowFailure) { throw "Command failed ($exitCode): $display" }
}

function Refresh-UserPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = (@($machinePath, $userPath) | Where-Object { $_ }) -join ";"
}

function Get-OpenClawCommandPath {
    $cmd = Get-Command openclaw.cmd -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $generic = Get-Command openclaw -ErrorAction SilentlyContinue
    if ($generic -and $generic.Source -like "*.ps1") {
        $candidate = [System.IO.Path]::ChangeExtension($generic.Source, ".cmd")
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    Refresh-UserPath
    $cmd = Get-Command openclaw.cmd -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Install-OpenClawIfNeeded([hashtable]$Config) {
    if ($SkipOpenClawInstall) { Write-WarnLine "Skipped official installer."; return }
    Write-Section "Install Node.js and OpenClaw"
    $tempInstaller = Join-Path $env:TEMP ("openclaw-install-" + [guid]::NewGuid().ToString("n") + ".ps1")
    if ($DryRun) {
        Write-DryRun "Download https://openclaw.ai/install.ps1 -> $tempInstaller"
        Write-DryRun "$PowerShellExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$tempInstaller`" -NoOnboard -Tag $($Config.openclaw.tag)"
        return
    }
    Invoke-WebRequest -UseBasicParsing -Uri "https://openclaw.ai/install.ps1" -OutFile $tempInstaller
    try {
        Invoke-ExternalCommand -FilePath $PowerShellExe -Arguments @("-NoLogo","-NoProfile","-ExecutionPolicy","Bypass","-File",$tempInstaller,"-NoOnboard","-Tag",[string]$Config.openclaw.tag)
    } finally {
        if (Test-Path -LiteralPath $tempInstaller) { Remove-Item -LiteralPath $tempInstaller -Force }
    }
}

function Build-OpenClawConfigFragment([hashtable]$Config) {
    $modelRef = [string]$Config.model.modelRef
    $fragment = @{
        gateway = @{ mode = "local" }
        agents = @{ defaults = @{ workspace = [string]$Config.workspace.path; model = @{ primary = $modelRef }; models = @{} } }
    }
    $fragment.agents.defaults.models[$modelRef] = @{ alias = "Default Model" }
    if ($Config.model.providerKind -eq "custom") {
        $compat = @{}
        if ($Config.model.requiresStringContent) { $compat.requiresStringContent = $true }
        if (-not $Config.model.supportsTools) { $compat.supportsTools = $false }
        $modelEntry = @{
            id = [string]$Config.model.customModelId; name = [string]$Config.model.customModelName; reasoning = $false; input = @("text")
            cost = @{ input = 0; output = 0; cacheRead = 0; cacheWrite = 0 }
            contextWindow = [int]$Config.model.contextWindow; maxTokens = [int]$Config.model.maxTokens
        }
        if ($compat.Count -gt 0) { $modelEntry.compat = $compat }
        $providers = @{}
        $providers[[string]$Config.model.providerId] = @{ baseUrl = [string]$Config.model.baseUrl; apiKey = '${CUSTOM_OPENAI_API_KEY}'; api = [string]$Config.model.customApi; models = @($modelEntry) }
        $fragment.models = @{ mode = "merge"; providers = $providers }
    }
    $channels = @{}
    if ($Config.channels.feishu.enabled) {
        $accounts = @{}
        $accounts[[string]$Config.channels.feishu.accountId] = @{ appId = '${FEISHU_APP_ID}'; appSecret = '${FEISHU_APP_SECRET}'; name = [string]$Config.channels.feishu.accountName }
        $channels.feishu = @{
            enabled = $true; domain = [string]$Config.channels.feishu.domain; connectionMode = [string]$Config.channels.feishu.connectionMode
            dmPolicy = [string]$Config.channels.feishu.dmPolicy; groupPolicy = [string]$Config.channels.feishu.groupPolicy; requireMention = [bool]$Config.channels.feishu.requireMention
            typingIndicator = [bool]$Config.channels.feishu.typingIndicator; resolveSenderNames = [bool]$Config.channels.feishu.resolveSenderNames; accounts = $accounts
        }
        if ($Config.channels.feishu.connectionMode -eq "webhook") {
            $channels.feishu.verificationToken = '${FEISHU_VERIFICATION_TOKEN}'
            $channels.feishu.encryptKey = '${FEISHU_ENCRYPT_KEY}'
            $channels.feishu.webhookPath = [string]$Config.channels.feishu.webhookPath
            $channels.feishu.webhookHost = [string]$Config.channels.feishu.webhookHost
            $channels.feishu.webhookPort = [int]$Config.channels.feishu.webhookPort
        }
    }
    if ($Config.channels.qqbot.enabled) { $channels.qqbot = @{ enabled = $true; appId = '${QQBOT_APP_ID}'; clientSecret = '${QQBOT_CLIENT_SECRET}'; dmPolicy = [string]$Config.channels.qqbot.dmPolicy } }
    if ($Config.channels.telegram.enabled) { $channels.telegram = @{ enabled = $true; botToken = '${TELEGRAM_BOT_TOKEN}'; dmPolicy = [string]$Config.channels.telegram.dmPolicy; groups = @{ "*" = @{ requireMention = [bool]$Config.channels.telegram.requireMention } } } }
    if ($Config.channels.discord.enabled) { $channels.discord = @{ enabled = $true; token = '${DISCORD_BOT_TOKEN}'; dmPolicy = [string]$Config.channels.discord.dmPolicy; groupPolicy = [string]$Config.channels.discord.groupPolicy } }
    if ($Config.channels.slack.enabled) {
        $channels.slack = @{ enabled = $true; mode = [string]$Config.channels.slack.mode; botToken = '${SLACK_BOT_TOKEN}'; dmPolicy = [string]$Config.channels.slack.dmPolicy; groupPolicy = [string]$Config.channels.slack.groupPolicy }
        if ($Config.channels.slack.mode -eq "socket") { $channels.slack.appToken = '${SLACK_APP_TOKEN}' } else { $channels.slack.signingSecret = '${SLACK_SIGNING_SECRET}'; $channels.slack.webhookPath = [string]$Config.channels.slack.webhookPath }
    }
    if ($Config.channels.line.enabled) { $channels.line = @{ enabled = $true; channelAccessToken = '${LINE_CHANNEL_ACCESS_TOKEN}'; channelSecret = '${LINE_CHANNEL_SECRET}'; dmPolicy = [string]$Config.channels.line.dmPolicy; webhookPath = [string]$Config.channels.line.webhookPath } }
    if ($Config.channels.whatsapp.enabled) { $channels.whatsapp = @{ enabled = $true; dmPolicy = [string]$Config.channels.whatsapp.dmPolicy; groupPolicy = [string]$Config.channels.whatsapp.groupPolicy } }
    if ($channels.Count -gt 0) { $fragment.channels = $channels }
    return $fragment
}

function Build-EnvUpdates([hashtable]$Config) {
    $providerSpec = Get-ProviderSpec -ProviderKind $Config.model.providerKind
    $updates = @{}
    if (-not [string]::IsNullOrWhiteSpace([string]$Config.model.apiKey)) { $updates[[string]$providerSpec.apiKeyEnv] = [string]$Config.model.apiKey }
    if ($Config.model.providerKind -eq "custom") { $updates["CUSTOM_OPENAI_API_KEY"] = [string]$Config.model.apiKey }
    if ($Config.channels.feishu.enabled) {
        $updates["FEISHU_APP_ID"] = [string]$Config.channels.feishu.appId
        $updates["FEISHU_APP_SECRET"] = [string]$Config.channels.feishu.appSecret
        if ($Config.channels.feishu.connectionMode -eq "webhook") {
            $updates["FEISHU_VERIFICATION_TOKEN"] = [string]$Config.channels.feishu.verificationToken
            $updates["FEISHU_ENCRYPT_KEY"] = [string]$Config.channels.feishu.encryptKey
        }
    }
    if ($Config.channels.qqbot.enabled) { $updates["QQBOT_APP_ID"] = [string]$Config.channels.qqbot.appId; $updates["QQBOT_CLIENT_SECRET"] = [string]$Config.channels.qqbot.clientSecret }
    if ($Config.channels.telegram.enabled) { $updates["TELEGRAM_BOT_TOKEN"] = [string]$Config.channels.telegram.botToken }
    if ($Config.channels.discord.enabled) { $updates["DISCORD_BOT_TOKEN"] = [string]$Config.channels.discord.token }
    if ($Config.channels.slack.enabled) {
        $updates["SLACK_BOT_TOKEN"] = [string]$Config.channels.slack.botToken
        if ($Config.channels.slack.mode -eq "socket") { $updates["SLACK_APP_TOKEN"] = [string]$Config.channels.slack.appToken } else { $updates["SLACK_SIGNING_SECRET"] = [string]$Config.channels.slack.signingSecret }
    }
    if ($Config.channels.line.enabled) { $updates["LINE_CHANNEL_ACCESS_TOKEN"] = [string]$Config.channels.line.channelAccessToken; $updates["LINE_CHANNEL_SECRET"] = [string]$Config.channels.line.channelSecret }
    return $updates
}

function Configure-OpenClawFiles([hashtable]$Config) {
    Write-Section "Write config"
    Ensure-Directory $OpenClawHome
    Ensure-Directory ([string]$Config.workspace.path)
    $mergedConfig = Merge-Hashtable -Base (Load-JsonAsHashtable $OpenClawConfigPath) -Overlay (Build-OpenClawConfigFragment -Config $Config)
    Backup-FileIfExists $OpenClawConfigPath
    Save-JsonFile -Path $OpenClawConfigPath -Data $mergedConfig
    $envMap = Load-EnvMap $OpenClawEnvPath
    $updates = Build-EnvUpdates -Config $Config
    foreach ($key in $updates.Keys) { $envMap[$key] = $updates[$key] }
    Backup-FileIfExists $OpenClawEnvPath
    Save-EnvMap -Path $OpenClawEnvPath -Map $envMap
    Write-Step "Config updated."
}

function Get-RequestedSkillSlugs([hashtable]$Config) {
    $slugs = @()
    foreach ($slug in @($Config.skills.presetSlugs)) { if (-not [string]::IsNullOrWhiteSpace([string]$slug)) { $slugs += [string]$slug } }
    foreach ($slug in @($Config.skills.customSlugs)) { if (-not [string]::IsNullOrWhiteSpace([string]$slug)) { $slugs += [string]$slug } }
    return @($slugs | Select-Object -Unique)
}

function Install-SelectedPlugins([string]$OpenClawCommand, [hashtable]$Config) {
    $packages = @()
    foreach ($definition in $script:ChannelCatalog) {
        if ([string]::IsNullOrWhiteSpace([string]$definition.pluginPackage)) { continue }
        $channel = $Config.channels[[string]$definition.id]
        if ($channel -and ($channel.selected -or $channel.enabled) -and $channel.installPlugin) { $packages += [string]$definition.pluginPackage }
    }
    $packages = @($packages | Select-Object -Unique)
    if ($packages.Count -eq 0) { Write-Step "No extra channel plugins selected."; return }
    Write-Section "Install selected plugins"
    foreach ($package in $packages) {
        Write-Step "Installing plugin: $package"
        Invoke-ExternalCommand -FilePath $OpenClawCommand -Arguments @("plugins","install",$package) -WorkingDirectory $Config.workspace.path
    }
}

function Install-Skills([string]$OpenClawCommand, [hashtable]$Config) {
    if ($SkipSkills) { Write-WarnLine "Skipped skills install."; return }
    $skills = Get-RequestedSkillSlugs -Config $Config
    if ($skills.Count -eq 0) { Write-Step "No skills selected."; return }
    Write-Section "Install skills"
    foreach ($slug in $skills) {
        Write-Step "Install skill: $slug"
        Invoke-ExternalCommand -FilePath $OpenClawCommand -Arguments @("skills","install",$slug,"--force") -WorkingDirectory $Config.workspace.path
    }
}

function Create-HelperScripts([hashtable]$Config) {
    if (-not $Config.gateway.createHelperScripts) { return }
    Write-Section "Create helper launchers"
    $helperDir = [string]$Config.gateway.helperDir
    Ensure-Directory $helperDir
    $files = @{
        "01-OpenClaw Dashboard.bat" = "@echo off`r`ncmd /d /c openclaw.cmd dashboard`r`n"
        "02-Restart Gateway.bat" = "@echo off`r`ncmd /d /c openclaw.cmd gateway restart`r`ncmd /d /c openclaw.cmd gateway status`r`npause`r`n"
        "03-Gateway Status.bat" = "@echo off`r`ncmd /d /c openclaw.cmd gateway status`r`npause`r`n"
        "04-Follow Logs.bat" = "@echo off`r`ncmd /d /c openclaw.cmd logs --follow`r`n"
        "05-Pairing List.bat" = "@echo off`r`ncmd /d /c openclaw.cmd pairing list`r`npause`r`n"
    }
    foreach ($name in $files.Keys) { Save-Utf8Text -Path (Join-Path $helperDir $name) -Content $files[$name] }
}

function Get-CallbackUrl([string]$PublicBaseUrl, [string]$PathValue) {
    if ([string]::IsNullOrWhiteSpace($PublicBaseUrl)) { return "" }
    $trimmedBase = $PublicBaseUrl.TrimEnd("/")
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $trimmedBase }
    $trimmedPath = if ($PathValue.StartsWith("/")) { $PathValue } else { "/" + $PathValue }
    return $trimmedBase + $trimmedPath
}

function Write-InstallSummary([hashtable]$Config) {
    if (-not $Config.gateway.writeSummaryFile) { return }
    Write-Section "Write install summary"
    $lines = @()
    $lines += "OpenClaw Windows install summary"
    $lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += ""
    $lines += "Workspace: $($Config.workspace.path)"
    $lines += "Config: $OpenClawConfigPath"
    $lines += "Env: $OpenClawEnvPath"
    $lines += "Model: $($Config.model.modelRef)"
    $lines += ""
    $lines += "Channels"
    foreach ($definition in $script:ChannelCatalog) {
        $channel = $Config.channels[[string]$definition.id]
        if (-not $channel.selected -and -not $channel.enabled) { continue }
        $state = if ($channel.enabled) { "configured" } else { "selected but skipped" }
        $lines += "- $($definition.label): $state"
        switch ($definition.id) {
            "feishu" { if ($channel.enabled -and $channel.connectionMode -eq "webhook") { $lines += "  callback URL: $(Get-CallbackUrl $Config.gateway.publicBaseUrl $channel.webhookPath)" } }
            "slack" { if ($channel.enabled -and $channel.mode -eq "http") { $lines += "  callback URL: $(Get-CallbackUrl $Config.gateway.publicBaseUrl $channel.webhookPath)" } }
            "line" { if ($channel.enabled) { $lines += "  callback URL: $(Get-CallbackUrl $Config.gateway.publicBaseUrl $channel.webhookPath)" } }
            "whatsapp" { if ($channel.selected) { $lines += "  login after install: $($channel.runLoginAfterInstall)" } }
        }
    }
    $lines += ""
    $lines += "Skills"
    $skillSlugs = @(Get-RequestedSkillSlugs -Config $Config)
    if ($skillSlugs.Count -eq 0) { $lines += "- none selected" } else { foreach ($slug in $skillSlugs) { $lines += "- $slug" } }
    $lines += ""
    $lines += "Next actions"
    $lines += "1. Run openclaw doctor --non-interactive"
    $lines += "2. Run openclaw gateway status"
    $lines += "3. Follow the PDF manual in docs/"
    Save-Utf8Text -Path ([string]$Config.gateway.summaryPath) -Content (($lines -join [Environment]::NewLine) + [Environment]::NewLine)
    Write-Step "Summary written: $($Config.gateway.summaryPath)"
}

function Run-PostInstallChannelLogins([string]$OpenClawCommand, [hashtable]$Config) {
    if ($Config.channels.whatsapp.selected -and $Config.channels.whatsapp.runLoginAfterInstall) {
        Write-Section "WhatsApp login"
        Invoke-ExternalCommand -FilePath $OpenClawCommand -Arguments @("channels","login","--channel","whatsapp") -AllowFailure
    }
}

function Start-OpenClawGateway([string]$OpenClawCommand, [hashtable]$Config) {
    Write-Section "Verify and start"
    Invoke-ExternalCommand -FilePath $OpenClawCommand -Arguments @("doctor","--non-interactive") -AllowFailure
    if ($Config.openclaw.installDaemon) { Invoke-ExternalCommand -FilePath $OpenClawCommand -Arguments @("gateway","install","--force") -AllowFailure }
    if ($Config.openclaw.startGateway) { Invoke-ExternalCommand -FilePath $OpenClawCommand -Arguments @("gateway","restart") -AllowFailure }
    Invoke-ExternalCommand -FilePath $OpenClawCommand -Arguments @("gateway","status") -AllowFailure
    if ($Config.openclaw.openDashboard) { Invoke-ExternalCommand -FilePath $OpenClawCommand -Arguments @("dashboard") -AllowFailure }
}

try {
    Write-Section "OpenClaw Windows Installer"
    Write-Step "Script root: $ScriptRoot"
    $config = if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) { Normalize-InstallerConfig -InputConfig (Load-JsonAsHashtable -Path $ConfigPath) }
    elseif ($NonInteractive) { throw "NonInteractive mode requires -ConfigPath." } else { Collect-InteractiveConfig }
    Validate-InstallerConfig -Config $config
    if (-not $NonInteractive -and $config.skills.saveGeneratedConfig) {
        $generatedPath = Join-Path $ScriptRoot "installer-config.generated.json"
        Save-JsonFile -Path $generatedPath -Data $config
        Write-Step "Generated config saved: $generatedPath"
    }
    Install-OpenClawIfNeeded -Config $config
    $openclawCommand = Get-OpenClawCommandPath
    if (-not $openclawCommand) { throw "openclaw.cmd not found. Reopen PowerShell and try again." }
    Configure-OpenClawFiles -Config $config
    Install-SelectedPlugins -OpenClawCommand $openclawCommand -Config $config
    Install-Skills -OpenClawCommand $openclawCommand -Config $config
    Create-HelperScripts -Config $config
    Write-InstallSummary -Config $config
    Run-PostInstallChannelLogins -OpenClawCommand $openclawCommand -Config $config
    Start-OpenClawGateway -OpenClawCommand $openclawCommand -Config $config
    Write-Section "Done"
    Write-Host "OpenClaw install flow completed." -ForegroundColor Green
    Write-Host "Check the generated summary and PDF manual before handing the package to others."
} catch {
    Write-Host ""
    Write-Host "Install failed: " -ForegroundColor Red -NoNewline
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
} finally {
    if (-not $NoPause -and $Host.Name -eq "ConsoleHost") { Write-Host ""; Read-Host "Press Enter to exit" }
}
