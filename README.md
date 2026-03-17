# Speedtest Bottleneck Project — Raspberry Pi Setup

This README explains how to prepare a Raspberry Pi (headless or with the built-in UI), flash the OS, connect to Wi‑Fi, and run the project's `install.sh` to configure the Pi as a Salt minion that runs the speedtest/bottleneck tooling and uploads results to a Salt master.

> **IMPORTANT:** Always run the installer **exactly** as shown below (with `sudo`). The `raspi_name` argument must be **unique** across all your Raspberry Pis. If two Pis use the same name, data on the master can be lost and SaltStack may become corrupted.


## Quick links

* Downloading Debian bookworm 12 OS for Raspberry pi:

```bash
https://downloads.raspberrypi.com/raspios_oldstable_arm64/images/raspios_oldstable_arm64-2025-10-02/2025-10-01-raspios-bookworm-arm64.img.xz
```

* Installer source (curl):

```bash
curl -L -o install.sh https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/install.sh
```


## Table of contents

* [Requirements](#requirements)
* [1) Flash OS & connect to Wi‑Fi](#1-flash-os--connect-to-wi‑fi)
* [2) Open a terminal (local or SSH)](#2-open-a-terminal-local-or-ssh)
* [3) Download & make the installer executable](#3-download--make-the-installer-executable)
* [4) Run the installer (usage)](#4-run-the-installer-usage)
* [5) Accept the Salt key on the master](#5-accept-the-salt-key-on-the-master)
* [What the script does](#what-the-script-does)
* [Post‑install checks](#post‑install-checks)
* [Troubleshooting & notes](#troubleshooting--notes)


## Requirements

* A Raspberry Pi (tested on Pi models running current Raspberry Pi OS)
* Access to a monitor & keyboard (for the Pi UI) **or** ability to SSH into the Pi
* A Salt master reachable at `34.131.196.248` by default (see usage below to change)
* Internet access to download packages and tools


## 1) Flash OS & connect to Wi‑Fi

1. Flash Raspberry Pi OS (link for OS given above) onto the SD card / eMMC following Raspberry Pi official instructions (use Raspberry Pi Imager or your preferred flashing tool).
2. Boot the Pi and complete the first-boot steps.
> IMPORTANT: Always keep the username of the pi as "raspi" when asked during boot and always set the timezone to your local timezone when prompted for first time after boot (eg. Asia/Kolkata)
3. Connect to Wi‑Fi using the Pi's UI (network icon in the top-right/system tray) or configure Wi‑Fi via `raspi-config` (for headless setups).

> If you plan to use SSH-only (headless), enable SSH from the UI or terminal during the boot.


## 2) Open a terminal (local or SSH)

* If you’re using the Pi's desktop UI: open **Terminal**.
* If you’re using SSH: Open a SSH connection using
  ```bash
  ssh raspi@<IP>
  ```

## 3) Download & make the installer executable

Run these commands in the Pi terminal (or over SSH):

```bash
curl -L -o install.sh https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/install.sh
chmod +x install.sh
```


## 4) Run the installer (usage)

**Usage:**

```bash
sudo ./install.sh <raspi_name> [master_ip]
```

* `<raspi_name>` (required): A unique identifier for this Raspberry Pi. **It MUST be unique** across all minions.
* `[master_ip]` (optional): IP of the Salt master. If omitted, the script defaults to `34.131.196.248`.

**Examples:**

```bash
# Basic (uses default master IP)
sudo ./install.sh raspi-room1

# With explicit master IP and master folder
sudo ./install.sh raspi-room2 34.131.196.248
```

**Important:** Run with `sudo` exactly as shown. The script expects elevated privileges and will fail or behave incorrectly if not run as root. Also you might be asked to enter Y/N during the installation process, simply proceed by pressing Y.


## 5) Restart Salt Minion and Accept the Salt key on the master

Once the script is finished, run the below two commands on raspberry pi to restart salt minion and send its key to master.

```bash
sudo systemctl restart salt-minion
sudo systemctl enable salt-minion
```

After the minion restarts, it will register with the Salt master and present its key. On the Salt master run:

```bash
# List keys — you should see the new minion under "Unaccepted"
sudo salt-key -L

# Accept all unaccepted keys (or accept individual key instead)
sudo salt-key -A

# (Optional) accept a single minion by id:
# sudo salt-key -a <minion_id>
```

Verify the minion shows up under `Accepted` after acceptance.


## What the installer script does (summary)

The installer performs the following high-level tasks:

* Ensures the Salt minion is installed and configured to the correct version expected by the master
* Registers the minion with the Salt master (the minion will send its key to the master)
* Installs required tools and libraries for the project, including:

  * Go (golang)
  * `netrics` and the speedtest bottleneck tool (project binaries)
* Configures the system to automatically schedule and run the test tools at regular intervals
* Sets up a service that detects new pcap/json results and uploads them to the master automatically


## Post‑install checks

On the **minion** (Raspberry Pi):

```bash
# Check Salt minion service
sudo systemctl status salt-minion

# Tail the minion logs for errors
sudo journalctl -u salt-minion -f
```

On the **master**:

```bash
# Confirm the minion is accepted
sudo salt-key -L

# Query the minion (replace <minion_id>)
sudo salt '<minion_id>' test.ping
```


## Troubleshooting & notes

* **Duplicate `raspi_name`:** If a new minion uses the same `raspi_name` as an existing one, data on the master may be overwritten and Salt configuration may break. Always pick a unique name (e.g., `raspi-<room>-<number>` or `raspi-<serial-suffix>`).
* **If the minion key does not appear on the master:** Make sure the Pi can reach the master's IP and that any firewall rules allow Salt traffic.
* **If install fails:** Inspect the install script's output and system logs. Re-run the script with `sudo` and check `/var/log` and `journalctl` for errors.

---


# Speedtest Bottleneck Project — macOS Setup

This guide explains how to configure a Mac as an automated diagnostic node for the **Speedtest Bottleneck Project**. The setup installs all necessary network tools, configures Google Cloud authentication, and schedules a background service to run periodic tests.

---

## 1) Install Homebrew

The installation script relies on Homebrew (the macOS package manager) to install dependencies like Go, Wireshark, and Python.

1. Open your Terminal (found in **Applications > Utilities**).
2. Copy and paste the following command, then press Return:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

3. Follow the **"Next steps"** instructions printed in the terminal after the installation finishes to add Homebrew to your `PATH`.
4. Verify it is installed by typing:

```bash
brew --version
```

---

## 2) Download the Installer

Run the following command to download the macOS-specific installer script from the repository:

```bash
curl -L -o install_mac.sh https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/install_mac.sh
```

---

## 3) Run the Installer

The script will create a self-contained folder at `~/speedtest_agent` and configure a background daemon to run the tests every hour.

1. Make the script executable:

```bash
chmod +x install_mac.sh
```

2. Run the installer:

```bash
./install_mac.sh <mac_name>
```

Replace `<mac_name>` with a unique identifier for this Mac (e.g., `Arnav-MacBook-Air`).

> **NOTE:** During installation, you will be prompted for your macOS login password. This is required to install the background service and Wireshark dependencies. Unlike the Raspberry Pi version, **do not run this script with `sudo`**; the script will ask for permissions only when necessary.

---

## 4) Post‑Install Checks

Everything is installed in `~/speedtest_agent`. You can verify the background service is running with these commands:

### Check the background service status

```bash
sudo launchctl list | grep com.speedtest.diagnostics
```

### View the live diagnostic logs

```bash
# Check standard output
cat /tmp/speedtest_diagnostics.out

# Check for errors
cat /tmp/speedtest_diagnostics.err
```

### Manually trigger a test run

If you want to ensure the pipeline works immediately without waiting for the hour:

```bash
sudo launchctl start com.speedtest.diagnostics
```

---

## What the macOS Installer Does

- **Environment Isolation:** Creates a master directory at `~/speedtest_agent` so no random folders are created across your system.
- **Toolchain Setup:** Installs `go`, `wireshark` (for `tshark`), `gnupg`, and `speedtest-cli`.
- **Python Sandbox:** Sets up a Python Virtual Environment (`venv`) to install `pandas`, `scapy`, and `dpkt` without affecting your system Python.
- **GCP Configuration:** Decrypts and activates the Google Cloud Service Account for automated data uploads.
- **IPv6 Workaround:** Configures the run script to temporarily disable IPv6 during the test to bypass a known Go bug on macOS, ensuring you get 100% RTT samples.
- **Persistence:** Installs a macOS LaunchDaemon to ensure the script runs automatically every hour and on every boot.

---

## Troubleshooting

- **Permission Denied:** Ensure you ran `chmod +x install_mac.sh`.
- **No RTT Samples:** If your logs show `NaN` errors, ensure the Mac's Firewall is not in **Stealth Mode** (System Settings > Network > Firewall > Options).
- **Missing `gcloud`:** If the installer fails to find `gcloud`, ensure you followed the Homebrew **"Next steps"** to update your shell's `PATH`.


