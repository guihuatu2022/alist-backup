#!/bin/bash

# AList 安装脚本：从个人仓库安装，支持管理菜单、自定义路径，针对 v3.x
# 仓库: https://github.com/guihuatu2022/alist-backup
# 版本: 1.0.0
# 最后更新: 2025-06-14

# 错误处理函数
handle_error() {
    local exit_code=$1
    local error_msg=$2
    echo -e "${RED_COLOR}错误：${error_msg}${RES}"
    exit ${exit_code}
}

# 颜色配置
RED_COLOR='\e[1;31m'
GREEN_COLOR='\e[1;32m'
YELLOW_COLOR='\e[1;33m'
RES='\e[0m'

# 环境检查
if ! command -v curl >/dev/null 2>&1; then
    handle_error 1 "未找到 curl 命令，请先安装"
fi
if ! command -v tar >/dev/null 2>&1; then
    handle_error 1 "未找到 tar 命令，请先安装"
fi
if ! command -v systemctl >/dev/null 2>&1; then
    handle_error 1 "未找到 systemctl，当前系统不支持 systemd"
fi

# 获取已安装路径
GET_INSTALLED_PATH() {
    if [ -f "/etc/systemd/system/alist.service" ]; then
        local installed_path=$(grep "WorkingDirectory=" /etc/systemd/system/alist.service | cut -d'=' -f2)
        if [ -f "$installed_path/alist" ]; then
            echo "$installed_path"
            return 0
        fi
    fi
    echo "/opt/alist"
}

# 设置安装路径
if [ -z "$2" ]; then
    INSTALL_PATH="/opt/alist"
else
    INSTALL_PATH=${2%/}
    if ! [[ $INSTALL_PATH == */alist ]]; then
        INSTALL_PATH="$INSTALL_PATH/alist"
    fi
    parent_dir=$(dirname "$INSTALL_PATH")
    mkdir -p "$parent_dir" || handle_error 1 "无法创建目录 $parent_dir"
    if ! [ -w "$parent_dir" ]; then
        handle_error 1 "目录 $parent_dir 没有写入权限"
    fi
fi

# 更新或卸载时使用已安装路径
if [ "$1" = "update" ] || [ "$1" = "uninstall" ]; then
    INSTALL_PATH=$(GET_INSTALLED_PATH)
fi

MANAGER_PATH="/usr/local/sbin/alist-manager"
COMMAND_LINK="/usr/local/bin/alist"

# 获取架构
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH_TYPE="amd64";;
    aarch64|arm64) ARCH_TYPE="arm64";;
    *) handle_error 1 "不支持的架构: $ARCH，仅支持 x86_64 和 arm64";;
esac

# 仓库配置
REPO_URL="https://github.com/guihuatu2022/alist-backup/releases/download/alist-backup"
BINARY_PREFIX="alist-linux-${ARCH_TYPE}.tar.gz"

# 安装依赖
install_deps() {
    echo -e "${GREEN_COLOR}安装依赖...${RES}"
    case $(grep -oE '^ID=.*$' /etc/os-release | cut -d'=' -f2) in
        ubuntu|debian) apt update && apt install -y curl tar;;
        centos|rhel|fedora) yum install -y curl tar || dnf install -y curl tar;;
        *) handle_error 1 "不支持的发行版";;
    esac
}

# 下载文件（带重试机制）
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
            echo -e "${YELLOW_COLOR}下载失败，${wait_time}秒后重试（第$((retry_count + 1))次）...${RES}"
            sleep $wait_time
            wait_time=$((wait_time + 5))
        else
            handle_error 1 "下载失败，已重试 $max_retries 次"
        fi
    done
}

# 检查安装目录
CHECK() {
    if [ -f "$INSTALL_PATH/alist" ]; then
        handle_error 1 "此位置已安装，请选择其他路径或使用 update 命令"
    fi
    mkdir -p "$INSTALL_PATH" || handle_error 1 "无法创建安装目录 $INSTALL_PATH"
    echo -e "${GREEN_COLOR}安装目录准备就绪：$INSTALL_PATH${RES}"
}

