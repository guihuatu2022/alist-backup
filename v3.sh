#!/bin/bash
###############################################################################
#
# Alist Manager Script
#
# Version: 1.0.3
# Last Updated: 2025-06-14
#
# Description: 
#   A management script for Alist (https://alist.nn.ci)
#   Provides installation, update, uninstallation and management functions
#
# Requirements:
#   - Linux with systemd
#   - Root privileges for installation
#   - curl, tar
#   - x86_64 or arm64 architecture
#
# Author: guihuatu2022 (adapted from Troray's original script)
# Repository: https://github.com/guihuatu2022/alist-backup
# License: MIT
#
###############################################################################

# 错误处理函数
handle_error() {
    local exit_code=$1
    local error_msg=$2
    echo -e "${RED_COLOR}错误：${error_msg}${RES}"
    exit ${exit_code}
}

# 检查依赖
if ! command -v curl >/dev/null 2>&1; then
    handle_error 1 "未找到 curl 命令，请先安装"
fi
if ! command -v tar >/dev/null 2>&1; then
    handle_error 1 "未找到 tar 命令，请先安装"
fi

# 配置部分
#######################
# GitHub 相关配置
GH_DOWNLOAD_URL="https://github.com/guihuatu2022/alist-backup/releases/download/alist-backup"
#######################

# 颜色配置
RED_COLOR='\e[1;31m'
GREEN_COLOR='\e[1;32m'
YELLOW_COLOR='\e[1;33m'
RES='\e[0m'

# 获取已安装的 Alist 路径
GET_INSTALLED_PATH() {
    if [ -f "/etc/systemd/system/alist.service" ]; then
        installed_path=$(grep "WorkingDirectory=" /etc/systemd/system/alist.service | cut -d'=' -f2)
        if [ -f "$installed_path/alist" ]; then
            echo "$installed_path"
            return 0
        fi
    fi
    echo "/opt/alist"
}

# 设置安装路径
if [ -z "$2" ]; then
    INSTALL_PATH='/opt/alist'
else
    INSTALL_PATH=${2%/}
    if ! [[ $INSTALL_PATH == */alist ]]; then
        INSTALL_PATH="$INSTALL_PATH/alist"
    fi
    parent_dir=$(dirname "$INSTALL_PATH")
    if [ ! -d "$parent_dir" ]; then
        mkdir -p "$parent_dir" || handle_error 1 "无法创建目录 $parent_dir"
    fi
    if ! [ -w "$parent_dir" ]; then
        handle_error 1 "目录 $parent_dir 没有写入权限"
    fi
fi

# 如果是更新或卸载操作，使用已安装的路径
if [ "$1" = "update" ] || [ "$1" = "uninstall" ]; then
    INSTALL_PATH=$(GET_INSTALLED_PATH)
fi

clear

# 获取平台架构
if command -v arch >/dev/null 2>&1; then
    platform=$(arch)
else
    platform=$(uname -m)
fi

ARCH="UNKNOWN"

if [ "$platform" = "x86_64" ]; then
    ARCH=amd64
elif [ "$platform" = "aarch64" ]; then
    ARCH=arm64
fi

# 权限和环境检查
if [ "$(id -u)" != "0" ]; then
    if [ "$1" = "install" ] || [ "$1" = "update" ] || [ "$1" = "uninstall" ]; then
        echo -e "\r\n${RED_COLOR}错误：请使用 root 权限运行此命令！${RES}\r\n"
        echo -e "提示：使用 ${GREEN_COLOR}sudo $0 $1${RES} 重试\r\n"
        exit 1
    fi
elif [ "$ARCH" == "UNKNOWN" ]; then
    echo -e "\r\n${RED_COLOR}出错了${RES}，一键安装目前仅支持 x86_64 和 arm64 平台。\r\n"
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
        mkdir -p "$INSTALL_PATH" || handle_error 1 "无法创建安装目录 $INSTALL_PATH"
    else
        rm -rf "$INSTALL_PATH" && mkdir -p "$INSTALL_PATH"
    fi
    echo -e "${GREEN_COLOR}安装目录准备就绪：$INSTALL_PATH${RES}"
}

