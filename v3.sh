#!/bin/bash
###############################################################################
#
# Alist Backup Manager Script
#
# Version: 1.0.0
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
#   - x86_64 architecture
#
# Author: Adapted from Troray's Alist script
# Repository: N/A
# License: MIT
#
###############################################################################

# Error handling function
handle_error() {
    local exit_code=$1
    local error_msg=$2
    echo -e "${RED_COLOR}错误：${error_msg}${RES}"
    exit ${exit_code}
}

# Check for curl
if ! command -v curl >/dev/null 2>&1; then
    handle_error 1 "未找到 curl 命令，请先安装"
fi

# Configuration
#######################
# Download URL for Alist Backup
BACKUP_DOWNLOAD_URL="https://github.com/guihuatu2022/alist-backup/releases/download/alist-backup/alist-linux-amd64.tar.gz"
#######################

# Color configuration
RED_COLOR='\e[1;31m'
GREEN_COLOR='\e[1;32m'
YELLOW_COLOR='\e[1;33m'
RES='\e[0m'

# Function to get installed Alist Backup path
GET_INSTALLED_PATH() {
    if [ -f "/etc/systemd/system/alist-backup.service" ]; then
        installed_path=$(grep "WorkingDirectory=" /etc/systemd/system/alist-backup.service | cut -d'=' -f2)
        if [ -f "$installed_path/alist" ]; then
            echo "$installed_path"
            return 0
        fi
    fi
    echo "/opt/alist-backup"
}

# Set installation path
if [ ! -n "$2" ]; then
    INSTALL_PATH='/opt/alist-backup'
else
    INSTALL_PATH=${2%/}
    if ! [[ $INSTALL_PATH == */alist-backup ]]; then
        INSTALL_PATH="$INSTALL_PATH/alist-backup"
    fi
    parent_dir=$(dirname "$INSTALL_PATH")
    if [ ! -d "$parent_dir" ]; then
        mkdir -p "$parent_dir" || handle_error 1 "无法创建目录 $parent_dir"
    fi
    if ! [ -w "$parent_dir" ]; then
        handle_error 1 "目录 $parent_dir 没有写入权限"
    fi
fi

# Use installed path for update or uninstall
if [ "$1" = "update" ] || [ "$1" = "uninstall" ]; then
    INSTALL_PATH=$(GET_INSTALLED_PATH)
fi

clear

# Get platform architecture
if command -v arch >/dev/null 2>&1; then
    platform=$(arch)
else
    platform=$(uname -m)
fi

ARCH="UNKNOWN"
if [ "$platform" = "x86_64" ]; then
    ARCH=amd64
fi

# Permission and environment checks
if [ "$(id -u)" != "0" ]; then
    if [ "$1" = "install" ] || [ "$1" = "update" ] || [ "$1" = "uninstall" ]; then
        echo -e "\r\n${RED_COLOR}错误：请使用 root 权限运行此命令！${RES}\r\n"
        echo -e "提示：使用 ${GREEN_COLOR}sudo $0 $1${RES} 重试\r\n"
        exit 1
    fi
elif [ "$ARCH" == "UNKNOWN" ]; then
    echo -e "\r\n${RED_COLOR}出错了${RES}，一键安装目前仅支持 x86_64 平台。\r\n"
    exit 1
elif ! command -v systemctl >/dev/null 2>&1; then
    echo -e "\r\n${RED_COLOR}出错了${RES}，无法确定你当前的 Linux 发行版。\r\n建议手动安装。\r\n"
    exit 1
fi

CHECK() {
    if [ ! -d "$(dirname "$INSTALL_PATH")" ]; then
        echo -e "${GREEN_COLOR}目录不存在，正在创建...${RES}"
        mkdir -p "$(dirname "$INSTALL_PATH")" || handle_error 1 "无法创建目录 $(dirname "$INSTALL_PATH")"
    fi
    if [ -f "$INSTALL_PATH/alist" ]; then
        echo "此位置已经安装，请选择其他位置，或使用更新命令"
        exit 0
    fi
    if [ ! -d "$INSTALL_PATH/" ]; then
        mkdir -p $INSTALL_PATH || handle_error 1 "无法创建安装目录 $INSTALL_PATH"
    else
        rm -rf $INSTALL_PATH && mkdir -p $INSTALL_PATH
    fi
    echo -e "${GREEN_COLOR}安装目录准备就绪：$INSTALL_PATH${RES}"
}

