#!/usr/bin/env bash
# =========================================================
# ForgeX Panel - Installation & Management
# =========================================================
# Installs ONLY the ForgeX production panel and the host
# dependencies it actually requires. There is no developer panel.
# =========================================================

set -u

GREEN='\033[38;5;48m'
EMERALD='\033[38;5;42m'
CYAN='\033[38;5;51m'
TEAL='\033[38;5;37m'
BLUE='\033[38;5;75m'
VIOLET='\033[38;5;141m'
YELLOW='\033[38;5;220m'
AMBER='\033[38;5;214m'
RED='\033[38;5;196m'
WHITE='\033[1;37m'
GRAY='\033[38;5;242m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

FORGEX_REPO="${FORGEX_REPO:-https://github.com/y4sh-x/ForgeX.git}"
FORGEX_VERSION="1.0.0"
INSTALL_DIR="${FORGEX_DIR:-/opt/forgex}"
PANEL_PORT=6060
SFTP_PORT=2022
PM2_APP="forgex"

is_android_environment() {
    case "$(uname -s 2>/dev/null)" in Android) return 0 ;; esac
    [ -n "${ANDROID_ROOT:-}" ] || [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ]
}

require_supported_install_environment() {
    if is_android_environment; then
        log_error "Android/Termux is not a supported ForgeX production host."
        log_warning "This installer requires a Debian/Ubuntu or supported RPM-based Linux VPS with system services and Docker Engine."
        log_info "Use a Linux VPS or a compatible Linux VM/container with a working Docker daemon; no su/sudo workaround will be attempted."
        return 1
    fi
    if [ "${EUID:-$(id -u)}" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
        log_error "Root privileges are required, but sudo is not installed."
        log_info "Run as root (bash install.sh) or install/configure sudo on a supported Linux VPS."
        return 1
    fi
    if ! command -v apt-get >/dev/null 2>&1 && ! command -v dnf >/dev/null 2>&1 && ! command -v yum >/dev/null 2>&1; then
        log_error "Unsupported Linux distribution: expected apt-get, dnf, or yum."
        return 1
    fi
    return 0
}

run_root() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo -n true >/dev/null 2>&1 || { log_error "sudo is present but cannot obtain root privileges. Run this installer with working sudo access."; return 1; }
        sudo "$@"
    else
        log_error "Cannot run '$*': neither root access nor sudo is available."
        return 1
    fi
}

log_info() { echo -e "  ${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "  ${GREEN}✔${NC} $1"; }
log_warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "  ${RED}✖${NC} $1"; }

get_ip() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -n "$ip" ] || ip=$(curl -fsS --max-time 2 https://api.ipify.org 2>/dev/null || true)
    echo "${ip:-127.0.0.1}"
}

port_active() {
    ss -lnt 2>/dev/null | grep -qE ":$1[[:space:]]" || return 1
}

print_banner() {
    clear 2>/dev/null || true
    local ip
    ip=$(get_ip)
    local state="${GRAY}○ STOPPED${NC}"
    if port_active "$PANEL_PORT"; then state="${GREEN}● ONLINE (:${PANEL_PORT})${NC}"; fi

    echo -e "
  ${EMERALD}${BOLD}╭──────────────────────────────────────────────────────────────╮
  │  ${WHITE}██████╗██████╗  █████╗ ███████╗████████╗██╗  ██╗${EMERALD}        │
  │  ${WHITE}██╔════╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝██║  ██║${EMERALD}        │
  │  ${WHITE}██║     ██████╔╝███████║█████╗     ██║   ███████║${EMERALD}        │
  │  ${WHITE}██║     ██╔══██╗██╔══██║██╔══╝     ██║   ██╔══██║${EMERALD}        │
  │  ${WHITE}╚██████╗██║  ██║██║  ██║██║        ██║   ██║  ██║${EMERALD}        │
  │  ${WHITE} ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝        ╚═╝   ╚═╝  ╚═╝${EMERALD}        │
  │  ${CYAN}Minecraft Server Management Panel${EMERALD} · ${AMBER}v${FORGEX_VERSION}${EMERALD}             │
  ├──────────────────────────────────────────────────────────────┤
  │  ${GRAY}Host :${NC} ${WHITE}${ip}${EMERALD}   ${GRAY}Panel :${NC} ${CYAN}:${PANEL_PORT}${EMERALD}   ${GRAY}Status :${NC} ${state}${EMERALD}
  │  ${GRAY}SFTP :${NC} ${CYAN}:${SFTP_PORT}${EMERALD}   ${GRAY}Runtime :${NC} ${WHITE}Node.js + Docker${EMERALD}                     │
  ╰──────────────────────────────────────────────────────────────╯${NC}
"
}

