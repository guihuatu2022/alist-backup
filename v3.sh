#!/bin/bash
###############################################################################
#
# Alist Backup Manager Script
#
# Version: 3.0.0
# Last Updated: 2025-06-15
#
# Description:
#   A management script for Alist Backup (https://github.com/guihuatu2022/alist-backup)
#   Provides installation, update, uninstallation, and management functions
#
# Requirements:
#   - Linux with systemd
#   - Root privileges for installation
#   - curl, tar
#   - x86_64 or arm64 architecture
#
# Author: Adapted from Troray's Alist script
# Repository: https://github.com/guihuatu2022/alist-backup
# License: MIT
#
###############################################################################

# 确保使用 bash
if [ -z "$BASH_VERSION" ]; then
    echo "错误：此脚本需要 bash，请使用 bash 执行" >&2
    exit 1
fi
if [ "$(readlink /bin/sh)" != "bash" ]; then
    echo "警告：/bin/sh 未链接到 bash，可能导致解析错误" >&2
    echo "建议运行：sudo ln -sf /bin/bash /bin/sh" >&2
fi

# 日志文件
LOG_FILE="/var/log/alist-backup-install.log"
echo "Starting script execution at $(date)" >> "$LOG_FILE"

# 错误处理函数
handle_error() {
    local exit_code="$1"
    local error_msg="$2"
    echo -e "${RED_COLOR}错误：${error_msg}${RES}" >&2
    echo "ERROR: $error_msg" >> "$LOG_FILE"
    exit "$exit_code"
}

# 检查必要命令
if ! command -v curl >/dev/null 2>&1; then
    handle_error 1 "未找到 curl 命令，请先安装"
fi
if ! command -v tar >/dev/null 2>&1; then
    handle_error 1 "未找到 tar 命令，请先安装"
fi
if ! command -v netstat >/dev/null 2>&1; then
    handle_error 1 "未找到 netstat 命令，请先安装"
fi

# 配置部分
#######################
# Alist 备份下载地址
DOWNLOAD_URL_AMD64="https://github.com/guihuatu2022/alist-backup/releases/download/alist-backup/alist-linux-amd64.tar.gz"
DOWNLOAD_URL_ARM64="https://github.com/guihuatu2022/alist-backup/releases/download/alist-backup/alist-linux-arm64.tar.gz"
#######################

# 颜色配置
RED_COLOR='\e[1;31m'
GREEN_COLOR='\e[1;32m'
YELLOW_COLOR='\e[1;33m'
RES='\e[0m'

# 获取已安装路径的函数
GET_INSTALLED_PATH() {
    echo "Executing GET_INSTALLED_PATH" >> "$LOG_FILE"
    if [ -f "/etc/systemd/system/alist-backup.service" ]; then
        installed_path=$(grep "WorkingDirectory=" /etc/systemd/system/alist-backup.service | cut -d'=' -f2)
        if [ -n "$installed_path" ] && [ -f "$installed_path/alist" ]; then
            echo "$installed_path"
            echo "Found installed path: $installed_path" >> "$LOG_FILE"
            return 0
        fi
    fi
    echo "/opt/alist-backup"
    echo "Using default path: /opt/alist-backup" >> "$LOG_FILE"
}

# 设置安装路径
if [ -z "$2" ]; then
    INSTALL_PATH="/opt/alist-backup"
else
    INSTALL_PATH="${2%/}"
    if ! [[ "$INSTALL_PATH" == */alist-backup ]]; then
        INSTALL_PATH="$INSTALL_PATH/alist-backup"
    fi
    parent_dir=$(dirname "$INSTALL_PATH")
    if [ ! -d "$parent_dir" ]; then
        mkdir -p "$parent_dir" || handle_error 1 "无法创建目录 $parent_dir"
    fi
    if [ ! -w "$parent_dir" ]; then
        handle_error 1 "目录 $parent_dir 没有写入权限"
    fi
