#!/bin/bash
# Alist Backup Installation Script
# Version: 1.0.0
# Description: Installs and manages Alist Backup (https://github.com/guihuatu2022/alist-backup)
# Requirements: Linux with systemd, curl, tar, netstat, root privileges
# License: MIT

# Constants
VERSION="1.0.0"
LOG_FILE="/var/log/alist-backup-install.log"
INSTALL_PATH="/opt/alist-backup"
SERVICE_NAME="alist-backup"
PORT="5244"
DOWNLOAD_URL_AMD64="https://github.com/guihuatu2022/alist-backup/releases/download/alist-backup/alist-linux-amd64.tar.gz"
DOWNLOAD_URL_ARM64="https://github.com/guihuatu2022/alist-backup/releases/download/alist-backup/alist-linux-arm64.tar.gz"
MANAGER_PATH="/usr/local/sbin/alist-backup-manager"
COMMAND_LINK="/usr/local/bin/alist-backup"

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    echo -e "${RED}Error: $1${RESET}" >&2
    log "ERROR: $1"
    exit 1
}

# Check requirements
check_requirements() {
    log "Checking requirements"
    [ "$(id -u)" != "0" ] && error_exit "Root privileges required"
    command -v curl >/dev/null || error_exit "curl not found, please install"
    command -v tar >/dev/null || error_exit "tar not found, please install"
    command -v netstat >/dev/null || error_exit "netstat not found, please install"
    command -v systemctl >/dev/null || error_exit "systemctl not found, systemd required"
}

# Get architecture
get_arch() {
    log "Detecting architecture"
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64"; echo "$DOWNLOAD_URL_AMD64" ;;
        aarch64) echo "arm64"; echo "$DOWNLOAD_URL_ARM64" ;;
        *) error_exit "Unsupported architecture: $arch" ;;
    esac
}

# Download file with retries
download_file() {
    local url="$1"
    local output="$2"
    local retries=3
    local count=0
    log "Downloading $url to $output"
    while [ "$count" -lt "$retries" ]; do
        if curl -sL --connect-timeout 10 -o "$output" "$url"; then
            [ -s "$output" ] && { log "Download successful"; return 0; }
        fi
        count=$((count + 1))
        log "Download failed, retry $count/$retries"
        sleep 5
    done
    error_exit "Download failed after $retries retries"
}

# Check installation prerequisites
check_install() {
    log "Checking installation prerequisites"
    if netstat -tuln | grep -q ":$PORT"; then
        echo -e "${RED}Error: Port $PORT is in use${RESET}" >&2
        echo -e "Run: ${YELLOW}sudo netstat -tulnp | grep $PORT${RESET} to find and terminate the process" >&2
        error_exit "Port $PORT conflict"
    fi
    if [ -f "$INSTALL_PATH/alist" ]; then
        echo -e "${YELLOW}Alist Backup already installed at $INSTALL_PATH${RESET}"
        echo -e "Use './install_alist.sh update' to update or choose another path" >&2
        exit 0
    fi
    mkdir -p "$INSTALL_PATH" || error_exit "Cannot create directory $INSTALL_PATH"
    rm -rf "$INSTALL_PATH/*" 2>/dev/null
}

# Install binary
install_binary() {
    local download_url="$1"
    log "Installing binary"
    echo -e "${GREEN}Downloading Alist Backup...${RESET}"
    download_file "$download_url" "/tmp/alist-backup.tar.gz"
    tar -zxf "/tmp/alist-backup.tar.gz" -C "$INSTALL_PATH" || error_exit "Failed to extract tar.gz"
    rm -f "/tmp/alist-backup.tar.gz"
    if [ -f "$INSTALL_PATH/alist" ]; then
        chmod +x "$INSTALL_PATH/alist" || error_exit "Cannot set executable permissions"
        log "Binary installed successfully"
    else
        error_exit "Binary not found after extraction"
    fi
}

