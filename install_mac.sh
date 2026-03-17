#!/bin/bash
# Usage: ./install_mac.sh <mac_name>

set -e

if [ -z "$1" ]; then
  echo "Error: mac_name argument is required."
  echo "Usage: ./install_mac.sh <mac_name>"
  exit 1
fi

MAC_NAME="$1"
REMOTE_DIR="netrics_results_${MAC_NAME}"
INSTALL_DIR="$HOME/speedtest_agent"

echo "Starting macOS installation script..."
echo "Using MAC Name: $MAC_NAME"
echo "Project Directory: $INSTALL_DIR"

mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/scripts"
mkdir -p "$INSTALL_DIR/gcloud_config"

cd "$INSTALL_DIR"

echo "========================= Checking for Homebrew ========================="
if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Please install Homebrew first (https://brew.sh/)."
    exit 1
fi

echo "========================= Installing Global Dependencies ========================="
brew update
brew install make libpcap python3 wireshark go gnupg

echo "========================= Downloading Speedtest Diagnostics ========================="
curl -LO https://github.com/ArnavJain18/Speedtest-Bottleneck-Project/raw/main/speedtest_diagnostics.zip
unzip -o speedtest_diagnostics.zip
rm speedtest_diagnostics.zip

echo "========================= Building Bottleneck Finder ========================="
cd speedtest_diagnostics/
make build
cp bin/bottleneck-finder "$INSTALL_DIR/bin/"
cd ..

echo "========================= Installing NDT7 Client ========================="
export GOPATH="$INSTALL_DIR/go_workspace"
go install github.com/m-lab/ndt7-client-go/cmd/ndt7-client@latest
cp "$GOPATH/bin/ndt7-client" "$INSTALL_DIR/bin/ndt"
cp "$GOPATH/bin/ndt7-client" "$INSTALL_DIR/bin/ndt7-client"
chmod +x "$INSTALL_DIR/bin/ndt" "$INSTALL_DIR/bin/ndt7-client"
go clean -modcache
rm -rf "$INSTALL_DIR/go_workspace"

echo "========================= Installing OOKLA Speedtest CLI ========================="
brew tap teamookla/speedtest
brew install speedtest
speedtest --accept-license --accept-gdpr

echo "========================= Installing Google Cloud SDK ========================="
if ! command -v gcloud &> /dev/null; then
    brew install --cask google-cloud-sdk
else
    echo "Google Cloud SDK is already installed."
fi

echo "========================= Configuring Google Cloud SDK ========================="
curl -sSL "https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/speedtest-bottleneck-finder-64390a06f380.json.gpg" | gpg --batch --passphrase "checkmate" -d > "$INSTALL_DIR/gcloud_config/key.json"
if ! command -v gcloud &> /dev/null; then
    source "$(brew --prefix)/share/google-cloud-sdk/path.bash.inc"
fi
gcloud auth activate-service-account --key-file="$INSTALL_DIR/gcloud_config/key.json"

echo "========================= Installing Python Dependencies ========================="
cd "$INSTALL_DIR/scripts"
curl -O https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/pcap_processor.py
curl -O https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/speedtest_boundaries.py
curl -O https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/requirements.txt

echo "Creating Python virtual environment..."
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate

echo "========================= Setting up Automation Scripts ========================="
# Calculate gcloud path once during install
GCLOUD_INSTALLED_PATH="$(brew --prefix)/share/google-cloud-sdk"

# Download and configure the run script
curl -sL "https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/run_mac.sh" \
  | sed -e "s|__REMOTE_DIR__|$REMOTE_DIR|g" \
        -e "s|__BASE_DIR__|$INSTALL_DIR|g" \
        -e "s|__GCLOUD_PATH__|$GCLOUD_INSTALLED_PATH|g" \
  > run_mac.sh
chmod +x run_mac.sh
# Download and configure the LaunchDaemon XML
cd "$INSTALL_DIR"
curl -sL "https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/mac_schedule.plist" \
  | sed "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
  > com.speedtest.diagnostics.plist

echo "========================= Activating Background Service ========================="
echo "You may be prompted for your password to install the background service."
sudo mv com.speedtest.diagnostics.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.speedtest.diagnostics.plist
sudo chmod 644 /Library/LaunchDaemons/com.speedtest.diagnostics.plist

# Unload first just in case this is a re-installation
sudo launchctl unload /Library/LaunchDaemons/com.speedtest.diagnostics.plist 2>/dev/null || true
# Load and start the background timer
sudo launchctl load -w /Library/LaunchDaemons/com.speedtest.diagnostics.plist

echo "========================= Yayyy, All installation finished !! ========================="
echo "Data collection will now run silently in the background every hour."