fi
echo "Install path set to: $INSTALL_PATH" >> "$LOG_FILE"

# 更新或卸载时使用已安装路径
if [ "$1" = "update" ] || [ "$1" = "uninstall" ]; then
    INSTALL_PATH=$(GET_INSTALLED_PATH)
fi

# 获取平台架构并设置下载链接
if command -v arch >/dev/null 2>&1; then
    platform=$(arch)
else
    platform=$(uname -m)
fi
echo "Detected platform: $platform" >> "$LOG_FILE"

ARCH="UNKNOWN"
DOWNLOAD_URL=""
case "$platform" in
    x86_64)
        ARCH="amd64"
        DOWNLOAD_URL="$DOWNLOAD_URL_AMD64"
        ;;
    aarch64)
        ARCH="arm64"
        DOWNLOAD_URL="$DOWNLOAD_URL_ARM64"
        ;;
    *)
        handle_error 1 "一键安装目前仅支持 x86_64 和 arm64 平台"
        ;;
esac
echo "Selected architecture: $ARCH, Download URL: $DOWNLOAD_URL" >> "$LOG_FILE"

# 权限和环境检查
if [ "$(id -u)" != "0" ]; then
    if [ "$1" = "install" ] || [ "$1" = "update" ] || [ "$1" = "uninstall" ]; then
        echo -e "\r\n${RED_COLOR}错误：请使用 root 权限运行此命令！${RES}\r\n" >&2
        echo -e "提示：使用 ${GREEN_COLOR}sudo $0 $1${RES} 重试\r\n" >&2
        echo "ERROR: Root privileges required for $1" >> "$LOG_FILE"
        exit 1
    fi
fi
if ! command -v systemctl >/dev/null 2>&1; then
    handle_error 1 "无法确定你当前的 Linux 发行版，建议手动安装"
fi

CHECK() {
    echo "Executing CHECK" >> "$LOG_FILE"
    # 检查端口冲突
    if netstat -tuln | grep -q ":5244"; then
        echo -e "${RED_COLOR}错误：5244 端口已被占用！${RES}" >&2
        echo -e "请运行以下命令查找占用进程并终止：${YELLOW_COLOR}sudo netstat -tulnp | grep 5244${RES}" >&2
        echo "ERROR: Port 5244 is already in use" >> "$LOG_FILE"
        exit 1
    fi
    if [ ! -d "$(dirname "$INSTALL_PATH")" ]; then
        echo -e "${GREEN_COLOR}目录不存在，正在创建...${RES}"
        mkdir -p "$(dirname "$INSTALL_PATH")" || handle_error 1 "无法创建目录 $(dirname "$INSTALL_PATH")"
    fi
    if [ -f "$INSTALL_PATH/alist" ]; then
        echo -e "${YELLOW_COLOR}此位置已经安装，请选择其他位置，或使用更新命令${RES}" >&2
        echo "ERROR: Alist already installed at $INSTALL_PATH" >> "$LOG_FILE"
        exit 0
    fi
    if [ ! -d "$INSTALL_PATH" ]; then
        mkdir -p "$INSTALL_PATH" || handle_error 1 "无法创建安装目录 $INSTALL_PATH"
    else
        rm -rf "$INSTALL_PATH" && mkdir -p "$INSTALL_PATH" || handle_error 1 "无法重置安装目录 $INSTALL_PATH"
    fi
    echo -e "${GREEN_COLOR}安装目录准备就绪：$INSTALL_PATH${RES}"
    echo "CHECK completed, install path ready: $INSTALL_PATH" >> "$LOG_FILE"
}

