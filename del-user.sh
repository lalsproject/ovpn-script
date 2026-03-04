#!/bin/bash

# CONFIG
EASYRSA_DIR="/root/openvpn-ca"
CCD_DIR="/etc/openvpn/ccd"
SERVER_CONF="/etc/openvpn/server.conf"
OPENVPN_DIR="/etc/openvpn"

if [ -z "$1" ]; then
    echo "Usage: $0 username"
    echo "Example: $0 mikrotik1"
    exit 1
fi

USERNAME=$1
CCD_FILE="$CCD_DIR/$USERNAME"

# Cek apakah user ada
if [ ! -f "$CCD_FILE" ] && [ ! -f "$EASYRSA_DIR/pki/issued/$USERNAME.crt" ]; then
    echo "❌ User '$USERNAME' not found."
    exit 1
fi

echo "======================================"
echo "Removing user: $USERNAME"
echo "======================================"

# -----------------------------------------------
# 1. Baca iroute dari file CCD sebelum dihapus
# -----------------------------------------------
ROUTES_TO_REMOVE=()
if [ -f "$CCD_FILE" ]; then
    echo ""
    echo "📄 CCD file found: $CCD_FILE"
    echo "Contents:"
    cat "$CCD_FILE"
    echo ""

    while IFS= read -r line; do
        if [[ "$line" == iroute* ]]; then
            # Ambil network dan mask dari baris iroute
            NETWORK=$(echo $line | awk '{print $2}')
            MASK=$(echo $line | awk '{print $3}')
            ROUTES_TO_REMOVE+=("$NETWORK $MASK")
        fi
    done < "$CCD_FILE"
fi

# -----------------------------------------------
# 2. Hapus route dari server.conf
# -----------------------------------------------
if [ ${#ROUTES_TO_REMOVE[@]} -gt 0 ]; then
    echo "🗑  Removing routes from server.conf:"
    for ROUTE in "${ROUTES_TO_REMOVE[@]}"; do
        NETWORK=$(echo $ROUTE | awk '{print $1}')
        MASK=$(echo $ROUTE | awk '{print $2}')
        ROUTE_ENTRY="route $NETWORK $MASK"

        if grep -q "$ROUTE_ENTRY" "$SERVER_CONF"; then
            # Hapus baris route dari server.conf
            sed -i "/^$ROUTE_ENTRY$/d" "$SERVER_CONF"
            echo "  ✅ Removed: $ROUTE_ENTRY"
        else
            echo "  ⚠  Not found in server.conf: $ROUTE_ENTRY"
        fi
    done
else
    echo "⚠  No iroute entries found in CCD, skipping server.conf cleanup."
fi

# -----------------------------------------------
# 3. Hapus file CCD
# -----------------------------------------------
if [ -f "$CCD_FILE" ]; then
    rm -f "$CCD_FILE"
    echo ""
    echo "🗑  CCD file removed: $CCD_FILE"
fi

# -----------------------------------------------
# 4. Revoke certificate via EasyRSA
# -----------------------------------------------
echo ""
echo "🔐 Revoking certificate for $USERNAME..."
cd $EASYRSA_DIR || exit 1

./easyrsa revoke $USERNAME <<EOF
yes
EOF

# Update CRL
./easyrsa gen-crl
cp pki/crl.pem $OPENVPN_DIR/crl.pem
echo "✅ CRL updated: $OPENVPN_DIR/crl.pem"

# -----------------------------------------------
# 5. Hapus file cert & key dari /etc/openvpn
# -----------------------------------------------
echo ""
echo "🗑  Removing cert/key files from $OPENVPN_DIR..."
for EXT in crt key; do
    FILE="$OPENVPN_DIR/$USERNAME.$EXT"
    if [ -f "$FILE" ]; then
        rm -f "$FILE"
        echo "  ✅ Removed: $FILE"
    else
        echo "  ⚠  Not found: $FILE"
    fi
done

# -----------------------------------------------
# 6. Restart OpenVPN
# -----------------------------------------------
echo ""
echo "🔄 Restarting OpenVPN..."
systemctl restart openvpn@server
sleep 2
STATUS=$(systemctl is-active openvpn@server)
if [ "$STATUS" = "active" ]; then
    echo "✅ OpenVPN restarted successfully."
else
    echo "❌ OpenVPN failed to restart. Check: journalctl -u openvpn@server"
fi

# -----------------------------------------------
# Summary
# -----------------------------------------------
echo ""
echo "======================================"
echo "✅ User Removed : $USERNAME"
if [ ${#ROUTES_TO_REMOVE[@]} -gt 0 ]; then
echo "🗑  Routes Removed:"
for ROUTE in "${ROUTES_TO_REMOVE[@]}"; do
echo "   - $ROUTE"
done
fi
echo "🔐 Certificate  : Revoked"
echo "📄 CRL          : Updated"
echo "======================================"
