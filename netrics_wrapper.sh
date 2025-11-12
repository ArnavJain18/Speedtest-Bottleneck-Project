#!/bin/bash
set -e  # exit on first error
set -u  # treat unset variables as error

# --- Config ---

REMOTE_DIR="__REMOTE_DIR__"
SCRIPTS_DIR=/home/raspi/scripts

# --- Temporary workspace ---
timestamp=$(date +"%Y%m%d_%H%M%S")
workdir="/tmp/netrics_bottleneck_$timestamp"
outfile="$workdir/bottleneck_ndt7_${timestamp}.tar.gz"
outfile_ookla="$workdir/bottleneck_ookla_${timestamp}.tar.gz"

mkdir -p "$workdir"

# --- Step 1: Run bottleneck tester and save output ---
echo "[INFO] Running bottleneck-finder..."
export PATH=/usr/bin:/bin:/usr/local/bin:/usr/sbin:/sbin
export HOME=/root
netrics-bottleneck-finder --tool ookla > "$outfile_ookla"
export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:.
export HOME=
netrics-bottleneck-finder > "$outfile"

# --- Step 2: Extract files ---
echo "[INFO] Extracting files..."
mkdir -p "$workdir/extracted"
tar -xzf "$outfile" -C "$workdir/extracted"
mkdir -p "$workdir/extracted_ookla"
tar -xzf "$outfile_ookla" -C "$workdir/extracted_ookla"

echo "[INFO] Finding timestamp from filenames..."

json_file=$(find "$workdir/extracted" -name '*.json' -print -quit)
pcap_file=$(find "$workdir/extracted" -name '*.pcap' -print -quit)

if [ -z "$json_file" ]; then
    echo "[ERROR] No .json file found in extracted tarball. Aborting."
    exit 1
fi
filename=$(basename "$json_file")
folder_name=$(echo "$filename" | sed -e 's/metadata-//' -e 's/\.json//')

echo "[INFO] Extracted folder name: $folder_name"

json_file_ookla=$(find "$workdir/extracted_ookla" -name '*.json' -print -quit)
pcap_file_ookla=$(find "$workdir/extracted_ookla" -name '*.pcap' -print -quit)

if [ -z "$json_file_ookla" ]; then
    echo "[ERROR] No .json file found in extracted Ookla tarball. Aborting."
    exit 1
fi
filename_ookla=$(basename "$json_file_ookla")
folder_name_ookla=$(echo "$filename_ookla" | sed -e 's/metadata-//' -e 's/\.json//')
echo "[INFO] Extracted Ookla folder name: $folder_name_ookla"

echo "[INFO] Processing pcap and json files to extract RTT samples..."
cd "$SCRIPTS_DIR"
python "$SCRIPTS_DIR/pcap_processor.py" "$json_file" "$pcap_file"
python "$SCRIPTS_DIR/pcap_processor.py" "$json_file_ookla" "$pcap_file_ookla"
cd ..
# --- Step 3: Upload to Google Cloud Storage ---
gsutil cp "$workdir"/extracted/* gs://speedtest-data/$REMOTE_DIR/ndt7/$folder_name/
gsutil cp "$workdir"/extracted_ookla/* gs://speedtest-data/$REMOTE_DIR/ookla/$folder_name_ookla/

# --- Step 5: Cleanup ---
echo "[INFO] Cleaning up temporary files..."
rm -rf "$workdir"

echo "[SUCCESS] Upload complete. Temporary files deleted. Files stored at $REMOTE_DIR on cloud."
