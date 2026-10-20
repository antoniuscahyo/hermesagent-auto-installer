#Requires -Version 5.1
<#
=============================================================================
 Hermes Agent - Windows one-shot installer
=============================================================================
 Satu script, sekali jalan, selesai:
   1. Install Hermes Agent (kalau belum ada) - non-interactive
   2. Set default provider + model
   3. Simpan API key provider ke %HERMES_HOME%\.env
   4. Simpan Telegram bot token + allowlist + home channel
   5. Install autostart (Windows Scheduled Task, fallback Startup folder)
   6. Smoke test 1x call ke provider + tampilkan status

 Cara pakai (pilih salah satu):

   A. Zero-prompt (rekomendasi):
      - Edit blok $CFG di bawah ini (provider, model, API key, telegram token)
      - Double-click install-hermes.cmd

   B. Dari PowerShell:
      powershell -ExecutionPolicy Bypass -File .\install-hermes.ps1 `
        -Provider deepseek -Model deepseek-v4-flash `
        -ApiKey "sk-xxxx" -TelegramToken "123456789:AAxxxx" `
        -TelegramAllowedUsers "111111111,222222222"

   C. Semi-interaktif (kalau API key / token dikosongkan, script nanya):
      powershell -ExecutionPolicy Bypass -File .\install-hermes.ps1

 Catatan:
   - TIDAK butuh admin. Jangan run as Administrator (task dibuat per-user).
   - Script idempotent: aman dijalankan ulang.
   - Pakai -Force untuk reinstall Hermes walau sudah terpasang.
   - Pakai -SkipGateway untuk skip autostart, -SkipSmokeTest untuk skip tes call.
=============================================================================
#>
[CmdletBinding()]
param(
    [string]$Provider              = "",
    [string]$Model                 = "",
    [string]$ApiKey                = "",
    [string]$ApiKeyEnv             = "",
    [string]$TelegramToken         = "",
    [string]$TelegramAllowedUsers  = "",
    [string]$TelegramHomeChannel   = "",
    [string]$HermesHome            = "",
    [switch]$Force,
    [switch]$SkipGateway,
    [switch]$SkipSmokeTest,
    [switch]$NoInstall,
    [switch]$Unattended
)

# =============================================================================
#  EDIT DI SINI SAJA (blok $CFG) -> lalu double-click install-hermes.cmd
#  Kosongkan ApiKey / TelegramToken kalau mau script nanya interaktif.
# =============================================================================
$CFG = @{
    Provider             = "deepseek"                 # deepseek | openrouter | anthropic | openai-api | gemini | zai | kimi-coding | minimax | xai | nvidia | ...
    Model                = "deepseek-v4-flash"        # model default
    ApiKey               = ""                         # API key provider (mis. "sk-...")
    TelegramToken        = ""                         # "123456789:AAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    TelegramAllowedUsers = ""                         # "111111111,222222222" (ID numerik, pisah koma)
    TelegramHomeChannel  = ""                         # opsional: "-1001234567890"
}
# =============================================================================

$ErrorActionPreference = "Stop"
try { $ProgressPreference = "SilentlyContinue" } catch { }
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# ---------------------------------------------------------------- merge config
if (-not $Provider)             { $Provider = $CFG.Provider }
if (-not $Model)                { $Model = $CFG.Model }
if (-not $ApiKey)               { $ApiKey = $CFG.ApiKey }
if (-not $TelegramToken)        { $TelegramToken = $CFG.TelegramToken }
if (-not $TelegramAllowedUsers) { $TelegramAllowedUsers = $CFG.TelegramAllowedUsers }
if (-not $TelegramHomeChannel)  { $TelegramHomeChannel = $CFG.TelegramHomeChannel }

# ------------------------------------------------------------------- ui helper
function Write-Step { param([string]$Msg) Write-Host ""; Write-Host "==> $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "    [OK]  $Msg" -ForegroundColor Green }
function Write-Note { param([string]$Msg) Write-Host "    $Msg" -ForegroundColor Gray }
function Write-Warn { param([string]$Msg) Write-Host "    [!]   $Msg" -ForegroundColor Yellow }
function Write-Bad  { param([string]$Msg) Write-Host "    [x]   $Msg" -ForegroundColor Red }

$script:Transcript = $false
$script:LogFile = ""
$script:Secrets = New-Object System.Collections.ArrayList

function Register-Secret {
    param([string]$Value)
    if ($Value -and $Value.Length -ge 6) { [void]$script:Secrets.Add($Value) }
}

function Stop-Log {
    if ($script:Transcript) {
        try { Stop-Transcript | Out-Null } catch { }
        $script:Transcript = $false
    }
    # Scrub secrets that leaked into the transcript header (Start-Transcript
    # records the host command line, which may carry -ApiKey/-TelegramToken).
    if ($script:LogFile -and (Test-Path $script:LogFile) -and $script:Secrets.Count -gt 0) {
        try {
            $content = [System.IO.File]::ReadAllText($script:LogFile)
            foreach ($s in $script:Secrets) {
                if ($s) { $content = $content.Replace($s, "***REDACTED***") }
            }
            [System.IO.File]::WriteAllText($script:LogFile, $content, (New-Object System.Text.UTF8Encoding($false)))
        } catch { }
    }
}
function Fail {
    param([string]$Msg)
    Write-Host ""
    Write-Bad $Msg
    Write-Host ""
    Stop-Log
    exit 1
}

function Read-Secret {
    param([string]$Label)
    if ($Unattended) { return "" }
    $sec = Read-Host $Label -AsSecureString
    if (-not $sec -or $sec.Length -eq 0) { return "" }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Read-Text {
    param([string]$Label)
    if ($Unattended) { return "" }
    return (Read-Host $Label)
}

function Mask-Value {
    param([string]$Value)
    if (-not $Value) { return "(kosong)" }
    if ($Value.Length -le 8) { return "****" }
    return ($Value.Substring(0, 4) + "..." + $Value.Substring($Value.Length - 4))
}

# --------------------------------------------------------- .env upsert (no BOM)
function Set-EnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $lines = @()
    if (Test-Path $Path) {
        $lines = @([System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8))
    }

    # Quote only when the value would break dotenv parsing.
    $serialized = $Value
    if ($Value -match '[\s"''#$\r\n]') {
        $serialized = '"' + ($Value -replace '"', '\"') + '"'
    }

    $pattern = '^\s*(export\s+)?' + [regex]::Escape($Key) + '\s*='
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $pattern) {
            $lines[$i] = "$Key=$serialized"
            $found = $true
        }
    }
    if (-not $found) { $lines = @($lines) + @("$Key=$serialized") }

    [System.IO.File]::WriteAllLines($Path, $lines, $utf8NoBom)

    # Verify by reading back.
    $check = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
    $hit = @($check | Where-Object { $_ -match ('^\s*(export\s+)?' + [regex]::Escape($Key) + '\s*=') })
    if ($hit.Count -ne 1) { Fail "Gagal menulis $Key ke $Path (ditemukan $($hit.Count) baris)." }
    return $true
}

# ---------------------------------------------------------------------- banner
Write-Host ""
Write-Host "  ###########################################################" -ForegroundColor DarkCyan
Write-Host "  #   HERMES AGENT - WINDOWS AUTO INSTALLER                  #" -ForegroundColor DarkCyan
Write-Host "  #   install + provider/model + telegram + autostart        #" -ForegroundColor DarkCyan
Write-Host "  ###########################################################" -ForegroundColor DarkCyan

# ---------------------------------------------------- admin check (jangan root)
$isAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }
if ($isAdmin) {
    Write-Host ""
    Write-Warn "Kamu jalan sebagai Administrator."
    Write-Note "Hermes sebaiknya dipasang sebagai user biasa supaya Scheduled Task"
    Write-Note "jalan di sesi login kamu. Kalau ini memang disengaja, lanjut saja."
}

# ------------------------------------------------------------ resolve hermes home
if (-not $HermesHome) {
    $HermesHome = [Environment]::GetEnvironmentVariable("HERMES_HOME", "User")
    if (-not $HermesHome) { $HermesHome = Join-Path $env:LOCALAPPDATA "hermes" }
}
$env:HERMES_HOME = $HermesHome
$envFile    = Join-Path $HermesHome ".env"
$configFile = Join-Path $HermesHome "config.yaml"
$venvDir    = Join-Path $HermesHome "hermes-agent\venv\Scripts"
$hermesExe  = Join-Path $venvDir "hermes.exe"
$hermesPy   = Join-Path $venvDir "python.exe"

Write-Step "Target install"
Write-Note "HERMES_HOME : $HermesHome"
Write-Note "Provider    : $Provider"
Write-Note "Model       : $Model"
Write-Note "API key     : $(Mask-Value $ApiKey)"
Write-Note "Telegram    : $(Mask-Value $TelegramToken)"
Write-Note "Allowlist   : $(if ($TelegramAllowedUsers) { $TelegramAllowedUsers } else { '(kosong - SIAPA PUN bisa pakai bot!)' })"

# ------------------------------------------------------------ transcript (log)
try {
    $logDir = Join-Path $HermesHome "logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $logFile = Join-Path $logDir ("install-win-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
    Start-Transcript -Path $logFile -Append | Out-Null
    $script:Transcript = $true
    $script:LogFile = $logFile
    Write-Note "Log         : $logFile"
} catch { }

# --------------------------------------------------------------- prompt secrets
if (-not $ApiKey) {
    if ($Unattended) {
        Write-Warn "ApiKey kosong (mode unattended) - langkah API key dilewati."
    } else {
        Write-Host ""
        Write-Note "API key $Provider belum diisi. (Enter 2x = kosongkan / sudah pernah di-set)"
        $ApiKey = Read-Secret "API key $Provider"
    }
}
if (-not $TelegramToken -and -not $SkipGateway) {
    if ($Unattended) {
        Write-Warn "TelegramToken kosong (mode unattended) - autostart gateway dilewati."
        $SkipGateway = $true
    } else {
        Write-Host ""
        Write-Note "Bot token dari @BotFather (format 123456789:AA...). Enter 2x = skip Telegram."
        $TelegramToken = Read-Secret "Telegram bot token"
        if ($TelegramToken) {
            $TelegramAllowedUsers = Read-Text "Allowed Telegram user IDs (pisah koma, Enter = tanpa allowlist)"
        }
    }
}

Register-Secret $ApiKey
Register-Secret $TelegramToken

# =============================================================================
# 1) INSTALL HERMES (kalau perlu)
# =============================================================================
$needInstall = (-not (Test-Path $hermesExe)) -or $Force

if ($needInstall) {
    if ($NoInstall) {
        Fail "Hermes belum terpasang di $HermesHome dan -NoInstall dipakai. Batalkan."
    }
    Write-Step "Install Hermes Agent (butuh internet, 5-15 menit)"
    Write-Note "Sumber: https://hermes-agent.nousresearch.com/install.ps1"

    $installer = Join-Path $env:TEMP ("hermes-install-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".ps1")
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "https://hermes-agent.nousresearch.com/install.ps1" -OutFile $installer
    } catch {
        Fail "Gagal download installer: $($_.Exception.Message)"
    }
    Write-Note "Installer: $installer"

    # Run in a child process so install.ps1's `exit` codes stay isolated.
    $hostExe = (Get-Process -Id $PID).Path
    if (-not $hostExe) { $hostExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }

    $proc = Start-Process -FilePath $hostExe -PassThru -NoNewWindow -Wait -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$installer`"", "-NonInteractive"
    )
    if ($proc.ExitCode -ne 0) {
        Fail "Installer Hermes gagal (exit $($proc.ExitCode)). Cek log di atas, lalu coba manual: $installer"
    }
    Write-Ok "Installer selesai"

    # Refresh PATH dari registry + session supaya launcher kebaca.
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath) { $env:Path = "$userPath;$env:Path" }
    $env:HERMES_HOME = $HermesHome
} else {
    Write-Step "Hermes sudah terpasang"
    Write-Ok "$hermesExe"
}