# 全局变量存储账号密码
ADMIN_USER=""
ADMIN_PASS=""

# 下载函数，包含重试机制
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
            handle_error 1 "下载失败，已重试 $max_retries 次"
        fi
    done
}

# 获取代理地址（统一处理）
get_proxy() {
    echo -e "${GREEN_COLOR}是否使用 GitHub 代理？（默认无代理）${RES}"
    echo -e "${GREEN_COLOR}代理地址必须为 https 开头，斜杠 / 结尾 ${RES}"
    echo -e "${GREEN_COLOR}例如：https://ghproxy.com/ ${RES}"
    if [ -t 0 ]; then
        read -p "请输入代理地址或直接按回车继续: " proxy_input
    else
        read -p "请输入代理地址或直接按回车继续: " proxy_input </dev/tty
    fi
    if [ -n "$proxy_input" ]; then
        echo -e "${GREEN_COLOR}已使用代理地址: $proxy_input${RES}"
        echo "$proxy_input"
    else
        echo -e "${GREEN_COLOR}使用默认 GitHub 地址进行下载${RES}"
        echo ""
    fi
}

INSTALL() {
    CURRENT_DIR=$(pwd)
    GH_PROXY=$(get_proxy)
    echo -e "\r\n${GREEN_COLOR}下载 Alist ...${RES}"
    if ! download_file "${GH_PROXY}${GH_DOWNLOAD_URL}/alist-linux-${ARCH}.tar.gz" "/tmp/alist.tar.gz"; then
        handle_error 1 "下载失败！"
    fi
    if ! tar zxf /tmp/alist.tar.gz -C "$INSTALL_PATH/"; then
        rm -f /tmp/alist.tar.gz
        handle_error 1 "解压失败！"
    fi
    if [ -f "$INSTALL_PATH/alist" ]; then
        echo -e "${GREEN_COLOR}下载成功，正在安装...${RES}"
        cd "$INSTALL_PATH"
        chmod +x alist
        systemctl stop alist 2>/dev/null || true
        TEMP_LOG=$(mktemp)
        ./alist admin random >"$TEMP_LOG" 2>/dev/null
        ADMIN_USER=$(grep "username:" "$TEMP_LOG" | sed 's/.*username: \(.*\)/\1/')
        ADMIN_PASS=$(grep "password:" "$TEMP_LOG" | sed 's/.*password: \(.*\)/\1/')
        rm -f "$TEMP_LOG"
        cd "$CURRENT_DIR"
    else
        rm -rf "$INSTALL_PATH"
        mkdir -p "$INSTALL_PATH"
        rm -f /tmp/alist.tar.gz
        handle_error 1 "安装失败！"
    fi
    rm -f /tmp/alist*
}

INIT() {
    if [ ! -f "$INSTALL_PATH/alist" ]; then
        handle_error 1 "当前系统未安装 Alist"
    fi
    cat >/etc/systemd/system/alist.service <<EOF
[Unit]
Description=Alist service
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
    systemctl enable alist >/dev/null 2>&1
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
    print_line "Alist 安装成功！"
    print_line ""
    print_line "访问地址："
    print_line "  局域网：http://${LOCAL_IP}:5244/"
    print_line "  公网：  http://${PUBLIC_IP}:5244/"
    print_line "配置文件：$INSTALL_PATH/data/config.json"
    print_line ""
    if [ -n "$ADMIN_USER" ] && [ -n "$ADMIN_PASS" ]; then
        print_line "账号信息："
        print_line "默认账号：$ADMIN_USER"
        print_line "初始密码：$ADMIN_PASS"
    fi
    echo -e "└────────────────────────────────────────────────────┘"
    if ! INSTALL_CLI; then
        echo -e "${YELLOW_COLOR}警告：命令行工具安装失败，但不影响 Alist 的使用${RES}"
    fi
    echo -e "\n${GREEN_COLOR}启动服务中...${RES}"
    systemctl restart alist
    echo -e "管理: 在任意目录输入 ${GREEN_COLOR}alist${RES} 打开管理菜单"
    echo -e "\n${YELLOW_COLOR}温馨提示：如果端口无法访问，请检查服务器安全组、防火墙和服务状态${RES}"
    echo
    exit 0
}