# 下载函数，带重试机制
download_file() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_count=0
    local wait_time=5
    echo "Downloading from $url to $output" >> "$LOG_FILE"
    while [ "$retry_count" -lt "$max_retries" ]; do
        if curl -L --connect-timeout 10 --retry 3 --retry-delay 3 "$url" -o "$output"; then
            if [ -f "$output" ] && [ -s "$output" ]; then
                echo "Download successful" >> "$LOG_FILE"
                return 0
            fi
        fi
        retry_count=$((retry_count + 1))
        if [ "$retry_count" -lt "$max_retries" ]; then
            echo -e "${YELLOW_COLOR}下载失败，${wait_time}秒后进行第$((retry_count + 1))次重试...${RES}"
            echo "Download failed, retrying $retry_count of $max_retries" >> "$LOG_FILE"
            sleep "$wait_time"
            wait_time=$((wait_time + 5))
        else
            echo -e "${RED_COLOR}下载失败，已重试 $max_retries 次${RES}" >&2
            echo "ERROR: Download failed after $max_retries retries" >> "$LOG_FILE"
            return 1
        fi
    done
    return 1
}

INSTALL() {
    echo "Executing INSTALL" >> "$LOG_FILE"
    CURRENT_DIR=$(pwd)
    echo "Current directory: $CURRENT_DIR" >> "$LOG_FILE"
    echo -e "${GREEN_COLOR}是否使用代理下载？（默认无代理）${RES}"
    echo -e "${GREEN_COLOR}代理地址必须以 https:// 开头，/ 结尾，例如 https://ghproxy.com/${RES}"
    read -p "请输入代理地址或按回车继续: " proxy_input
    if [ -n "$proxy_input" ]; then
        DOWNLOAD_URL="${proxy_input}${DOWNLOAD_URL#https://}"
        echo -e "${GREEN_COLOR}使用代理地址: $proxy_input${RES}"
        echo "Using proxy: $proxy_input" >> "$LOG_FILE"
    fi
    echo -e "${GREEN_COLOR}下载 Alist Backup ($ARCH) ...${RES}"
    echo "Starting download" >> "$LOG_FILE"
    if ! download_file "$DOWNLOAD_URL" "/tmp/alist-backup.tar.gz"; then
        handle_error 1 "下载失败"
    fi
    echo "Download completed, extracting" >> "$LOG_FILE"
    if ! tar zxf "/tmp/alist-backup.tar.gz" -C "$INSTALL_PATH"; then
        echo -e "${RED_COLOR}解压失败！${RES}" >&2
        echo "ERROR: Failed to extract tar.gz" >> "$LOG_FILE"
        rm -f "/tmp/alist-backup.tar.gz"
        exit 1
    fi
    if [ -f "$INSTALL_PATH/alist" ]; then
        echo -e "${GREEN_COLOR}下载成功，正在安装...${RES}"
        chmod +x "$INSTALL_PATH/alist" || handle_error 1 "无法设置执行权限"
        echo "Binary found and permissions set" >> "$LOG_FILE"
        # 尝试获取初始账号密码
        cd "$INSTALL_PATH" || handle_error 1 "无法切换到目录 $INSTALL_PATH"
        echo "Generating random admin credentials" >> "$LOG_FILE"
        ACCOUNT_INFO=$("$INSTALL_PATH/alist" admin random 2>&1)
        ADMIN_USER=$(echo "$ACCOUNT_INFO" | grep "username:" | sed 's/.*username://' | tr -d ' ')
        ADMIN_PASS=$(echo "$ACCOUNT_INFO" | grep "password:" | sed 's/.*password://' | tr -d ' ')
        echo "Admin user: $ADMIN_USER, Admin pass: $ADMIN_PASS" >> "$LOG_FILE"
        cd "$CURRENT_DIR" || handle_error 1 "无法切换回目录 $CURRENT_DIR"
    else
        echo -e "${RED_COLOR}安装失败，二进制文件未找到！${RES}" >&2
        echo "ERROR: Binary not found after extraction" >> "$LOG_FILE"
        rm -rf "$INSTALL_PATH"
        mkdir -p "$INSTALL_PATH"
        rm -f "/tmp/alist-backup.tar.gz"
        exit 1
    fi
    rm -f /tmp/alist-backup*
    echo "INSTALL completed" >> "$LOG_FILE"
}