# --------------------------------------------------- resolve launcher fallback
if (-not (Test-Path $hermesExe)) {
    $cmd = Get-Command "hermes" -ErrorAction SilentlyContinue
    if ($cmd) { $hermesExe = $cmd.Source }
}
if (-not (Test-Path $hermesExe) -and -not (Test-Path $hermesPy)) {
    Fail "Launcher Hermes tidak ditemukan di $venvDir. Cek manual: `"$HermesHome\hermes-agent`"."
}

function Invoke-Hermes {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$HermesArgs)
    if (Test-Path $script:hermesExe) {
        & $script:hermesExe @HermesArgs
    } elseif (Test-Path $script:hermesPy) {
        & $script:hermesPy -m hermes_cli.main @HermesArgs
    } else {
        throw "Launcher Hermes hilang."
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Perintah 'hermes $($HermesArgs -join ' ')' gagal (exit $LASTEXITCODE)."
    }
}

# =============================================================================
# 2) PROVIDER + MODEL DEFAULT
# =============================================================================
Write-Step "Set default provider dan model"
try {
    Invoke-Hermes config set model.provider $Provider
    if ($Model) { Invoke-Hermes config set model.default $Model }
    Write-Ok "model.provider = $Provider"
    if ($Model) { Write-Ok "model.default  = $Model" }
} catch {
    Write-Bad $_.Exception.Message
    Fail "Gagal set model/provider. Config: $configFile"
}

# =============================================================================
# 3) API KEY PROVIDER -> .env
# =============================================================================
$providerKeyEnv = @{
    "deepseek"        = "DEEPSEEK_API_KEY"
    "openrouter"      = "OPENROUTER_API_KEY"
    "openai"          = "OPENAI_API_KEY"
    "openai-api"      = "OPENAI_API_KEY"
    "anthropic"       = "ANTHROPIC_API_KEY"
    "gemini"          = "GOOGLE_API_KEY"
    "zai"             = "GLM_API_KEY"
    "kimi-coding"     = "KIMI_API_KEY"
    "kimi-coding-cn"  = "KIMI_CN_API_KEY"
    "minimax"         = "MINIMAX_API_KEY"
    "minimax-cn"      = "MINIMAX_CN_API_KEY"
    "xai"             = "XAI_API_KEY"
    "nvidia"          = "NVIDIA_API_KEY"
    "huggingface"     = "HF_TOKEN"
    "ollama-cloud"    = "OLLAMA_API_KEY"
    "deepinfra"       = "DEEPINFRA_API_KEY"
    "ai-gateway"      = "AI_GATEWAY_API_KEY"
    "kilocode"        = "KILOCODE_API_KEY"
    "xiaomi"          = "XIAOMI_API_KEY"
    "arcee"           = "ARCEEAI_API_KEY"
    "alibaba"         = "DASHSCOPE_API_KEY"
    "gmi"             = "GMI_API_KEY"
    "opencode-zen"    = "OPENCODE_ZEN_API_KEY"
    "nous-api"        = "NOUS_API_KEY"
}

if ($ApiKey) {
    Write-Step "Simpan API key provider"
    $envKey = $ApiKeyEnv
    if (-not $envKey) { $envKey = $providerKeyEnv[$Provider.ToLower()] }
    if (-not $envKey) {
        Fail "Nama env var untuk provider '$Provider' tidak dikenal. Jalankan ulang dengan -ApiKeyEnv NAMA_ENV_VAR."
    }
    if ($ApiKey -match '[^\x20-\x7E]') {
        Write-Warn "API key mengandung karakter non-ASCII - kemungkinan salah copy."
    }
    try {
        Set-EnvValue -Path $envFile -Key $envKey -Value $ApiKey.Trim() | Out-Null
        Write-Ok "$envKey tersimpan di $envFile"
    } catch {
        Fail "Gagal tulis $envFile : $($_.Exception.Message)"
    }
} else {
    Write-Step "API key provider dilewati"
    $existingKey = if (Test-Path $envFile) {
        @([System.IO.File]::ReadAllLines($envFile) | Where-Object { $_ -match '^[A-Z0-9_]*_API_KEY=.+' }) -join ", "
    } else { "" }
    if ($existingKey) { Write-Note "Sudah ada di .env: $existingKey" }
    else { Write-Warn "Belum ada API key. Jalankan: hermes config set <PROVIDER>_API_KEY <key>" }
}

# =============================================================================
# 4) TELEGRAM
# =============================================================================
if ($TelegramToken) {
    Write-Step "Konfigurasi Telegram bot"
    $TelegramToken = $TelegramToken.Trim()
    if ($TelegramToken -notmatch '^\d+:[A-Za-z0-9_-]{30,}$') {
        Fail "Format token Telegram tidak valid. Harus seperti 123456789:AAxxxxxxxxxxxxxxxxxxxxxxxxxx"
    }
    try {
        Set-EnvValue -Path $envFile -Key "TELEGRAM_BOT_TOKEN" -Value $TelegramToken | Out-Null
        Write-Ok "TELEGRAM_BOT_TOKEN tersimpan"

        if ($TelegramAllowedUsers) {
            $ids = ($TelegramAllowedUsers -replace '\s', '')
            if ($ids -notmatch '^-?\d+(,-?\d+)*$') {
                Fail "TELEGRAM_ALLOWED_USERS harus ID numerik dipisah koma (mis. 111111111,222222222)."
            }
            Set-EnvValue -Path $envFile -Key "TELEGRAM_ALLOWED_USERS" -Value $ids | Out-Null
            Write-Ok "TELEGRAM_ALLOWED_USERS = $ids"
        } else {
            Write-Warn "Tanpa TELEGRAM_ALLOWED_USERS, SIAPA PUN yang menemukan bot kamu bisa memakainya."
            Write-Note "Cari ID kamu lewat @userinfobot, lalu: hermes config set TELEGRAM_ALLOWED_USERS 123456789"
        }

        if ($TelegramHomeChannel) {
            Set-EnvValue -Path $envFile -Key "TELEGRAM_HOME_CHANNEL" -Value ($TelegramHomeChannel.Trim()) | Out-Null
            Write-Ok "TELEGRAM_HOME_CHANNEL = $TelegramHomeChannel"
        }
    } catch {
        Fail "Gagal menulis konfigurasi Telegram: $($_.Exception.Message)"
    }
} else {
    Write-Step "Telegram dilewati"
    Write-Note "Bisa ditambahkan nanti: hermes gateway setup"
}

# =============================================================================
# 5) AUTOSTART GATEWAY (Windows Scheduled Task + Startup fallback)
# =============================================================================
if (-not $SkipGateway) {
    Write-Step "Install autostart gateway (Scheduled Task, jalan tiap login)"
    try {
        Invoke-Hermes gateway install --force --start-now --start-on-login
        Write-Ok "Gateway terpasang sebagai Scheduled Task dan sudah distart"
    } catch {
        Write-Warn $_.Exception.Message
        Write-Note "Coba manual: `"$hermesExe`" gateway install --force --start-now --start-on-login"
        Write-Note "Kalau Scheduled Task diblokir kebijakan kantor, Hermes fallback ke Startup folder."
    }

    Write-Host ""
    Write-Note "---- hermes gateway status ----"
    try {
        if (Test-Path $hermesExe) { & $hermesExe gateway status } else { & $hermesPy -m hermes_cli.main gateway status }
    } catch { Write-Note "(status tidak bisa dibaca, cek nanti: hermes gateway status)" }
    Write-Note "-------------------------------"
} else {
    Write-Step "Autostart gateway dilewati (-SkipGateway)"
    Write-Note "Aktifkan nanti: hermes gateway install --force --start-now --start-on-login"
}

