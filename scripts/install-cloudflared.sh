#!/bin/bash

##############################################################################
# Cloudflare Tunnel 一键安装脚本
# 
# 功能：
#   1. 自动检测并安装 cloudflared
#   2. 智能连接：IPv6 优先，失败自动切换 IPv4
#   3. 配置 systemd 服务，开机自启
#
# 使用方法：
#   curl -fsSL https://raw.githubusercontent.com/Cuscito/cloudflare-tunnel-installer/main/scripts/install-cloudflared.sh | sudo bash -s -- "YOUR_TOKEN"
##############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VERSION="2.2.0"
LOG_FILE="/var/log/cloudflared-install.log"

log_info() { echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }

show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Cloudflare Tunnel 一键安装脚本 v${VERSION}                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 sudo 运行此脚本"
        exit 1
    fi
}

detect_os() {
    log_step "检测系统类型..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        case $OS in
            ubuntu|debian)
                PKG_MANAGER="apt"
                log_info "系统: $NAME (Debian系列)"
                ;;
            centos|rhel|rocky|almalinux|fedora)
                PKG_MANAGER="yum"
                if command -v dnf &> /dev/null; then PKG_MANAGER="dnf"; fi
                log_info "系统: $NAME (RedHat系列)"
                ;;
            *)
                PKG_MANAGER="unknown"
                log_info "系统: $NAME"
                ;;
        esac
    fi
}

# 安装 cloudflared
install_cloudflared() {
    log_step "安装 cloudflared..."
    
    # 删除可能损坏的安装
    if command -v cloudflared &> /dev/null; then
        log_info "删除旧版本..."
        rm -f $(which cloudflared)
    fi
    
    case $PKG_MANAGER in
        apt)
            echo -n "  添加 GPG 密钥... "
            curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | gpg --dearmor | tee /usr/share/keyrings/cloudflare-archive-keyring.gpg > /dev/null
            echo -e "${GREEN}完成${NC}"
            
            echo -n "  添加软件源... "
            echo 'deb [signed-by=/usr/share/keyrings/cloudflare-archive-keyring.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list > /dev/null
            echo -e "${GREEN}完成${NC}"
            
            echo -n "  更新软件包列表... "
            apt-get update -qq
            echo -e "${GREEN}完成${NC}"
            
            echo -n "  安装 cloudflared... "
            apt-get install -y cloudflared
            echo -e "${GREEN}完成${NC}"
            ;;
        yum|dnf)
            echo -n "  添加仓库... "
            tee /etc/yum.repos.d/cloudflared.repo > /dev/null << REPO
[cloudflared]
name=Cloudflare cloudflared
baseurl=https://pkg.cloudflare.com/cloudflared/el/7/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://pkg.cloudflare.com/cloudflare-public-v2.gpg
REPO
            echo -e "${GREEN}完成${NC}"
            
            echo -n "  安装 cloudflared... "
            $PKG_INSTALL cloudflared
            echo -e "${GREEN}完成${NC}"
            ;;
        *)
            echo -n "  下载二进制文件... "
            curl -fsSL -o /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
            chmod +x /usr/local/bin/cloudflared
            echo -e "${GREEN}完成${NC}"
            ;;
    esac
    
    # 验证安装
    if command -v cloudflared &> /dev/null; then
        log_success "cloudflared 安装完成: $(cloudflared --version)"
    elif [ -f /usr/local/bin/cloudflared ]; then
        log_success "cloudflared 安装完成: $(/usr/local/bin/cloudflared --version)"
        # 创建软链接
        ln -sf /usr/local/bin/cloudflared /usr/bin/cloudflared
    elif [ -f /usr/bin/cloudflared ]; then
        log_success "cloudflared 安装完成: $(/usr/bin/cloudflared --version)"
    else
        log_error "cloudflared 安装失败"
        exit 1
    fi
}

