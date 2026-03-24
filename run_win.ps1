# =======================================================================
# SPEEDTEST BOTTLENECK PROJECT - WINDOWS RUNNER
# =======================================================================
$ErrorActionPreference = "Continue"

# Start recording all terminal output to a log file
Start-Transcript -Path "$BASE_DIR\speedtest_diagnostics.log" -Append

# --- Config (Injected by Installer) ---
$REMOTE_DIR = "__REMOTE_DIR__"
$BASE_DIR = "__BASE_DIR__"

# --- Dynamic Paths ---
$SCRIPTS_DIR = "$BASE_DIR\scripts"
$BIN_DIR = "$BASE_DIR\bin"

# Add Bin directory to PATH for this session
$env:Path = "$BIN_DIR;" + $env:Path

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$workdir = "$env:TEMP\bottleneck_$timestamp"
New-Item -ItemType Directory -Force -Path $workdir | Out-Null

# 1. Detect Active Interface
# Exclude virtual adapters and loopbacks to find the true physical/Wi-Fi connection
$activeAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notmatch "Virtual|Pseudo|Software" } | Select-Object -First 1

if (-not $activeAdapter) {
    Write-Host "[ERROR] Could not detect an active network interface. Exiting."
    exit
}

$ACTIVE_IFACE = $activeAdapter.Name
Write-Host "[INFO] Using network interface: $ACTIVE_IFACE"

try {
    # 2. IPv6 Workaround
    Write-Host "[INFO] Temporarily disabling IPv6 to bypass tool bugs..."
    Disable-NetAdapterBinding -Name $ACTIVE_IFACE -ComponentID ms_tcpip6
    Start-Sleep -Seconds 3 

    # ==========================================
    # 3. RUN DIAGNOSTICS
    # ==========================================
    Write-Host "[INFO] Running bottleneck-finder with Ookla..."
    & "$BIN_DIR\bottleneck-finder.exe" -I $ACTIVE_IFACE -t ookla -a -o "$workdir\ookla"

    Write-Host "[INFO] Running bottleneck-finder with NDT..."
    & "$BIN_DIR\bottleneck-finder.exe" -I $ACTIVE_IFACE -t ndt -a -o "$workdir\ndt"

    # ==========================================
    # 4. EXTRACT ARCHIVES
    # ==========================================
    Write-Host "[INFO] Finding archives to process..."
    $archive_ookla = Get-ChildItem -Path "$workdir\ookla" -Filter "*.tar.gz" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    $archive_ndt = Get-ChildItem -Path "$workdir\ndt" -Filter "*.tar.gz" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

    New-Item -ItemType Directory -Force -Path "$workdir\extracted_ookla" | Out-Null
    New-Item -ItemType Directory -Force -Path "$workdir\extracted_ndt" | Out-Null

    if ($archive_ookla) {
        # Modern Windows 10/11 natively includes tar
        tar -xzf $archive_ookla.FullName -C "$workdir\extracted_ookla"
    } else {
        Write-Host "[WARNING] No Ookla archive found."
    }

    if ($archive_ndt) {
        tar -xzf $archive_ndt.FullName -C "$workdir\extracted_ndt"
    } else {
        Write-Host "[WARNING] No NDT archive found."
    }

    # ==========================================
    # 5. PROCESS DATA (PYTHON)
    # ==========================================
    Write-Host "[INFO] Processing pcap and json files..."
    Set-Location $SCRIPTS_DIR

    $folder_name_ookla = $null
    $folder_name_ndt = $null

    if ($archive_ookla) {
        $json_file_ookla = Get-ChildItem -Path "$workdir\extracted_ookla" -Filter "*metadata*.json" -Recurse | Select-Object -First 1
        $pcap_file_ookla = Get-ChildItem -Path "$workdir\extracted_ookla" -Filter "*.pcap" -Recurse | Select-Object -First 1

        if ($json_file_ookla -and $pcap_file_ookla) {
            & "$SCRIPTS_DIR\venv\Scripts\python.exe" "$SCRIPTS_DIR\pcap_processor.py" $json_file_ookla.FullName $pcap_file_ookla.FullName
            $folder_name_ookla = $json_file_ookla.Name -replace "metadata-", "" -replace ".json", ""
        } else {
            Write-Host "[WARNING] Ookla json/pcap missing."
        }
    }

    if ($archive_ndt) {
        $json_file_ndt = Get-ChildItem -Path "$workdir\extracted_ndt" -Filter "*metadata*.json" -Recurse | Select-Object -First 1
        $pcap_file_ndt = Get-ChildItem -Path "$workdir\extracted_ndt" -Filter "*.pcap" -Recurse | Select-Object -First 1

        if ($json_file_ndt -and $pcap_file_ndt) {
            & "$SCRIPTS_DIR\venv\Scripts\python.exe" "$SCRIPTS_DIR\pcap_processor.py" $json_file_ndt.FullName $pcap_file_ndt.FullName
            $folder_name_ndt = $json_file_ndt.Name -replace "metadata-", "" -replace ".json", ""
        } else {
            Write-Host "[WARNING] NDT json/pcap missing."
        }
    }

    # ==========================================
    # 6. UPLOAD TO GCP
    # ==========================================
    Write-Host "[INFO] Uploading to GCP..."
    
    if ($folder_name_ookla) {
        Write-Host "[INFO] Uploading Ookla results..."
        cmd.exe /c "gsutil cp `"$workdir\extracted_ookla\*`" `"gs://speedtest-data/$REMOTE_DIR/ookla/$folder_name_ookla/`""
    }

    if ($folder_name_ndt) {
        Write-Host "[INFO] Uploading NDT results..."
        cmd.exe /c "gsutil cp `"$workdir\extracted_ndt\*`" `"gs://speedtest-data/$REMOTE_DIR/ndt/$folder_name_ndt/`""
    }

    Write-Host "[SUCCESS] Data processing and upload complete."

} finally {
    # ==========================================
    # 7. CLEANUP & RESTORE
    # ==========================================
    Write-Host "[INFO] Restoring IPv6 on $ACTIVE_IFACE..."
    Enable-NetAdapterBinding -Name $ACTIVE_IFACE -ComponentID ms_tcpip6

    Write-Host "[INFO] Cleaning up temporary files..."
    Set-Location $HOME
    Remove-Item -Path $workdir -Recurse -Force -ErrorAction SilentlyContinue
    Stop-Transcript
}