UPDATE() {
    if [ ! -f "$INSTALL_PATH/alist" ]; then
        handle_error 1 "未在 $INSTALL_PATH 找到 Alist"
    fi
    echo -e "${GREEN_COLOR}开始更新 Alist ...${RES}"
    GH_PROXY=$(get_proxy)
    echo -e "${GREEN_COLOR}停止 Alist 进程${RES}\r\n"
    systemctl stop alist
    cp "$INSTALL_PATH/alist" /tmp/alist.bak
    echo -e "${GREEN_COLOR}下载 Alist ...${RES}"
    if ! download_file "${GH_PROXY}${GH_DOWNLOAD_URL}/alist-linux-${ARCH}.tar.gz" "/tmp/alist.tar.gz"; then
        echo -e "${RED_COLOR}下载失败，更新终止${RES}"
        echo -e "${GREEN_COLOR}正在恢复之前的版本...${RES}"
        mv /tmp/alist.bak "$INSTALL_PATH/alist"
        systemctl start alist
        rm -f /tmp/alist.tar.gz
        exit 1
    fi
    if ! tar zxf /tmp/alist.tar.gz -C "$INSTALL_PATH/"; then
        echo -e "${RED_COLOR}解压失败，更新终止${RES}"
        echo -e "${GREEN_COLOR}正在恢复之前的版本...${RES}"
        mv /tmp/alist.bak "$INSTALL_PATH/alist"
        systemctl start alist
        rm -f /tmp/alist.tar.gz
        exit 1
    fi
    if [ -f "$INSTALL_PATH/alist" ]; then
        echo -e "${GREEN_COLOR}下载成功，正在更新${RES}"
        chmod +x "$INSTALL_PATH/alist"
    else
        echo -e "${RED_COLOR}更新失败！${RES}"
        echo -e "${GREEN_COLOR}正在恢复之前的版本...${RES}"
        mv /tmp/alist.bak "$INSTALL_PATH/alist"
        systemctl start alist
        rm -f /tmp/alist.tar.gz
        exit 1
    fi
    rm -f /tmp/alist.tar.gz /tmp/alist.bak
    echo -e "${GREEN_COLOR}启动 Alist 进程${RES}\r\n"
    systemctl restart alist
    echo -e "${GREEN_COLOR}更新完成！${RES}"
}

UNINSTALL() {
    if [ ! -f "$INSTALL_PATH/alist" ]; then
        handle_error 1 "未在 $INSTALL_PATH 找到 Alist"
    fi
    echo -e "${RED_COLOR}警告：卸载后将删除本地 Alist 目录、数据库文件及命令行工具！${RES}"
    if [ -t 0 ]; then
        read -p "是否确认卸载？[Y/n]: " choice
    else
        read -p "是否确认卸载？[Y/n]: " choice </dev/tty
    fi
    case "${choice:-y}" in
        [yY]|"")
            echo -e "${GREEN_COLOR}开始卸载...${RES}"
            echo -e "${GREEN_COLOR}停止 Alist 进程${RES}"
            systemctl stop alist
            systemctl disable alist
            echo -e "${GREEN_COLOR}删除 Alist 文件${RES}"
            rm -rf "$INSTALL_PATH"
            rm -f /etc/systemd/system/alist.service
            systemctl daemon-reload
            if [ -f "$MANAGER_PATH" ] || [ -L "$COMMAND_LINK" ]; then
                echo -e "${GREEN_COLOR}删除命令行工具${RES}"
                rm -f "$MANAGER_PATH" "$COMMAND_LINK" || {
                    echo -e "${YELLOW_COLOR}警告：删除命令行工具失败，请手动删除：${RES}"
                    echo -e "${YELLOW_COLOR}1. $MANAGER_PATH${RES}"
                    echo -e "${YELLOW_COLOR}2. $COMMAND_LINK${RES}"
                }
            fi
            echo -e "${GREEN_COLOR}Alist 已完全卸载${RES}"
            ;;
        *)
            echo -e "${GREEN_COLOR}已取消卸载${RES}"
            ;;
    esac
}