# Get admin credentials
get_admin_credentials() {
    log "Generating admin credentials"
    cd "$INSTALL_PATH" || error_exit "Cannot change to directory $INSTALL_PATH"
    local output
    output=$("./alist" admin random 2>&1)
    ADMIN_USER=$(echo "$output" | grep "username:" | sed 's/.*username://' | tr -d ' ')
    ADMIN_PASS=$(echo "$output" | grep "password:" | sed 's/.*password://' | tr -d ' ')
    log "Admin user: $ADMIN_USER, Password: $ADMIN_PASS"
    cd - >/dev/null
}

# Create systemd service
create_service() {
    log "Creating systemd service"
    cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Alist Backup Service
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_PATH
ExecStart=$INSTALL_PATH/alist server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || error_exit "Cannot enable $SERVICE_NAME service"
    log "Service created and enabled"
}

# Install CLI tools
install_cli() {
    log "Installing CLI tools"
    local script_path
    script_path=$(realpath "$0")
    mkdir -p "$(dirname "$MANAGER_PATH")" || error_exit "Cannot create directory for $MANAGER_PATH"
    cp "$script_path" "$MANAGER_PATH" || error_exit "Cannot copy script to $MANAGER_PATH"
    chmod 755 "$MANAGER_PATH" || error_exit "Cannot set permissions for $MANAGER_PATH"
    ln -sf "$MANAGER_PATH" "$COMMAND_LINK" || error_exit "Cannot create symlink $COMMAND_LINK"
    log "CLI tools installed"
}

# Display success message
display_success() {
    log "Displaying success message"
    local local_ip public_ip
    local_ip=$(ip addr show | grep -w inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -n1 || echo "Unknown")
    public_ip=$(curl -s4 ip.sb || echo "Unknown")
    clear
    echo -e "┌───────────────────────────────────────────────────┐"
    echo -e "│ ${GREEN}Alist Backup v$VERSION Installed Successfully${RESET} │"
    echo -e "│                                                   │"
    echo -e "│ Access URLs:                                      │"
    echo -e "│   LAN:  http://$local_ip:$PORT/                   │"
    echo -e "│   WAN:  http://$public_ip:$PORT/                  │"
    echo -e "│ Config: $INSTALL_PATH/data/config.json            │"
    echo -e "│                                                   │"
    if [ -n "$ADMIN_USER" ] && [ -n "$ADMIN_PASS" ]; then
        echo -e "│ Admin Credentials:                                │"
        echo -e "│   Username: $ADMIN_USER                           │"
        echo -e "│   Password: $ADMIN_PASS                           │"
    else
        echo -e "│ Admin Credentials:                                │"
        echo -e "│   Reset via: alist-backup -> Option 5             │"
    fi
    echo -e "└───────────────────────────────────────────────────┘"
    echo -e "\n${GREEN}Starting service...${RESET}"
    systemctl restart "$SERVICE_NAME" || error_exit "Cannot start $SERVICE_NAME service"
    echo -e "Manage with: ${GREEN}alist-backup${RESET}"
    echo -e "${YELLOW}Note: If port $PORT is not accessible, check firewall or security groups${RESET}"
}

# Install function
install() {
    check_requirements
    local arch_info download_url
    read -r arch download_url <<< "$(get_arch)"
    log "Architecture: $arch, URL: $download_url"
    check_install
    install_binary "$download_url"
    get_admin_credentials
    create_service
    install_cli
    display_success
}

# Update function
update() {
    log "Starting update"
    [ ! -f "$INSTALL_PATH/alist" ] && error_exit "Alist Backup not found at $INSTALL_PATH"
    local arch_info download_url
    read -r arch download_url <<< "$(get_arch)"
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    cp "$INSTALL_PATH/alist" "/tmp/alist.bak" || error_exit "Cannot backup binary"
    install_binary "$download_url"
    systemctl restart "$SERVICE_NAME" || error_exit "Cannot restart $SERVICE_NAME service"
    rm -f "/tmp/alist.bak"
    echo -e "${GREEN}Update completed${RESET}"
    log "Update completed"
}

