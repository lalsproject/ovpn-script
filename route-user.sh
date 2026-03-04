#!/bin/bash

# CONFIG
CCD_DIR="/etc/openvpn/ccd"
SERVER_CONF="/etc/openvpn/server.conf"

# Warna
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# -----------------------------------------------
# Usage
# -----------------------------------------------
usage() {
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  $0 add    <username> <subnet1> [subnet2] ..."
    echo "  $0 remove <username> <subnet1> [subnet2] ..."
    echo "  $0 list   <username>"
    echo ""
    echo -e "${BOLD}Example:${NC}"
    echo "  $0 add    cli2 192.168.10.0/24 10.10.0.0/16"
    echo "  $0 remove cli2 192.168.10.0/24"
    echo "  $0 list   cli2"
    echo ""
    exit 1
}

# -----------------------------------------------
# Validasi argumen
# -----------------------------------------------
if [ -z "$1" ] || [ -z "$2" ]; then
    usage
fi

ACTION=$1
USERNAME=$2
shift 2
SUBNETS=("$@")
CCD_FILE="$CCD_DIR/$USERNAME"

# Cek user ada di CCD
if [ ! -f "$CCD_FILE" ] && [ "$ACTION" != "list" ]; then
    echo -e "${RED}❌ User '$USERNAME' tidak ditemukan di CCD.${NC}"
    echo "User yang tersedia:"
    ls $CCD_DIR 2>/dev/null | sed 's/^/  - /'
    exit 1
fi

# -----------------------------------------------
# Fungsi konversi CIDR ke subnet mask
# -----------------------------------------------
cidr_to_mask() {
    case $1 in
        8)  echo "255.0.0.0" ;;
        16) echo "255.255.0.0" ;;
        24) echo "255.255.255.0" ;;
        32) echo "255.255.255.255" ;;
        *)  echo "255.255.255.0" ;;
    esac
}

# -----------------------------------------------
# ACTION: list
# -----------------------------------------------
action_list() {
    echo ""
    echo -e "${BOLD}======================================${NC}"
    echo -e "${BOLD} Routes for user: $USERNAME${NC}"
    echo -e "${BOLD}======================================${NC}"

    if [ ! -f "$CCD_FILE" ]; then
        echo -e "${YELLOW}⚠  User '$USERNAME' tidak ditemukan di CCD.${NC}"
        exit 1
    fi

    FOUND=false
    while IFS= read -r line; do
        if [[ "$line" == iroute* ]]; then
            NETWORK=$(echo $line | awk '{print $2}')
            MASK=$(echo $line | awk '{print $3}')
            echo -e "  ${CYAN}🔀 $NETWORK / $MASK${NC}"
            FOUND=true
        fi
    done < "$CCD_FILE"

    if ! $FOUND; then
        echo -e "${YELLOW}  Tidak ada iroute untuk user ini.${NC}"
    fi

    echo -e "${BOLD}======================================${NC}"
    echo ""
}

