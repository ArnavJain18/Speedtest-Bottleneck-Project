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

timestamp=$(date +"%Y%m%d_%H%M%S")
workdir="/tmp/bottleneck_$timestamp"
mkdir -p "$workdir"

ACTIVE_IFACE=$(route get default | grep interface | awk '{print $2}')
if [[ -z "$ACTIVE_IFACE" ]]; then
    echo "[ERROR] Could not detect an active network interface. Exiting."
    exit 1
fi

SERVICE_NAME=$(networksetup -listallhardwareports | grep -B 1 "Device: $ACTIVE_IFACE" | sed -n '1p' | awk -F': ' '{print $2}')
echo "[INFO] Using network interface: $ACTIVE_IFACE ($SERVICE_NAME)"

cleanup() {
    echo "[INFO] Restoring IPv6 on $SERVICE_NAME..."
    sudo networksetup -setv6automatic "$SERVICE_NAME"
    echo "[INFO] Cleaning up temporary files..."
    sudo rm -rf "$workdir"
}
trap cleanup EXIT

echo "[INFO] Temporarily disabling IPv6 to bypass Go tool bug..."
sudo networksetup -setv6off "$SERVICE_NAME"
sleep 3 

# ==========================================
# 1. RUN DIAGNOSTICS
# ==========================================
echo "[INFO] Running bottleneck-finder with Ookla..."
# Using || true so a crash in one tool doesn't stop the other
sudo env PATH="$PATH" "$BIN_DIR/bottleneck-finder" -I "$ACTIVE_IFACE" -t ookla -a -o "$workdir/ookla" || true

echo "[INFO] Running bottleneck-finder with NDT..."
sudo env PATH="$PATH" "$BIN_DIR/bottleneck-finder" -I "$ACTIVE_IFACE" -t ndt -a -o "$workdir/ndt" || true

# ==========================================
# 2. EXTRACT ARCHIVES
# ==========================================
echo "[INFO] Finding archives to process..."
archive_ookla=$(find "$workdir/ookla" -name '*.tar.gz' -print -quit 2>/dev/null || true)
archive_ndt=$(find "$workdir/ndt" -name '*.tar.gz' -print -quit 2>/dev/null || true)

mkdir -p "$workdir/extracted_ookla"
mkdir -p "$workdir/extracted_ndt"

if [[ -n "$archive_ookla" ]]; then
    tar -xzf "$archive_ookla" -C "$workdir/extracted_ookla"
else
    echo "[WARNING] No Ookla archive found."
fi

if [[ -n "$archive_ndt" ]]; then
    tar -xzf "$archive_ndt" -C "$workdir/extracted_ndt"
else
    echo "[WARNING] No NDT archive found."
fi

# ==========================================
# 3. PROCESS DATA (PYTHON)
# ==========================================
echo "[INFO] Processing pcap and json files..."
cd "$SCRIPTS_DIR"

if [[ -n "$archive_ookla" ]]; then
    json_file_ookla=$(find "$workdir/extracted_ookla" -name '*metadata*.json' -print -quit)
    pcap_file_ookla=$(find "$workdir/extracted_ookla" -name '*.pcap' -print -quit)

    if [[ -n "$json_file_ookla" && -n "$pcap_file_ookla" ]]; then
        "$SCRIPTS_DIR/venv/bin/python" "$SCRIPTS_DIR/pcap_processor.py" "$json_file_ookla" "$pcap_file_ookla"
        folder_name_ookla=$(basename "$json_file_ookla" | sed -e 's/metadata-//' -e 's/.json//')
    else
        echo "[WARNING] Ookla json/pcap missing."
    fi
fi

if [[ -n "$archive_ndt" ]]; then
    json_file_ndt=$(find "$workdir/extracted_ndt" -name '*metadata*.json' -print -quit)
    pcap_file_ndt=$(find "$workdir/extracted_ndt" -name '*.pcap' -print -quit)

    if [[ -n "$json_file_ndt" && -n "$pcap_file_ndt" ]]; then
        "$SCRIPTS_DIR/venv/bin/python" "$SCRIPTS_DIR/pcap_processor.py" "$json_file_ndt" "$pcap_file_ndt"
        folder_name_ndt=$(basename "$json_file_ndt" | sed -e 's/metadata-//' -e 's/.json//')
    else
        echo "[WARNING] NDT json/pcap missing."
    fi
fi

# ==========================================
# 4. UPLOAD TO GCP
# ==========================================
echo "[INFO] Uploading to GCP..."
source "__GCLOUD_PATH__/path.bash.inc"

if [[ -n "${folder_name_ookla:-}" ]]; then
    echo "[INFO] Uploading Ookla results..."
    gsutil cp "$workdir"/extracted_ookla/* "gs://speedtest-data/$REMOTE_DIR/ookla/$folder_name_ookla/"
fi

if [[ -n "${folder_name_ndt:-}" ]]; then
    echo "[INFO] Uploading NDT results..."
    gsutil cp "$workdir"/extracted_ndt/* "gs://speedtest-data/$REMOTE_DIR/ndt7/$folder_name_ndt/"
fi

echo "[SUCCESS] Data processing and upload complete."
