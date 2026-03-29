# =======================================================================
# SPEEDTEST BOTTLENECK PROJECT - WINDOWS INSTALLER
# =======================================================================

# --- CONFIGURATION ---
# USER: PLEASE CHANGE THE LINE BELOW TO A UNIQUE NAME FOR THIS WINDOWS MACHINE
$WIN_NAME = "Aru-Windows-01"

# --- VALIDATION ---
if ($WIN_NAME -eq "__WIN_NAME__") {
    Write-Host "-----------------------------------------------------------------------" -ForegroundColor Red
    Write-Host "ERROR: WIN_NAME is not set." -ForegroundColor Red
    Write-Host "Please open this script (install_win.ps1) in a text editor and change"
    Write-Host "`$WIN_NAME = `"__WIN_NAME__`""
    Write-Host "to a unique name for this machine (e.g., `"MyWin-01`")."
    Write-Host "Then save the file and run it again."
    Write-Host "-----------------------------------------------------------------------"
    exit
}

# Ensure Administrator Privileges
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Please close this window, right-click PowerShell, select 'Run as Administrator', and try again."
    exit
}

$ErrorActionPreference = "Stop"

$REMOTE_DIR = "netrics_results_$WIN_NAME"
$INSTALL_DIR = "$HOME\speedtest_agent"
$BIN_DIR = "$INSTALL_DIR\bin"
$SCRIPTS_DIR = "$INSTALL_DIR\scripts"
$GCLOUD_DIR = "$INSTALL_DIR\gcloud_config"

Write-Host "Starting Windows installation script..." -ForegroundColor Cyan
Write-Host "Using Windows Name: $WIN_NAME"
Write-Host "Project Directory: $INSTALL_DIR"

# Create Directories
New-Item -ItemType Directory -Force -Path $BIN_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $SCRIPTS_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $GCLOUD_DIR | Out-Null

Write-Host "========================= Installing Global Dependencies =========================" -ForegroundColor Cyan
# Winget silently installs dependencies. (Wireshark will install Npcap, which is required for packet capture).
$packages = @("GoLang.Go", "WiresharkFoundation.Wireshark", "Python.Python.3.11", "GnuPG.GnuPG", "Google.CloudSDK")
foreach ($pkg in $packages) {
    Write-Host "Checking/Installing $pkg via Winget..."
    winget install --id $pkg --exact --accept-package-agreements --accept-source-agreements --silent
}

# Refresh Environment Variables in the current script so we can use Go and Python immediately
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "========================= Installing OOKLA Speedtest CLI =========================" -ForegroundColor Cyan
Invoke-WebRequest -Uri "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip" -OutFile "$INSTALL_DIR\speedtest.zip"
Expand-Archive -Path "$INSTALL_DIR\speedtest.zip" -DestinationPath "$INSTALL_DIR\speedtest_cli" -Force
Copy-Item -Path "$INSTALL_DIR\speedtest_cli\speedtest.exe" -Destination "$BIN_DIR\speedtest.exe"
Remove-Item -Path "$INSTALL_DIR\speedtest.zip"
Remove-Item -Path "$INSTALL_DIR\speedtest_cli" -Recurse -Force
# Accept Ookla License automatically
& "$BIN_DIR\speedtest.exe" --accept-license --accept-gdpr | Out-Null

Write-Host "========================= Downloading Speedtest Diagnostics =========================" -ForegroundColor Cyan
Invoke-WebRequest -Uri "https://github.com/ArnavJain18/Speedtest-Bottleneck-Project/raw/main/speedtest_diagnostics_win.zip" -OutFile "$INSTALL_DIR\speedtest_diagnostics.zip"
Expand-Archive -Path "$INSTALL_DIR\speedtest_diagnostics.zip" -DestinationPath "$INSTALL_DIR\" -Force
Remove-Item -Path "$INSTALL_DIR\speedtest_diagnostics.zip"

Write-Host "========================= Building Bottleneck Finder =========================" -ForegroundColor Cyan
# Dynamically find the main.go file to bypass any nested ZIP folder issues
$GoModFile = Get-ChildItem -Path "$INSTALL_DIR\speedtest_diagnostics" -Filter "main.go" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if ($GoModFile) {
    Set-Location $GoModFile.DirectoryName
    go build -o "$BIN_DIR\bottleneck-finder.exe"
    Write-Host "Build successful!" -ForegroundColor Green
} else {
    Write-Host "ERROR: Could not find main.go in the extracted files!" -ForegroundColor Red
    exit
}
Set-Location $INSTALL_DIR

Write-Host "========================= Installing NDT7 Client =========================" -ForegroundColor Cyan
$env:GOPATH = "$INSTALL_DIR\go_workspace"
go install github.com/m-lab/ndt7-client-go/cmd/ndt7-client@latest
Copy-Item -Path "$env:GOPATH\bin\ndt7-client.exe" -Destination "$BIN_DIR\ndt.exe"
Copy-Item -Path "$env:GOPATH\bin\ndt7-client.exe" -Destination "$BIN_DIR\ndt7-client.exe"
go clean -modcache
Remove-Item -Path $env:GOPATH -Recurse -Force

Write-Host "========================= Configuring Google Cloud SDK =========================" -ForegroundColor Cyan
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/speedtest-bottleneck-finder-64390a06f380.json.gpg" -OutFile "$GCLOUD_DIR\key.json.gpg"
# Decrypt the key file securely
& gpg --batch --passphrase "checkmate" -d "$GCLOUD_DIR\key.json.gpg" | Out-File -FilePath "$GCLOUD_DIR\key.json" -Encoding ascii
& gcloud auth activate-service-account --key-file="$GCLOUD_DIR\key.json"

Write-Host "========================= Installing Python Dependencies =========================" -ForegroundColor Cyan
Set-Location $SCRIPTS_DIR
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/pcap_processor.py" -OutFile "pcap_processor.py"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/speedtest_boundaries.py" -OutFile "speedtest_boundaries.py"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/requirements.txt" -OutFile "requirements.txt"

python -m venv venv
& ".\venv\Scripts\pip.exe" install -r requirements.txt

Write-Host "========================= Setting up Automation Scripts =========================" -ForegroundColor Cyan
# Download the run_win.ps1 script and inject variables
$runScriptUrl = "https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/run_win.ps1"
$runScriptContent = Invoke-RestMethod -Uri $runScriptUrl
$runScriptContent = $runScriptContent -replace "__REMOTE_DIR__", $REMOTE_DIR
$runScriptContent = $runScriptContent -replace "__BASE_DIR__", $INSTALL_DIR
$runScriptContent | Out-File -FilePath "$SCRIPTS_DIR\run_win.ps1" -Encoding UTF8

Write-Host "========================= Activating Background Service =========================" -ForegroundColor Cyan
$TaskName = "SpeedtestDiagnostics"

# Remove old task if it exists
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Create a task that runs every 30 mins, hidden in the background, as SYSTEM/Administrator
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SCRIPTS_DIR\run_win.ps1`""
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration (New-TimeSpan -Days 3650)
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal | Out-Null

# Start the very first run immediately
Start-ScheduledTask -TaskName $TaskName

Write-Host "========================= Yayyy, All installation finished !! =========================" -ForegroundColor Green
Write-Host "Data collection will now run silently in the background every 30 minutes via Windows Task Scheduler." -ForegroundColor Green