RESET_PASSWORD() {
    if [ ! -f "$INSTALL_PATH/alist" ]; then
        echo -e "\r\n${RED_COLOR}错误：系统未安装 Alist，请先安装！${RES}\r\n"
        exit 1
    fi
    echo -e "\n请选择密码重置方式："
    echo -e "${GREEN_COLOR}1、生成随机密码${RES}"
    echo -e "${GREEN_COLOR}2、设置新密码${RES}"
    echo -e "${GREEN_COLOR}0、返回主菜单${RES}"
    echo
    if [ -t 0 ]; then
        read -p "请输入选项 [0-2]: " choice
    else
        read -p "请输入选项 [0-2]: " choice </dev/tty
    fi
    cd "$INSTALL_PATH"
    systemctl stop alist >/dev/null 2>&1
    case "$choice" in
        1)
            echo -e "${GREEN_COLOR}正在生成随机密码...${RES}"
            echo -e "\n${GREEN_COLOR}账号信息：${RES}"
            TEMP_LOG=$(mktemp)
            ./alist admin random >"$TEMP_LOG" 2>/dev/null
            grep -E "username:|password:" "$TEMP_LOG" | sed 's/.*username:/账号: /; s/.*password:/密码: /'
            rm -f "$TEMP_LOG"
            systemctl start alist
            exit 0
            ;;
        2)
            if [ -t 0 ]; then
                read -p "请输入新密码: " new_password
            else
                read -p "请输入新密码: " new_password </dev/tty
            fi
            if [ -z "$new_password" ]; then
                echo -e "${RED_COLOR}错误：密码不能为空${RES}"
                systemctl start alist
                exit 1
            fi
            echo -e "${GREEN_COLOR}正在设置新密码...${RES}"
            echo -e "\n${GREEN_COLOR}账号信息：${RES}"
            TEMP_LOG=$(mktemp)
            ./alist admin set "$new_password" >"$TEMP_LOG" 2>/dev/null
            grep "username:" "$TEMP_LOG" | sed 's/.*username:/账号: /'
            echo "密码: $new_password"
            rm -f "$TEMP_LOG"
            systemctl start alist
            exit 0
            ;;
        0)
            systemctl start alist
            return 0
            ;;
        *)
            echo -e "${RED_COLOR}无效的选项${RES}"
            systemctl start alist
            exit 1
            ;;
    esac
}

MANAGER_PATH="/usr/local/sbin/alist-manager"
COMMAND_LINK="/usr/local/bin/alist"

INSTALL_CLI() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED_COLOR}错误：安装命令行工具需要 root 权限${RES}"
        return 1
    fi
    TEMP_SCRIPT=$(mktemp)
    if ! download_file "https://raw.githubusercontent.com/guihuatu2022/alist-backup/main/v3.sh" "$TEMP_SCRIPT"; then
        echo -e "${RED_COLOR}错误：下载管理脚本失败${RES}"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    mkdir -p "$(dirname "$MANAGER_PATH")" || {
        echo -e "${RED_COLOR}错误：无法创建目录 $(dirname "$MANAGER_PATH")${RES}"
        rm -f "$TEMP_SCRIPT"
        return 1
    }
    cp "$TEMP_SCRIPT" "$MANAGER_PATH" || {
        echo -e "${RED_COLOR}错误：无法复制管理脚本${RES}"
        rm -f "$TEMP_SCRIPT"
        return 1
    }
    chmod 755 "$MANAGER_PATH" || {
        echo -e "${RED_COLOR}错误：设置权限失败${RES}"
        rm -f "$MANAGER_PATH" "$TEMP_SCRIPT"
        return 1
    }
    chmod 755 "$(dirname "$MANAGER_PATH")" || {
        echo -e "${YELLOW_COLOR}警告：设置目录权限失败${RES}"
    }
    mkdir -p "$(dirname "$COMMAND_LINK")" || {
        echo -e "${RED_COLOR}错误：无法创建目录 $(dirname "$COMMAND_LINK")${RES}"
        rm -f "$MANAGER_PATH" "$TEMP_SCRIPT"
        return 1
    }
    ln -sf "$MANAGER_PATH" "$COMMAND_LINK" || {
        echo -e "${RED_COLOR}错误：创建命令链接失败${RES}"
        rm -f "$MANAGER_PATH" "$TEMP_SCRIPT"
        return 1
    }
    rm -f "$TEMP_SCRIPT"
    echo -e "${GREEN_COLOR}命令行工具安装成功！${RES}"
    echo -e "\n现在你可以："
    echo -e "1. ${GREEN_COLOR}alist${RES}          - 快捷命令"
    echo -e "2. ${GREEN_COLOR}alist-manager${RES}  - 完整命令"
    return 0
}

