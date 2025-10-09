#!/bin/bash
set -e  # exit on first error
set -u  # treat unset variables as error

# --- Config ---
MASTER_USER="baadalvm"
MASTER_HOST="10.17.9.73"
MASTER_PASS="5855bfd1"   # TODO: use SSH key later
REMOTE_DIR="/home/baadalvm/netrics_results_raspberrypi"

# --- Temporary workspace ---
timestamp=$(date +"%Y%m%d_%H%M%S")
workdir="/tmp/netrics_bottleneck_$timestamp"
outfile="$workdir/bottleneck_${timestamp}.tar.gz"

mkdir -p "$workdir"

# --- Step 1: Run bottleneck tester and save output ---
echo "[INFO] Running bottleneck-finder..."
netrics-bottleneck-finder > "$outfile"

# --- Step 2: Extract files ---
echo "[INFO] Extracting files..."
mkdir -p "$workdir/extracted"
tar -xzf "$outfile" -C "$workdir/extracted"

# --- Step 3: Ensure sshpass exists ---
if ! command -v sshpass &> /dev/null; then
    echo "[INFO] sshpass not found, installing..."
    sudo apt-get update && sudo apt-get install -y sshpass
fi

# --- Step 4: Upload to remote master ---
echo "[INFO] Uploading files to $MASTER_HOST..."
sshpass -p "$MASTER_PASS" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "$workdir"/extracted/* "$MASTER_USER@$MASTER_HOST:$REMOTE_DIR/"

# --- Step 5: Cleanup ---
echo "[INFO] Cleaning up temporary files..."
rm -rf "$workdir"

echo "[SUCCESS] Upload complete. Temporary files deleted. Files stored at $REMOTE_DIR on $MASTER_HOST."