# Download function with retry mechanism
download_file() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_count=0
    local wait_time=5
    while [ $retry_count -lt $max_retries ]; do
        if curl -L --connect-timeout 10 --retry 3 --retry-delay 3 "$url" -o "$output"; then
            if [ -f "$output" ] && [ -s "$output" ]; then
                return 0
            fi
        fi
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo -e "${YELLOW_COLOR}下载失败，${wait_time} 秒后进行第 $((retry_count + 1)) 次重试...${RES}"
            sleep $wait_time
            wait_time=$((wait_time + 5))
        else
            echo -e "${RED_COLOR}下载失败，已重试 $max_retries 次${RES}"
            return 1
        fi
    done
    return 1
}

INSTALL() {
    CURRENT_DIR=$(pwd)
    echo -e "${GREEN_COLOR}下载 Alist Backup ...${RES}"
    if ! download_file "${BACKUP_DOWNLOAD_URL}" "/tmp/alist-backup.tar.gz"; then
        handle_error 1 "下载失败！"
    fi
    if ! tar zxf /tmp/alist-backup.tar.gz -C $INSTALL_PATH/; then
        echo -e "${RED_COLOR}解压失败！${RES}"
        rm -f /tmp/alist-backup.tar.gz
        exit 1
    fi
    if [ -f $INSTALL_PATH/alist ]; then
        echo -e "${GREEN_COLOR}下载成功，正在安装...${RES}"
    else
        echo -e "${RED_COLOR}安装失败！${RES}"
        rm -rf $INSTALL_PATH
        mkdir -p $INSTALL_PATH
        exit 1
    fi
    rm -f /tmp/alist-backup*
}

INIT() {
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

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable alist-backup >/dev/null 2>&1
}

SUCCESS() {
    clear
    print_line() {
        local text="$1"
        local width=51
        printf "│ %-${width}s │\n" "$text"
    }
    LOCAL_IP=$(ip addr show | grep -w inet | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -n1)
    PUBLIC_IP=$(curl -s4 ip.sb || curl -s4 ifconfig.me || echo "获取失败")
    echo -e "┌────────────────────────────────────────────────────┐"
    print_line "Alist Backup 安装成功！"
    print_line ""
    print_line "访问地址："
    print_line "  局域网：http://${LOCAL_IP}:5244/"
    print_line "  公网：  http://${PUBLIC_IP}:5244/"
    print_line "配置文件：$INSTALL_PATH/data/config.json"
    print_line ""
    echo -e "└────────────────────────────────────────────────────┘"
    if ! INSTALL_CLI; then
        echo -e "${YELLOW_COLOR}警告：命令行工具安装失败，但不影响 Alist Backup 的使用${RES}"
    fi
    echo -e "\n${GREEN_COLOR}启动服务中...${RES}"
    systemctl restart alist-backup
    echo -e "管理: 在任意目录输入 ${GREEN_COLOR}alist-backup${RES} 打开管理菜单"
    echo -e "\n${YELLOW_COLOR}温馨提示：如果端口无法访问，请检查服务器安全组、防火墙和服务状态${RES}"
    exit 0
}

UPDATE() {
    if [ ! -f "$INSTALL_PATH/alist" ]; then
        handle_error 1 "未在 $INSTALL_PATH 找到 Alist Backup"
    fi
    echo -e "${GREEN_COLOR}开始更新 Alist Backup ...${RES}"
    systemctl stop alist-backup
    cp $INSTALL_PATH/alist /tmp/alist.bak
    echo -e "${GREEN_COLOR}下载 Alist Backup ...${RES}"
    if ! download_file "${BACKUP_DOWNLOAD_URL}" "/tmp/alist-backup.tar.gz"; then
        echo -e "${RED_COLOR}下载失败，更新终止${RES}"
        mv /tmp/alist.bak $INSTALL_PATH/alist
        systemctl start alist-backup
        exit 1
    fi
    if ! tar zxf /tmp/alist-backup.tar.gz -C $INSTALL_PATH/; then
        echo -e "${RED_COLOR}解压失败，更新终止${RES}"
        mv /tmp/alist.bak $INSTALL_PATH/alist
        systemctl start alist-backup
        rm -f /tmp/alist-backup.tar.gz
        exit 1
    fi
    if [ -f $INSTALL_PATH/alist ]; then
        echo -e "${GREEN_COLOR}下载成功，正在更新${RES}"
    else
        echo -e "${RED_COLOR}更新失败！${RES}"
        mv /tmp/alist.bak $INSTALL_PATH/alist
        systemctl start alist-backup
        rm -f /tmp/alist-backup.tar.gz
        exit 1
    fi
    rm -f /tmp/alist-backup.tar.gz /tmp/alist.bak
    echo -e "${GREEN_COLOR}启动 Alist Backup 进程${RES}"
    systemctl restart alist-backup
    echo -e "${GREEN_COLOR}更新完成！${RES}"
}

