#!/bin/bash

# CONFIG
EASYRSA_DIR="/root/openvpn-ca"
CCD_DIR="/etc/openvpn/ccd"
SERVER_CONF="/etc/openvpn/server.conf"

if [ -z "$1" ]; then
    echo "Usage: $0 username [subnet1] [subnet2] ..."
    echo "Example: $0 mikrotik1 192.168.183.0/24 192.168.10.0/24"
    exit 1
fi

USERNAME=$1
shift
SUBNETS=("$@")

cd $EASYRSA_DIR || exit 1

echo "Generating certificate for $USERNAME..."

./easyrsa gen-req $USERNAME nopass
./easyrsa sign-req client $USERNAME <<EOF
yes
EOF

# Buat direktori CCD jika belum ada
mkdir -p $CCD_DIR

# Kosongkan / buat file CCD baru
> $CCD_DIR/$USERNAME

# Fungsi konversi CIDR prefix ke subnet mask
cidr_to_mask() {
    case $1 in
        8)  echo "255.0.0.0" ;;
        16) echo "255.255.0.0" ;;
        24) echo "255.255.255.0" ;;
        32) echo "255.255.255.255" ;;
        *)  echo "255.255.255.0" ;;
    esac
}

# Proses setiap subnet
IROUTE_LIST=()
if [ ${#SUBNETS[@]} -gt 0 ]; then
    for SUBNET in "${SUBNETS[@]}"; do
        NETWORK=$(echo $SUBNET | cut -d'/' -f1)
        PREFIX=$(echo $SUBNET | cut -d'/' -f2)
        MASK=$(cidr_to_mask $PREFIX)

        # Tulis iroute ke file CCD
        echo "iroute $NETWORK $MASK" >> $CCD_DIR/$USERNAME
        IROUTE_LIST+=("$NETWORK $MASK")
        echo "Adding iroute $NETWORK $MASK for $USERNAME"

        # Tambahkan route di server.conf jika belum ada
        ROUTE_ENTRY="route $NETWORK $MASK"
        if ! grep -q "$ROUTE_ENTRY" $SERVER_CONF; then
            echo "$ROUTE_ENTRY" >> $SERVER_CONF
            echo "Route $NETWORK $MASK added to server.conf"
        else
            echo "Route $NETWORK $MASK already exists in server.conf"
        fi
    done

    echo ""
    echo "⚠  Restart OpenVPN to apply new routes:"
    echo "   systemctl restart openvpn@server"
fi

# Copy file ke /etc/openvpn
cp pki/issued/$USERNAME.crt /etc/openvpn/
cp pki/private/$USERNAME.key /etc/openvpn/

echo ""
echo "======================================"
echo "User Created : $USERNAME"
if [ ${#IROUTE_LIST[@]} -gt 0 ]; then
echo "Subnets      :"
for ROUTE in "${IROUTE_LIST[@]}"; do
echo "  - $ROUTE"
done
fi
echo "CCD File     : $CCD_DIR/$USERNAME"
echo "--------------------------------------"
echo "CCD Contents :"
cat $CCD_DIR/$USERNAME
echo "--------------------------------------"
echo "Files ready in /etc/openvpn/:"
echo "  - ca.crt"
echo "  - $USERNAME.crt"
echo "  - $USERNAME.key"
echo "======================================"
