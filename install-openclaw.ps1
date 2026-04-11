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
    $options = @()
    foreach ($value in $Values) { $options += [ordered]@{ id = $value; label = $value; summary = "Use $value policy." } }
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
    if (-not (Prompt-YesNo "Configure Feishu credentials now?" $true)) { $channel.enabled = $false; return }
    $channel.enabled = $true
    $channel.domain = Prompt-Default "Feishu domain (feishu or lark)" $channel.domain
    $channel.accountId = Prompt-Default "Feishu account id" $channel.accountId
    $channel.accountName = Prompt-Default "Feishu bot display name" $channel.accountName
    $channel.appId = Prompt-Default "Feishu App ID" "cli_xxx"
    $channel.appSecret = Read-SecretText "Feishu App Secret"
    $channel.connectionMode = Prompt-Choice -Title "Feishu connection mode" -Options @(
        [ordered]@{ id = "websocket"; label = "websocket"; summary = "Recommended. No public webhook needed." },
        [ordered]@{ id = "webhook"; label = "webhook"; summary = "Need verification token and encrypt key." }
    ) -DefaultId $channel.connectionMode
    $channel.dmPolicy = Prompt-Policy "Feishu DM policy" @("pairing", "allowlist", "open", "disabled") $channel.dmPolicy
    $channel.groupPolicy = Prompt-Policy "Feishu group policy" @("allowlist", "open", "disabled") $channel.groupPolicy
    $channel.requireMention = Prompt-YesNo "Require @mention in Feishu groups?" $channel.requireMention
    if ($channel.connectionMode -eq "webhook") {
        $channel.verificationToken = Read-SecretText "Feishu verification token"
        $channel.encryptKey = Read-SecretText "Feishu encrypt key"
        $channel.webhookPath = Prompt-Default "Feishu webhook path" $channel.webhookPath
        $channel.webhookHost = Prompt-Default "Feishu webhook host" $channel.webhookHost
        $channel.webhookPort = [int](Prompt-Default "Feishu webhook port" ([string]$channel.webhookPort))
    }
}

function Configure-QqBotChannel([hashtable]$Config) {
    $channel = $Config.channels.qqbot; $channel.selected = $true
    $channel.installPlugin = Prompt-YesNo "Install QQ Bot plugin now?" $channel.installPlugin
    if (-not (Prompt-YesNo "Configure QQ Bot now?" $true)) { $channel.enabled = $false; return }
    $channel.enabled = $true
    $channel.appId = Prompt-Default "QQ Bot AppID" ""
    $channel.clientSecret = Read-SecretText "QQ Bot AppSecret"
    $channel.dmPolicy = Prompt-Policy "QQ Bot DM policy" @("pairing", "allowlist", "open", "disabled") $channel.dmPolicy
}

function Configure-TelegramChannel([hashtable]$Config) {
    $channel = $Config.channels.telegram; $channel.selected = $true
    if (-not (Prompt-YesNo "Configure Telegram now?" $true)) { $channel.enabled = $false; return }
    $channel.enabled = $true
    $channel.botToken = Read-SecretText "Telegram bot token"
    $channel.dmPolicy = Prompt-Policy "Telegram DM policy" @("pairing", "allowlist", "open", "disabled") $channel.dmPolicy
    $channel.requireMention = Prompt-YesNo "Require @mention in Telegram groups?" $channel.requireMention
}

function Configure-DiscordChannel([hashtable]$Config) {
    $channel = $Config.channels.discord; $channel.selected = $true
    if (-not (Prompt-YesNo "Configure Discord now?" $true)) { $channel.enabled = $false; return }
    $channel.enabled = $true
    $channel.token = Read-SecretText "Discord bot token"
    $channel.dmPolicy = Prompt-Policy "Discord DM policy" @("pairing", "allowlist", "open", "disabled") $channel.dmPolicy
    $channel.groupPolicy = Prompt-Policy "Discord group policy" @("allowlist", "open", "disabled") $channel.groupPolicy
}

function Configure-SlackChannel([hashtable]$Config) {
    $channel = $Config.channels.slack; $channel.selected = $true
    if (-not (Prompt-YesNo "Configure Slack now?" $true)) { $channel.enabled = $false; return }
    $channel.enabled = $true
    $channel.mode = Prompt-Choice -Title "Slack mode" -Options @(
        [ordered]@{ id = "socket"; label = "socket"; summary = "Needs bot token + app token." },
        [ordered]@{ id = "http"; label = "http"; summary = "Needs bot token + signing secret + callback URL." }
    ) -DefaultId $channel.mode
    $channel.botToken = Read-SecretText "Slack bot token (xoxb-...)"
    if ($channel.mode -eq "socket") { $channel.appToken = Read-SecretText "Slack app token (xapp-...)" }
    else {
        $channel.signingSecret = Read-SecretText "Slack signing secret"
        $channel.webhookPath = Prompt-Default "Slack webhook path" $channel.webhookPath
    }
    $channel.dmPolicy = Prompt-Policy "Slack DM policy" @("pairing", "allowlist", "open", "disabled") $channel.dmPolicy
    $channel.groupPolicy = Prompt-Policy "Slack channel policy" @("allowlist", "open", "disabled") $channel.groupPolicy
}

