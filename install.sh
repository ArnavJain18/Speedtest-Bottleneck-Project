#!/bin/bash
# Usage: sudo ./install.sh <raspi_name> [master_ip] [master_home]
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root:"
  echo "  sudo ./install.sh <raspi_name> [master_ip] [master_home]"
  exit 1
fi

if [ -z "$1" ]; then
  echo "Error: raspi_name argument is required."
  echo "Usage: sudo ./install.sh <raspi_name> [master_ip] [master_home]"
  exit 1
fi

RASPI_NAME="$1"
MASTER_IP=${2:-"10.17.9.73"}
MASTER_HOME=${3:-"/home/baadalvm"}
REMOTE_DIR=${MASTER_HOME}/netrics_results_${RASPI_NAME}

echo "Starting installation script..."
echo "Using  RASPI Name: $RASPI_NAME"
echo "Using  MASTER IP: $MASTER_IP"
echo "Using  MASTER HOME: $MASTER_HOME"
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

echo "========================= Yayyy, All installation finished !!...========================================================="










