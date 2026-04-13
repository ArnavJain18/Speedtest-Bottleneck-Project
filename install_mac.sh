#!/bin/bash
# Usage: ./install_mac.sh

# --- CONFIGURATION ---
# USER: PLEASE CHANGE THE LINE BELOW TO A UNIQUE NAME FOR THIS MAC
# Example: MAC_NAME="Arnav-MacBook-Pro"
MAC_NAME="__MAC_NAME__"

# --- VALIDATION ---
if [ "$MAC_NAME" == "__MAC_NAME__" ]; then
  echo "-----------------------------------------------------------------------"
  echo "ERROR: MAC_NAME is not set."
  echo "-----------------------------------------------------------------------"
  echo "Please open this script (install_mac.sh) in a text editor and change"
  echo "the line: MAC_NAME=\"__MAC_NAME__\""
  echo "to a unique name for this machine (e.g., MAC_NAME=\"MyMac-01\")."
  echo "Then save the file and run it again."
  echo "-----------------------------------------------------------------------"
  exit 1
fi

set -e

REMOTE_DIR="netrics_results_${MAC_NAME}"
INSTALL_DIR="$HOME/speedtest_agent"

# ==========================================
# LOGGING SETUP
# Create INSTALL_DIR first so the log file path always exists,
# regardless of whether the user chose $HOME or $INSTALL_DIR.
# ==========================================
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/scripts"
mkdir -p "$INSTALL_DIR/gcloud_config"

LOG_FILE="$INSTALL_DIR/speedtest_install.log"

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
log "INFO" "  Speedtest Diagnostics Installer - $(date)"
log "INFO" "============================================================"
log "INFO" "MAC Name:          $MAC_NAME"
log "INFO" "Install Directory: $INSTALL_DIR"
log "INFO" "Log File:          $LOG_FILE"

cd "$INSTALL_DIR"

# ==========================================
# HELPER: brew_install_if_missing
# Skips 'brew install' (and any Xcode checks) if the formula is already installed.
# ==========================================
brew_install_if_missing() {
    local pkg="$1"
    if brew list --formula "$pkg" &>/dev/null; then
        log "INFO" "[$pkg] Already installed via Homebrew — skipping."
    else
        log "INFO" "[$pkg] Installing via Homebrew..."
        HOMEBREW_NO_AUTO_UPDATE=1 brew install "$pkg"
    fi
}

brew_cask_install_if_missing() {
    local pkg="$1"
    if brew list --cask "$pkg" &>/dev/null; then
        log "INFO" "[$pkg] Already installed (cask) — skipping."
    else
        log "INFO" "[$pkg] Installing cask via Homebrew..."
        HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask "$pkg"
    fi
}

# ==========================================
# 1. HOMEBREW
# ==========================================
log "INFO" "========================= Checking for Homebrew ========================="
if ! command -v brew &> /dev/null; then
    log "INFO" "Homebrew not found. Installing Homebrew automatically..."
    log "INFO" "(You may be prompted for your Mac password to grant installation permissions)"

    sudo -v

    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        BREW_BIN="/opt/homebrew/bin/brew"
    elif [[ -x "/usr/local/bin/brew" ]]; then
        BREW_BIN="/usr/local/bin/brew"
    else
        log "ERROR" "Homebrew installed but executable not found. Aborting."
        exit 1
    fi

    eval "$($BREW_BIN shellenv)"

    USER_SHELL=$(basename "$SHELL")
    if [[ "$USER_SHELL" == "zsh" ]]; then
        PROFILE_FILE="$HOME/.zprofile"
    else
        PROFILE_FILE="$HOME/.bash_profile"
    fi

    if ! grep -q "$BREW_BIN shellenv" "$PROFILE_FILE" 2>/dev/null; then
        log "INFO" "Permanently adding Homebrew to $PROFILE_FILE..."
        echo "" >> "$PROFILE_FILE"
        echo "# Speedtest Bottleneck Project - Homebrew Path" >> "$PROFILE_FILE"
        echo "eval \"\$($BREW_BIN shellenv)\"" >> "$PROFILE_FILE"
    fi

    log "INFO" "Homebrew installed and added to PATH successfully."
else
    log "INFO" "Homebrew is already installed."
fi

# ==========================================
# 2. DEPENDENCIES
# Run 'brew update' only once, only if it hasn't been run recently (within 24h).
# Install each package only if it is not already present.
# HOMEBREW_NO_AUTO_UPDATE=1 prevents brew from silently re-running update on
# every individual 'brew install' call (which is the default behaviour that
# causes multi-minute delays).
# ==========================================
log "INFO" "========================= Checking / Installing Dependencies ========================="

