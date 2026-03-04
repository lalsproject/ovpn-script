#!/bin/bash

# ================================================
# OpenVPN Auto Install Script
# Target OS : Ubuntu 20.04 LTS (Focal Fossa)
# OpenVPN   : 2.4.x
# EasyRSA   : 3.0.x
# TUN IP    : 10.252.0.1/24
# Proto     : TCP 1194
# ================================================

# Warna
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# -----------------------------------------------
# CONFIG — sesuaikan jika perlu
# -----------------------------------------------
VPN_NETWORK="10.252.0.0"
VPN_MASK="255.255.255.0"
VPN_SERVER_IP="10.252.0.1"
VPN_PORT="1194"
VPN_PROTO="tcp"
VPN_DEV="tun"
VPN_CIPHER="AES-256-CBC"
VPN_AUTH="SHA1"
VPN_KEEPALIVE="10 60"
VPN_VERB="3"

EASYRSA_DIR="/root/openvpn-ca"
OPENVPN_DIR="/etc/openvpn"
CCD_DIR="/etc/openvpn/ccd"
SERVER_CONF="/etc/openvpn/server.conf"
LOG_DIR="/var/log/openvpn"

CA_CN="OpenVPN-CA"
SERVER_CN="server"
KEY_SIZE="2048"
CA_EXPIRE="3650"
CERT_EXPIRE="3650"

# Deteksi interface internet otomatis
WAN_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -1)

# -----------------------------------------------
# Cek root
# -----------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Script harus dijalankan sebagai root.${NC}"
    exit 1
fi

# -----------------------------------------------
# Cek OS
# -----------------------------------------------
if [ ! -f /etc/os-release ]; then
    echo -e "${RED}❌ Tidak dapat mendeteksi OS.${NC}"
    exit 1
fi

source /etc/os-release
if [[ "$ID" != "ubuntu" ]] || [[ "$VERSION_ID" != "20.04" ]]; then
    echo -e "${YELLOW}⚠  Script ini dioptimalkan untuk Ubuntu 20.04.${NC}"
    echo -ne "  Lanjutkan tetap? [y/N]: "
    read CONT
    [[ ! "$CONT" =~ ^[Yy]$ ]] && exit 1
fi

# -----------------------------------------------
# Header
# -----------------------------------------------
clear
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║        OpenVPN Auto Installer                ║"
echo "  ║        Ubuntu 20.04 LTS - TCP 1194           ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  WAN Interface : ${CYAN}$WAN_IFACE${NC}"
echo -e "  VPN Network   : ${CYAN}$VPN_NETWORK/$VPN_MASK${NC}"
echo -e "  VPN Server IP : ${CYAN}$VPN_SERVER_IP${NC}"
echo -e "  Protocol      : ${CYAN}$VPN_PROTO:$VPN_PORT${NC}"
echo ""
echo -ne "  Mulai instalasi? [y/N]: "
read START
[[ ! "$START" =~ ^[Yy]$ ]] && exit 0

echo ""

# -----------------------------------------------
# STEP 1: Install packages
# -----------------------------------------------
echo -e "${BOLD}[1/7] Install packages...${NC}"
apt update -qq
apt install -y openvpn easy-rsa iptables-persistent bc 2>&1 | grep -E "^(Setting up|Get:|Err:)"
echo -e "${GREEN}  ✅ Packages installed.${NC}"

# -----------------------------------------------
# STEP 2: Setup EasyRSA
# -----------------------------------------------
echo -e "${BOLD}[2/7] Setup EasyRSA & PKI...${NC}"

mkdir -p $EASYRSA_DIR
cd $EASYRSA_DIR

# Buat symlink EasyRSA
ln -sf /usr/share/easy-rsa/easyrsa $EASYRSA_DIR/easyrsa
ln -sf /usr/share/easy-rsa/x509-types $EASYRSA_DIR/x509-types
cp /usr/share/easy-rsa/openssl-easyrsa.cnf $EASYRSA_DIR/ 2>/dev/null || true

# Buat file vars
cat > $EASYRSA_DIR/vars <<EOF
set_var EASYRSA_ALGO       rsa
set_var EASYRSA_KEY_SIZE   $KEY_SIZE
set_var EASYRSA_CA_EXPIRE  $CA_EXPIRE
set_var EASYRSA_CERT_EXPIRE $CERT_EXPIRE
set_var EASYRSA_DN         "cn_only"
set_var EASYRSA_REQ_CN     "$CA_CN"
EOF

# Init PKI
./easyrsa init-pki

# Build CA (nopass)
./easyrsa build-ca nopass <<EOF
$CA_CN
EOF

# Generate DH
echo -e "  Generating DH parameters (ini butuh beberapa menit)..."
./easyrsa gen-dh

# Generate server cert
./easyrsa gen-req $SERVER_CN nopass <<EOF
$SERVER_CN
EOF
./easyrsa sign-req server $SERVER_CN <<EOF
yes
EOF

# Generate CRL
./easyrsa gen-crl

echo -e "${GREEN}  ✅ PKI & certificates ready.${NC}"