install_base_packages() {
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        run_root apt-get update -y
        run_root apt-get install -y curl git ca-certificates build-essential openssl jq unzip
    elif command -v dnf >/dev/null 2>&1; then
        run_root dnf install -y curl git ca-certificates gcc-c++ make openssl jq unzip
    elif command -v yum >/dev/null 2>&1; then
        run_root yum install -y curl git ca-certificates gcc-c++ make openssl jq unzip
    else
        log_error "Unsupported package manager. Install curl, git, ca-certificates, build tools and jq manually."
        return 1
    fi
}

install_node() {
    local major=0
    if command -v node >/dev/null 2>&1; then
        major=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)
    fi
    if [ "$major" -lt 24 ]; then
        if command -v apt-get >/dev/null 2>&1; then
            curl -fsSL https://deb.nodesource.com/setup_24.x | run_root bash -
            run_root apt-get install -y nodejs
        elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
            curl -fsSL https://rpm.nodesource.com/setup_24.x | run_root bash -
            if command -v dnf >/dev/null 2>&1; then run_root dnf install -y nodejs; else run_root yum install -y nodejs; fi
        else
            log_error "Cannot install Node.js 24 automatically on this OS."
            return 1
        fi
    fi
    node -e 'if(Number(process.versions.node.split(".")[0])<24) process.exit(1)'
}

install_pnpm() {
    if command -v corepack >/dev/null 2>&1; then
        run_root corepack enable || true
        corepack prepare pnpm@11.25.0 --activate || true
    fi
    if ! command -v pnpm >/dev/null 2>&1; then
        run_root npm install -g pnpm@11.25.0
    fi
    pnpm --version
}

install_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com | run_root sh
    fi
    if command -v systemctl >/dev/null 2>&1; then
        run_root systemctl enable --now docker
    fi
    docker info >/dev/null 2>&1 || run_root docker info >/dev/null 2>&1
    if ! docker compose version >/dev/null 2>&1; then
        log_warning "Docker Compose plugin is unavailable. Installing the official plugin package."
        if command -v apt-get >/dev/null 2>&1; then
            run_root apt-get install -y docker-compose-plugin
        fi
    fi
    docker compose version >/dev/null 2>&1 || run_root docker compose version >/dev/null 2>&1
}

install_pm2() {
    if ! command -v pm2 >/dev/null 2>&1; then
        run_root npm install -g pm2
    fi
}

prepare_project() {
    run_root mkdir -p "$INSTALL_DIR"
    run_root chown -R "$(id -u):$(id -g)" "$INSTALL_DIR"

    if [ -f "$INSTALL_DIR/package.json" ]; then
        cd "$INSTALL_DIR" || return 1
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            git remote set-url origin "$FORGEX_REPO" 2>/dev/null || true
        fi
    else
        if [ -n "${FORGEX_SOURCE_DIR:-}" ] && [ -f "${FORGEX_SOURCE_DIR}/package.json" ]; then
            cp -a "${FORGEX_SOURCE_DIR}/." "$INSTALL_DIR/"
        else
            git clone --depth 1 "$FORGEX_REPO" "$INSTALL_DIR"
        fi
        cd "$INSTALL_DIR" || return 1
    fi

    [ -f package.json ] || { log_error "ForgeX package.json was not found."; return 1; }
}

configure_panel() {
    mkdir -p data backups
    if [ ! -f .env ]; then
        if [ -f .env.example ]; then cp .env.example .env; else : > .env; fi
    fi

    # Only set the production values needed for this deployment.
    sed -i '/^PANEL_HOST=/d;/^PANEL_PORT=/d;/^SFTP_PORT=/d' .env
    {
        echo 'PANEL_HOST=127.0.0.1'
        echo "PANEL_PORT=${PANEL_PORT}"
        echo "SFTP_PORT=${SFTP_PORT}"
    } >> .env
}

