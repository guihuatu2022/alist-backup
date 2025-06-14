#!/bin/bash

# AList 安装脚本：支持 install、uninstall，默认路径 /opt/alist，配置开机自启和守护进程，针对 v3.45

# 检查 root 权限
[ "$(id -u)" != "0" ] && { echo "需要 root 权限，请使用 sudo"; exit 1; }

# 默认安装路径和脚本路径
INSTALL_DIR="/opt/alist"
SCRIPT_PATH="/usr/local/bin/v3.sh"

# 检测 CPU 架构
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH_TYPE="amd64";;
    aarch64|arm64) ARCH_TYPE="arm64";;
    *) echo "不支持的架构: $ARCH"; exit 1;;
esac

# 检测 Linux 发行版
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    echo "无法检测发行版"; exit 1
fi

# GitHub 仓库地址
REPO_URL="https://github.com/guihuatu2022/alist-backup/releases/download/alist-backup"
BINARY_PREFIX="alist-linux-${ARCH_TYPE}.tar.gz"

# 安装依赖
install_deps() {
    case $DISTRO in
        ubuntu|debian) apt update && apt install -y wget tar;;
        centos|rhel|fedora) yum install -y wget tar || dnf install -y wget tar;;
        *) echo "不支持的发行版: $DISTRO"; exit 1;;
    esac
}

# 下载 AList 文件
download_alist() {
    echo "正在下载 AList ($ARCH_TYPE)..."
    wget -O "/tmp/${BINARY_PREFIX}" "${REPO_URL}/${BINARY_PREFIX}"
    [ $? -ne 0 ] && { echo "下载失败"; exit 1; }
}

# 安装 AList
install_alist() {
    download_alist
    mkdir -p "$INSTALL_DIR"
    tar -zxf "/tmp/${BINARY_PREFIX}" -C "$INSTALL_DIR"
    [ ! -f "$INSTALL_DIR/alist" ] && { echo "安装失败"; exit 1; }
    chmod +x "$INSTALL_DIR/alist"
    rm "/tmp/${BINARY_PREFIX}"

    # 清理旧的符号链接和脚本
    rm -f /usr/local/bin/alist "$SCRIPT_PATH"

    # 写入脚本到 /usr/local/bin/v3.sh
    echo "正在写入脚本到 $SCRIPT_PATH..."
    cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash

# AList 管理脚本：支持 server、admin、管理菜单，默认路径 /opt/alist，针对 v3.45

# 检查 root 权限
[ "$(id -u)" != "0" ] && { echo "需要 root 权限，请使用 sudo"; exit 1; }

# 默认安装路径
INSTALL_DIR="/opt/alist"

# 卸载 AList
uninstall_alist() {
    systemctl stop alist 2>/dev/null || true
    systemctl disable alist 2>/dev/null || true
    rm -f /etc/systemd/system/alist.service
    systemctl daemon-reload
    rm -rf "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR/data"
    rm -f /usr/local/bin/alist "$SCRIPT_PATH"
    echo "AList 已卸载！"
    exit 0
}

# 管理菜单
manage_menu() {
    [ ! -f "$INSTALL_DIR/alist" ] && { echo "AList 未安装，请先运行 install"; exit 1; }
    while true; do
        echo -e "\e[32m"
        echo "AList 管理菜单"
        echo "1. 启动"
        echo "2. 停止"
        echo "3. 重启"
        echo "4. 状态"
        echo "5. 日志"
        echo "6. 重置密码"
        echo "7. 卸载"
        echo "0. 退出"
        echo -e "\e[0m"
        read -p "选择 [0-7]: " choice
        case $choice in
            1) systemctl start alist; echo "已启动";;
            2) systemctl stop alist; echo "已停止";;
            3) systemctl restart alist; echo "已重启";;
            4) systemctl status alist;;
            5) journalctl -u alist -b;;
            6)
                echo -e "\e[32m"
                echo "选择重置密码方式："
                echo "1. 随机生成密码"
                echo "2. 手动设置密码"
                echo -e "\e[0m"
                read -p "选择 [1-2]: " pwd_choice
                # 停止服务以避免 token 错误
                systemctl stop alist 2>/dev/null || true
                case $pwd_choice in
                    1) "$INSTALL_DIR/alist" admin random;;
                    2)
                        read -p "请输入新密码: " new_password
                        "$INSTALL_DIR/alist" admin set "$new_password"
                        ;;
                    *) echo "无效选项";;
                esac
                # 重启服务
                systemctl start al
