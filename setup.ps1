# setup.ps1 — Cài đặt OpenClaw trên Windows
# Chạy: powershell -ExecutionPolicy Bypass -File setup.ps1

param(
    [switch]$UpdateToken,
    [switch]$Reset
)

$ErrorActionPreference = "Stop"

$OPENCLAW_DIR = "$env:USERPROFILE\.openclaw"
$REPO_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

function Restart-OpenClawGateway {
    Write-Host ""
    Write-Host "♻️  Restart gateway..." -ForegroundColor Yellow

    $nssmCmd = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssmCmd) {
        try {
            nssm restart OpenClawGateway | Out-Null
        } catch {
            # ignore if service not installed via NSSM
        }
    }

    try {
        Restart-ScheduledTask -TaskName "OpenClawGateway" -ErrorAction Stop | Out-Null
    } catch {
        # ignore if Task Scheduler path not used
    }

    Write-Host "✅ Gateway đã restart (nếu service tồn tại)" -ForegroundColor Green
}

Write-Host ""
Write-Host "🦞 OpenClaw Setup Script (Windows)" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host ""

# --- Option: -UpdateToken ---
if ($UpdateToken) {
    Write-Host "🔄 Cập nhật Telegram token..." -ForegroundColor Yellow
    Write-Host ""

    do {
        $NEW_TOKEN = Read-Host "Telegram Bot Token mới"
        if ([string]::IsNullOrWhiteSpace($NEW_TOKEN)) {
            Write-Host "❌ Token không được để trống." -ForegroundColor Red
        }
    } while ([string]::IsNullOrWhiteSpace($NEW_TOKEN))

    $NEW_USER_ID = Read-Host "Telegram User ID (Enter để giữ nguyên)"

    & openclaw config set channels.telegram.botToken $NEW_TOKEN | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($NEW_USER_ID)) {
        $allowFrom = ('["{0}"]' -f $NEW_USER_ID)
        $ownerAllow = ('["telegram:{0}"]' -f $NEW_USER_ID)
        & openclaw config set channels.telegram.allowFrom $allowFrom | Out-Null
        & openclaw config set commands.ownerAllowFrom $ownerAllow | Out-Null
    }

    Restart-OpenClawGateway

    Write-Host "✅ Token đã cập nhật và gateway đã restart" -ForegroundColor Green
    Write-Host ""
    Write-Host "Kiểm tra kết nối: openclaw status --deep" -ForegroundColor Cyan
    exit 0
}

# --- Option: -Reset ---
if ($Reset) {
    Write-Host "⚠️  Reset sẽ xóa openclaw.json hiện tại." -ForegroundColor Yellow
    $confirm = Read-Host "Bạn chắc chắn? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Hủy." -ForegroundColor Yellow
        exit 0
    }
    $configFile = Join-Path $OPENCLAW_DIR "openclaw.json"
    if (Test-Path $configFile) {
        Remove-Item -Force $configFile
    }
    Write-Host "✅ Đã xóa openclaw.json, tiếp tục setup..." -ForegroundColor Green
    Write-Host ""
}

# --- 1. Kiểm tra Node.js ---
try {
    $nodeVersion = node -v
    Write-Host "✅ Node.js $nodeVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Node.js chưa được cài." -ForegroundColor Red
    Write-Host "   Tải tại: https://nodejs.org" -ForegroundColor Yellow
    exit 1
}

# --- 2. Cài OpenClaw ---
$oclawInstalled = Get-Command openclaw -ErrorAction SilentlyContinue
if (-not $oclawInstalled) {
    Write-Host "📦 Đang cài OpenClaw..." -ForegroundColor Yellow
    npm install -g openclaw
    Write-Host "✅ OpenClaw đã cài" -ForegroundColor Green
} else {
    Write-Host "✅ OpenClaw đã được cài" -ForegroundColor Green
}

# --- 3. Tạo thư mục config ---
Write-Host ""
Write-Host "📁 Tạo thư mục cấu hình..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "$OPENCLAW_DIR\agents\main" | Out-Null
New-Item -ItemType Directory -Force -Path "$OPENCLAW_DIR\workspace" | Out-Null

# --- 4. Copy BOOTSTRAP.md ---
Write-Host "📝 Copy agent BOOTSTRAP.md..." -ForegroundColor Yellow
Copy-Item "$REPO_DIR\agents\main\BOOTSTRAP.md" "$OPENCLAW_DIR\agents\main\BOOTSTRAP.md" -Force
Write-Host "✅ BOOTSTRAP.md đã copy" -ForegroundColor Green

# --- 5. Tạo openclaw.json từ template ---
$configPath = "$OPENCLAW_DIR\openclaw.json"