INIT() {
    echo "Executing INIT" >> "$LOG_FILE"
    if [ ! -f "$INSTALL_PATH/alist" ]; then
        handle_error 1 "当前系统未安装 Alist Backup"
    fi
    cat >/etc/systemd/system/alist-backup.service <<EOF
[Unit]
Description=Alist Backup service
Wants=network.target
After=network.target network.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_PATH
ExecStart=$INSTALL_PATH/alist server
KillMode=process
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable alist-backup >/dev/null 2>&1 || handle_error 1 "无法启用 alist-backup 服务"
    echo "Systemd service created and enabled" >> "$LOG_FILE"
}

SUCCESS() {
    echo "Executing SUCCESS" >> "$LOG_FILE"
    clear
    print_line() {
        local text="$1"
        local width=51
        printf "│ %-${width}s │\n" "$text"
    }
    LOCAL_IP=$(ip addr show | grep -w inet | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -n1 || echo "获取失败")
    PUBLIC_IP=$(curl -s4 ip.sb || curl -s4 ifconfig.me || echo "获取失败")
    echo -e "┌────────────────────────────────────────────────────┐"
    print_line "Alist Backup 安装成功！"
    print_line ""
    print_line "访问地址："
    print_line "  局域网：http://${LOCAL_IP}:5244/"
    print_line "  公网：  http://${PUBLIC_IP}:5244/"
    print_line "配置文件：$INSTALL_PATH/data/config.json"
    print_line ""
    if [ -n "$ADMIN_USER" ] && [ -n "$ADMIN_PASS" ]; then
        print_line "账号信息："
        print_line "  默认账号：$ADMIN_USER"
        print_line "  初始密码：$ADMIN_PASS"
    else
        print_line "账号信息："
        print_line "  请通过 'alist-backup' 菜单选项5重置密码"
    fi
    echo -e "└────────────────────────────────────────────────────┐"
    if ! INSTALL_CLI; then
        echo -e "${YELLOW_COLOR}警告：命令行工具安装失败，但不影响 Alist Backup 的使用${RES}" >&2
        echo "WARNING: Failed to install CLI tools" >> "$LOG_FILE"
    fi
    echo -e "\n${GREEN_COLOR}启动服务中...${RES}"
    systemctl restart alist-backup || handle_error 1 "无法启动 alist-backup 服务"
    echo -e "管理: 在任意目录输入 ${GREEN_COLOR}alist-backup${RES} 打开管理菜单"
    echo -e "\n${YELLOW_COLOR}温馨提示：如果端口无法访问，请检查服务器安全组、防火墙和服务状态${RES}"
    echo "SUCCESS completed" >> "$LOG_FILE"
    exit 0
}

