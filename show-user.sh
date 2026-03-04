#!/bin/bash

# CONFIG
CCD_DIR="/etc/openvpn/ccd"
STATUS_FILE=$(grep -i "^status" /etc/openvpn/server.conf | awk '{print $2}')

# Warna
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# -----------------------------------------------
# Validasi status file
# -----------------------------------------------
if [ -z "$STATUS_FILE" ] || [ ! -f "$STATUS_FILE" ]; then
    echo -e "${RED}❌ Status file tidak ditemukan.${NC}"
    echo "Pastikan di server.conf ada baris:"
    echo "  status /var/log/openvpn/status.log 10"
    exit 1
fi

# Fungsi konversi bytes ke human readable
human_bytes() {
    local BYTES=$1
    if [ "$BYTES" -ge 1073741824 ]; then
        echo "$(echo "scale=2; $BYTES/1073741824" | bc) GB"
    elif [ "$BYTES" -ge 1048576 ]; then
        echo "$(echo "scale=2; $BYTES/1048576" | bc) MB"
    elif [ "$BYTES" -ge 1024 ]; then
        echo "$(echo "scale=2; $BYTES/1024" | bc) KB"
    else
        echo "${BYTES} B"
    fi
}

echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}   OpenVPN Active Users - $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${BOLD}======================================================${NC}"

# -----------------------------------------------
# Parse CLIENT LIST section
# Format: CN,RealIP:Port,BytesRX,BytesTX,ConnectedSince
# -----------------------------------------------
IN_CLIENT_SECTION=false
ACTIVE_USERS=()

while IFS= read -r line; do
    # Masuk section CLIENT LIST
    if [[ "$line" == "OpenVPN CLIENT LIST" ]]; then
        IN_CLIENT_SECTION=true
        continue
    fi

    # Keluar saat masuk section ROUTING TABLE
    if [[ "$line" == "ROUTING TABLE" ]]; then
        IN_CLIENT_SECTION=false
        continue
    fi

    # Skip baris header dan Updated
    if [[ "$line" == Updated,* ]] || [[ "$line" == "Common Name,Real Address"* ]]; then
        continue
    fi

    # Parse baris client
    if $IN_CLIENT_SECTION && [ -n "$line" ]; then
        # Format: CN,RealIP:Port,BytesRX,BytesTX,ConnectedSince (date bisa pakai koma)
        CN=$(echo "$line" | cut -d',' -f1)
        REAL_IP=$(echo "$line" | cut -d',' -f2)
        BYTES_RX=$(echo "$line" | cut -d',' -f3)
        BYTES_TX=$(echo "$line" | cut -d',' -f4)
        CONNECTED=$(echo "$line" | cut -d',' -f5-)

        ACTIVE_USERS+=("$CN|$REAL_IP|$BYTES_RX|$BYTES_TX|$CONNECTED")
    fi
done < "$STATUS_FILE"

# -----------------------------------------------
# Ambil VPN IP dari ROUTING TABLE per CN
# -----------------------------------------------
get_vpn_ip() {
    local TARGET_CN=$1
    grep "^10\." "$STATUS_FILE" | while IFS=',' read -r vaddr cn raddr lref; do
        if [ "$cn" = "$TARGET_CN" ]; then
            echo "$vaddr"
            break
        fi
    done
}

TOTAL=${#ACTIVE_USERS[@]}

if [ $TOTAL -eq 0 ]; then
    echo -e "${YELLOW}⚠  Tidak ada user yang sedang terkoneksi.${NC}"
else
    echo -e "${GREEN}✅ Total user aktif: $TOTAL${NC}"
    echo ""

    for USER_DATA in "${ACTIVE_USERS[@]}"; do
        CN=$(echo "$USER_DATA" | cut -d'|' -f1)
        REAL_IP=$(echo "$USER_DATA" | cut -d'|' -f2)
        BYTES_RX=$(echo "$USER_DATA" | cut -d'|' -f3)
        BYTES_TX=$(echo "$USER_DATA" | cut -d'|' -f4)
        CONNECTED=$(echo "$USER_DATA" | cut -d'|' -f5)

        VPN_IP=$(get_vpn_ip "$CN")
        RX_HR=$(human_bytes $BYTES_RX)
        TX_HR=$(human_bytes $BYTES_TX)

        # Ambil iroute dari CCD
        IROUTES=""
        CCD_FILE="$CCD_DIR/$CN"
        if [ -f "$CCD_FILE" ]; then
            while IFS= read -r cline; do
                if [[ "$cline" == iroute* ]]; then
                    NETWORK=$(echo $cline | awk '{print $2}')
                    MASK=$(echo $cline | awk '{print $3}')
                    IROUTES+="      🔀 $NETWORK / $MASK\n"
                fi
            done < "$CCD_FILE"
        fi

        echo -e "${CYAN}┌─ User     : ${BOLD}$CN${NC}"
        echo -e "${CYAN}│${NC}  Real IP   : $REAL_IP"
        echo -e "${CYAN}│${NC}  VPN IP    : ${VPN_IP:-unknown}"
        echo -e "${CYAN}│${NC}  Connected : $CONNECTED"
        echo -e "${CYAN}│${NC}  RX / TX   : $RX_HR / $TX_HR"
        if [ -n "$IROUTES" ]; then
            echo -e "${CYAN}│${NC}  Subnets   :"
            echo -ne "$IROUTES"
        else
            echo -e "${CYAN}│${NC}  Subnets   : -"
        fi
        echo -e "${CYAN}└──────────────────────────────────────${NC}"
        echo ""
    done
fi

# -----------------------------------------------
# Semua user terdaftar di CCD + status online/offline
# -----------------------------------------------
echo -e "${BOLD}------------------------------------------------------${NC}"
echo -e "${BOLD} Registered Users (CCD)${NC}"
echo -e "${BOLD}------------------------------------------------------${NC}"

CCD_USERS=$(ls $CCD_DIR 2>/dev/null)
if [ -z "$CCD_USERS" ]; then
    echo -e "${YELLOW}⚠  Tidak ada user terdaftar di CCD.${NC}"
else
    for CCD_USER in $CCD_USERS; do
        IS_ACTIVE=false
        for USER_DATA in "${ACTIVE_USERS[@]}"; do
            CN=$(echo "$USER_DATA" | cut -d'|' -f1)
            if [ "$CN" = "$CCD_USER" ]; then
                IS_ACTIVE=true
                break
            fi
        done

        if $IS_ACTIVE; then
            STATUS="${GREEN}● ONLINE ${NC}"
        else
            STATUS="${RED}○ OFFLINE${NC}"
        fi

        echo -e "  $STATUS  $CCD_USER"

        while IFS= read -r line; do
            if [[ "$line" == iroute* ]]; then
                NETWORK=$(echo $line | awk '{print $2}')
                MASK=$(echo $line | awk '{print $3}')
                echo -e "             └─ $NETWORK / $MASK"
            fi
        done < "$CCD_DIR/$CCD_USER"
    done
fi

echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "Status file : $STATUS_FILE"
echo -e "Last update : $(stat -c '%y' $STATUS_FILE | cut -d'.' -f1)"
echo -e "${BOLD}======================================================${NC}"
echo ""