if (Test-Path $configPath) {
    Write-Host ""
    Write-Host "⚠️  $configPath đã tồn tại." -ForegroundColor Yellow
    Write-Host "   Để update token: powershell -ExecutionPolicy Bypass -File setup.ps1 -UpdateToken" -ForegroundColor Yellow
    Write-Host "   Để setup lại từ đầu: powershell -ExecutionPolicy Bypass -File setup.ps1 -Reset" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "⚙️  Tạo openclaw.json từ template..." -ForegroundColor Yellow

    do {
        $TELEGRAM_TOKEN = Read-Host "Telegram Bot Token"
        if ([string]::IsNullOrWhiteSpace($TELEGRAM_TOKEN)) {
            Write-Host "❌ Token không được để trống." -ForegroundColor Red
        }
    } while ([string]::IsNullOrWhiteSpace($TELEGRAM_TOKEN))

    do {
        $TELEGRAM_USER_ID = Read-Host "Telegram User ID của bạn"
        if ([string]::IsNullOrWhiteSpace($TELEGRAM_USER_ID)) {
            Write-Host "❌ User ID không được để trống." -ForegroundColor Red
        }
    } while ([string]::IsNullOrWhiteSpace($TELEGRAM_USER_ID))

    # Tạo random gateway token
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $GATEWAY_TOKEN = [System.BitConverter]::ToString($bytes).Replace("-", "").ToLower()

    # Đọc template và thay thế
    $config = Get-Content "$REPO_DIR\openclaw.template.json" -Raw
    $config = $config -replace "__REPLACE_WITH_TELEGRAM_BOT_TOKEN__", $TELEGRAM_TOKEN
    $config = $config -replace "__REPLACE_WITH_YOUR_TELEGRAM_USER_ID__", $TELEGRAM_USER_ID
    $config = $config -replace "__REPLACE_WITH_RANDOM_TOKEN__", $GATEWAY_TOKEN

    $config | Set-Content $configPath -Encoding UTF8
    Write-Host "✅ openclaw.json đã tạo" -ForegroundColor Green
}

# --- 6. Cài Windows Service qua NSSM hoặc Task Scheduler ---
Write-Host ""
Write-Host "🔧 Cài gateway service..." -ForegroundColor Yellow

$nssmInstalled = Get-Command nssm -ErrorAction SilentlyContinue
$openclawPath = (Get-Command openclaw).Source

if ($nssmInstalled) {
    # Dùng NSSM nếu có
    Write-Host "   Dùng NSSM để cài service..." -ForegroundColor Gray
    $nodePath = (Get-Command node).Source
    $openclawModule = npm root -g | ForEach-Object { "$_\openclaw\dist\index.js" }

    nssm install OpenClawGateway $nodePath "$openclawModule gateway --port 18789"
    nssm set OpenClawGateway AppDirectory $OPENCLAW_DIR
    nssm set OpenClawGateway Start SERVICE_AUTO_START
    nssm start OpenClawGateway
    Write-Host "✅ Service đã cài qua NSSM" -ForegroundColor Green
} else {
    # Dùng Task Scheduler
    Write-Host "   NSSM không có, dùng Task Scheduler..." -ForegroundColor Gray

    $nodePath = (Get-Command node).Source
    $npmRoot = npm root -g
    $openclawModule = "$npmRoot\openclaw\dist\index.js"

    $action = New-ScheduledTaskAction `
        -Execute $nodePath `
        -Argument "$openclawModule gateway --port 18789" `
        -WorkingDirectory $OPENCLAW_DIR

    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest

    Register-ScheduledTask `
        -TaskName "OpenClawGateway" `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Force | Out-Null

    Start-ScheduledTask -TaskName "OpenClawGateway"
    Write-Host "✅ Task Scheduler đã cài" -ForegroundColor Green
}

# --- 7. Tìm Chrome trên Windows ---
Write-Host ""
Write-Host "🌐 Kiểm tra Google Chrome..." -ForegroundColor Yellow

$chromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)

$chromePath = $null
foreach ($path in $chromePaths) {
    if (Test-Path $path) {
        $chromePath = $path
        break
    }
}

if ($chromePath) {
    Write-Host "✅ Chrome tìm thấy: $chromePath" -ForegroundColor Green

    # Tạo script khởi động Chrome
    $chromeScript = @"
Start-Process -FilePath "$chromePath" -ArgumentList @(
    "--remote-debugging-port=9222",
    "--user-data-dir=$env:TEMP\openclaw-chrome",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-mode"
)
"@
    $chromeScript | Set-Content "$REPO_DIR\start-chrome.ps1" -Encoding UTF8
    Write-Host "✅ Tạo start-chrome.ps1 để khởi động Chrome" -ForegroundColor Green
} else {
    Write-Host "⚠️  Chrome không tìm thấy. Tải tại: https://www.google.com/chrome" -ForegroundColor Yellow
}

# --- 8. Đăng nhập OpenAI ---
Write-Host ""
Write-Host "🤖 Đăng nhập OpenAI (cần thiết để agent hoạt động)..." -ForegroundColor Yellow
Write-Host ""

$openaiStatus = ""
try {
    $openaiStatus = & openclaw models status 2>$null
} catch {
    $openaiStatus = ""
}

if ($openaiStatus -match "(?i)(ok|ready|authenticated)") {
    Write-Host "✅ OpenAI đã đăng nhập" -ForegroundColor Green
} else {
    Write-Host "Cần đăng nhập OpenAI để agent có thể xử lý lệnh." -ForegroundColor Yellow
    Read-Host "Nhấn Enter để chạy 'openclaw configure' và mở trình duyệt đăng nhập" | Out-Null
    & openclaw configure 2>$null
    Write-Host ""
    Write-Host "✅ Nếu đăng nhập thành công, gateway sẽ tự nhận token." -ForegroundColor Green
    Restart-OpenClawGateway
}

# --- 9. Xong ---
Write-Host ""
Write-Host "🎉 Setup hoàn tất!" -ForegroundColor Green
Write-Host ""
Write-Host "Bước tiếp theo:" -ForegroundColor Cyan
Write-Host "  1. Khởi động Chrome với remote debugging:"
Write-Host "     powershell -File start-chrome.ps1"
Write-Host ""
Write-Host "  2. Đăng nhập Upwork trong Chrome đó (chỉ cần làm 1 lần)"
Write-Host ""
Write-Host "  3. Kiểm tra kết nối:"
Write-Host "     openclaw status --deep"
Write-Host ""
Write-Host "  4. Nhắn /apply <job_id> qua Telegram bot của bạn"
Write-Host ""
