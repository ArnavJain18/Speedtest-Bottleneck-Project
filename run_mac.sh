#!/bin/bash
set -e
set -u

# --- Config (Injected by Installer) ---
REMOTE_DIR="__REMOTE_DIR__"

# --- Dynamic Paths ---
BASE_DIR="__BASE_DIR__"
SCRIPTS_DIR="$BASE_DIR/scripts"
BIN_DIR="$BASE_DIR/bin"

export PATH="$BIN_DIR:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# ==========================================
# LOGGING
# ==========================================
LOG_FILE="$BASE_DIR/logs/run_$(date +"%Y%m%d_%H%M%S").log"
mkdir -p "$BASE_DIR/logs"

log() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts=$(date "+%Y-%m-%d %H:%M:%S")
    local line="[$ts] [$level] $msg"
    echo "$line"
    echo "$line" >> "$LOG_FILE"
}

log "INFO" "============================================================"
log "INFO" "  Speedtest Diagnostics Run  —  $(date)"
log "INFO" "============================================================"

timestamp=$(date +"%Y%m%d_%H%M%S")
workdir="/tmp/bottleneck_$timestamp"
mkdir -p "$workdir"

# ==========================================
# NETWORK INTERFACE DETECTION
# ==========================================
ACTIVE_IFACE=$(route get default 2>/dev/null | grep interface | awk '{print $2}')
if [[ -z "$ACTIVE_IFACE" ]]; then
    log "ERROR" "Could not detect an active network interface. Is the machine connected to a network?"
    exit 1
fi

SERVICE_NAME=$(networksetup -listallhardwareports | grep -B 1 "Device: $ACTIVE_IFACE" | sed -n '1p' | awk -F': ' '{print $2}')
log "INFO" "Network interface: $ACTIVE_IFACE  ($SERVICE_NAME)"

# ==========================================
# CLEANUP TRAP
# ==========================================
cleanup() {
    log "INFO" "Restoring IPv6 on $SERVICE_NAME..."
    sudo networksetup -setv6automatic "$SERVICE_NAME" 2>/dev/null || true
    log "INFO" "Removing temporary files: $workdir"
    sudo rm -rf "$workdir"
    log "INFO" "Cleanup complete."
}
trap cleanup EXIT

# ==========================================
# GCLOUD PATH — resolved robustly at runtime.
# The injected __GCLOUD_PATH__ is the primary source; we fall back to a
# set of known locations so the script survives SDK reinstalls or moves.
# ==========================================
GCLOUD_HINT="__GCLOUD_PATH__"

resolve_gcloud_path() {
    # 1. Use installer-injected path if it still has path.bash.inc
    if [[ -f "$GCLOUD_HINT/path.bash.inc" ]]; then
        echo "$GCLOUD_HINT"
        return
    fi

    # 2. Derive from live 'gcloud' binary on PATH
    if command -v gcloud &>/dev/null; then
        local sdk_root
        sdk_root=$(gcloud info --format="value(installation.sdk_root)" 2>/dev/null || true)
        if [[ -f "$sdk_root/path.bash.inc" ]]; then
            echo "$sdk_root"
            return
        fi
    fi

    # 3. Well-known Homebrew cask locations (Apple Silicon + Intel)
    local candidates=(
        "/opt/homebrew/share/google-cloud-sdk"
        "/usr/local/share/google-cloud-sdk"
        "/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk"
        "/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk"
    )
    for dir in "${candidates[@]}"; do
        if [[ -f "$dir/path.bash.inc" ]]; then
            echo "$dir"
            return
        fi
    done

    echo ""
}

GCLOUD_PATH=$(resolve_gcloud_path)

if [[ -z "$GCLOUD_PATH" ]]; then
    log "ERROR" "Cannot locate google-cloud-sdk/path.bash.inc."
    log "ERROR" "Hint path tried: $GCLOUD_HINT"
    log "ERROR" "Please re-run install_mac.sh or install Google Cloud SDK manually."
    exit 1
fi

log "INFO" "Using Google Cloud SDK at: $GCLOUD_PATH"
# shellcheck disable=SC1090
source "$GCLOUD_PATH/path.bash.inc"

# ==========================================
# 1. DISABLE IPv6 (workaround for Go tool bug)
# ==========================================
log "INFO" "Temporarily disabling IPv6 on $SERVICE_NAME to bypass Go tool bug..."
sudo networksetup -setv6off "$SERVICE_NAME"
sleep 3

# ==========================================
# 2. RUN DIAGNOSTICS
# ==========================================
log "INFO" "Running bottleneck-finder with Ookla..."
sudo env PATH="$PATH" "$BIN_DIR/bottleneck-finder" \
    -I "$ACTIVE_IFACE" -t ookla -a -o "$workdir/ookla" \
    >> "$LOG_FILE" 2>&1 || { log "WARNING" "bottleneck-finder (ookla) exited with error — continuing."; }