# 安装 AList
INSTALL() {
    CURRENT_DIR=$(pwd)
    echo -e "${GREEN_COLOR}是否使用 GitHub 代理？（默认无代理）${RES}"
    read -p "请输入代理地址（如 https://ghproxy.com/）或直接回车: " proxy_input
    if [ -n "$proxy_input" ]; then
        GH_PROXY="$proxy_input"
        echo -e "${GREEN_COLOR}使用代理: $GH_PROXY${RES}"
    else
        GH_PROXY=""
        echo -e "${GREEN_COLOR}使用默认地址${RES}"
    fi

    echo -e "${GREEN_COLOR}下载 AList...${RES}"
    download_file "${GH_PROXY}${REPO_URL}/${BINARY_PREFIX}" "/tmp/alist.tar.gz"
    tar zxf "/tmp/alist.tar.gz" -C "$INSTALL_PATH" || {
        rm -f /tmp/alist.tar.gz
        handle_error 1 "解压失败"
    }
    if [ -f "$INSTALL_PATH/alist" ]; then
        chmod +x "$INSTALL_PATH/alist"
        cd "$INSTALL_PATH"
        systemctl stop alist 2>/dev/null || true
        ACCOUNT_INFO=$($INSTALL_PATH/alist admin random 2>&1)
        ADMIN_USER=$(echo "$ACCOUNT_INFO" | grep "username:" | sed 's/.*username: \(.*\)/\1/')
        ADMIN_PASS=$(echo "$ACCOUNT_INFO" | grep "password:" | sed 's/.*password: \(.*\)/\1/')
        cd "$CURRENT_DIR"
        rm -f /tmp/alist.tar.gz
    else
        rm -f /tmp/alist.tar.gz
        handle_error 1 "安装失败，二进制文件未找到"
    fi
}

# 初始化 systemd 服务
INIT() {
    cat > /etc/systemd/system/alist.service <<EOF
[Unit]
Description=AList File Server
After=network.target
[Service]
Type=simple
WorkingDirectory=$INSTALL_PATH
ExecStart=$INSTALL_PATH/alist server
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable alist >/dev/null 2>&1
}

# 显示成功信息
SUCCESS() {
    LOCAL_IP=$(ip addr show | grep -w inet | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -n1)
    PUBLIC_IP=$(curl -s4 ip.sb || curl -s4 ifconfig.me || echo "获取失败")
    echo -e "${GREEN_COLOR}┌────────────────────────────────────────────────────┐${RES}"
    echo -e "${GREEN_COLOR}│ AList 安装成功！                                   │${RES}"
    echo -e "${GREEN_COLOR}│ 访问地址：                                         │${RES}"
    echo -e "${GREEN_COLOR}│   局域网：http://${LOCAL_IP}:5244/                │${RES}"
    echo -e "${GREEN_COLOR}│   公网：  http://${PUBLIC_IP}:5244/               │${RES}"
    echo -e "${GREEN_COLOR}│ 配置文件：$INSTALL_PATH/data/config.json          │${RES}"
    echo -e "${GREEN_COLOR}│ 账号信息：                                        │${RES}"
    echo -e "${GREEN_COLOR}│   用户名：$ADMIN_USER                             │${RES}"
    echo -e "${GREEN_COLOR}│   密码：  $ADMIN_PASS                             │${RES}"
    echo -e "${GREEN_COLOR}└────────────────────────────────────────────────────┘${RES}"
    echo -e "${GREEN_COLOR}管理命令：alist${RES}"
}