UNINSTALL() {
    if [ ! -f "$INSTALL_PATH/alist" ]; then
        handle_error 1 "未在 $INSTALL_PATH 找到 Alist Backup"
    fi
    echo -e "${RED_COLOR}警告：卸载后将删除本地 Alist Backup 目录、数据库文件及命令行工具！${RES}"
    read -p "是否确认卸载？[Y/n]: " choice
    case "${choice:-y}" in
        [yY]|"")
            echo -e "${GREEN_COLOR}开始卸载...${RES}"
            systemctl stop alist-backup
            systemctl disable alist-backup
            rm -rf $INSTALL_PATH
            rm -f /etc/systemd/system/alist-backup.service
            systemctl daemon-reload
            if [ -f "$MANAGER_PATH" ] || [ -L "$COMMAND_LINK" ]; then
                rm -f "$MANAGER_PATH" "$COMMAND_LINK" || {
                    echo -e "${YELLOW_COLOR}警告：删除命令行工具失败，请手动删除：${RES}"
                    echo -e "${YELLOW_COLOR}1. $MANAGER_PATH${RES}"
                    echo -e "${YELLOW_COLOR}2. $COMMAND_LINK${RES}"
                }
            }
            echo -e "${GREEN_COLOR}Alist Backup 已完全卸载${RES}"
            ;;
        *)
            echo -e "${GREEN_COLOR}已取消卸载${RES}"
            ;;
    esac
}

RESET_PASSWORD() {
    if [ ! -f "$INSTALL_PATH/alist" ]; then
        handle_error 1 "系统未安装 Alist Backup，请先安装！"
    fi
    echo -e "\n请选择密码重置方式"
    echo -e "${GREEN_COLOR}1、生成随机密码${RES}"
    echo -e "${GREEN_COLOR}2、设置新密码${RES}"
    echo -e "${GREEN_COLOR}0、返回主菜单${RES}"
    read -p "请输入选项 [0-2]: " choice
    cd $INSTALL_PATH
    case "$choice" in
        1)
            echo -e "${GREEN_COLOR}正在生成随机密码...${RES}"
            echo -e "\n${GREEN_COLOR}账号信息：${RES}"
            ./alist admin random 2>&1 | grep -E "username:|password:" | sed 's/.*username:/账号: /' | sed 's/.*password:/密码: /'
            exit 0
            ;;
        2)
            read -p "请输入新密码: " new_password
            if [ -z "$new_password" ]; then
                handle_error 1 "密码不能为空"
            fi
            echo -e "${GREEN_COLOR}正在设置新密码...${RES}"
            echo -e "\n${GREEN_COLOR}账号信息：${RES}"
            ./alist admin set "$new_password" 2>&1 | grep -E "username:|password:" | sed 's/.*username:/账号: /' | sed 's/.*password:/密码: /'
            exit 0
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED_COLOR}无效的选项${RES}"
            exit 1
            ;;
    esac
}

MANAGER_PATH="/usr/local/sbin/alist-backup-manager"
COMMAND_LINK="/usr/local/bin/alist-backup"