UPDATE() {
    echo "Executing UPDATE" >> "$LOG_FILE"
    if [ ! -f "$INSTALL_PATH/alist" ]; then
        handle_error 1 "未在 $INSTALL_PATH 找到 Alist Backup"
    fi
    echo -e "${GREEN_COLOR}开始更新 Alist Backup ($ARCH) ...${RES}"
    echo -e "${GREEN_COLOR}是否使用代理下载？（默认无代理）${RES}"
    echo -e "${GREEN_COLOR}代理地址必须以 https:// 开头，/ 结尾，例如 https://ghproxy.com/${RES}"
    read -p "请输入代理地址或按回车继续: " proxy_input
    if [ -n "$proxy_input" ]; then
        DOWNLOAD_URL="${proxy_input}${DOWNLOAD_URL#https://}"
        echo -e "${GREEN_COLOR}使用代理地址: $proxy_input${RES}"
        echo "Using proxy: $proxy_input" >> "$LOG_FILE"
    fi
    systemctl stop alist-backup || echo -e "${YELLOW_COLOR}警告：停止服务失败，继续尝试更新${RES}" >&2
    cp "$INSTALL_PATH/alist" /tmp/alist.bak || handle_error 1 "无法备份现有二进制文件"
    echo -e "${GREEN_COLOR}下载 Alist Backup ...${RES}"
    if ! download_file "$DOWNLOAD_URL" "/tmp/alist-backup.tar.gz"; then
        echo -e "${RED_COLOR}下载失败，更新终止${RES}" >&2
        mv /tmp/alist.bak "$INSTALL_PATH/alist"
        systemctl start alist-backup
        echo "ERROR: Update failed, download unsuccessful" >> "$LOG_FILE"
        exit 1
    fi
    if ! tar zxf "/tmp/alist-backup.tar.gz" -C "$INSTALL_PATH"; then
        echo -e "${RED_COLOR}解压失败，更新终止${RES}" >&2
        mv /tmp/alist.bak "$INSTALL_PATH/alist"
        systemctl start alist-backup
        rm -f "/tmp/alist-backup.tar.gz"
        echo "ERROR: Update failed, extraction unsuccessful" >> "$LOG_FILE"
        exit 1
    fi
    if [ -f "$INSTALL_PATH/alist" ]; then
        echo -e "${GREEN_COLOR}下载成功，正在更新${RES}"
        chmod +x "$INSTALL_PATH/alist" || handle_error 1 "无法设置执行权限"
    else
        echo -e "${RED_COLOR}更新失败，二进制文件未找到！${RES}" >&2
        mv /tmp/alist.bak "$INSTALL_PATH/alist"
        systemctl start alist-backup
        rm -f "/tmp/alist-backup.tar.gz"
        echo "ERROR: Update failed, binary not found" >> "$LOG_FILE"
        exit 1
    fi
    rm -f /tmp/alist-backup* /tmp/alist.bak
    echo -e "${GREEN_COLOR}启动 Alist Backup 进程${RES}"
    systemctl restart alist-backup || handle_error 1 "无法重启 alist-backup 服务"
    echo -e "${GREEN_COLOR}更新完成！${RES}"
    echo "UPDATE completed" >> "$LOG_FILE"
}

UNINSTALL() {
    echo "Executing UNINSTALL" >> "$LOG_FILE"
    if [ ! -f "$INSTALL_PATH/alist" ]; then
        handle_error 1 "未在 $INSTALL_PATH 找到 Alist Backup"
    fi
    echo -e "${RED_COLOR}警告：卸载后将删除本地 Alist Backup 目录、数据库文件及命令行工具！${RES}"
    read -p "是否确认卸载？[Y/n]: " choice
    case "${choice:-y}" in
        [yY]|"")
            echo -e "${GREEN_COLOR}开始卸载...${RES}"
            systemctl stop alist-backup >/dev/null 2>&1 || echo -e "${YELLOW_COLOR}警告：停止服务失败${RES}" >&2
            systemctl disable alist-backup >/dev/null 2>&1 || echo -e "${YELLOW_COLOR}警告：禁用服务失败${RES}" >&2
            rm -rf "$INSTALL_PATH" || echo -e "${YELLOW_COLOR}警告：删除 $INSTALL_PATH 失败${RES}" >&2
            rm -f /etc/systemd/system/alist-backup.service
            systemctl daemon-reload
            if [ -f "$MANAGER_PATH" ] || [ -L "$COMMAND_LINK" ]; then
                rm -f "$MANAGER_PATH" "$COMMAND_LINK" || {
                    echo -e "${YELLOW_COLOR}警告：删除命令行工具失败，请手动删除：${RES}" >&2
                    echo -e "${YELLOW_COLOR}1. $MANAGER_PATH${RES}" >&2
                    echo -e "${YELLOW_COLOR}2. $COMMAND_LINK${RES}" >&2
                    echo "WARNING: Failed to remove CLI tools" >> "$LOG_FILE"
                }
            }
            echo -e "${GREEN_COLOR}Alist Backup 已完全卸载${RES}"
            echo "UNINSTALL completed" >> "$LOG_FILE"
            ;;
        *)
            echo -e "${GREEN_COLOR}已取消卸载${RES}"
            echo "UNINSTALL cancelled" >> "$LOG_FILE"
            ;;
    esac
}

