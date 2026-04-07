#!/bin/bash

##############################################################################
# Cloudflare Tunnel 一键安装脚本
# 
# 功能：
#   1. 自动检测并安装 cloudflared
#   2. 智能连接：IPv6 优先，失败自动切换 IPv4
#   3. 配置 systemd 服务，开机自启
#   4. 显示详细安装进度和连接状态
#
# 使用方法：
#   curl -fsSL https://raw.githubusercontent.com/Cuscito/cloudflare-tunnel-installer/main/scripts/install-cloudflared.sh | sudo bash -s -- "YOUR_TOKEN"
#
# GitHub: https://github.com/Cuscito/cloudflare-tunnel-installer
# Version: 2.4.0
##############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

VERSION="2.4.0"

# 进度条函数
show_progress() {
    local msg="$1"
    echo -ne "${CYAN}  ${msg}${NC} "
    for i in {1..3}; do
        echo -ne "."
        sleep 0.2
    done
    echo -e " ${GREEN}✓${NC}"
}

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

show_title() {
    clear
    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                                                              ║${NC}"
    echo -e "${MAGENTA}║     Cloudflare Tunnel 一键安装脚本 v${VERSION}                    ║${NC}"
    echo -e "${MAGENTA}║     https://github.com/Cuscito/cloudflare-tunnel-installer  ║${NC}"
    echo -e "${MAGENTA}║                                                              ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
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
        case $ID in
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

clean_old_service() {
    log_step "清理旧服务..."
    
    if systemctl is-active --quiet cloudflared.service 2>/dev/null; then
        echo -n "  停止运行中的服务... "
        systemctl stop cloudflared.service && echo -e "${GREEN}完成${NC}"
    fi
    
    if systemctl is-enabled --quiet cloudflared.service 2>/dev/null; then
        echo -n "  禁用开机自启... "
        systemctl disable cloudflared.service && echo -e "${GREEN}完成${NC}"
    fi
    
    echo -n "  删除配置文件... "
    rm -f /etc/systemd/system/cloudflared.service
    rm -f /usr/local/bin/cloudflared-smart.sh
    systemctl daemon-reload
    echo -e "${GREEN}完成${NC}"
    
    log_success "清理完成"
}

install_cloudflared() {
    log_step "安装 cloudflared..."
    
    if command -v cloudflared &> /dev/null; then
        local current_version=$(cloudflared --version 2>/dev/null | head -1)
        log_info "cloudflared 已安装: $current_version"
        return
    fi
    
    case $PKG_MANAGER in
        apt)
            show_progress "添加 GPG 密钥"
            curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | gpg --dearmor | tee /usr/share/keyrings/cloudflare-archive-keyring.gpg > /dev/null
            
            show_progress "添加软件源"
            echo 'deb [signed-by=/usr/share/keyrings/cloudflare-archive-keyring.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list > /dev/null
            
            show_progress "更新软件包列表"
            apt-get update -qq
            
            show_progress "安装 cloudflared"
            apt-get install -y cloudflared > /dev/null 2>&1
            ;;
        yum|dnf)
            show_progress "添加仓库"
            tee /etc/yum.repos.d/cloudflared.repo > /dev/null << REPO
[cloudflared]
name=Cloudflare cloudflared
baseurl=https://pkg.cloudflare.com/cloudflared/el/7/\$basearch
enabled=1
gpgcheck=1
gpgkey=https://pkg.cloudflare.com/cloudflare-public-v2.gpg
REPO
            
            show_progress "安装 cloudflared"
            $PKG_INSTALL cloudflared > /dev/null 2>&1
            ;;
        *)
            show_progress "下载二进制文件"
            curl -fsSL -o /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
            chmod +x /usr/local/bin/cloudflared
            ;;
    esac
    
    # 确保命令可用
    if ! command -v cloudflared &> /dev/null && [ -f /usr/local/bin/cloudflared ]; then
        ln -sf /usr/local/bin/cloudflared /usr/bin/cloudflared
    fi
    
    log_success "cloudflared 安装完成: $(cloudflared --version)"
}

create_smart_script() {
    log_step "创建智能连接脚本..."
    
    cat > /usr/local/bin/cloudflared-smart.sh << 'SCRIPT'
#!/bin/bash

TOKEN="$1"
LOG_FILE="/var/log/cloudflared.log"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

if [ -z "$TOKEN" ]; then
    echo -e "${RED}[ERROR]${NC} 未提供 Token"
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} 启动 Cloudflare Tunnel 智能连接..."

# 检测 IPv6
check_ipv6() {
    if [ ! -f /proc/net/if_inet6 ]; then
        return 1
    fi
    if ! ping6 -c 1 -W 2 2606:4700::1111 >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# 获取连接的边缘节点信息
get_edge_info() {
    local log_line=$(journalctl -u cloudflared -n 20 2>/dev/null | grep -oP 'connIndex=\d+ ip=\S+' | head -1)
    if [ -n "$log_line" ]; then
        echo "$log_line"
    fi
}

# 尝试 IPv6
if check_ipv6; then
    echo -e "${GREEN}[INFO]${NC} IPv6 可用，正在尝试连接..."
    log "IPv6 可用，尝试连接"
    
    if timeout 30 cloudflared tunnel --edge-ip-version 6 --protocol http2 run --token "$TOKEN" 2>/dev/null; then
        log "IPv6 连接成功"
        echo -e "${GREEN}[✓]${NC} IPv6 连接成功！"
        echo -e "${CYAN}[INFO]${NC} 当前使用: IPv6"
        exec cloudflared tunnel --edge-ip-version 6 --protocol http2 --retries 5 --no-autoupdate run --token "$TOKEN"
    else
        log "IPv6 连接失败，切换到 IPv4"
        echo -e "${YELLOW}[WARN]${NC} IPv6 连接失败，切换到 IPv4"
    fi
else
    log "IPv6 不可用"
    echo -e "${YELLOW}[WARN]${NC} IPv6 不可用"
fi

# 使用 IPv4
log "使用 IPv4 连接"
echo -e "${GREEN}[INFO]${NC} 当前使用: IPv4"
exec cloudflared tunnel --protocol http2 --retries 5 --no-autoupdate run --token "$TOKEN"
SCRIPT
    
    chmod +x /usr/local/bin/cloudflared-smart.sh
    log_success "智能连接脚本创建完成"
}