# =============================================================================
# 6) SMOKE TEST
# =============================================================================
if (-not $SkipSmokeTest) {
    Write-Step "Smoke test: 1x call ke $Provider"
    try {
        if (Test-Path $hermesExe) {
            $file = $hermesExe
            $sargs = @("chat", "-q", "Reply with exactly: OK", "-Q")
        } else {
            $file = $hermesPy
            $sargs = @("-m", "hermes_cli.main", "chat", "-q", "Reply with exactly: OK", "-Q")
        }
        $sp = Start-Process -FilePath $file -ArgumentList $sargs -NoNewWindow -PassThru
        if (-not $sp.WaitForExit(180000)) {
            try { $sp.Kill() } catch { }
            Write-Warn "Smoke test timeout 180s (tidak fatal). Cek: hermes chat -q \"halo\""
        } elseif ($sp.ExitCode -eq 0) {
            Write-Ok "Provider merespons - API key & model valid"
        } else {
            Write-Warn "Smoke test exit $($sp.ExitCode) (tidak fatal). Cek: hermes doctor"
        }
    } catch {
        Write-Warn "Smoke test tidak bisa dijalankan: $($_.Exception.Message)"
    }
}

# =============================================================================
# RINGKASAN
# =============================================================================
Write-Host ""
Write-Host "  ===========================================================" -ForegroundColor Green
Write-Host "   SELESAI" -ForegroundColor Green
Write-Host "  ===========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "   HERMES_HOME : $HermesHome"
Write-Host "   Config      : $configFile"
Write-Host "   Secrets     : $envFile"
Write-Host "   Provider    : $Provider  ($Model)"
if ($TelegramToken) {
    Write-Host "   Telegram    : token OK, allowlist: $(if ($TelegramAllowedUsers) { $TelegramAllowedUsers } else { 'TERBUKA' })"
}
Write-Host ""
Write-Host "   Langkah berikutnya:" -ForegroundColor Cyan
Write-Host "     1. Tutup jendela ini, buka PowerShell BARU (biar PATH ke-refresh)"
Write-Host "     2. Ketik:  hermes        (chat di terminal)"
if ($TelegramToken) {
    Write-Host "     3. Cari bot kamu di Telegram, kirim /start"
    Write-Host "        Cek service:  hermes gateway status"
    Write-Host "        Log       :  Get-Content `"$(Join-Path $HermesHome 'logs\gateway.log')`" -Tail 50 -Wait"
}
Write-Host "     Diagnosa:  hermes doctor"
Write-Host ""

Stop-Log
