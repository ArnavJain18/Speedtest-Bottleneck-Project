#!/bin/bash
set -e
set -u

# --- Config (Injected by Installer) ---
REMOTE_DIR="__REMOTE_DIR__"

# --- Dynamic Paths ---
BASE_DIR="$HOME/speedtest_agent"
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

echo "[INFO] Running bottleneck-finder with Ookla..."
sudo env PATH="$PATH" "$BIN_DIR/bottleneck-finder" -I "$ACTIVE_IFACE" -t ookla -a -o "$workdir/ookla"

echo "[INFO] Finding archives to process..."
archive_ookla=$(find "$workdir/ookla" -name '*.tar.gz' -print -quit)
mkdir -p "$workdir/extracted_ookla"

if [[ -n "$archive_ookla" ]]; then
    tar -xzf "$archive_ookla" -C "$workdir/extracted_ookla"
else
    echo "[ERROR] No Ookla archive found. Exiting."
    exit 1
fi

echo "[INFO] Processing pcap and json files..."
cd "$SCRIPTS_DIR"

json_file_ookla=$(find "$workdir/extracted_ookla" -name '*metadata*.json' -print -quit)
pcap_file_ookla=$(find "$workdir/extracted_ookla" -name '*.pcap' -print -quit)

if [[ -n "$json_file_ookla" && -n "$pcap_file_ookla" ]]; then
    "$SCRIPTS_DIR/venv/bin/python" "$SCRIPTS_DIR/pcap_processor.py" "$json_file_ookla" "$pcap_file_ookla"
    folder_name_ookla=$(basename "$json_file_ookla" | sed -e 's/metadata-//' -e 's/.json//')
else
    echo "[WARNING] Ookla json/pcap missing."
fi

echo "[INFO] Uploading to GCP..."
source "$(brew --prefix)/share/google-cloud-sdk/path.bash.inc"

if [[ -n "${folder_name_ookla:-}" ]]; then
    gsutil cp "$workdir"/extracted_ookla/* "gs://speedtest-data/$REMOTE_DIR/ookla/$folder_name_ookla/"
fi

echo "[SUCCESS] Data processing and upload complete."