create_systemd_service() {
    log_step "创建 systemd 服务..."
    
    cat > /etc/systemd/system/cloudflared.service << SERVICE
[Unit]
Description=Cloudflare Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10s
ExecStart=/usr/local/bin/cloudflared-smart.sh ${TOKEN}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE
    
    log_success "systemd 服务创建完成"
}

start_service() {
    log_step "启动服务..."
    
    show_progress "重新加载 systemd"
    systemctl daemon-reload
    
    show_progress "启用开机自启"
    systemctl enable cloudflared.service > /dev/null 2>&1
    
    show_progress "启动 cloudflared"
    systemctl start cloudflared.service
    
    sleep 5
}

test_connection() {
    log_step "测试连接状态..."
    echo ""
    
    # 等待连接建立
    local max_wait=30
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if journalctl -u cloudflared.service -n 10 --no-pager 2>/dev/null | grep -q "Registered\|连接成功\|Initial protocol"; then
            echo -e "  ${GREEN}✓ Tunnel 已成功注册${NC}"
            return 0
        fi
        echo -ne "  ${CYAN}.${NC}"
        sleep 2
        waited=$((waited + 2))
    done
    echo ""
    log_warn "Tunnel 注册中，请稍后查看日志"
}

check_service() {
    log_step "检查服务状态..."
    echo ""
    
    if systemctl is-active --quiet cloudflared.service; then
        log_success "服务运行中"
        echo ""
        
        # 显示当前使用的协议
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}📡 当前连接状态:${NC}"
        
        # 查看最近的连接日志确定使用的协议
        if journalctl -u cloudflared.service -n 30 --no-pager 2>/dev/null | grep -q "IPv6 连接成功\|IPv6.*成功"; then
            echo -e "  ${GREEN}✓ 当前使用: IPv6${NC}"
        elif journalctl -u cloudflared.service -n 30 --no-pager 2>/dev/null | grep -q "IPv4"; then
            echo -e "  ${GREEN}✓ 当前使用: IPv4${NC}"
        else
            echo -e "  ${YELLOW}⚠ 连接建立中...${NC}"
        fi
        
        # 显示 Cloudflare 边缘节点信息
        local edge_info=$(journalctl -u cloudflared.service -n 50 --no-pager 2>/dev/null | grep -oP 'connIndex=\d+ ip=\S+' | head -1)
        if [ -n "$edge_info" ]; then
            echo -e "  ${CYAN}📍 边缘节点: ${edge_info}${NC}"
        fi
        
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        # 显示服务状态摘要
        systemctl status cloudflared.service --no-pager -l | head -12
        
        return 0
    else
        log_error "服务未运行"
        journalctl -u cloudflared.service -n 20 --no-pager
        return 1
    fi
}

show_complete() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    安装完成！                                ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_info "Cloudflare Tunnel 已安装并启动"
    log_info "开机自启: 已启用"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📋 常用管理命令:${NC}"
    echo -e "  ${YELLOW}查看状态:${NC} sudo systemctl status cloudflared"
    echo -e "  ${YELLOW}查看日志:${NC} sudo journalctl -u cloudflared -f"
    echo -e "  ${YELLOW}查看连接:${NC} sudo tail -f /var/log/cloudflared.log"
    echo -e "  ${YELLOW}重启服务:${NC} sudo systemctl restart cloudflared"
    echo -e "  ${YELLOW}停止服务:${NC} sudo systemctl stop cloudflared"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

uninstall() {
    log_step "卸载 Cloudflare Tunnel..."
    
    systemctl stop cloudflared.service 2>/dev/null
    systemctl disable cloudflared.service 2>/dev/null
    rm -f /etc/systemd/system/cloudflared.service
    rm -f /usr/local/bin/cloudflared-smart.sh
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

show_help() {
    cat << EOF
Cloudflare Tunnel 安装脚本 v${VERSION}

用法:
    curl -fsSL https://raw.githubusercontent.com/Cuscito/cloudflare-tunnel-installer/main/scripts/install-cloudflared.sh | sudo bash -s -- "YOUR_TOKEN"

选项:
    --uninstall    卸载服务
    -h, --help     显示帮助

示例:
    # 安装
    curl -fsSL https://raw.githubusercontent.com/Cuscito/cloudflare-tunnel-installer/main/scripts/install-cloudflared.sh | sudo bash -s -- "your-token"
    
    # 卸载
    wget https://raw.githubusercontent.com/Cuscito/cloudflare-tunnel-installer/main/scripts/install-cloudflared.sh
    sudo bash install-cloudflared.sh --uninstall
EOF
}

main() {
    case "$1" in
        --uninstall)
            check_root
            uninstall
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
    esac
    
    TOKEN="$1"
    if [[ -z "$TOKEN" ]]; then
        log_error "请提供 Cloudflare Token"
        show_help
        exit 1
    fi
    
    check_root
    show_title
    detect_os
    clean_old_service
    install_cloudflared
    create_smart_script
    create_systemd_service
    start_service
    test_connection
    check_service
    show_complete
}

main "$@"
