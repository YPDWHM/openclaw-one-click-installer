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

function Write-Section([string]$Text) {
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Write-Step([string]$Text) {
    Write-Host "[*] $Text" -ForegroundColor Green
}

function Write-WarnLine([string]$Text) {
    Write-Host "[!] $Text" -ForegroundColor Yellow
}

function Write-DryRun([string]$Text) {
    Write-Host "[DRY RUN] $Text" -ForegroundColor Magenta
}

function ConvertTo-PlainObject($InputObject) {
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string] -or $InputObject.GetType().IsPrimitive) { return $InputObject }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) {
            $result[[string]$key] = ConvertTo-PlainObject $InputObject[$key]
        }
        return $result
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = @()
        foreach ($item in $InputObject) {
            $items += ,(ConvertTo-PlainObject $item)
        }
        return $items
    }
    if ($InputObject -is [pscustomobject]) {
        $result = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-PlainObject $property.Value
        }
        return $result
    }
    return $InputObject
}

function Merge-Hashtable([hashtable]$Base, [hashtable]$Overlay) {
    $result = @{}
    if ($Base) {
        foreach ($key in $Base.Keys) {
            $result[$key] = ConvertTo-PlainObject $Base[$key]
        }
    }
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
    if ($DryRun) {
        Write-DryRun "Write JSON $Path"
        return
    }
    $json = $Data | ConvertTo-Json -Depth 100
    $dir = Split-Path -Parent $Path
    if ($dir) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
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
    if ($DryRun) {
        Write-DryRun "Write env $Path"
        return
    }
    $dir = Split-Path -Parent $Path
    if ($dir) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $lines = @()
    foreach ($key in ($Map.Keys | Sort-Object)) {
        $lines += "$key=$($Map[$key])"
    }
    [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Backup-FileIfExists([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $backupPath = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    if ($DryRun) {
        Write-DryRun "Backup $Path -> $backupPath"
        return
    }
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    Write-Step "Backup created: $backupPath"
}

function Ensure-Directory([string]$Path) {
    if ($DryRun) {
        Write-DryRun "Create directory $Path"
        return
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Expand-UserPath([string]$PathValue) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $PathValue }
    $expanded = $PathValue.Replace("%USERPROFILE%", $HomeDir)
    if ($expanded -eq "~") { $expanded = $HomeDir }
    if ($expanded.StartsWith("~\")) { $expanded = Join-Path $HomeDir $expanded.Substring(2) }
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

function Prompt-Default([string]$Prompt, [string]$DefaultValue = "") {
    if ([string]::IsNullOrEmpty($DefaultValue)) {
        return (Read-Host $Prompt).Trim()
    }
    $value = Read-Host "$Prompt [$DefaultValue]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $DefaultValue }
    return $value.Trim()
}

function Prompt-YesNo([string]$Prompt, [bool]$DefaultValue) {
    $hint = if ($DefaultValue) { "Y/n" } else { "y/N" }
    $value = Read-Host "$Prompt [$hint]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $DefaultValue }
    return @("y", "yes") -contains $value.Trim().ToLowerInvariant()
}

function Read-SecretText([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        if ($ptr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
    }
}

function Normalize-InstallerConfig([hashtable]$InputConfig) {
    $defaults = @{
        openclaw = @{ tag = "latest"; installDaemon = $true; startGateway = $true; openDashboard = $true }
        workspace = @{ path = "%USERPROFILE%\.openclaw\workspace" }
        model = @{
            providerKind = "openai"; modelRef = ""; apiKey = ""; baseUrl = ""; providerId = "customai"
            customModelId = "your-model-id"; customModelName = "My Custom Model"; customApi = "openai-completions"
            contextWindow = 131072; maxTokens = 8192; requiresStringContent = $false; supportsTools = $true
        }
        channels = @{
            feishu = @{ enabled = $false; domain = "feishu"; accountId = "main"; accountName = "OpenClaw Assistant"; appId = ""; appSecret = "" }
            qqbot = @{ enabled = $false; appId = ""; clientSecret = "" }
        }
        skills = @{ slugs = @() }
    }
    $config = Merge-Hashtable -Base $defaults -Overlay $InputConfig
    $providerSpec = Get-ProviderSpec -ProviderKind $config.model.providerKind
    if ([string]::IsNullOrWhiteSpace([string]$config.model.modelRef)) {
        if ($config.model.providerKind -ieq "custom") {
            $config.model.modelRef = "{0}/{1}" -f $config.model.providerId, $config.model.customModelId
        } else {
            $config.model.modelRef = $providerSpec.defaultModelRef
        }
    }
    $config.workspace.path = Expand-UserPath ([string]$config.workspace.path)
    return $config
}

function Collect-InteractiveConfig {
    Write-Section "Interactive Config"
    $providerKind = Prompt-Default "Provider (openai/openrouter/moonshot/custom)" "openai"
    $providerSpec = Get-ProviderSpec -ProviderKind $providerKind
    $config = @{
        openclaw = @{ tag = (Prompt-Default "OpenClaw tag" "latest"); installDaemon = $true; startGateway = $true; openDashboard = $true }
        workspace = @{ path = (Prompt-Default "Workspace path" "%USERPROFILE%\.openclaw\workspace") }
        model = @{
            providerKind = $providerKind; modelRef = ""; apiKey = ""; baseUrl = ""; providerId = "customai"
            customModelId = "your-model-id"; customModelName = "My Custom Model"; customApi = "openai-completions"
            contextWindow = 131072; maxTokens = 8192; requiresStringContent = $false; supportsTools = $true
        }
        channels = @{
            feishu = @{ enabled = $false; domain = "feishu"; accountId = "main"; accountName = "OpenClaw Assistant"; appId = ""; appSecret = "" }
            qqbot = @{ enabled = $false; appId = ""; clientSecret = "" }
        }
        skills = @{ slugs = @() }
    }
    if ($providerKind -ieq "custom") {
        $config.model.providerId = Prompt-Default "Custom providerId" "customai"
        $config.model.baseUrl = Prompt-Default "Custom Base URL (include /v1)" "https://your-api.example.com/v1"
        $config.model.customModelId = Prompt-Default "Custom model ID" "your-model-id"
        $config.model.customModelName = Prompt-Default "Custom model display name" "My Custom Model"
        $config.model.customApi = Prompt-Default "Custom API type" "openai-completions"
        $config.model.contextWindow = [int](Prompt-Default "Context window tokens" "131072")
        $config.model.maxTokens = [int](Prompt-Default "Max output tokens" "8192")
        $config.model.requiresStringContent = Prompt-YesNo "Backend requires string-only content" $false
        $config.model.supportsTools = Prompt-YesNo "Backend supports tool calling" $true
        $config.model.modelRef = "{0}/{1}" -f $config.model.providerId, $config.model.customModelId
    } else {
        $config.model.modelRef = Prompt-Default "Default model ref provider/model" $providerSpec.defaultModelRef
    }
    $config.model.apiKey = Read-SecretText "Model API Key"
    $config.channels.feishu.enabled = Prompt-YesNo "Enable Feishu bot" $false
    if ($config.channels.feishu.enabled) {
        $config.channels.feishu.domain = Prompt-Default "Feishu domain (feishu or lark)" "feishu"
        $config.channels.feishu.accountId = Prompt-Default "Feishu account ID" "main"
        $config.channels.feishu.accountName = Prompt-Default "Feishu bot display name" "OpenClaw Assistant"
        $config.channels.feishu.appId = Prompt-Default "Feishu App ID" "cli_xxx"
        $config.channels.feishu.appSecret = Read-SecretText "Feishu App Secret"
    }
    $config.channels.qqbot.enabled = Prompt-YesNo "Enable QQ Bot" $false
    if ($config.channels.qqbot.enabled) {
        $config.channels.qqbot.appId = Prompt-Default "QQ Bot AppID" ""
        $config.channels.qqbot.clientSecret = Read-SecretText "QQ Bot AppSecret"
    }
    $config.skills.slugs = Split-CommaList (Prompt-Default "Skills to install, comma separated" "")
    $config.openclaw.installDaemon = Prompt-YesNo "Install gateway service" $true
    $config.openclaw.startGateway = Prompt-YesNo "Start gateway after config" $true
    $config.openclaw.openDashboard = Prompt-YesNo "Open dashboard after config" $true
    return Normalize-InstallerConfig -InputConfig $config
}

function Validate-InstallerConfig([hashtable]$Config) {
    if ([string]::IsNullOrWhiteSpace([string]$Config.openclaw.tag)) { throw "openclaw.tag cannot be empty." }
    if ([string]::IsNullOrWhiteSpace([string]$Config.workspace.path)) { throw "workspace.path cannot be empty." }
    if ([string]::IsNullOrWhiteSpace([string]$Config.model.providerKind)) { throw "model.providerKind cannot be empty." }
    if ([string]::IsNullOrWhiteSpace([string]$Config.model.apiKey)) { throw "model.apiKey cannot be empty." }
    if ([string]::IsNullOrWhiteSpace([string]$Config.model.modelRef)) { throw "model.modelRef cannot be empty." }
    if ($Config.model.providerKind -ieq "custom" -and [string]::IsNullOrWhiteSpace([string]$Config.model.baseUrl)) { throw "model.baseUrl cannot be empty in custom mode." }
    if ($Config.channels.feishu.enabled -and ([string]::IsNullOrWhiteSpace([string]$Config.channels.feishu.appId) -or [string]::IsNullOrWhiteSpace([string]$Config.channels.feishu.appSecret))) { throw "feishu appId/appSecret cannot be empty when enabled." }
    if ($Config.channels.qqbot.enabled -and ([string]::IsNullOrWhiteSpace([string]$Config.channels.qqbot.appId) -or [string]::IsNullOrWhiteSpace([string]$Config.channels.qqbot.clientSecret))) { throw "qqbot appId/clientSecret cannot be empty when enabled." }
}

function Invoke-ExternalCommand([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory = "", [switch]$AllowFailure) {
    $quotedArgs = $Arguments | ForEach-Object { if ($_ -match "\s") { '"' + $_ + '"' } else { $_ } }
    $display = $FilePath + " " + ($quotedArgs -join " ")
    if ($DryRun) {
        Write-DryRun $display
        return
    }
    if ($WorkingDirectory) { Push-Location $WorkingDirectory }
    try {
        & $FilePath @Arguments
        $exitCode = $LASTEXITCODE
    } finally {
        if ($WorkingDirectory) { Pop-Location }
    }
    if (($null -ne $exitCode) -and $exitCode -ne 0 -and -not $AllowFailure) {
        throw "Command failed ($exitCode): $display"
    }
}

function Refresh-UserPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = (@($machinePath, $userPath) | Where-Object { $_ }) -join ";"
}

function Get-OpenClawCommandPath {
    $command = Get-Command openclaw -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    Refresh-UserPath
    $command = Get-Command openclaw -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

function Install-OpenClawIfNeeded([hashtable]$Config) {
    if ($SkipOpenClawInstall) {
        Write-WarnLine "Skipped official installer."
        return
    }
    Write-Section "Install Node.js and OpenClaw"
    Write-Step "Using official install.ps1."
    $tempInstaller = Join-Path $env:TEMP ("openclaw-install-" + [guid]::NewGuid().ToString("n") + ".ps1")
    if ($DryRun) {
        Write-DryRun "Download https://openclaw.ai/install.ps1 -> $tempInstaller"
        Write-DryRun "$PowerShellExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$tempInstaller`" -NoOnboard -Tag $($Config.openclaw.tag)"
        return
    }
    Invoke-WebRequest -UseBasicParsing -Uri "https://openclaw.ai/install.ps1" -OutFile $tempInstaller
    try {
        Invoke-ExternalCommand -FilePath $PowerShellExe -Arguments @(
            "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", $tempInstaller, "-NoOnboard", "-Tag", [string]$Config.openclaw.tag
        )
    } finally {
        if (Test-Path -LiteralPath $tempInstaller) {
            Remove-Item -LiteralPath $tempInstaller -Force
        }
    }
}

function Build-OpenClawConfigFragment([hashtable]$Config) {
    $modelRef = [string]$Config.model.modelRef
    $fragment = @{
        gateway = @{ mode = "local" }
        agents = @{
            defaults = @{
                workspace = [string]$Config.workspace.path
                model = @{ primary = $modelRef }
                models = @{}
            }
        }
    }
    $fragment.agents.defaults.models[$modelRef] = @{ alias = "Default Model" }

    if ($Config.model.providerKind -ieq "custom") {
        $compat = @{}
        if ($Config.model.requiresStringContent) { $compat.requiresStringContent = $true }
        if (-not $Config.model.supportsTools) { $compat.supportsTools = $false }

        $modelEntry = @{
            id = [string]$Config.model.customModelId
            name = [string]$Config.model.customModelName
            reasoning = $false
            input = @("text")
            cost = @{ input = 0; output = 0; cacheRead = 0; cacheWrite = 0 }
            contextWindow = [int]$Config.model.contextWindow
            maxTokens = [int]$Config.model.maxTokens
        }
        if ($compat.Count -gt 0) {
            $modelEntry.compat = $compat
        }
        $providers = @{}
        $providers[[string]$Config.model.providerId] = @{
            baseUrl = [string]$Config.model.baseUrl
            apiKey = '${CUSTOM_OPENAI_API_KEY}'
            api = [string]$Config.model.customApi
            models = @($modelEntry)
        }
        $fragment.models = @{
            mode = "merge"
            providers = $providers
        }
    }

    $channels = @{}
    if ($Config.channels.feishu.enabled) {
        $accounts = @{}
        $accounts[[string]$Config.channels.feishu.accountId] = @{
            appId = '${FEISHU_APP_ID}'
            appSecret = '${FEISHU_APP_SECRET}'
            name = [string]$Config.channels.feishu.accountName
        }
        $channels.feishu = @{
            enabled = $true
            domain = [string]$Config.channels.feishu.domain
            accounts = $accounts
        }
    }
    if ($Config.channels.qqbot.enabled) {
        $channels.qqbot = @{
            enabled = $true
            appId = '${QQBOT_APP_ID}'
            clientSecret = '${QQBOT_CLIENT_SECRET}'
        }
    }
    if ($channels.Count -gt 0) {
        $fragment.channels = $channels
    }

    return $fragment
}

function Build-EnvUpdates([hashtable]$Config) {
    $providerSpec = Get-ProviderSpec -ProviderKind $Config.model.providerKind
    $updates = @{}
    $updates[[string]$providerSpec.apiKeyEnv] = [string]$Config.model.apiKey
    if ($Config.model.providerKind -ieq "custom") {
        $updates["CUSTOM_OPENAI_API_KEY"] = [string]$Config.model.apiKey
    }
    if ($Config.channels.feishu.enabled) {
        $updates["FEISHU_APP_ID"] = [string]$Config.channels.feishu.appId
        $updates["FEISHU_APP_SECRET"] = [string]$Config.channels.feishu.appSecret
    }
    if ($Config.channels.qqbot.enabled) {
        $updates["QQBOT_APP_ID"] = [string]$Config.channels.qqbot.appId
        $updates["QQBOT_CLIENT_SECRET"] = [string]$Config.channels.qqbot.clientSecret
    }
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
    foreach ($key in $updates.Keys) {
        $envMap[$key] = $updates[$key]
    }
    Backup-FileIfExists $OpenClawEnvPath
    Save-EnvMap -Path $OpenClawEnvPath -Map $envMap
    Write-Step "Config updated."
}

function Install-Skills([string]$OpenClawCommand, [hashtable]$Config) {
    if ($SkipSkills) {
        Write-WarnLine "Skipped skills install."
        return
    }
    foreach ($slug in @($Config.skills.slugs)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$slug)) {
            Write-Step "Install skill: $slug"
            Invoke-ExternalCommand -FilePath $OpenClawCommand -Arguments @("skills", "install", [string]$slug, "--force") -WorkingDirectory ([string]$Config.workspace.path)
        }
    }
}

function Start-OpenClawGateway([string]$OpenClawCommand, [hashtable]$Config) {
    Write-Section "Verify and start"
    Invoke-ExternalCommand -FilePath $OpenClawCommand -Arguments @("doctor", "--non-interactive") -AllowFailure
    if ($Config.openclaw.installDaemon) {
        Invoke-ExternalCommand -FilePath $OpenClawCommand -Arguments @("gateway", "install", "--force") -AllowFailure
    }
    if ($Config.openclaw.startGateway) {
        Invoke-ExternalCommand -FilePath $OpenClawCommand -Arguments @("gateway", "restart") -AllowFailure
    }
    Invoke-ExternalCommand -FilePath $OpenClawCommand -Arguments @("gateway", "status") -AllowFailure
    if ($Config.openclaw.openDashboard) {
        Invoke-ExternalCommand -FilePath $OpenClawCommand -Arguments @("dashboard") -AllowFailure
    }
}

try {
    Write-Section "OpenClaw Windows Installer"
    Write-Step "Script root: $ScriptRoot"
    $config = if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        Normalize-InstallerConfig -InputConfig (Load-JsonAsHashtable -Path $ConfigPath)
    } elseif ($NonInteractive) {
        throw "NonInteractive mode requires -ConfigPath."
    } else {
        Collect-InteractiveConfig
    }
    Validate-InstallerConfig -Config $config
    Install-OpenClawIfNeeded -Config $config
    $openclawCommand = Get-OpenClawCommandPath
    if (-not $openclawCommand) {
        throw "openclaw command not found. Reopen PowerShell and try again."
    }
    Configure-OpenClawFiles -Config $config
    Install-Skills -OpenClawCommand $openclawCommand -Config $config
    Start-OpenClawGateway -OpenClawCommand $openclawCommand -Config $config
    Write-Section "Done"
    Write-Host "OpenClaw install flow completed." -ForegroundColor Green
    Write-Host "Next:"
    Write-Host "1. Open dashboard and send a test message."
    Write-Host "2. If Feishu or QQ is enabled, send the bot a message and finish pairing."
    Write-Host "3. Edit $OpenClawConfigPath and $OpenClawEnvPath when needed."
} catch {
    Write-Host ""
    Write-Host "Install failed: " -ForegroundColor Red -NoNewline
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
} finally {
    if (-not $NoPause -and $Host.Name -eq "ConsoleHost") {
        Write-Host ""
        Read-Host "Press Enter to exit"
    }
}