# 更新 AList
UPDATE() {
    if [ ! -f "$INSTALL_PATH/alist" ]; then
        handle_error 1 "未在 $INSTALL_PATH 找到 AList"
    fi
    echo -e "${GREEN_COLOR}是否使用 GitHub 代理？（默认无代理）${RES}"
    read -p "请输入代理地址（如 https://ghproxy.com/）或直接回车: " proxy_input
    if [ -n "$proxy_input" ]; then
        GH_PROXY="$proxy_input"
        echo -e "${GREEN_COLOR}使用代理: $GH_PROXY${RES}"
    else
        GH_PROXY=""
        echo -e "${GREEN_COLOR}使用默认地址${RES}"
    fi

    systemctl stop alist
    cp "$INSTALL_PATH/alist" "/tmp/alist.bak"
    echo -e "${GREEN_COLOR}下载新版本...${RES}"
    download_file "${GH_PROXY}${REPO_URL}/${BINARY_PREFIX}" "/tmp/alist.tar.gz"
    tar zxf "/tmp/alist.tar.gz" -C "$INSTALL_PATH" || {
        mv /tmp/alist.bak "$INSTALL_PATH/alist"
        systemctl start alist
        rm -f /tmp/alist.tar.gz
        handle_error 1 "解压失败，已恢复旧版本"
    }
    if [ -f "$INSTALL_PATH/alist" ]; then
        chmod +x "$INSTALL_PATH/alist"
        rm -f /tmp/alist.tar.gz /tmp/alist.bak
        systemctl restart alist
        echo -e "${GREEN_COLOR}更新完成！${RES}"
    else
        mv /tmp/alist.bak "$INSTALL_PATH/alist"
        systemctl start alist
        rm -f /tmp/alist.tar.gz
        handle_error 1 "更新失败，已恢复旧版本"
    fi
}

# 卸载 AList
UNINSTALL() {
    if [ ! -f "$INSTALL_PATH/alist" ]; then
        handle_error 1 "未在 $INSTALL_PATH 找到 AList"
    fi
    echo -e "${RED_COLOR}警告：卸载将删除 $INSTALL_PATH 及其数据！${RES}"
    read -p "确认卸载？[Y/n]: " choice
    case "${choice:-y}" in
        [yY]|"")
            systemctl stop alist 2>/dev/null || true
            systemctl disable alist 2>/dev/null || true
            rm -f /etc/systemd/system/alist.service
            systemctl daemon-reload
            rm -rf "$INSTALL_PATH" "$INSTALL_PATH/data"
            rm -f "$MANAGER_PATH" "$COMMAND_LINK"
            echo -e "${GREEN_COLOR}AList 已卸载！${RES}"
            ;;
        *) echo -e "${GREEN_COLOR}取消卸载${RES}";;
    esac
}

# 重置密码
RESET_PASSWORD() {
    if [ ! -f "$INSTALL_PATH/alist" ]; then
        handle_error 1 "未安装 AList，请先安装"
    fi
    echo -e "${GREEN_COLOR}1. 生成随机密码${RES}"
    echo -e "${GREEN_COLOR}2. 设置新密码${RES}"
    echo -e "${GREEN_COLOR}0. 返回${RES}"
    read -p "选择 [0-2]: " choice
    systemctl stop alist 2>/dev/null || true
    cd "$INSTALL_PATH"
    case $choice in
        1)
            ACCOUNT_INFO=$($INSTALL_PATH/alist admin random 2>&1)
            ADMIN_USER=$(echo "$ACCOUNT_INFO" | grep "username:" | sed 's/.*username: \(.*\)/\1/')
            ADMIN_PASS=$(echo "$ACCOUNT_INFO" | grep "password:" | sed 's/.*password: \(.*\)/\1/')
            echo -e "${GREEN_COLOR}用户名：$ADMIN_USER${RES}"
            echo -e "${GREEN_COLOR}密码：  $ADMIN_PASS${RES}"
            ;;
        2)
            read -p "请输入新密码: " new_password
            [ -z "$new_password" ] && handle_error 1 "密码不能为空"
            $INSTALL_PATH/alist admin set "$new_password"
            echo -e "${GREEN_COLOR}密码已设置为：$new_password${RES}"
            ;;
        0) ;;
        *) handle_error 1 "无效选项";;
    esac
    systemctl start alist
    cd - >/dev/null
}

# 安装命令行工具
INSTALL_CLI() {
    mkdir -p "$(dirname "$MANAGER_PATH")" || handle_error 1 "无法创建目录 $(dirname "$MANAGER_PATH")"
    cp "$0" "$MANAGER_PATH" || handle_error 1 "无法复制管理脚本"
    chmod 755 "$MANAGER_PATH" "$(dirname "$MANAGER_PATH")" || handle_error 1 "设置权限失败"
    mkdir -p "$(dirname "$COMMAND_LINK")" || handle_error 1 "无法创建目录 $(dirname "$COMMAND_LINK")"
    ln -sf "$MANAGER_PATH" "$COMMAND_LINK" || handle_error 1 "创建命令链接失败"
    echo -e "${GREEN_COLOR}命令行工具安装成功！使用 'alist' 打开管理菜单${RES}"
}

