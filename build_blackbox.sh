#! /bin/bash

export Linux_hardened_branch=6.12
export debian_rootfs_size=750
NO_COLOR="${NO_COLOR:-}"

COLOR_RESET="\033[0m"
COLOR_CYAN="\033[36m"
COLOR_YELLOW="\033[33m"
COLOR_GREEN="\033[32m"
COLOR_RED="\033[31m"
COLOR_DIM="\033[2m"

if [[ -n "${NO_COLOR}" ]] || [[ ! -t 1 ]]; then
  COLOR_RESET=""
  COLOR_CYAN=""
  COLOR_YELLOW=""
  COLOR_GREEN=""
  COLOR_RED=""
  COLOR_DIM=""
fi

STEP_CURRENT=0
STEP_TOTAL=10

banner() {
  echo -e "${COLOR_CYAN}============================================================${COLOR_RESET}"
  echo -e "${COLOR_CYAN}BlackBox Build: linux-hardened + Debian rootfs${COLOR_RESET}"
  echo -e "${COLOR_CYAN}Kernel branch: ${Linux_hardened_branch} | Rootfs size: ${debian_rootfs_size}MB${COLOR_RESET}"
  echo -e "${COLOR_CYAN}============================================================${COLOR_RESET}"
}

section() {
  STEP_CURRENT=$((STEP_CURRENT + 1))
  echo -e "${COLOR_DIM}[Step ${STEP_CURRENT}/${STEP_TOTAL}]${COLOR_RESET} $*"
}

info() {
  echo -e "${COLOR_CYAN}[i]${COLOR_RESET} $*"
}

ok() {
  echo -e "${COLOR_GREEN}[+]${COLOR_RESET} $*"
}

warn() {
  echo -e "${COLOR_YELLOW}[!]${COLOR_RESET} $*"
}

err() {
  echo -e "${COLOR_RED}[x]${COLOR_RESET} $*" >&2
}

banner

# Install necessary depandency for build Kernel and RootFS
section "Install build dependencies"
sudo apt install build-essential llvm clang lld debootstrap qemu-user-static gcc-aarch64-linux-gnu atftpd nfs-kernel-server fdisk libcap-dev libgbm-dev pkg-config protobuf-compiler bc bison flex libssl-dev make libc6-dev libncurses5-dev crossbuild-essential-arm64 wget

# Clone source code from Linux-hardened
section "Clone and build linux-hardened kernel"
git clone --depth=1 https://github.com/anthraxx/linux-hardened -b $Linux_hardened_branch

info "Entering linux-hardened"
cd linux-hardened

# Fetch Microdroid Kernel config from Google

wget https://android.googlesource.com/kernel/common/+archive/refs/tags/android-15.0.0_r0.81/arch/arm64/configs.tar.gz && tar xvf configs.tar.gz microdroid_defconfig
cp microdroid_defconfig .config

# Apply Feature and Hardened config

export KBUILD_BUILD_USER="black"
export KBUILD_BUILD_HOST="black@QubesOS"

./scripts/config --set-str SERIAL_8250_RUNTIME_UARTS 4 \
-e CGROUPS \
-e CGROUP_CPUACCT \
-e CGROUP_DEBUG \
-e CGROUP_DEVICE \
-e CGROUP_DMEM \
-e CGROUP_FAVOR_DYNMODS \
-e CGROUP_FREEZER \
-e CGROUP_MISC \
-e CGROUP_PERF \
-e CGROUP_PIDS \
-e CGROUP_RDMA \
-e CGROUP_SCHED \
-e CGROUP_WRITEBACK \
-e DEVTMPFS \
-e VIRTIO_NET \
-e NETDEVICES \
-e VIRTIO_FS \
-e INIT_ON_FREE_DEFAULT_ON \
-e ZERO_CALL_USED_REGS

make LLVM=1 ARCH=arm64 olddefconfig

make LLVM=1 ARCH=arm64 -j$(nproc) Image

cp arch/arm64/boot/Image ../Image
info "Leaving linux-hardened"
cd ..

# Get started with RootFS
section "Create Debian rootfs image"
mkdir rootfs
dd if=/dev/zero of=debian.img bs=1M count=$debian_rootfs_size
sudo mkfs.ext4 debian.img
sudo mount debian.img rootfs/
sudo debootstrap --arch=arm64 trixie rootfs/

# Setup network
section "Configure network and journal limits"
echo "black" | sudo tee ./rootfs/etc/hostname
echo "127.0.0.1    black" | sudo tee -a ./rootfs/etc/hosts > /dev/null
cat <<EOF | sudo tee -a ./rootfs/etc/systemd/network/20-enp0s2.network > /dev/null
[Match]
Name=enp0s2

[Network]
Address=192.168.8.2/24
Gateway=192.168.8.1
DNS=1.1.1.1
EOF