RESET_PASSWORD() {
    echo "Executing RESET_PASSWORD" >> "$LOG_FILE"
    if [ ! -f "$INSTALL_PATH/alist" ]; then
        handle_error 1 "系统未安装 Alist Backup，请先安装！"
    fi
    echo -e "\n请选择密码重置方式"
    echo -e "${GREEN_COLOR}1、生成随机密码${RES}"
    echo -e "${GREEN_COLOR}2、设置新密码${RES}"
    echo -e "${GREEN_COLOR}0、返回主菜单${RES}"
    read -p "请输入选项 [0-2]: " choice
    cd "$INSTALL_PATH" || handle_error 1 "无法切换到目录 $INSTALL_PATH"
    case "$choice" in
        1)
            echo -e "${GREEN_COLOR}正在生成随机密码...${RES}"
            echo -e "\n${GREEN_COLOR}账号信息：${RES}"
            ./alist admin random 2>&1 | grep -E "username:|password:" | sed 's/.*username:/账号: /' | sed 's/.*password:/密码: /' || handle_error 1 "无法生成随机密码"
            echo "Random password generated" >> "$LOG_FILE"
            exit 0
            ;;
        2)
            read -p "请输入新密码: " new_password
            if [ -z "$new_password" ]; then
                handle_error 1 "密码不能为空"
            fi
            echo -e "${GREEN_COLOR}正在设置新密码...${RES}"
            echo -e "\n${GREEN_COLOR}账号信息：${RES}"
            ./alist admin set "$new_password" 2>&1 | grep -E "username:|password:" | sed 's/.*username:/账号: /' | sed 's/.*password:/密码: /' || handle_error 1 "无法设置新密码"
            echo "New password set" >> "$LOG_FILE"
            exit 0
            ;;
        0)
            echo "Returned to main menu" >> "$LOG_FILE"
            return 0
            ;;
        *)
            echo -e "${RED_COLOR}无效的选项${RES}" >&2
            echo "ERROR: Invalid option in RESET_PASSWORD" >> "$LOG_FILE"
            exit 1
            ;;
    esac
}

MANAGER_PATH="/usr/local/sbin/alist-backup-manager"
COMMAND_LINK="/usr/local/bin/alist-backup"