BREW_UPDATED_FLAG="/tmp/.speedtest_brew_updated_today"
TODAY=$(date +%Y%m%d)

if [[ ! -f "$BREW_UPDATED_FLAG" ]] || [[ "$(cat "$BREW_UPDATED_FLAG" 2>/dev/null)" != "$TODAY" ]]; then
    log "INFO" "Running 'brew update' (once per day)..."
    brew update
    echo "$TODAY" > "$BREW_UPDATED_FLAG"
else
    log "INFO" "'brew update' already ran today — skipping."
fi

# Export so every brew call in this session skips auto-update
export HOMEBREW_NO_AUTO_UPDATE=1

for pkg in make libpcap python3 gnupg; do
    brew_install_if_missing "$pkg"
done

# wireshark: needed for tshark/dumpcap — install headless (no GUI, no Xcode Qt build)
# The 'wireshark' formula on Homebrew is the CLI-only build; the GUI lives in the cask.
brew_install_if_missing "wireshark"

# go: required to compile speedtest_diagnostics and ndt7-client
brew_install_if_missing "go"

# ==========================================
# 3. OOKLA SPEEDTEST CLI
#
# Strategy (tried in order, stops at first success):
#   A) Binary already installed  → skip entirely
#   B) Direct CDN download       → fastest, no Xcode
#   C) brew tap + install        → fallback; works if CDN is back
#   D) Manual download prompt    → last resort with clear instructions
#
# The teamookla/homebrew-speedtest tap formula directly downloads the
# same CDN binary (no source build, no Xcode).  However the CDN URLs
# periodically return 403.  Strategy B+C together cover both cases.
# ==========================================
log "INFO" "========================= Installing Ookla Speedtest CLI ========================="

OOKLA_BIN="$INSTALL_DIR/bin/speedtest"
ARCH=$(uname -m)

install_ookla_from_github() {
    # Primary source: universal binary hosted in your own GitHub repo.
    # Upload ookla-speedtest-1.2.0-macosx-universal.tgz to the repo root
    # (same place as speedtest_diagnostics.zip) and this will just work.
    local url="https://github.com/ArnavJain18/Speedtest-Bottleneck-Project/raw/main/ookla-speedtest-1.2.0-macosx-universal.tgz"
    log "INFO" "  Trying GitHub-hosted universal binary..."
    local tmp
    tmp=$(mktemp -d)
    if curl -fsSL --max-time 60 "$url" -o "$tmp/speedtest.tgz" 2>/dev/null; then
        tar -xzf "$tmp/speedtest.tgz" -C "$tmp"
        # The tgz extracts into a subfolder; find the binary regardless of layout
        local bin
        bin=$(find "$tmp" -type f -name "speedtest" -not -name "*.md" -not -name "*.5" | head -1)
        if [[ -n "$bin" ]]; then
            cp "$bin" "$OOKLA_BIN"
            chmod +x "$OOKLA_BIN"
            rm -rf "$tmp"
            log "INFO" "  GitHub download succeeded."
            return 0
        fi
    fi
    rm -rf "$tmp"
    log "INFO" "  GitHub download failed — trying next strategy..."
    return 1
}

install_ookla_from_cdn() {
    # Fallback: Ookla's own CDN (may return 403 intermittently).
    # Tries universal binary first, then arch-specific ones.
    local ARCH
    ARCH=$(uname -m)
    local urls=(
        "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-macosx-universal.tgz"
        "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-macosx-arm64.tgz"
        "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-macosx-x86_64.tgz"
    )
    local tmp
    tmp=$(mktemp -d)
    for url in "${urls[@]}"; do
        log "INFO" "  Trying Ookla CDN: $url"
        if curl -fsSL --max-time 30 "$url" -o "$tmp/speedtest.tgz" 2>/dev/null; then
            tar -xzf "$tmp/speedtest.tgz" -C "$tmp"
            local bin
            bin=$(find "$tmp" -type f -name "speedtest" -not -name "*.md" -not -name "*.5" | head -1)
            if [[ -n "$bin" ]]; then
                cp "$bin" "$OOKLA_BIN"
                chmod +x "$OOKLA_BIN"
                rm -rf "$tmp"
                log "INFO" "  CDN download succeeded."
                return 0
            fi
        fi
        log "INFO" "  CDN URL returned error — trying next..."
    done
    rm -rf "$tmp"
    return 1
}

