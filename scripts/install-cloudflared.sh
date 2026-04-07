#!/bin/bash

##############################################################################
# Cloudflare Tunnel 一键安装脚本
# 
# 功能：
#   1. 自动检测并安装 cloudflared
#   2. 智能连接：IPv6 优先，失败自动切换 IPv4
#   3. 配置 systemd 服务，开机自启
#   4. 支持卸载后重新安装
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
CYAN='\033[0;36m'
NC='\033[0m'

VERSION="2.1.0"
LOG_FILE="/var/log/cloudflared-install.log"

log_info() { echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }

show_title() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Cloudflare Tunnel 一键安装脚本 v${VERSION}                    ║"
    echo "║     https://github.com/Cuscito/cloudflare-tunnel-installer  ║"
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
            centos|rhel|rocky|almalinux)
                PKG_MANAGER="yum"
                if command -v dnf &> /dev/null; then PKG_MANAGER="dnf"; fi
                log_info "系统: $NAME (RedHat系列)"
                ;;
            fedora)
                PKG_MANAGER="dnf"
                log_info "系统: $NAME (Fedora系列)"
                ;;
            *)
                PKG_MANAGER="unknown"
                log_warn "未识别的系统: $OS"
                ;;
        esac
    fi
}

# 完整清理函数（彻底删除所有相关文件）
full_cleanup() {
    log_step "执行完整清理..."
    
    # 停止并禁用服务
    echo -n "  停止服务... "
    systemctl stop cloudflared.service 2>/dev/null && echo -e "${GREEN}完成${NC}" || echo -e "${YELLOW}跳过${NC}"
    
    echo -n "  禁用服务... "
    systemctl disable cloudflared.service 2>/dev/null && echo -e "${GREEN}完成${NC}" || echo -e "${YELLOW}跳过${NC}"
    
    # 删除 systemd 服务文件
    echo -n "  删除服务文件... "
    rm -f /etc/systemd/system/cloudflared.service
    rm -f /etc/systemd/system/cloudflared.service.d/override.conf
    echo -e "${GREEN}完成${NC}"
    
    # 删除智能脚本
    echo -n "  删除脚本文件... "
    rm -f /usr/local/bin/cloudflared-smart.sh
    echo -e "${GREEN}完成${NC}"
    
    # 删除日志文件
    echo -n "  删除日志文件... "
    rm -f /var/log/cloudflared.log
    rm -f /var/log/cloudflared-install.log
    echo -e "${GREEN}完成${NC}"
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    log_success "清理完成"
}

# 安装 cloudflared（强制重新安装）
install_cloudflared() {
    log_step "安装 cloudflared..."
    
    # 如果已安装，询问是否重新安装
    if command -v cloudflared &> /dev/null; then
        log_info "检测到已安装: $(cloudflared --version)"
        echo -n "是否重新安装? (y/N): "
        read -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "使用现有版本"
            return
        fi
        # 重新安装：先删除旧版本
        echo -n "  删除旧版本... "
        rm -f $(which cloudflared)
        echo -e "${GREEN}完成${NC}"
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
            apt-get install -y cloudflared > /dev/null 2>&1
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
            $PKG_INSTALL cloudflared > /dev/null 2>&1
            echo -e "${GREEN}完成${NC}"
            ;;
        *)
            local arch=$(uname -m)
            case $arch in
                x86_64) binary_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" ;;
                aarch64) binary_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" ;;
                armv7l) binary_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm" ;;
                *) log_error "不支持的架构: $arch"; exit 1 ;;
            esac
            
            echo -n "  下载 cloudflared... "
            curl -fsSL -o /usr/local/bin/cloudflared "$binary_url"
            chmod +x /usr/local/bin/cloudflared
            echo -e "${GREEN}完成${NC}"
            ;;
    esac
    
    log_success "cloudflared 安装完成: $(cloudflared --version)"
}

# 创建智能连接脚本
create_smart_script() {
    log_step "创建智能连接脚本（IPv6优先，失败自动切换IPv4）..."
    
    cat > /usr/local/bin/cloudflared-smart.sh << 'SCRIPT'
#!/bin/bash

TOKEN="'"${TOKEN}"'"
LOG_FILE="/var/log/cloudflared.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log "启动 Cloudflare Tunnel 智能连接"

# 检测 IPv6
check_ipv6() {
    if [ ! -f /proc/net/if_inet6 ]; then
        log "系统不支持 IPv6"
        return 1
    fi
    
    # 尝试 ping IPv6 地址
    if command -v ping6 &> /dev/null; then
        ping6 -c 1 -W 3 2606:4700::1111 >/dev/null 2>&1
    else
        ping -6 -c 1 -W 3 2606:4700::1111 >/dev/null 2>&1
    fi
    
    if [ $? -ne 0 ]; then
        log "IPv6 网络不可达"
        return 1
    fi
    
    return 0
}

# 尝试 IPv6 连接
try_ipv6() {
    log "尝试 IPv6 连接..."
    timeout 30 cloudflared tunnel --edge-ip-version 6 --protocol http2 run --token $TOKEN 2>/dev/null
    return $?
}

# 主逻辑
if check_ipv6; then
    log "IPv6 可用，尝试连接"
    if try_ipv6; then
        log "IPv6 连接成功"
        exec cloudflared tunnel --edge-ip-version 6 --protocol http2 --retries 5 --no-autoupdate run --token $TOKEN
    else
        log "IPv6 连接失败，切换到 IPv4"
    fi
else
    log "IPv6 不可用"
fi

# 使用 IPv4
log "使用 IPv4 连接"
exec cloudflared tunnel --protocol http2 --retries 5 --no-autoupdate run --token $TOKEN
SCRIPT
    
    chmod +x /usr/local/bin/cloudflared-smart.sh
    log_success "智能连接脚本创建完成"
}

