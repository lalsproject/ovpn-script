#!/bin/bash

# CONFIG
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADD_USER="$SCRIPT_DIR/add-user.sh"
DEL_USER="$SCRIPT_DIR/del-user.sh"
SHOW_USER="$SCRIPT_DIR/show-user.sh"
ROUTE_USER="$SCRIPT_DIR/route-user.sh"

# Warna
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# -----------------------------------------------
# Cek script dependencies
# -----------------------------------------------
check_scripts() {
    MISSING=false
    for SCRIPT in "$ADD_USER" "$DEL_USER" "$SHOW_USER" "$ROUTE_USER"; do
        if [ ! -f "$SCRIPT" ]; then
            echo -e "${RED}❌ Script tidak ditemukan: $SCRIPT${NC}"
            MISSING=true
        else
            chmod +x "$SCRIPT"
        fi
    done
    if $MISSING; then
        echo ""
        echo "Pastikan semua script berada dalam direktori yang sama:"
        echo "  add-user.sh, del-user.sh, show-user.sh, route-user.sh"
        echo ""
        exit 1
    fi
}

# -----------------------------------------------
# Header
# -----------------------------------------------
print_header() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║         OpenVPN Management Console           ║"
    echo "  ║                ACS-2026                      ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# -----------------------------------------------
# Main Menu
# -----------------------------------------------
main_menu() {
    print_header
    echo -e "${BOLD}  Pilih menu:${NC}"
    echo ""
    echo -e "  ${GREEN}[1]${NC} 👤  Tambah User"
    echo -e "  ${RED}[2]${NC} 🗑   Hapus User"
    echo -e "  ${CYAN}[3]${NC} 👁   Lihat User Aktif"
    echo -e "  ${YELLOW}[4]${NC} 🔀  Kelola Route User"
    echo ""
    echo -e "  ${RED}[0]${NC} 🚪  Keluar"
    echo ""
    echo -e "${BOLD}  ══════════════════════════════════════════════${NC}"
    echo -ne "  Pilihan: "
    read CHOICE

    case $CHOICE in
        1) menu_add_user ;;
        2) menu_del_user ;;
        3) menu_show_user ;;
        4) menu_route_user ;;
        0) echo -e "\n${GREEN}  Sampai jumpa!${NC}\n"; exit 0 ;;
        *) echo -e "\n${RED}  ❌ Pilihan tidak valid.${NC}"; sleep 1; main_menu ;;
    esac
}

# -----------------------------------------------
# Menu: Tambah User
# -----------------------------------------------
menu_add_user() {
    print_header
    echo -e "${BOLD}${GREEN}  ╔══════════════════════════════════════════════╗"
    echo -e "  ║              Tambah User Baru                ║"
    echo -e "  ╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -ne "  Username      : "
    read USERNAME

    if [ -z "$USERNAME" ]; then
        echo -e "${RED}  ❌ Username tidak boleh kosong.${NC}"
        sleep 1; menu_add_user; return
    fi

    echo -ne "  Subnet LAN    : (kosongkan jika tidak ada, pisah spasi misal: 192.168.1.0/24 10.0.0.0/8)"
    echo ""
    echo -ne "  > "
    read SUBNETS_INPUT

    echo ""
    echo -e "${BOLD}  ══════════════════════════════════════════════${NC}"
    echo -e "  Username : ${CYAN}$USERNAME${NC}"
    echo -e "  Subnets  : ${CYAN}${SUBNETS_INPUT:-"-"}${NC}"
    echo -e "${BOLD}  ══════════════════════════════════════════════${NC}"
    echo -ne "\n  Konfirmasi? [y/N]: "
    read CONFIRM

    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo ""
        bash "$ADD_USER" "$USERNAME" $SUBNETS_INPUT
    else
        echo -e "\n${YELLOW}  ⚠  Dibatalkan.${NC}"
    fi

    back_to_menu
}