# 创建智能连接脚本
create_smart_script() {
    log_step "创建智能连接脚本..."
    
    # 获取 cloudflared 路径
    CLOUDFLARED_PATH=$(which cloudflared 2>/dev/null || echo "/usr/local/bin/cloudflared")
    
    cat > /usr/local/bin/cloudflared-smart.sh << 'SCRIPT'
#!/bin/bash

TOKEN="'"${TOKEN}"'"
CLOUDFLARED_PATH="'"${CLOUDFLARED_PATH}"'"
LOG_FILE="/var/log/cloudflared.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log "启动 Cloudflare Tunnel"

# 检测 IPv6
check_ipv6() {
    if [ ! -f /proc/net/if_inet6 ]; then
        return 1
    fi
    
    # 尝试 ping IPv6
    if command -v ping6 &> /dev/null; then
        ping6 -c 1 -W 2 2606:4700::1111 >/dev/null 2>&1
    else
        ping -6 -c 1 -W 2 2606:4700::1111 >/dev/null 2>&1
    fi
    return $?
}

# 尝试 IPv6
if check_ipv6; then
    log "IPv6 可用，尝试连接"
    if timeout 20 $CLOUDFLARED_PATH tunnel --edge-ip-version 6 --protocol http2 run --token $TOKEN 2>/dev/null; then
        log "IPv6 连接成功"
        exec $CLOUDFLARED_PATH tunnel --edge-ip-version 6 --protocol http2 --retries 5 --no-autoupdate run --token $TOKEN
    else
        log "IPv6 连接失败，切换到 IPv4"
    fi
else
    log "IPv6 不可用"
fi

# 使用 IPv4
log "使用 IPv4 连接"
exec $CLOUDFLARED_PATH tunnel --protocol http2 --retries 5 --no-autoupdate run --token $TOKEN
SCRIPT
    
    chmod +x /usr/local/bin/cloudflared-smart.sh
    log_success "智能连接脚本创建完成"
}

# 创建 systemd 服务
create_systemd_service() {
    log_step "创建 systemd 服务..."
    
    cat > /etc/systemd/system/cloudflared.service << 'SERVICE'
[Unit]
Description=Cloudflare Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10s
ExecStart=/usr/local/bin/cloudflared-smart.sh
KillMode=process

[Install]
WantedBy=multi-user.target
SERVICE
    
    log_success "systemd 服务创建完成"
}

# 启动服务
start_service() {
    log_step "启动服务..."
    
    systemctl daemon-reload
    systemctl enable cloudflared.service
    systemctl start cloudflared.service
    
    sleep 3
}

# 检查服务状态
check_service() {
    log_step "检查服务状态..."
    echo ""
    
    if systemctl is-active --quiet cloudflared.service; then
        log_success "服务运行中"
        echo ""
        systemctl status cloudflared.service --no-pager -l | head -15
        return 0
    else
        log_error "服务未运行"
        journalctl -u cloudflared.service -n 20 --no-pager
        return 1
    fi
}

# 显示完成信息
show_complete() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    安装完成！                                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Cloudflare Tunnel 已安装并启动"
    log_info "开机自启: 已启用"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "常用管理命令:"
    echo "  查看状态: sudo systemctl status cloudflared"
    echo "  查看日志: sudo journalctl -u cloudflared -f"
    echo "  重启服务: sudo systemctl restart cloudflared"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 卸载函数
uninstall() {
    log_step "卸载 Cloudflare Tunnel..."
    
    systemctl stop cloudflared.service 2>/dev/null
    systemctl disable cloudflared.service 2>/dev/null
    rm -f /etc/systemd/system/cloudflared.service
    rm -f /usr/local/bin/cloudflared-smart.sh
    rm -f /var/log/cloudflared.log
    systemctl daemon-reload
    
    log_success "卸载完成"
    
    read -p "是否删除 cloudflared? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f $(which cloudflared 2>/dev/null)
        rm -f /usr/local/bin/cloudflared
        rm -f /usr/bin/cloudflared
        log_info "cloudflared 已删除"
    fi
}

# 主函数
main() {
    case "$1" in
        --uninstall)
            check_root
            uninstall
            exit 0
            ;;
        -h|--help)
            echo "用法: curl ... | sudo bash -s -- 'YOUR_TOKEN'"
            exit 0
            ;;
    esac
    
    TOKEN="$1"
    if [[ -z "$TOKEN" ]]; then
        log_error "请提供 Cloudflare Token"
        exit 1
    fi
    
    check_root
    show_title
    detect_os
    install_cloudflared
    create_smart_script
    create_systemd_service
    start_service
    
    if check_service; then
        show_complete
    else
        log_error "服务启动失败"
        exit 1
    fi
}

main "$@"