# -----------------------------------------------
# ACTION: add
# -----------------------------------------------
action_add() {
    if [ ${#SUBNETS[@]} -eq 0 ]; then
        echo -e "${RED}❌ Subnet tidak boleh kosong.${NC}"
        usage
    fi

    echo ""
    echo -e "${BOLD}======================================${NC}"
    echo -e "${BOLD} Add Routes - User: $USERNAME${NC}"
    echo -e "${BOLD}======================================${NC}"

    ADDED=()
    SKIPPED=()

    for SUBNET in "${SUBNETS[@]}"; do
        NETWORK=$(echo $SUBNET | cut -d'/' -f1)
        PREFIX=$(echo $SUBNET | cut -d'/' -f2)
        MASK=$(cidr_to_mask $PREFIX)
        IROUTE_ENTRY="iroute $NETWORK $MASK"
        ROUTE_ENTRY="route $NETWORK $MASK"

        # Cek duplikat di CCD
        if grep -q "^$IROUTE_ENTRY$" "$CCD_FILE" 2>/dev/null; then
            echo -e "  ${YELLOW}⚠  Sudah ada: $NETWORK / $MASK${NC}"
            SKIPPED+=("$NETWORK $MASK")
            continue
        fi

        # Tambah iroute ke CCD
        echo "$IROUTE_ENTRY" >> "$CCD_FILE"
        echo -e "  ${GREEN}✅ iroute ditambahkan: $NETWORK / $MASK${NC}"
        ADDED+=("$NETWORK $MASK")

        # Tambah route ke server.conf jika belum ada
        if ! grep -q "^$ROUTE_ENTRY$" "$SERVER_CONF"; then
            echo "$ROUTE_ENTRY" >> "$SERVER_CONF"
            echo -e "  ${GREEN}✅ route ditambahkan ke server.conf: $NETWORK / $MASK${NC}"
        else
            echo -e "  ${CYAN}ℹ  Route sudah ada di server.conf: $NETWORK / $MASK${NC}"
        fi
    done

    echo ""
    echo -e "${BOLD}--------------------------------------${NC}"
    echo -e "${BOLD} CCD $USERNAME saat ini:${NC}"
    cat "$CCD_FILE"
    echo -e "${BOLD}--------------------------------------${NC}"

    if [ ${#ADDED[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}⚠  Restart OpenVPN untuk menerapkan perubahan:${NC}"
        echo "   systemctl restart openvpn@server"
    fi
    echo ""
}

# -----------------------------------------------
# ACTION: remove
# -----------------------------------------------
action_remove() {
    if [ ${#SUBNETS[@]} -eq 0 ]; then
        echo -e "${RED}❌ Subnet tidak boleh kosong.${NC}"
        usage
    fi

    echo ""
    echo -e "${BOLD}======================================${NC}"
    echo -e "${BOLD} Remove Routes - User: $USERNAME${NC}"
    echo -e "${BOLD}======================================${NC}"

    REMOVED=()
    NOT_FOUND=()

    for SUBNET in "${SUBNETS[@]}"; do
        NETWORK=$(echo $SUBNET | cut -d'/' -f1)
        PREFIX=$(echo $SUBNET | cut -d'/' -f2)
        MASK=$(cidr_to_mask $PREFIX)
        IROUTE_ENTRY="iroute $NETWORK $MASK"
        ROUTE_ENTRY="route $NETWORK $MASK"

        # Hapus iroute dari CCD
        if grep -q "^$IROUTE_ENTRY$" "$CCD_FILE" 2>/dev/null; then
            sed -i "/^$IROUTE_ENTRY$/d" "$CCD_FILE"
            echo -e "  ${GREEN}✅ iroute dihapus dari CCD: $NETWORK / $MASK${NC}"
            REMOVED+=("$NETWORK $MASK")
        else
            echo -e "  ${YELLOW}⚠  Tidak ditemukan di CCD: $NETWORK / $MASK${NC}"
            NOT_FOUND+=("$NETWORK $MASK")
            continue
        fi

        # Cek apakah subnet masih dipakai user lain
        STILL_USED=false
        for OTHER_CCD in "$CCD_DIR"/*; do
            OTHER_USER=$(basename "$OTHER_CCD")
            if [ "$OTHER_USER" = "$USERNAME" ]; then
                continue
            fi
            if grep -q "^$IROUTE_ENTRY$" "$OTHER_CCD" 2>/dev/null; then
                STILL_USED=true
                echo -e "  ${CYAN}ℹ  Route masih dipakai oleh: $OTHER_USER, tidak dihapus dari server.conf${NC}"
                break
            fi
        done

        # Hapus dari server.conf jika tidak dipakai user lain
        if ! $STILL_USED; then
            if grep -q "^$ROUTE_ENTRY$" "$SERVER_CONF"; then
                sed -i "/^$ROUTE_ENTRY$/d" "$SERVER_CONF"
                echo -e "  ${GREEN}✅ route dihapus dari server.conf: $NETWORK / $MASK${NC}"
            fi
        fi
    done

    echo ""
    echo -e "${BOLD}--------------------------------------${NC}"
    echo -e "${BOLD} CCD $USERNAME saat ini:${NC}"
    if [ -s "$CCD_FILE" ]; then
        cat "$CCD_FILE"
    else
        echo -e "  ${YELLOW}(kosong)${NC}"
    fi
    echo -e "${BOLD}--------------------------------------${NC}"

    if [ ${#REMOVED[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}⚠  Restart OpenVPN untuk menerapkan perubahan:${NC}"
        echo "   systemctl restart openvpn@server"
    fi
    echo ""
}

# -----------------------------------------------
# Router ke action
# -----------------------------------------------
case $ACTION in
    add)    action_add ;;
    remove) action_remove ;;
    list)   action_list ;;
    *)
        echo -e "${RED}❌ Action tidak dikenal: $ACTION${NC}"
        usage
        ;;
esac
