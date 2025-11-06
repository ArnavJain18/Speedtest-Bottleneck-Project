#!/bin/bash
# Usage: sudo ./install.sh <raspi_name> [master_ip]
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root:"
  echo "  sudo ./install.sh <raspi_name> [master_ip]"
  exit 1
fi

if [ -z "$1" ]; then
  echo "Error: raspi_name argument is required."
  echo "Usage: sudo ./install.sh <raspi_name> [master_ip]"
  exit 1
fi

RASPI_NAME="$1"
MASTER_IP=${2:-"10.17.9.73"}
REMOTE_DIR=netrics_results_${RASPI_NAME}

echo "Starting installation script..."
echo "Using  RASPI Name: $RASPI_NAME"
echo "Using  MASTER IP: $MASTER_IP"
echo "Using  REMOTE DIR: $REMOTE_DIR"

echo "========================= Installing Salt Minion...========================================================="

curl -LO https://github.com/ArnavJain18/Speedtest-Bottleneck-Project/raw/main/salt-common_3007.7_arm64.deb
curl -LO https://github.com/ArnavJain18/Speedtest-Bottleneck-Project/raw/main/salt-minion_3007.7_arm64.deb
DEBIAN_FRONTEND=noninteractive sudo apt install -y \
  -o Dpkg::Options::="--force-confnew" \
  ./salt-common_3007.7_arm64.deb ./salt-minion_3007.7_arm64.deb
# ip: 10.17.9.73 and add id: raspberrypi[no]

echo "master: $MASTER_IP" | tee -a /etc/salt/minion > /dev/null
echo "id: $RASPI_NAME" | tee -a /etc/salt/minion > /dev/null

echo "========================= Updating and installing dependencies...========================================================="
sudo apt update
sudo apt install -y build-essential git make libpcap-dev libcap2-bin python3-pip
git clone https://github.com/internet-innovation/netrics.git netrics

echo "========================= Downloading files from Speedtest Diagnostics Repository...========================================================="
wget https://github.com/ArnavJain18/Speedtest-Bottleneck-Project/raw/main/speedtest_diagnostics.zip
sudo apt-get update -y && sudo apt-get install -y unzip
unzip speedtest_diagnostics.zip
rm speedtest_diagnostics.zip
cd netrics 
python3 install.py
cd ..
sudo netrics init conf
sudo netrics init
VER=$(curl -s https://go.dev/VERSION?m=text | head -n1)
TARBALL="${VER}.linux-arm64.tar.gz"
URL="https://go.dev/dl/${TARBALL}"
echo "Downloading $URL ..."
wget --progress=dot:giga -O /tmp/$TARBALL "$URL"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf /tmp/$TARBALL
sudo rm /tmp/$TARBALL
export PATH=/usr/local/go/bin:$PATH
grep -qxF 'export PATH=/usr/local/go/bin:$PATH' ~/.profile || echo 'export PATH=/usr/local/go/bin:$PATH' >> ~/.profile
source ~/.profile
cd speedtest_diagnostics/
export NETRICS=true
make build setcap
setcap 'cap_net_raw,cap_net_admin+ep' ./bin/netrics-bottleneck-finder
sudo ln -s /home/raspi/speedtest_diagnostics/bin/netrics-bottleneck-finder /usr/local/bin/netrics-bottleneck-finder
sudo apt update
sudo apt install golang -y
go install github.com/m-lab/ndt7-client-go/cmd/ndt7-client@latest
mv $HOME/go/bin/ndt7-client /usr/local/bin/ndt
sudo ln -s /usr/local/bin/ndt /usr/bin/ndt
sudo rm /usr/local/bin/ndt
sudo rm /usr/bin/ndt
cd ..
go install github.com/m-lab/ndt7-client-go/cmd/ndt7-client@latest
mv $HOME/go/bin/ndt7-client /usr/local/bin/
chmod +x /usr/local/bin/ndt7-client

echo "========================= Installing OOKLA Speedtest CLI...========================================================="
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
sudo apt-get install speedtest -y
speedtest --accept-license --accept-gdpr

echo "========================= Installing Google Cloud SDK...========================================================="
sudo apt-get install -y apt-transport-https ca-certificates gnupg curl

echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
  sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
  sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -

sudo apt-get update && sudo apt-get install -y google-cloud-cli

echo "========================= Configuring Google Cloud SDK...========================================================="
mkdir -p gcloud_config
curl -sSL "https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/speedtest-bottleneck-finder-64390a06f380.json.gpg" | gpg --batch --passphrase "checkmate" -d > gcloud_config/key.json
gcloud auth activate-service-account --key-file=gcloud_config/key.json

echo "========================= Installing Additional Scripts and  Python dependencies...========================================================="
mkdir scripts
cd scripts
curl -O https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/pcap_processor.py
curl -O https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/speedtest_boundaries.py
curl -O https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/requirements.txt
pip install -r requirements.txt --break-system-packages
cd ..

echo "========================= Setting up transfer data to master service...========================================================="
#curl -O https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/netrics_wrapper.sh
curl -sL https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/netrics_wrapper.sh \
  | sed "s|__REMOTE_DIR__|$REMOTE_DIR|g" \
  > netrics_wrapper.sh

chmod +x netrics_wrapper.sh
curl -O https://raw.githubusercontent.com/ArnavJain18/Speedtest-Bottleneck-Project/main/measurements.yaml
mv measurements.yaml /etc/netrics/
sudo systemctl daemon-reload
sudo systemctl restart netrics
echo "[INFO] Enabling netrics startup at boot time"
sudo systemctl enable netrics

echo "========================= Yayyy, All installation finished !!...========================================================="