install_ookla_via_brew_tap() {
    log "INFO" "  Trying Homebrew tap (teamookla/speedtest)..."
    # The tap formula downloads the same Ookla binary — no source build.
    # HOMEBREW_NO_INSTALL_FROM_API=1 forces brew to use the tap formula directly.
    if HOMEBREW_NO_AUTO_UPDATE=1 brew tap teamookla/speedtest 2>>"$LOG_FILE" \
    && HOMEBREW_NO_AUTO_UPDATE=1 brew install speedtest --force 2>>"$LOG_FILE"; then
        # Copy the brew-managed binary into our own bin/ so run_mac.sh finds it
        local brew_bin
        brew_bin=$(brew --prefix)/bin/speedtest
        if [[ -x "$brew_bin" ]]; then
            cp "$brew_bin" "$OOKLA_BIN"
            chmod +x "$OOKLA_BIN"
            log "INFO" "  Homebrew tap install succeeded."
            return 0
        fi
    fi
    return 1
}

if [[ -x "$OOKLA_BIN" ]]; then
    log "INFO" "Ookla speedtest binary already present at $OOKLA_BIN — skipping."
else
    log "INFO" "Ookla binary not found. Trying install strategies (arch=$(uname -m))..."

    if install_ookla_from_github; then
        : # success — GitHub-hosted universal binary
    elif install_ookla_from_cdn; then
        : # success — Ookla's own CDN
    elif install_ookla_via_brew_tap; then
        : # success — Homebrew tap
    else
        # ---------- MANUAL FALLBACK ----------
        log "ERROR" "------------------------------------------------------------"
        log "ERROR" "Could not download the Ookla Speedtest CLI automatically."
        log "ERROR" ""
        log "ERROR" "Please download it manually:"
        log "ERROR" "  1. Open this URL in your browser:"
        log "ERROR" "     https://www.speedtest.net/apps/cli"
        log "ERROR" "  2. Download the macOS package (.tgz) and unzip it."
        log "ERROR" "  3. Copy the 'speedtest' binary to:"
        log "ERROR" "     $OOKLA_BIN"
        log "ERROR" "  4. Run:  chmod +x $OOKLA_BIN"
        log "ERROR" "  5. Re-run this installer."
        log "ERROR" "------------------------------------------------------------"
        exit 1
    fi
fi

# Accept license/GDPR non-interactively (safe to re-run)
log "INFO" "Accepting Ookla license and GDPR terms..."
"$OOKLA_BIN" --accept-license --accept-gdpr > /dev/null 2>&1 || true

# Make speedtest reachable on PATH for the rest of this script
export PATH="$INSTALL_DIR/bin:$PATH"

# ==========================================
# 4. SPEEDTEST DIAGNOSTICS (bottleneck-finder)
# ==========================================
log "INFO" "========================= Downloading Speedtest Diagnostics ========================="
cd "$INSTALL_DIR"
curl -fsSL -o speedtest_diagnostics.zip \
    https://github.com/ArnavJain18/Speedtest-Bottleneck-Project/raw/main/speedtest_diagnostics.zip
unzip -o speedtest_diagnostics.zip
rm speedtest_diagnostics.zip

log "INFO" "========================= Building Bottleneck Finder ========================="
cd speedtest_diagnostics/
make build
cp bin/bottleneck-finder "$INSTALL_DIR/bin/"
cd ..

# ==========================================
# 5. NDT7 CLIENT
# ==========================================
log "INFO" "========================= Installing NDT7 Client ========================="

NDT_BIN="$INSTALL_DIR/bin/ndt7-client"
if [[ -x "$NDT_BIN" ]]; then
    log "INFO" "ndt7-client already present — skipping Go install."
else
    log "INFO" "Compiling ndt7-client via 'go install' ..."
    export GOPATH="$INSTALL_DIR/go_workspace"
    go install github.com/m-lab/ndt7-client-go/cmd/ndt7-client@latest
    cp "$GOPATH/bin/ndt7-client" "$INSTALL_DIR/bin/ndt"
    cp "$GOPATH/bin/ndt7-client" "$NDT_BIN"
    chmod +x "$INSTALL_DIR/bin/ndt" "$NDT_BIN"
    go clean -modcache
    rm -rf "$INSTALL_DIR/go_workspace"
    log "INFO" "ndt7-client installed."
fi

# ==========================================
# 6. GOOGLE CLOUD SDK
# ==========================================
log "INFO" "========================= Installing Google Cloud SDK ========================="