function Configure-LineChannel([hashtable]$Config) {
    $channel = $Config.channels.line; $channel.selected = $true
    if (-not (Prompt-YesNo "Configure LINE now?" $true)) { $channel.enabled = $false; return }
    $channel.enabled = $true
    $channel.channelAccessToken = Read-SecretText "LINE channel access token"
    $channel.channelSecret = Read-SecretText "LINE channel secret"
    $channel.dmPolicy = Prompt-Policy "LINE DM policy" @("pairing", "allowlist", "open", "disabled") $channel.dmPolicy
    $channel.webhookPath = Prompt-Default "LINE webhook path" $channel.webhookPath
}

function Configure-WhatsAppChannel([hashtable]$Config) {
    $channel = $Config.channels.whatsapp; $channel.selected = $true
    $channel.installPlugin = Prompt-YesNo "Install WhatsApp plugin now?" $channel.installPlugin
    $channel.enabled = Prompt-YesNo "Enable WhatsApp config now?" $true
    $channel.dmPolicy = Prompt-Policy "WhatsApp DM policy" @("pairing", "allowlist", "open", "disabled") $channel.dmPolicy
    $channel.groupPolicy = Prompt-Policy "WhatsApp group policy" @("allowlist", "open", "disabled") $channel.groupPolicy
    $channel.runLoginAfterInstall = Prompt-YesNo "Run WhatsApp QR login after install?" $channel.runLoginAfterInstall
}

function Collect-InteractiveConfig {
    Write-Section "OpenClaw Windows Installer Wizard"
    $providerKind = Prompt-Choice -Title "Choose a model provider" -Options @(
        [ordered]@{ id = "openai"; label = "OpenAI"; summary = "Use OPENAI_API_KEY." },
        [ordered]@{ id = "openrouter"; label = "OpenRouter"; summary = "Use OPENROUTER_API_KEY." },
        [ordered]@{ id = "moonshot"; label = "Moonshot"; summary = "Use MOONSHOT_API_KEY." },
        [ordered]@{ id = "custom"; label = "Custom OpenAI-compatible"; summary = "Use your own Base URL + API key." }
    ) -DefaultId "openai"
    $config = Normalize-InstallerConfig -InputConfig @{ model = @{ providerKind = $providerKind } }
    $providerSpec = Get-ProviderSpec -ProviderKind $providerKind
    $config.openclaw.tag = Prompt-Default "OpenClaw tag" $config.openclaw.tag
    $config.workspace.path = Expand-PathLike (Prompt-Default "Workspace path" $config.workspace.path) $ScriptRoot
    $config.openclaw.installDaemon = Prompt-YesNo "Install gateway service?" $config.openclaw.installDaemon
    $config.openclaw.startGateway = Prompt-YesNo "Start gateway after config?" $config.openclaw.startGateway
    $config.openclaw.openDashboard = Prompt-YesNo "Open dashboard after config?" $config.openclaw.openDashboard
    if ($providerKind -eq "custom") {
        $config.model.providerId = Prompt-Default "Custom provider id" $config.model.providerId
        $config.model.baseUrl = Prompt-Default "Custom Base URL (must include /v1)" "https://your-api.example.com/v1"
        $config.model.customModelId = Prompt-Default "Custom model id" $config.model.customModelId
        $config.model.customModelName = Prompt-Default "Custom model display name" $config.model.customModelName
        $config.model.customApi = Prompt-Default "Custom API type" $config.model.customApi
        $config.model.contextWindow = [int](Prompt-Default "Context window tokens" ([string]$config.model.contextWindow))
        $config.model.maxTokens = [int](Prompt-Default "Max output tokens" ([string]$config.model.maxTokens))
        $config.model.requiresStringContent = Prompt-YesNo "Backend requires string-only content?" $config.model.requiresStringContent
        $config.model.supportsTools = Prompt-YesNo "Backend supports tool calling?" $config.model.supportsTools
        $config.model.modelRef = "{0}/{1}" -f $config.model.providerId, $config.model.customModelId
    } else {
        $config.model.modelRef = Prompt-Default "Default model ref provider/model" $providerSpec.defaultModelRef
    }
    $config.model.apiKey = Read-SecretText "Model API Key"
    $selectedChannels = Prompt-MultiSelect -Title "Choose channels to configure" -Options $script:ChannelCatalog
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
    if ($needsPublicBaseUrl) { $config.gateway.publicBaseUrl = Prompt-Default "Public gateway base URL (https://...)" "" }
    $config.skills.presetSlugs = @(
        Prompt-MultiSelect -Title "Choose recommended skills to install" -Options ($script:SkillCatalog | ForEach-Object {
            [ordered]@{ id = $_.slug; label = $_.label; summary = $_.summary }
        })
    )
    $config.skills.customSlugs = Split-CommaList (Prompt-Default "Custom skill slugs to install (comma separated, optional)" "")
    $config.gateway.writeSummaryFile = Prompt-YesNo "Write install summary file?" $config.gateway.writeSummaryFile
    $config.gateway.createHelperScripts = Prompt-YesNo "Create helper launcher .bat files?" $config.gateway.createHelperScripts
    $config.skills.saveGeneratedConfig = Prompt-YesNo "Save installer-config.generated.json?" $config.skills.saveGeneratedConfig
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