# -----------------------------------------------
# STEP 3: Copy certs ke /etc/openvpn
# -----------------------------------------------
echo -e "${BOLD}[3/7] Copy certificates...${NC}"

cp $EASYRSA_DIR/pki/ca.crt          $OPENVPN_DIR/
cp $EASYRSA_DIR/pki/issued/$SERVER_CN.crt  $OPENVPN_DIR/server.crt
cp $EASYRSA_DIR/pki/private/$SERVER_CN.key $OPENVPN_DIR/server.key
cp $EASYRSA_DIR/pki/dh.pem          $OPENVPN_DIR/
cp $EASYRSA_DIR/pki/crl.pem         $OPENVPN_DIR/

chmod 600 $OPENVPN_DIR/server.key
echo -e "${GREEN}  ✅ Certificates copied.${NC}"

# -----------------------------------------------
# STEP 4: Buat server.conf
# -----------------------------------------------
echo -e "${BOLD}[4/7] Generate server.conf...${NC}"

mkdir -p $CCD_DIR
mkdir -p $LOG_DIR

cat > $SERVER_CONF <<EOF
port $VPN_PORT
proto $VPN_PROTO
dev $VPN_DEV
topology subnet

ca ca.crt
cert server.crt
key server.key
dh dh.pem
crl-verify crl.pem

server $VPN_NETWORK $VPN_MASK

keepalive $VPN_KEEPALIVE
persist-key
persist-tun

cipher $VPN_CIPHER
auth $VPN_AUTH

user nobody
group nogroup

verb $VPN_VERB

push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

client-config-dir $CCD_DIR
client-to-client
status $LOG_DIR/status.log 10
log-append $LOG_DIR/openvpn.log
EOF

echo -e "${GREEN}  ✅ server.conf created.${NC}"

# -----------------------------------------------
# STEP 5: IP Forwarding
# -----------------------------------------------
echo -e "${BOLD}[5/7] Enable IP Forwarding...${NC}"

# Aktifkan sysctl
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p -q

echo -e "${GREEN}  ✅ IP forwarding enabled.${NC}"

# -----------------------------------------------
# STEP 6: iptables rules
# -----------------------------------------------
echo -e "${BOLD}[6/7] Setup iptables...${NC}"

# Flush rules lama terkait VPN (hindari duplikat)
iptables -t nat -D POSTROUTING -s $VPN_NETWORK/$VPN_MASK -o $WAN_IFACE -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -i tun0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -o tun0 -j ACCEPT 2>/dev/null || true

# Tambah rules
iptables -t nat -A POSTROUTING -s $VPN_NETWORK/$VPN_MASK -o $WAN_IFACE -j MASQUERADE
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A FORWARD -o tun0 -j ACCEPT

# Simpan iptables permanen
netfilter-persistent save

echo -e "${GREEN}  ✅ iptables rules applied & saved.${NC}"

# -----------------------------------------------
# STEP 7: Enable & Start OpenVPN
# -----------------------------------------------
echo -e "${BOLD}[7/7] Start OpenVPN service...${NC}"

systemctl enable openvpn@server
systemctl restart openvpn@server
sleep 3

STATUS=$(systemctl is-active openvpn@server)
if [ "$STATUS" = "active" ]; then
    echo -e "${GREEN}  ✅ OpenVPN is running.${NC}"
else
    echo -e "${RED}  ❌ OpenVPN gagal start. Cek log:${NC}"
    echo "     journalctl -u openvpn@server --no-pager | tail -20"
fi

# -----------------------------------------------
# Summary
# -----------------------------------------------
echo ""
echo -e "${BOLD}${CYAN}======================================================${NC}"
echo -e "${BOLD}  ✅ Instalasi Selesai!${NC}"
echo -e "${BOLD}${CYAN}======================================================${NC}"
echo ""
echo -e "  OS            : $PRETTY_NAME"
echo -e "  OpenVPN       : $(openvpn --version 2>&1 | head -1 | awk '{print $2}')"
echo -e "  EasyRSA       : $(./easyrsa --version 2>/dev/null | grep 'EasyRSA' | awk '{print $2}')"
echo -e "  WAN Interface : $WAN_IFACE"
echo -e "  VPN Network   : $VPN_NETWORK/$VPN_MASK"
echo -e "  VPN Server IP : $VPN_SERVER_IP"
echo -e "  Protocol      : $VPN_PROTO:$VPN_PORT"
echo -e "  CCD Dir       : $CCD_DIR"
echo -e "  EasyRSA Dir   : $EASYRSA_DIR"
echo -e "  Log Dir       : $LOG_DIR"
echo -e "  server.conf   : $SERVER_CONF"
echo ""
echo -e "${BOLD}  Langkah selanjutnya:${NC}"
echo -e "  1. Tambah user  : bash add-user.sh <username> <subnet>"
echo -e "  2. Lihat user   : bash show-user.sh"
echo -e "  3. Kelola menu  : bash ovpn-menu.sh"
echo ""
echo -e "${BOLD}${CYAN}======================================================${NC}"
echo ""