log "INFO" "Running bottleneck-finder with NDT..."
sudo env PATH="$PATH" "$BIN_DIR/bottleneck-finder" \
    -I "$ACTIVE_IFACE" -t ndt -a -o "$workdir/ndt" \
    >> "$LOG_FILE" 2>&1 || { log "WARNING" "bottleneck-finder (ndt) exited with error — continuing."; }

# ==========================================
# 3. EXTRACT ARCHIVES
# ==========================================
log "INFO" "Extracting result archives..."
archive_ookla=$(find "$workdir/ookla" -name '*.tar.gz' -print -quit 2>/dev/null || true)
archive_ndt=$(find "$workdir/ndt"   -name '*.tar.gz' -print -quit 2>/dev/null || true)

mkdir -p "$workdir/extracted_ookla"
mkdir -p "$workdir/extracted_ndt"

if [[ -n "$archive_ookla" ]]; then
    tar -xzf "$archive_ookla" -C "$workdir/extracted_ookla"
    log "INFO" "Ookla archive extracted."
else
    log "WARNING" "No Ookla archive found in $workdir/ookla"
fi

if [[ -n "$archive_ndt" ]]; then
    tar -xzf "$archive_ndt" -C "$workdir/extracted_ndt"
    log "INFO" "NDT archive extracted."
else
    log "WARNING" "No NDT archive found in $workdir/ndt"
fi

# ==========================================
# 4. PROCESS DATA (PYTHON)
# ==========================================
log "INFO" "Processing pcap and JSON files..."
cd "$SCRIPTS_DIR"

folder_name_ookla=""
folder_name_ndt=""

if [[ -n "$archive_ookla" ]]; then
    json_file_ookla=$(find "$workdir/extracted_ookla" -name '*metadata*.json' -print -quit || true)
    pcap_file_ookla=$(find "$workdir/extracted_ookla" -name '*.pcap' -print -quit || true)

    if [[ -n "$json_file_ookla" && -n "$pcap_file_ookla" ]]; then
        log "INFO" "Running pcap_processor.py for Ookla..."
        "$SCRIPTS_DIR/venv/bin/python" "$SCRIPTS_DIR/pcap_processor.py" \
            "$json_file_ookla" "$pcap_file_ookla" >> "$LOG_FILE" 2>&1
        folder_name_ookla=$(basename "$json_file_ookla" | sed -e 's/metadata-//' -e 's/.json//')
        log "INFO" "Ookla folder name: $folder_name_ookla"
    else
        log "WARNING" "Ookla json or pcap file missing — skipping processing."
    fi
fi

if [[ -n "$archive_ndt" ]]; then
    json_file_ndt=$(find "$workdir/extracted_ndt" -name '*metadata*.json' -print -quit || true)
    pcap_file_ndt=$(find "$workdir/extracted_ndt" -name '*.pcap' -print -quit || true)

    if [[ -n "$json_file_ndt" && -n "$pcap_file_ndt" ]]; then
        log "INFO" "Running pcap_processor.py for NDT..."
        "$SCRIPTS_DIR/venv/bin/python" "$SCRIPTS_DIR/pcap_processor.py" \
            "$json_file_ndt" "$pcap_file_ndt" >> "$LOG_FILE" 2>&1
        folder_name_ndt=$(basename "$json_file_ndt" | sed -e 's/metadata-//' -e 's/.json//')
        log "INFO" "NDT folder name: $folder_name_ndt"
    else
        log "WARNING" "NDT json or pcap file missing — skipping processing."
    fi
fi

# ==========================================
# 5. UPLOAD TO GCP
# ==========================================
log "INFO" "Uploading results to GCP bucket: gs://speedtest-data/$REMOTE_DIR/"

if [[ -n "$folder_name_ookla" ]]; then
    log "INFO" "Uploading Ookla results..."
    gsutil cp "$workdir/extracted_ookla/"* \
        "gs://speedtest-data/$REMOTE_DIR/ookla/$folder_name_ookla/" \
        >> "$LOG_FILE" 2>&1
    log "INFO" "Ookla upload complete."
else
    log "WARNING" "No Ookla results to upload."
fi

if [[ -n "$folder_name_ndt" ]]; then
    log "INFO" "Uploading NDT results..."
    gsutil cp "$workdir/extracted_ndt/"* \
        "gs://speedtest-data/$REMOTE_DIR/ndt7/$folder_name_ndt/" \
        >> "$LOG_FILE" 2>&1
    log "INFO" "NDT upload complete."
else
    log "WARNING" "No NDT results to upload."
fi

log "INFO" "============================================================"
log "INFO" "  Run complete. Log saved to: $LOG_FILE"
log "INFO" "============================================================"