# Uninstall function
uninstall() {
    log "Starting uninstall"
    [ ! -f "$INSTALL_PATH/alist" ] && error_exit "Alist Backup not found at $INSTALL_PATH"
    echo -e "${RED}Warning: This will remove $INSTALL_PATH and all data${RESET}"
    read -p "Confirm uninstall? [y/N]: " confirm
    [ "${confirm,,}" != "y" ] && { echo -e "${GREEN}Uninstall cancelled${RESET}"; exit 0; }
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    systemctl disable "$SERVICE_NAME" 2>/dev/null
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload
    rm -rf "$INSTALL_PATH"
    rm -f "$MANAGER_PATH" "$COMMAND_LINK"
    echo -e "${GREEN}Uninstall completed${RESET}"
    log "Uninstall completed"
}

# Reset password
reset_password() {
    log "Resetting password"
    [ ! -f "$INSTALL_PATH/alist" ] && error_exit "Alist Backup not installed"
    echo -e "\n${GREEN}1. Generate random password${RESET}"
    echo -e "${GREEN}2. Set custom password${RESET}"
    echo -e "${GREEN}0. Return to menu${RESET}"
    read -p "Select option [0-2]: " choice
    cd "$INSTALL_PATH" || error_exit "Cannot change to $INSTALL_PATH"
    case "$choice" in
        1)
            echo -e "${GREEN}Generating random password...${RESET}"
            ./alist admin random | grep -E "username:|password:" | sed 's/.*username:/Username: /; s/.*password:/Password: /'
            log "Random password generated"
            ;;
        2)
            read -p "Enter new password: " new_pass
            [ -z "$new_pass" ] && error_exit "Password cannot be empty"
            echo -e "${GREEN}Setting new password...${RESET}"
            ./alist admin set "$new_pass" | grep -E "username:|password:" | sed 's/.*username:/Username: /; s/.*password:/Password: /'
            log "Custom password set"
            ;;
        0) return ;;
        *) error_exit "Invalid option" ;;
    esac
}

# Show menu
show_menu() {
    log "Showing menu"
    clear
    echo -e "Alist Backup Manager v$VERSION"
    echo -e "──────────────────────────────"
    echo -e "${GREEN}1. Install${RESET}"
    echo -e "${GREEN}2. Update${RESET}"
    echo -e "${GREEN}3. Uninstall${RESET}"
    echo -e "${GREEN}4. Check status${RESET}"
    echo -e "${GREEN}5. Reset password${RESET}"
    echo -e "${GREEN}6. Start service${RESET}"
    echo -e "${GREEN}7. Stop service${RESET}"
    echo -e "${GREEN}8. Restart service${RESET}"
    echo -e "${GREEN}0. Exit${RESET}"
    read -p "Select option [0-8]: " choice
    case "$choice" in
        1) install ;;
        2) update ;;
        3) uninstall ;;
        4)
            if systemctl is-active "$SERVICE_NAME" >/dev/null; then
                echo -e "${GREEN}Status: Running${RESET}"
                log "Status: Running"
            else
                echo -e "${RED}Status: Stopped${RESET}"
                log "Status: Stopped"
            fi
            ;;
        5) reset_password ;;
        6)
            systemctl start "$SERVICE_NAME" && echo -e "${GREEN}Service started${RESET}" || error_exit "Cannot start service"
            log "Service started"
            ;;
        7)
            systemctl stop "$SERVICE_NAME" && echo -e "${GREEN}Service stopped${RESET}" || echo -e "${YELLOW}Warning: Cannot stop service${RESET}"
            log "Service stopped"
            ;;
        8)
            systemctl restart "$SERVICE_NAME" && echo -e "${GREEN}Service restarted${RESET}" || error_exit "Cannot restart service"
            log "Service restarted"
            ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid option${RESET}"; sleep 2 ;;
    esac
}

# Main
log "Script started"
case "$1" in
    install) install ;;
    update) update ;;
    uninstall) uninstall ;;
    *)
        while true; do
            show_menu
            echo
            sleep 3
            clear
        done
        ;;
esac
log "Script completed"
echo "END_OF_SCRIPT" >> "$LOG_FILE"