install_dependencies() {
    pnpm install --frozen-lockfile=false --prod=false
}

build_panel() {
    pnpm run build
}

start_panel() {
    cd "$INSTALL_DIR" || return 1
    pm2 delete "$PM2_APP" >/dev/null 2>&1 || true
    pm2 start npm --name "$PM2_APP" -- start
    pm2 save
    if command -v systemctl >/dev/null 2>&1; then
        pm2 startup systemd -u "$(id -un)" --hp "$HOME" 2>/dev/null | tail -n 1 || true
    fi
}

health_check() {
    sleep 3
    if curl -fsS --max-time 5 "http://127.0.0.1:${PANEL_PORT}/login" >/dev/null 2>&1 || \
       curl -fsS --max-time 5 "http://127.0.0.1:${PANEL_PORT}/" >/dev/null 2>&1; then
        log_success "ForgeX is responding on port ${PANEL_PORT}."
        return 0
    fi
    log_error "ForgeX did not answer on port ${PANEL_PORT}."
    pm2 logs "$PM2_APP" --lines 30 --nostream || true
    return 1
}

install_panel() {
    require_supported_install_environment || return 1
    print_banner
    echo -e "  ${GRAY}┌──${NC} ${BOLD}FORGEX PRODUCTION INSTALLATION${NC} ${GRAY}──────────────────────────┐${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}  ${CYAN}✓${NC} ForgeX web panel                                  ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}  ${CYAN}✓${NC} Node.js 24+ / pnpm                                  ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}  ${CYAN}✓${NC} Docker Engine + Compose for Minecraft servers       ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}  ${CYAN}✓${NC} Built-in SFTP service (:${SFTP_PORT})                  ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}  ${CYAN}✓${NC} PM2 production process                                ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}  ${DIM}No Developer Panel. No separate developer runtime.${NC}       ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}└───────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    install_base_packages || return 1
    install_node || return 1
    install_pnpm || return 1
    install_docker || return 1
    install_pm2 || return 1
    prepare_project || return 1
    configure_panel || return 1
    install_dependencies || return 1
    build_panel || return 1
    start_panel || return 1
    health_check || return 1

    local ip
    ip=$(get_ip)
    echo -e "\n  ${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗"
    echo -e "  ║  ✔  FORGEX INSTALLATION COMPLETED                       ║"
    echo -e "  ╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ║  Panel       : ${CYAN}http://127.0.0.1:${PANEL_PORT}${NC}                    ║"
    echo -e "  ║  VPS IP      : ${CYAN}http://${ip}:${PANEL_PORT}${NC}                     ║"
    echo -e "  ║  SFTP        : ${YELLOW}Port ${SFTP_PORT}${NC}                                  ║"
    echo -e "  ║  Installation: ${WHITE}${INSTALL_DIR}${NC}                  ║"
    echo -e "  ║  Process     : ${GREEN}PM2 / ${PM2_APP}${NC}                              ║"
    echo -e "  ║                                                            ║"
    echo -e "  ║  First login/setup: open ${CYAN}/setup${NC} when prompted.         ║"
    echo -e "  ║  Logs: ${CYAN}pm2 logs ${PM2_APP}${NC}                                  ║"
    echo -e "  ${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}\n"
}

update_panel() {
    require_supported_install_environment || return 1
    print_banner
    cd "$INSTALL_DIR" 2>/dev/null || { log_error "ForgeX is not installed at $INSTALL_DIR"; return 1; }
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git fetch --all --prune
        git pull --ff-only || log_warning "Fast-forward update was not possible; check local changes."
    else
        log_error "$INSTALL_DIR is not a Git checkout."
        return 1
    fi
    install_dependencies || return 1
    build_panel || return 1
    pm2 restart "$PM2_APP" || start_panel
    health_check
}