SHOW_MENU() {
    INSTALL_PATH=$(GET_INSTALLED_PATH)
    echo -e "\n欢迎使用 Alist 管理脚本\n"
    echo -e "${GREEN_COLOR}1、安装 Alist${RES}"
    echo -e "${GREEN_COLOR}2、更新 Alist${RES}"
    echo -e "${GREEN_COLOR}3、卸载 Alist${RES}"
    echo -e "${GREEN_COLOR}-------------------${RES}"
    echo -e "${GREEN_COLOR}4、查看状态${RES}"
    echo -e "${GREEN_COLOR}5、重置密码${RES}"
    echo -e "${GREEN_COLOR}-------------------${RES}"
    echo -e "${GREEN_COLOR}6、启动 Alist${RES}"
    echo -e "${GREEN_COLOR}7、停止 Alist${RES}"
    echo -e "${GREEN_COLOR}8、重启 Alist${RES}"
    echo -e "${GREEN_COLOR}-------------------${RES}"
    echo -e "${GREEN_COLOR}0、退出脚本${RES}"
    echo
    if [ -t 0 ]; then
        read -p "请输入选项 [0-8]: " choice
    else
        read -p "请输入选项 [0-8]: " choice </dev/tty
    fi
    case "$choice" in
        1)
            INSTALL_PATH='/opt/alist'
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
                echo -e "\r\n${RED_COLOR}错误：系统未安装 Alist，请先安装！${RES}\r\n"
                return 1
            fi
            if systemctl is-active alist >/dev/null 2>&1; then
                echo -e "${GREEN_COLOR}Alist 当前状态为：运行中${RES}"
            else
                echo -e "${RED_COLOR}Alist 当前状态为：停止${RES}"
            fi
            return 0
            ;;
        5)
            RESET_PASSWORD
            return 0
            ;;
        6)
            if [ ! -f "$INSTALL_PATH/alist" ]; then
                echo -e "\r\n${RED_COLOR}错误：系统未安装 Alist，请先安装！${RES}\r\n"
                return 1
            fi
            systemctl start alist
            echo -e "${GREEN_COLOR}Alist 已启动${RES}"
            return 0
            ;;
        7)
            if [ ! -f "$INSTALL_PATH/alist" ]; then
                echo -e "\r\n${RED_COLOR}错误：系统未安装 Alist，请先安装！${RES}\r\n"
                return 1
            fi
            systemctl stop alist
            echo -e "${GREEN_COLOR}Alist 已停止${RES}"
            return 0
            ;;
        8)
            if [ ! -f "$INSTALL_PATH/alist" ]; then
                echo -e "\r\n${RED_COLOR}错误：系统未安装 Alist，请先安装！${RES}\r\n"
                return 1
            fi
            systemctl restart alist
            echo -e "${GREEN_COLOR}Alist 已重启${RES}"
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
    echo -e "用法: $0 install [安装路径]    # 安装 Alist"
    echo -e "     $0 update              # 更新 Alist"
    echo -e "     $0 uninstall          # 卸载 Alist"
    echo -e "     $0                    # 显示交互菜单"
    exit 1
fi