# -----------------------------------------------
# Menu: Hapus User
# -----------------------------------------------
menu_del_user() {
    print_header
    echo -e "${BOLD}${RED}  ╔══════════════════════════════════════════════╗"
    echo -e "  ║                Hapus User                    ║"
    echo -e "  ╚══════════════════════════════════════════════╝${NC}"
    echo ""

    # Tampilkan daftar user
    echo -e "  ${BOLD}User terdaftar:${NC}"
    ls /etc/openvpn/ccd 2>/dev/null | sed 's/^/    - /' || echo "    (tidak ada)"
    echo ""

    echo -ne "  Username yang akan dihapus: "
    read USERNAME

    if [ -z "$USERNAME" ]; then
        echo -e "${RED}  ❌ Username tidak boleh kosong.${NC}"
        sleep 1; menu_del_user; return
    fi

    echo ""
    echo -e "${RED}${BOLD}  ⚠  PERINGATAN: Tindakan ini tidak dapat dibatalkan!${NC}"
    echo -e "  User ${BOLD}$USERNAME${NC} akan di-revoke dan dihapus permanen."
    echo -ne "\n  Ketik '${BOLD}yes${NC}' untuk konfirmasi: "
    read CONFIRM

    if [ "$CONFIRM" = "yes" ]; then
        echo ""
        bash "$DEL_USER" "$USERNAME"
    else
        echo -e "\n${YELLOW}  ⚠  Dibatalkan.${NC}"
    fi

    back_to_menu
}

# -----------------------------------------------
# Menu: Lihat User Aktif
# -----------------------------------------------
menu_show_user() {
    print_header
    bash "$SHOW_USER"
    back_to_menu
}

# -----------------------------------------------
# Menu: Kelola Route User
# -----------------------------------------------
menu_route_user() {
    print_header
    echo -e "${BOLD}${YELLOW}  ╔══════════════════════════════════════════════╗"
    echo -e "  ║            Kelola Route User                 ║"
    echo -e "  ╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}[1]${NC}  Tambah route ke user"
    echo -e "  ${RED}[2]${NC}  Hapus route dari user"
    echo -e "  ${CYAN}[3]${NC}  Lihat route user"
    echo -e "  ${YELLOW}[0]${NC}  Kembali ke menu utama"
    echo ""
    echo -ne "  Pilihan: "
    read ROUTE_CHOICE

    case $ROUTE_CHOICE in
        1) menu_route_add ;;
        2) menu_route_remove ;;
        3) menu_route_list ;;
        0) main_menu; return ;;
        *) echo -e "${RED}  ❌ Pilihan tidak valid.${NC}"; sleep 1; menu_route_user ;;
    esac
}

menu_route_add() {
    echo ""
    echo -e "  ${BOLD}User terdaftar:${NC}"
    ls /etc/openvpn/ccd 2>/dev/null | sed 's/^/    - /' || echo "    (tidak ada)"
    echo ""
    echo -ne "  Username  : "
    read USERNAME
    echo -ne "  Subnet(s) : (pisah spasi, misal: 192.168.1.0/24 10.0.0.0/8)"
    echo ""
    echo -ne "  > "
    read SUBNETS_INPUT

    if [ -z "$USERNAME" ] || [ -z "$SUBNETS_INPUT" ]; then
        echo -e "${RED}  ❌ Username dan subnet tidak boleh kosong.${NC}"
        sleep 1; menu_route_add; return
    fi

    echo ""
    bash "$ROUTE_USER" add "$USERNAME" $SUBNETS_INPUT
    back_to_menu
}

menu_route_remove() {
    echo ""
    echo -e "  ${BOLD}User terdaftar:${NC}"
    ls /etc/openvpn/ccd 2>/dev/null | sed 's/^/    - /' || echo "    (tidak ada)"
    echo ""
    echo -ne "  Username  : "
    read USERNAME
    echo -ne "  Subnet(s) : (pisah spasi, misal: 192.168.1.0/24)"
    echo ""
    echo -ne "  > "
    read SUBNETS_INPUT

    if [ -z "$USERNAME" ] || [ -z "$SUBNETS_INPUT" ]; then
        echo -e "${RED}  ❌ Username dan subnet tidak boleh kosong.${NC}"
        sleep 1; menu_route_remove; return
    fi

    echo ""
    bash "$ROUTE_USER" remove "$USERNAME" $SUBNETS_INPUT
    back_to_menu
}

menu_route_list() {
    echo ""
    echo -e "  ${BOLD}User terdaftar:${NC}"
    ls /etc/openvpn/ccd 2>/dev/null | sed 's/^/    - /' || echo "    (tidak ada)"
    echo ""
    echo -ne "  Username  : "
    read USERNAME

    if [ -z "$USERNAME" ]; then
        echo -e "${RED}  ❌ Username tidak boleh kosong.${NC}"
        sleep 1; menu_route_list; return
    fi

    echo ""
    bash "$ROUTE_USER" list "$USERNAME"
    back_to_menu
}

# -----------------------------------------------
# Kembali ke menu
# -----------------------------------------------
back_to_menu() {
    echo ""
    echo -ne "  Tekan ${BOLD}Enter${NC} untuk kembali ke menu..."
    read
    main_menu
}

# -----------------------------------------------
# Entry point
# -----------------------------------------------
check_scripts
main_menu