sudo chroot ./rootfs /bin/bash -c "systemctl enable --now systemd-networkd"
sudo chroot ./rootfs /bin/bash -c "networkctl reload"
sudo chroot ./rootfs /bin/bash -c "networkctl reconfigure enp0s2"

# Limit log size to 512K
sudo mkdir -p ./rootfs/etc/systemd/journald.conf.d/
cat <<EOF | sudo tee ./rootfs/etc/systemd/journald.conf.d/limit-size.conf > /dev/null
[Journal]
SystemMaxUse=512K
RuntimeMaxUse=512K
EOF

# Setup proxy chain
section "Install proxy chain packages"
sudo chroot ./rootfs /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get update
sudo chroot ./rootfs /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    tor \
    i2pd \
    obfs4proxy \
    sudo \
    curl

wget https://github.com/MetaCubeX/mihomo/releases/download/v1.19.20/mihomo-linux-arm64-v1.19.20.deb

sudo cp mihomo-linux-arm64-v1.19.20.deb ./rootfs/
sudo chroot ./rootfs /usr/bin/dpkg -i /mihomo-linux-arm64-v1.19.20.deb
sudo chroot ./rootfs /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get install -f -y
sudo rm ./rootfs/mihomo-linux-arm64-v1.19.20.deb

# Setup services
section "Configure mihomo service"
cat <<EOF | sudo tee ./rootfs/etc/systemd/system/mihomo.service > /dev/null
[Unit]
Description=mihomo Daemon, Another Clash Kernel.
Documentation=https://wiki.metacubex.one
After=network.target nss-lookup.target network-online.target

[Service]
User=black
WorkingDirectory=/home/black/mihomo
Type=simple
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
ExecStart=/usr/bin/mihomo -d /home/black/mihomo
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

sudo chroot ./rootfs /bin/bash -c "systemctl daemon-reload"
sudo chroot ./rootfs /bin/bash -c "systemctl enable mihomo" # for test purpose

sudo chroot ./rootfs /bin/bash -c "systemctl disable mihomo"
sudo chroot ./rootfs /bin/bash -c "systemctl disable tor"
sudo chroot ./rootfs /bin/bash -c "systemctl disable i2pd"

# Copy Config files
section "Install configs and init wizard"
sudo cp torrc ./rootfs/etc/tor/
sudo cp i2pd.conf ./rootfs/etc/i2pd/


# Setup login-exec setup wizard
sudo cp init.sh ./rootfs/usr/local/sbin/
sudo chroot ./rootfs /bin/bash -c "chmod 755 /usr/local/sbin/init.sh"

cat <<EOF | sudo tee ./rootfs/etc/sudoers.d/blackbox > /dev/null
# Allow BlackBox init script to run without auth
black ALL=(root) NOPASSWD: /usr/local/sbin/init.sh, /usr/bin/touch /run/blackbox_mihomo_ran
EOF

sudo chmod 0440 ./rootfs/etc/sudoers.d/blackbox

# Setup user
section "Create user and initialize mihomo workspace"
sudo chroot ./rootfs /bin/bash -c "useradd -m -g sudo black"
echo "black:Rk8V1gm98vpqNPWXChu4UrDmzcser2aFnrKHd5Yek3hEHXnbPT0VwwSdlJ2hBhbTkRPeJFi1Xq089Eg4QbP7SclYhtsvgM9s65EypxaD50a5Ikrnx45iCh6JlNCpUpGp" | sudo chroot ./rootfs /usr/sbin/chpasswd
sudo mkdir -p ./rootfs/home/black/mihomo
sudo cp ./rootfs/etc/mihomo/config.yaml ./rootfs/home/black/mihomo/

# Post-usersetup: pre-download Clash Meta DB
section "Pre-download geo databases"
wget https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb
sudo cp geoip.metadb ./rootfs/home/black/mihomo
wget https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb
sudo cp country.mmdb ./rootfs/home/black/mihomo
wget https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb
sudo cp GeoLite2-ASN.mmdb ./rootfs/home/black/mihomo

cat <<'EOF' | sudo tee -a ./rootfs/home/black/.bashrc > /dev/null

# Auto-run BlackBox once per boot on ttyS0
if [[ -t 0 ]] && [[ "$(tty)" == "/dev/ttyS0" ]] && [[ ! -e /run/blackbox_mihomo_ran ]]; then
  sudo /usr/local/sbin/init.sh --lang zh
  sudo touch /run/blackbox_mihomo_ran
fi
EOF

sudo chroot ./rootfs chown black /home/black/.bashrc
sudo chroot ./rootfs chmod 644 /home/black/.bashrc
sudo chroot ./rootfs chsh -s /bin/bash black

# Setup Autologin
section "Setup serial autologin"
sudo mkdir -p ./rootfs/etc/systemd/system/serial-getty@ttyS0.service.d
cat <<EOF | sudo tee ./rootfs/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf > /dev/null
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin black --keep-baud 115200,57600,38400,9600 %I \$TERM
EOF

section "Finalize image"
sudo umount rootfs/
ok "Build script completed."