# 显示管理菜单
SHOW_MENU() {
    INSTALL_PATH=$(GET_INSTALLED_PATH)
    echo -e "${GREEN_COLOR}AList 管理菜单${RES}"
    echo -e "${GREEN_COLOR}1. 安装 AList${RES}"
    echo -e "${GREEN_COLOR}2. 更新 AList${RES}"
    echo -e "${GREEN_COLOR}3. 卸载 AList${RES}"
    echo -e "${GREEN_COLOR}4. 查看状态${RES}"
    echo -e "${GREEN_COLOR}5. 重置密码${RES}"
    echo -e "${GREEN_COLOR}6. 启动 AList${RES}"
    echo -e "${GREEN_COLOR}7. 停止 AList${RES}"
    echo -e "${GREEN_COLOR}8. 重启 AList${RES}"
    echo -e "${GREEN_COLOR}9. 查看日志${RES}"
    echo -e "${GREEN_COLOR}0. 退出${RES}"
    read -p "选择 [0-9]: " choice
    case $choice in
        1)
            INSTALL_PATH="/opt/alist"
            CHECK
            INSTALL
            INIT
            INSTALL_CLI
            SUCCESS
            ;;
        2) UPDATE;;
        3) UNINSTALL;;
        4)
            if [ ! -f "$INSTALL_PATH/alist" ]; then
                echo -e "${RED_COLOR}未安装 AList${RES}"
            elif systemctl is-active alist >/dev/null 2>&1; then
                echo -e "${GREEN_COLOR}AList 运行中${RES}"
            else
                echo -e "${RED_COLOR}AList 已停止${RES}"
            fi
            ;;
        5) RESET_PASSWORD;;
        6)
            [ ! -f "$INSTALL_PATH/alist" ] && handle_error 1 "未安装 AList"
            systemctl start alist
            echo -e "${GREEN_COLOR}AList 已启动${RES}"
            ;;
        7)
            [ ! -f "$INSTALL_PATH/alist" ] && handle_error 1 "未安装 AList"
            systemctl stop alist
            echo -e "${GREEN_COLOR}AList 已停止${RES}"
            ;;
        8)
            [ ! -f "$INSTALL_PATH/alist" ] && handle_error 1 "未安装 AList"
            systemctl restart alist
            echo -e "${GREEN_COLOR}AList 已重启${RES}"
            ;;
        9)
            [ ! -f "$INSTALL_PATH/alist" ] && handle_error 1 "未安装 AList"
            journalctl -u alist -b
            ;;
        0) exit 0;;
        *) echo -e "${RED_COLOR}无效选项${RES}";;
    esac
}

# 主逻辑
if [ $# -eq 0 ]; then
    while true; do
        clear
        SHOW_MENU
        sleep 3
    done
elif [ "$1" = "install" ]; then
    CHECK
    INSTALL
    INIT
    INSTALL_CLI
    SUCCESS
elif [ "$1" = "update" ]; then
    [ $# -gt 1 ] && handle_error 1 "update 命令不需要指定路径"
    UPDATE
elif [ "$1" = "uninstall" ]; then
    [ $# -gt 1 ] && handle_error 1 "uninstall 命令不需要指定路径"
    UNINSTALL
elif [ "$1" = "server" ]; then
    [ -f "$INSTALL_PATH/alist" ] && "$INSTALL_PATH/alist" server || handle_error 1 "未安装 AList"
elif [ "$1" = "admin" ]; then
    [ -f "$INSTALL_PATH/alist" ] && { systemctl stop alist 2>/dev/null || true; "$INSTALL_PATH/alist" admin; systemctl start alist; } || handle_error 1 "未安装 AList"
else
    echo -e "${RED_COLOR}用法: $0 {install [路径]|update|uninstall|server|admin}${RES}"
    exit 1
fi