INSTALL_CLI() {
    echo "Executing INSTALL_CLI" >> "$LOG_FILE"
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED_COLOR}错误：安装命令行工具需要 root 权限${RES}" >&2
        echo "ERROR: Root privileges required for INSTALL_CLI" >> "$LOG_FILE"
        return 1
    fi
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
    SCRIPT_NAME=$(basename "$0")
    SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"
    echo "Script path: $SCRIPT_PATH" >> "$LOG_FILE"
    if [ ! -f "$SCRIPT_PATH" ]; then
        echo -e "${RED_COLOR}错误：找不到源脚本文件 $SCRIPT_PATH${RES}" >&2
        echo "ERROR: Source script $SCRIPT_PATH not found" >> "$LOG_FILE"
        return 1
    fi
    mkdir -p "$(dirname "$MANAGER_PATH")" || {
        echo -e "${RED_COLOR}错误：无法创建目录 $(dirname "$MANAGER_PATH")${RES}" >&2
        echo "ERROR: Failed to create directory $(dirname "$MANAGER_PATH")" >> "$LOG_FILE"
        return 1
    }
    cp "$SCRIPT_PATH" "$MANAGER_PATH" || {
        echo -e "${RED_COLOR}错误：无法复制管理脚本到 $MANAGER_PATH${RES}" >&2
        echo "ERROR: Failed to copy script to $MANAGER_PATH" >> "$LOG_FILE"
        return 1
    }
    chmod 755 "$MANAGER_PATH" || {
        echo -e "${RED_COLOR}错误：设置 $MANAGER_PATH 权限失败${RES}" >&2
        echo "ERROR: Failed to set permissions for $MANAGER_PATH" >> "$LOG_FILE"
        rm -f "$MANAGER_PATH"
        return 1
    }
    chmod 755 "$(dirname "$MANAGER_PATH")" || {
        echo -e "${YELLOW_COLOR}警告：设置目录 $(dirname "$MANAGER_PATH") 权限失败${RES}" >&2
        echo "WARNING: Failed to set permissions for $(dirname "$MANAGER_PATH")" >> "$LOG_FILE"
    }
    mkdir -p "$(dirname "$COMMAND_LINK")" || {
        echo -e "${RED_COLOR}错误：无法创建目录 $(dirname "$COMMAND_LINK")${RES}" >&2
        echo "ERROR: Failed to create directory $(dirname "$COMMAND_LINK")" >> "$LOG_FILE"
        rm -f "$MANAGER_PATH"
        return 1
    }
    ln -sf "$MANAGER_PATH" "$COMMAND_LINK" || {
        echo -e "${RED_COLOR}错误：创建命令链接 $COMMAND_LINK 失败${RES}" >&2
        echo "ERROR: Failed to create symlink $COMMAND_LINK" >> "$LOG_FILE"
        rm -f "$MANAGER_PATH"
        return 1
    }
    echo -e "${GREEN_COLOR}命令行工具安装成功！${RES}"
    echo -e "\n现在你可以使用以下命令："
    echo -e "1. ${GREEN_COLOR}alist-backup${RES}          - 快捷命令"
    echo -e "2. ${GREEN_COLOR}alist-backup-manager${RES}  - 完整命令"
    echo "INSTALL_CLI completed" >> "$LOG_FILE"
    return 0
}

SHOW_MENU() {
    echo "Executing SHOW_MENU" >> "$LOG_FILE"
    INSTALL_PATH=$(GET_INSTALLED_PATH)
    echo -e "\n欢迎使用 Alist Backup 管理脚本 V3.0.0\n"
    echo -e "${GREEN_COLOR}1、安装 Alist Backup${RES}"
    echo -e "${GREEN_COLOR}2、更新 Alist Backup${RES}"
    echo -e "${GREEN_COLOR}3、卸载 Alist Backup${RES}"
    echo -e "${GREEN_COLOR}-------------------${RES}"
    echo -e "${GREEN_COLOR}4、查看状态${RES}"
    echo -e "${GREEN_COLOR}5、重置密码${RES}"
    echo -e "${GREEN_COLOR}-------------------${RES}"
    echo -e "${GREEN_COLOR}6、启动 Alist Backup${RES}"
    echo -e "${GREEN_COLOR}7、停止 Alist Backup${RES}"
    echo -e "${GREEN_COLOR}8、重启 Alist Backup${RES}"
    echo -e "${GREEN_COLOR}-------------------${RES}"
    echo -e "${GREEN_COLOR}0、退出脚本${RES}"
    read -p "请输入选项 [0-8]: " choice
    case "$choice" in
        1)
            INSTALL_PATH="/opt/alist-backup"
            CHECK
            INSTALL
            INIT
            SUCCESS
            return 0
            ;;
        2)
            UPDATE
            exit 0
            ;;
        3)
            UNINSTALL
            exit 0
            ;;
        4)
            if [ ! -f "$INSTALL_PATH/alist" ]; then
                echo -e "\r\n${RED_COLOR}错误：系统未安装 Alist Backup，请先安装！${RES}\r\n" >&2
                echo "ERROR: Alist Backup not installed" >> "$LOG_FILE"
                return 1
            fi
            if systemctl is-active alist-backup >/dev/null 2>&1; then
                echo -e "${GREEN_COLOR}Alist Backup 当前状态为：运行中${RES}"
                echo "Status: Running" >> "$LOG_FILE"
            else
                echo -e "${RED_COLOR}Alist Backup 当前状态为：停止${RES}"
                echo "Status: Stopped" >> "$LOG_FILE"
            fi
            return 0
            ;;
        5)
            RESET_PASSWORD
            return 0
            ;;
        6)
            if [ ! -f "$INSTALL_PATH/alist" ]; then
                echo -e "\r\n${RED_COLOR}错误：系统未安装 Alist Backup，请先安装！${RES}\r\n" >&2
                echo "ERROR: Alist Backup not installed" >> "$LOG_FILE"
                return 1
            fi
            systemctl start alist-backup || handle_error 1 "无法启动 alist-backup 服务"
            echo -e "${GREEN_COLOR}Alist Backup 已启动${RES}"
            echo "Service started" >> "$LOG_FILE"
            return 0
            ;;
        7)
            if [ ! -f "$INSTALL_PATH/alist" ]; then
                echo -e "\r\n${RED_COLOR}错误：系统未安装 Alist Backup，请先安装！${RES}\r\n" >&2
                echo "ERROR: Alist Backup not installed" >> "$LOG_FILE"
                return 1
            fi
            systemctl stop alist-backup || echo -e "${YELLOW_COLOR}警告：停止服务失败${RES}" >&2
            echo -e "${GREEN_COLOR}Alist Backup 已停止${RES}"
            echo "Service stopped" >> "$LOG_FILE"
            return 0
            ;;
        8)
            if [ ! -f "$INSTALL_PATH/alist" ]; then
                echo -e "\r\n${RED_COLOR}错误：系统未安装 Alist Backup，请先安装！${RES}\r\n" >&2
                echo "ERROR: Alist Backup not installed" >> "$LOG_FILE"
                return 1
            fi
            systemctl restart alist-backup || handle_error 1 "无法重启 alist-backup 服务"
            echo -e "${GREEN_COLOR}Alist Backup 已重启${RES}"
            echo "Service restarted" >> "$LOG_FILE"
            return 0
            ;;
        0)
            echo "Exiting script" >> "$LOG_FILE"
            exit 0
            ;;
        *)
            echo -e "${RED_COLOR}无效的选项${RES}" >&2
            echo "ERROR: Invalid option in SHOW_MENU" >> "$LOG_FILE"
            return 1
            ;;
    esac
}