# 创建 systemd 服务
create_systemd_service() {
    log_step "创建 systemd 服务..."
    
    cat > /etc/systemd/system/cloudflared.service << SERVICE
[Unit]
Description=Cloudflare Tunnel (IPv6优先，自动切换IPv4)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
TimeoutStartSec=120
Restart=always
RestartSec=10s
StartLimitBurst=5
StartLimitIntervalSec=120
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
    
    echo -n "  重新加载 systemd... "
    systemctl daemon-reload && echo -e "${GREEN}完成${NC}"
    
    echo -n "  启用开机自启... "
    systemctl enable cloudflared.service > /dev/null 2>&1 && echo -e "${GREEN}完成${NC}"
    
    echo -n "  启动 cloudflared... "
    systemctl start cloudflared.service && echo -e "${GREEN}完成${NC}"
    
    sleep 5
}

# 检查服务状态
check_service() {
    log_step "检查服务状态..."
    echo ""
    
    if systemctl is-active --quiet cloudflared.service; then
        log_success "服务运行中"
        echo ""
        
        log_info "服务状态:"
        systemctl status cloudflared.service --no-pager -l | head -15
        echo ""
        
        log_info "最近日志:"
        journalctl -u cloudflared.service -n 10 --no-pager | grep -E "IPv[46]|Connected|Registered" || echo "  等待建立连接..."
        
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
    log_info "智能连接: IPv6 优先，失败自动切换 IPv4"
    log_info "开机自启: 已启用"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "常用管理命令:"
    echo "  查看状态: sudo systemctl status cloudflared"
    echo "  查看日志: sudo journalctl -u cloudflared -f"
    echo "  重启服务: sudo systemctl restart cloudflared"
    echo "  停止服务: sudo systemctl stop cloudflared"
    echo "  启动服务: sudo systemctl start cloudflared"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "安装日志: $LOG_FILE"
    log_info "运行日志: /var/log/cloudflared.log"
}

# 卸载函数
uninstall() {
    log_step "卸载 Cloudflare Tunnel..."
    
    echo ""
    echo "请选择卸载方式:"
    echo "  1) 仅停止服务，保留配置文件"
    echo "  2) 完全卸载，删除所有文件"
    echo "  3) 完全卸载并删除 cloudflared 二进制文件"
    echo ""
    read -p "请选择 (1/2/3): " choice
    
    case $choice in
        1)
            echo -n "  停止服务... "
            systemctl stop cloudflared.service 2>/dev/null && echo -e "${GREEN}完成${NC}"
            echo -n "  禁用服务... "
            systemctl disable cloudflared.service 2>/dev/null && echo -e "${GREEN}完成${NC}"
            log_success "服务已停止，配置文件保留"
            ;;
        2)
            full_cleanup
            ;;
        3)
            full_cleanup
            echo -n "  删除 cloudflared 二进制文件... "
            rm -f $(which cloudflared) 2>/dev/null && echo -e "${GREEN}完成${NC}"
            log_success "cloudflared 已删除"
            ;;
        *)
            log_error "无效选择"
            exit 1
            ;;
    esac
}

# 帮助信息
show_help() {
    cat << EOF
Cloudflare Tunnel 安装脚本 v${VERSION}

用法: 
    安装: curl -fsSL https://raw.githubusercontent.com/Cuscito/cloudflare-tunnel-installer/main/scripts/install-cloudflared.sh | sudo bash -s -- "YOUR_TOKEN"
    
    卸载: 下载脚本后执行 sudo bash install.sh --uninstall

选项:
    --uninstall            卸载服务
    -h, --help             显示帮助

说明:
    脚本会自动检测系统类型并安装 cloudflared
    安装后自动启动并设置开机自启
    智能连接: IPv6 优先，失败自动切换 IPv4
    支持卸载后重新安装
EOF
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
            show_help
            exit 0
            ;;
    esac
    
    # 获取 Token
    TOKEN="$1"
    if [[ -z "$TOKEN" ]]; then
        log_error "请提供 Cloudflare Token"
        echo ""
        echo "用法: curl -fsSL https://raw.githubusercontent.com/Cuscito/cloudflare-tunnel-installer/main/scripts/install-cloudflared.sh | sudo bash -s -- \"YOUR_TOKEN\""
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
        log_error "服务启动失败，请检查日志"
        exit 1
    fi
}

main "$@"