# Resolve the actual gcloud path robustly, covering both Apple Silicon and Intel Macs.
# We do this BEFORE installing so we can reuse the logic whether gcloud was
# pre-installed or just installed by us.
resolve_gcloud_path() {
    # Priority 1: already on PATH
    if command -v gcloud &>/dev/null; then
        local sdk_root
        sdk_root=$(gcloud info --format="value(installation.sdk_root)" 2>/dev/null || true)
        if [[ -f "$sdk_root/path.bash.inc" ]]; then
            echo "$sdk_root"
            return
        fi
    fi

    # Priority 2: well-known Homebrew cask locations
    local candidates=(
        "$(brew --prefix)/share/google-cloud-sdk"   # Apple Silicon: /opt/homebrew/share/...
        "/usr/local/share/google-cloud-sdk"          # Intel default
        "/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk"
        "/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk"
    )
    for dir in "${candidates[@]}"; do
        if [[ -f "$dir/path.bash.inc" ]]; then
            echo "$dir"
            return
        fi
    done

    echo ""  # not found
}

if ! command -v gcloud &> /dev/null; then
    log "INFO" "Google Cloud SDK not found. Installing via Homebrew cask..."
    brew_cask_install_if_missing "google-cloud-sdk"
else
    log "INFO" "Google Cloud SDK is already installed."
fi

# Source path.bash.inc so gcloud is usable in the rest of this script,
# then record the resolved path for injection into run_mac.sh.
GCLOUD_INSTALLED_PATH=$(resolve_gcloud_path)

if [[ -z "$GCLOUD_INSTALLED_PATH" ]]; then
    log "ERROR" "Could not locate google-cloud-sdk path.bash.inc after installation."
    log "ERROR" "Searched brew prefix: $(brew --prefix)/share/google-cloud-sdk"
    log "ERROR" "Please install Google Cloud SDK manually and re-run."
    exit 1
fi

log "INFO" "Google Cloud SDK path resolved to: $GCLOUD_INSTALLED_PATH"

# Load gcloud into current shell (needed for 'gcloud auth' below)
# shellcheck disable=SC1090
source "$GCLOUD_INSTALLED_PATH/path.bash.inc"

# ==========================================
# 7. CONFIGURE GCLOUD AUTH
# ==========================================
log "INFO" "========================= Configuring Google Cloud SDK ========================="
curl -fsSL \
    "https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/speedtest-bottleneck-finder-64390a06f380.json.gpg" \
    | gpg --batch --passphrase "checkmate" -d > "$INSTALL_DIR/gcloud_config/key.json"

gcloud auth activate-service-account --key-file="$INSTALL_DIR/gcloud_config/key.json"
log "INFO" "GCloud service account activated."

# ==========================================
# 8. PYTHON DEPENDENCIES
# ==========================================
log "INFO" "========================= Installing Python Dependencies ========================="
cd "$INSTALL_DIR/scripts"
curl -fsSO https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/pcap_processor.py
curl -fsSO https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/speedtest_boundaries.py
curl -fsSO https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/requirements.txt

log "INFO" "Creating Python virtual environment..."
python3 -m venv venv
source venv/bin/activate
pip install --quiet -r requirements.txt
deactivate
log "INFO" "Python dependencies installed."

# ==========================================
# 9. GENERATE run_mac.sh
# ==========================================
log "INFO" "========================= Setting up Automation Scripts ========================="

curl -fsSL "https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/run_mac.sh" \
  | sed \
        -e "s|__REMOTE_DIR__|$REMOTE_DIR|g" \
        -e "s|__BASE_DIR__|$INSTALL_DIR|g" \
        -e "s|__GCLOUD_PATH__|$GCLOUD_INSTALLED_PATH|g" \
  > "$INSTALL_DIR/scripts/run_mac.sh"
chmod +x "$INSTALL_DIR/scripts/run_mac.sh"
log "INFO" "run_mac.sh written to $INSTALL_DIR/scripts/run_mac.sh"
log "INFO" "  GCLOUD_PATH injected as: $GCLOUD_INSTALLED_PATH"

# ==========================================
# 10. LAUNCHDAEMON (background scheduler)
# ==========================================
cd "$INSTALL_DIR"
curl -fsSL "https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/mac_schedule.plist" \
  | sed "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
  > com.speedtest.diagnostics.plist

log "INFO" "========================= Activating Background Service ========================="
log "INFO" "You may be prompted for your password to install the background service."

sudo mv com.speedtest.diagnostics.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.speedtest.diagnostics.plist
sudo chmod 644 /Library/LaunchDaemons/com.speedtest.diagnostics.plist

sudo launchctl unload /Library/LaunchDaemons/com.speedtest.diagnostics.plist 2>/dev/null || true
sudo launchctl load -w /Library/LaunchDaemons/com.speedtest.diagnostics.plist

log "INFO" "============================================================"
log "INFO" "  Installation Complete!"
log "INFO" "  Data collection runs silently in the background every hour."
log "INFO" "  Full install log saved to: $LOG_FILE"
log "INFO" "============================================================"