INSTALL_CLI() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED_COLOR}错误：安装命令行工具需要 root 权限${RES}"
        return 1
    fi
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
    SCRIPT_NAME=$(basename "$0")
    SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"
    if [ ! -f "$SCRIPT_PATH" ]; then
        echo -e "${RED_COLOR}错误：找不到源脚本文件${RES}"
        return 1
    fi
    mkdir -p "$(dirname "$MANAGER_PATH")" || {
        echo -e "${RED_COLOR}错误：无法创建目录 $(dirname "$MANAGER_PATH")${RES}"
        return 1
    }
    cp "$SCRIPT_PATH" "$MANAGER_PATH" || {
        echo -e "${RED_COLOR}错误：无法复制管理脚本${RES}"
        return 1
    }
    chmod 755 "$MANAGER_PATH" || {
        echo -e "${RED_COLOR}错误：设置权限失败${RES}"
        rm -f "$MANAGER_PATH"
        return 1
    }
    chmod 755 "$(dirname "$MANAGER_PATH")" || {
        echo -e "${YELLOW_COLOR}警告：设置目录权限失败${RES}"
    }
    mkdir -p "$(dirname "$COMMAND_LINK")" || {
        echo -e "${RED_COLOR}错误：无法创建目录 $(dirname "$COMMAND_LINK")${RES}"
        return 1
    }
    ln -sf "$MANAGER_PATH" "$COMMAND_LINK" || {
        echo -e "${RED_COLOR}错误：创建命令链接失败${RES}"
        rm -f "$MANAGER_PATH"
        return 1
    }
    echo -e "${GREEN_COLOR}命令行工具安装成功！${RES}"
    echo -e "\n现在你可以使用以下命令："
    echo -e "1. ${GREEN_COLOR}alist-backup${RES}          - 快捷命令"
    echo -e "2. ${GREEN_COLOR}alist-backup-manager${RES}  - 完整命令"
    return 0
}

SHOW_MENU() {
    INSTALL_PATH=$(GET_INSTALLED_PATH)
    echo -e "\n欢迎使用 Alist Backup 管理脚本\n"
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
            INSTALL_PATH='/opt/alist-backup'
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
                echo -e "\r\n${RED_COLOR}错误：系统未安装 Alist Backup，请先安装！${RES}\r\n"
                return 1
            fi
            if systemctl is-active alist-backup >/dev/null 2>&1; then
                echo -e "${GREEN_COLOR}Alist Backup 当前状态为：运行中${RES}"
            else
                echo -e "${RED_COLOR}Alist Backup 当前状态为：停止${RES}"
            fi
            return 0
            ;;
        5)
            RESET_PASSWORD
            return 0
            ;;
        6)
            if [ ! -f "$INSTALL_PATH/alist" ]; then
                echo -e "\r\n${RED_COLOR}错误：系统未安装 Alist Backup，请先安装！${RES}\r\n"
                return 1
            fi
            systemctl start alist-backup
            echo -e "${GREEN_COLOR}Alist Backup 已启动${RES}"
            return 0
            ;;
        7)
            if [ ! -f "$INSTALL_PATH/alist" ]; then
                echo -e "\r\n${RED_COLOR}错误：系统未安装 Alist Backup，请先安装！${RES}\r\n"
                return 1
            fi
            systemctl stop alist-backup
            echo -e "${GREEN_COLOR}Alist Backup 已停止${RES}"
            return 0
            ;;
        8)
            if [ ! -f "$INSTALL_PATH/alist" ]; then
                echo -e "\r\n${RED_COLOR}错误：系统未安装 Alist Backup，请先安装！${RES}\r\n"
                return 1
            fi
            systemctl restart alist-backup
            echo -e "${GREEN_COLOR}Alist Backup 已重启${RES}"
            return 0
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED_COLOR}无效的选项${RES}"
            return 1
            ;;
    esac
}

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
        echo -e "${RED_COLOR}错误：update 命令不需要指定路径${RES}"
        echo -e "正确用法: $0 update"
        exit 1
    fi
    UPDATE
elif [ "$1" = "uninstall" ]; then
    if [ $# -gt 1 ]; then
        echo -e "${RED_COLOR}错误：uninstall 命令不需要指定路径${RES}"
        echo -e "正确用法: $0 uninstall"
        exit 1
    fi
    UNINSTALL
else
    echo -e "${RED_COLOR}错误的命令${RES}"
    echo -e "用法: $0 install [安装路径]    # 安装 Alist Backup"
    echo -e "     $0 update              # 更新 Alist Backup"
    echo -e "     $0 uninstall          # 卸载 Alist Backup"
    echo -e "     $0                    # 显示交互菜单"
fi