show_status() {
    print_banner
    echo -e "  ${GRAY}┌──${NC} ${BOLD}FORGEX SERVICE STATUS${NC} ${GRAY}───────────────────────────────────┐${NC}"
    echo -e "  ${GRAY}│${NC}  Panel : $(if port_active "$PANEL_PORT"; then echo -e "${GREEN}● ONLINE${NC}"; else echo -e "${RED}● OFFLINE${NC}"; fi)  ${CYAN}:$PANEL_PORT${NC}"
    echo -e "  ${GRAY}│${NC}  SFTP  : ${CYAN}:$SFTP_PORT${NC}"
    echo -e "  ${GRAY}│${NC}  Docker: $(if docker info >/dev/null 2>&1 || run_root docker info >/dev/null 2>&1; then echo -e "${GREEN}● AVAILABLE${NC}"; else echo -e "${YELLOW}● UNAVAILABLE${NC}"; fi)"
    echo -e "  ${GRAY}│${NC}  PM2   : $(pm2 describe "$PM2_APP" >/dev/null 2>&1 && echo -e "${GREEN}● REGISTERED${NC}" || echo -e "${RED}● NOT RUNNING${NC}")"
    echo -e "  ${GRAY}└───────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

setup_info() {
    print_banner
    echo -e "  ${GRAY}┌──${NC} ${BOLD}FIRST-RUN ADMIN SETUP${NC} ${GRAY}────────────────────────────────────┐${NC}"
    echo -e "  ${GRAY}│${NC} ForgeX creates the first administrator through its own       ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC} ${CYAN}/setup${NC} flow. The installer does not invent a separate admin   ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC} database or developer account.                                ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC} Local URL: ${CYAN}http://127.0.0.1:${PANEL_PORT}/setup${NC}                 ${GRAY}│${NC}"
    echo -e "  ${GRAY}└───────────────────────────────────────────────────────────────┘${NC}"
}

uninstall_panel() {
    require_supported_install_environment || return 1
    print_banner
    echo -ne "  ${RED}${BOLD}Remove ForgeX from ${INSTALL_DIR}? [y/N]: ${NC}"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]] || return 0
    pm2 delete "$PM2_APP" >/dev/null 2>&1 || true
    pm2 save >/dev/null 2>&1 || true
    run_root rm -rf "$INSTALL_DIR"
    log_success "ForgeX panel files and PM2 process removed."
    log_warning "Docker itself was NOT removed because ForgeX uses it for Minecraft servers."
}

if [ "${1:-}" = "install" ] || [ "${1:-}" = "main" ]; then
    install_panel
    exit $?
elif [ "${1:-}" = "update" ]; then
    update_panel
    exit $?
fi

while true; do
    print_banner
    echo -e "  ${EMERALD}${BOLD}╭──${NC} ${BOLD}${WHITE}CONTROL MENU${NC} ${EMERALD}─────────────────────────────────────────╮${NC}"
    echo -e "  ${EMERALD}│${NC}                                                              ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}  ${GREEN}${BOLD}[1]${NC}  ${WHITE}${BOLD}Install / Repair ForgeX${NC}   ${GRAY}Production Panel (:6060)     ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}  ${CYAN}${BOLD}[2]${NC}  ${WHITE}${BOLD}Update ForgeX${NC}             ${GRAY}Git + Dependencies + Build    ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}  ${VIOLET}${BOLD}[3]${NC}  ${WHITE}${BOLD}First-Run Setup Info${NC}       ${GRAY}Admin Setup (/setup)          ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}  ${BLUE}${BOLD}[4]${NC}  ${WHITE}${BOLD}System & Service Status${NC}    ${GRAY}Panel, Docker & PM2           ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}  ${RED}${BOLD}[5]${NC}  ${WHITE}${BOLD}Uninstall ForgeX Panel${NC}   ${GRAY}Remove Panel, Keep Docker      ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}  ${GRAY}${BOLD}[0]${NC}  ${WHITE}${BOLD}Exit Installer${NC}             ${GRAY}Close this terminal menu        ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}                                                              ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}╰─────────────────────────────────────────────────────────────╯${NC}"
    echo ""
    echo -ne "  ${EMERALD}▶${NC} ${BOLD}Choose option [0-5]${NC}: "
    read -r choice || exit 0
    case "$choice" in
        1) install_panel; read -r -p "  Press Enter to continue..." ;;
        2) update_panel; read -r -p "  Press Enter to continue..." ;;
        3) setup_info; read -r -p "  Press Enter to continue..." ;;
        4) show_status; read -r -p "  Press Enter to continue..." ;;
        5) uninstall_panel; read -r -p "  Press Enter to continue..." ;;
        0|q|exit) exit 0 ;;
        *) log_error "Invalid option: $choice"; sleep 1 ;;
    esac
done
