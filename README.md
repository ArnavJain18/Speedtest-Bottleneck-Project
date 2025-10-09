# Speedtest Bottleneck Project — Raspberry Pi Setup

This README explains how to prepare a Raspberry Pi (headless or with the built-in UI), flash the OS, connect to Wi‑Fi, and run the project's `install.sh` to configure the Pi as a Salt minion that runs the speedtest/bottleneck tooling and uploads results to a Salt master.

> **IMPORTANT:** Always run the installer **exactly** as shown below (with `sudo`). The `raspi_name` argument must be **unique** across all your Raspberry Pis. If two Pis use the same name, data on the master can be lost and SaltStack may become corrupted.


## Quick links

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
* [License & contact](#license--contact)


## Requirements

* A Raspberry Pi (tested on Pi models running current Raspberry Pi OS)
* Access to a monitor & keyboard (for the Pi UI) **or** ability to SSH into the Pi
* A Salt master reachable at `10.17.9.73` by default (see usage below to change)
* Internet access to download packages and tools


## 1) Flash OS & connect to Wi‑Fi

1. Flash Raspberry Pi OS onto the SD card / eMMC following Raspberry Pi official instructions (use Raspberry Pi Imager or your preferred flashing tool).
2. Boot the Pi and complete the first-boot steps.
3. Connect to Wi‑Fi using the Pi's UI (network icon in the top-right/system tray) or configure Wi‑Fi via `raspi-config` (for headless setups).

> If you plan to use SSH-only (headless), enable SSH before first boot by creating an empty file named `ssh` on the boot partition or enable it later from the UI / `raspi-config`.


## 2) Open a terminal (local or SSH)

* If you’re using the Pi's desktop UI: open **Terminal**.
* If you’re using SSH: enable SSH from the UI:

  1. Top-left menu → **Preferences** → **Raspberry Pi Configuration**
  2. Select the **Interfaces** tab
  3. Toggle **SSH** to **Enabled**

Also, while you are here, set a secure password for the `pi`/`raspi` user via the UI or by running:

```bash
passwd
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
sudo ./install.sh <raspi_name> [master_ip] [master_home]
```

* `<raspi_name>` (required): A unique identifier for this Raspberry Pi. **It MUST be unique** across all minions.
* `[master_ip]` (optional): IP of the Salt master. If omitted, the script defaults to `10.17.9.73`.
* `[master_home]` (optional): Absolute path on the master where data will be stored (e.g. `/home/baadalvm`). If omitted, defaults to `/home/baadalvm`.

**Examples:**

```bash
# Basic (uses default master IP and home)
sudo ./install.sh raspi-room1

# With explicit master IP and master folder
sudo ./install.sh raspi-room2 10.17.9.73 /home/baadalvm
```

**Important:** Run with `sudo` exactly as shown. The script expects elevated privileges and will fail or behave incorrectly if not run as root.


## 5) Accept the Salt key on the master

After the minion runs the installer it will register with the Salt master and present its key. On the Salt master run:

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
  * `netrics` and/or the speedtest bottleneck tool (project binaries)
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