echo "Script initialization complete" >> "$LOG_FILE"
if [ $# -eq 0 ]; then
    while true; do
        SHOW_MENU
        echo
        if [ $? -eq 0 ]; then
            sleep 3
        else
            sleep 5
        fi
        clear
    done
elif [ "$1" = "install" ]; then
    CHECK
    INSTALL
    INIT
    SUCCESS
elif [ "$1" = "update" ]; then
    if [ $# -gt 1 ]; then
        echo -e "${RED_COLOR}错误：update 命令不需要指定路径${RES}" >&2
        echo -e "正确用法: $0 update" >&2
        echo "ERROR: Invalid update command usage" >> "$LOG_FILE"
        exit 1
    fi
    UPDATE
elif [ "$1" = "uninstall" ]; then
    if [ $# -gt 1 ]; then
        echo -e "${RED_COLOR}错误：uninstall 命令不需要指定路径${RES}" >&2
        echo -e "正确用法: $0 uninstall" >&2
        echo "ERROR: Invalid uninstall command usage" >> "$LOG_FILE"
        exit 1
    fi
    UNINSTALL
else
    echo -e "${RED_COLOR}错误的命令${RES}" >&2
    echo -e "用法: $0 install [安装路径]    # 安装 Alist Backup" >&2
    echo -e "     $0 update              # 更新 Alist Backup" >&2
    echo -e "     $0 uninstall          # 卸载 Alist Backup" >&2
    echo -e "     $0                    # 显示交互菜单" >&2
    echo "ERROR: Invalid command" >> "$LOG_FILE"
    exit 1
fi
echo "Script execution completed" >> "$LOG_FILE"

# 脚本完整性标记
echo "END_OF_SCRIPT" >> "$LOG_FILE"
