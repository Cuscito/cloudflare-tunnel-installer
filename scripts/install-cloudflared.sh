cat > scripts/install-cloudflared.sh << 'EOF'
#!/bin/bash

##############################################################################
# Cloudflare Tunnel 一键安装脚本
# 
# 功能：
#   1. 自动检测并卸载旧服务
#   2. 智能连接：IPv6 优先，失败自动切换 IPv4
#   3. 配置 systemd 服务，开机自启
#   4. 实时显示安装进度和运行状态
#
# 支持系统：Ubuntu, Debian, CentOS, RHEL, Fedora, Rocky Linux, AlmaLinux
# GitHub：https://github.com/Cuscito/cloudflare-tunnel-installer
# 作者：Cuscito
# 版本：2.0.0
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

# 版本信息
VERSION="2.0.0"

# 日志文件
LOG_FILE="/var/log/cloudflared-install.log"

# ==================== 配置区域 ====================
# 请修改为您的 Cloudflare Tunnel Token
# 获取方式：Cloudflare Zero Trust > Networks > Tunnels > 创建 Tunnel
CLOUDFLARE_TOKEN=""
# =================================================

# 日志函数
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    log "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

log_step() {
    log "${BLUE}[STEP]${NC} $1"
}

log_success() {
    log "${GREEN}[✓]${NC} $1"
}

# 显示进度条
show_progress() {
    local msg="$1"
    echo -ne "${CYAN}  ${msg}${NC} "
    for i in {1..3}; do
        echo -ne "."
        sleep 0.3
    done
    echo -e " ${GREEN}完成${NC}"
}

# 显示标题
show_title() {
    clear
    echo ""
    log "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    log "${MAGENTA}║                                                              ║${NC}"
    log "${MAGENTA}║     Cloudflare Tunnel 一键安装脚本 v${VERSION}                    ║${NC}"
    log "${MAGENTA}║     https://github.com/Cuscito/cloudflare-tunnel-installer  ║${NC}"
    log "${MAGENTA}║                                                              ║${NC}"
    log "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 sudo 运行此脚本"
        exit 1
    fi
}

# 检查 Token
check_token() {
    if [[ -z "$CLOUDFLARE_TOKEN" ]]; then
        log_error "请先设置 Cloudflare Token"
        echo ""
        log_info "编辑脚本，修改 CLOUDFLARE_TOKEN 变量"
        log_info "或使用命令行参数: --token \"your-token\""
        exit 1
    fi
}

# 检测系统类型
detect_os() {
    log_step "检测系统类型..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        OS_NAME=$NAME
        
        case $OS in
            ubuntu|debian)
                PKG_MANAGER="apt"
                PKG_UPDATE="apt-get update -qq"
                PKG_INSTALL="apt-get install -y"
                log_info "系统: $OS_NAME $VER (Debian系列)"
                ;;
            centos|rhel|rocky|almalinux)
                PKG_MANAGER="yum"
                PKG_UPDATE="yum update -y -q"
                PKG_INSTALL="yum install -y"
                if command -v dnf &> /dev/null; then
                    PKG_MANAGER="dnf"
                    PKG_INSTALL="dnf install -y"
                fi
                log_info "系统: $OS_NAME $VER (RedHat系列)"
                ;;
            fedora)
                PKG_MANAGER="dnf"
                PKG_UPDATE="dnf update -y -q"
                PKG_INSTALL="dnf install -y"
                log_info "系统: $OS_NAME $VER (Fedora系列)"
                ;;
            *)
                log_warn "未识别的系统: $OS，将尝试通用安装"
                PKG_MANAGER="unknown"
                ;;
        esac
    else
        log_error "无法检测系统类型"
        exit 1
    fi
}

# 检测并卸载旧服务
check_and_uninstall() {
    log_step "检测并清理旧服务..."
    echo ""
    
    # 检查是否已安装
    if command -v cloudflared &> /dev/null; then
        log_warn "检测到已安装的 cloudflared: $(cloudflared --version)"
        
        # 停止服务
        if systemctl is-active --quiet cloudflared.service 2>/dev/null; then
            echo -n "  停止运行中的服务... "
            sudo systemctl stop cloudflared.service 2>/dev/null && echo -e "${GREEN}完成${NC}"
        fi
        
        # 禁用服务
        if systemctl is-enabled --quiet cloudflared.service 2>/dev/null; then
            echo -n "  禁用开机自启... "
            sudo systemctl disable cloudflared.service 2>/dev/null && echo -e "${GREEN}完成${NC}"
        fi
        
        # 卸载服务
        echo -n "  卸载 cloudflared 服务... "
        sudo cloudflared service uninstall 2>/dev/null && echo -e "${GREEN}完成${NC}"
        
        # 清理文件
        echo -n "  清理配置文件... "
        sudo rm -f /etc/systemd/system/cloudflared.service
        sudo rm -f /etc/systemd/system/cloudflared.service.d/override.conf
        sudo rm -f /usr/local/bin/cloudflared-smart.sh
        sudo rm -f /var/log/cloudflared.log
        echo -e "${GREEN}完成${NC}"
        
        echo ""
        log_warn "是否重新安装 cloudflared? (y/N): "
        read -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -n "  删除旧版本... "
            sudo rm -f $(which cloudflared)
            echo -e "${GREEN}完成${NC}"
            NEED_REINSTALL=true
        else
            NEED_REINSTALL=false
        fi
    else
        log_info "未检测到现有安装，将进行全新安装"
        NEED_REINSTALL=true
    fi
    
    log_success "旧服务清理完成"
}

# 安装 cloudflared
install_cloudflared() {
    if [[ "$NEED_REINSTALL" == "false" ]] && command -v cloudflared &> /dev/null; then
        log_info "使用现有 cloudflared: $(cloudflared --version)"
        return
    fi
    
    log_step "安装 cloudflared..."
    
    case $PKG_MANAGER in
        apt)
            echo -n "  添加 GPG 密钥... "
            curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | sudo gpg --dearmor | sudo tee /usr/share/keyrings/cloudflare-archive-keyring.gpg > /dev/null
            echo -e "${GREEN}完成${NC}"
            
            echo -n "  添加软件源... "
            echo 'deb [signed-by=/usr/share/keyrings/cloudflare-archive-keyring.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list > /dev/null
            echo -e "${GREEN}完成${NC}"
            
            echo -n "  更新软件包列表... "
            sudo apt-get update -qq
            echo -e "${GREEN}完成${NC}"
            
            echo -n "  安装 cloudflared... "
            sudo apt-get install -y cloudflared > /dev/null 2>&1
            echo -e "${GREEN}完成${NC}"
            ;;
        yum|dnf)
            echo -n "  添加仓库... "
            sudo tee /etc/yum.repos.d/cloudflared.repo > /dev/null << REPO
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
            sudo $PKG_INSTALL cloudflared > /dev/null 2>&1
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
            sudo curl -fsSL -o /usr/local/bin/cloudflared "$binary_url"
            sudo chmod +x /usr/local/bin/cloudflared
            echo -e "${GREEN}完成${NC}"
            ;;
    esac
    
    if command -v cloudflared &> /dev/null; then
        log_success "cloudflared 安装完成: $(cloudflared --version)"
    else
        log_error "cloudflared 安装失败"
        exit 1
    fi
}

# 创建智能连接脚本
create_smart_script() {
    log_step "创建智能连接脚本..."
    
    sudo tee /usr/local/bin/cloudflared-smart.sh > /dev/null << 'SCRIPT'
#!/bin/bash

TOKEN="'"${CLOUDFLARE_TOKEN}"'"
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
    
    if ! ping -6 -c 1 -W 3 2606:4700::1111 >/dev/null 2>&1; then
        log "IPv6 网络不可达"
        return 1
    fi
    
    return 0
}

# 尝试 IPv6
if check_ipv6; then
    log "IPv6 可用，尝试连接"
    if timeout 30 cloudflared tunnel --edge-ip-version 6 --protocol http2 run --token $TOKEN 2>/dev/null; then
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
    
    sudo chmod +x /usr/local/bin/cloudflared-smart.sh
    log_success "智能连接脚本创建完成"
}

# 创建 systemd 服务
create_systemd_service() {
    log_step "创建 systemd 服务..."
    
    sudo tee /etc/systemd/system/cloudflared.service > /dev/null << SERVICE
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
    sudo systemctl daemon-reload && echo -e "${GREEN}完成${NC}"
    
    echo -n "  启用开机自启... "
    sudo systemctl enable cloudflared.service > /dev/null 2>&1 && echo -e "${GREEN}完成${NC}"
    
    echo -n "  启动 cloudflared... "
    sudo systemctl start cloudflared.service && echo -e "${GREEN}完成${NC}"
    
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
        sudo systemctl status cloudflared.service --no-pager -l | head -15
        echo ""
        
        log_info "最近日志:"
        sudo journalctl -u cloudflared.service -n 10 --no-pager | grep -E "IPv[46]|Connected|Registered" || echo "  等待建立连接..."
        
        return 0
    else
        log_error "服务未运行"
        sudo journalctl -u cloudflared.service -n 20 --no-pager
        return 1
    fi
}

# 显示完成信息
show_complete() {
    echo ""
    log "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    log "${GREEN}║                    安装完成！                                ║${NC}"
    log "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_info "Cloudflare Tunnel 已安装并启动"
    log_info "智能连接: IPv6 优先，失败自动切换 IPv4"
    log_info "开机自启: 已启用"
    echo ""
    log "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${GREEN}常用管理命令:${NC}"
    log "${YELLOW}  查看状态:${NC} sudo systemctl status cloudflared"
    log "${YELLOW}  查看日志:${NC} sudo journalctl -u cloudflared -f"
    log "${YELLOW}  重启服务:${NC} sudo systemctl restart cloudflared"
    log "${YELLOW}  停止服务:${NC} sudo systemctl stop cloudflared"
    log "${YELLOW}  启动服务:${NC} sudo systemctl start cloudflared"
    log "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log_info "安装日志: $LOG_FILE"
    log_info "运行日志: /var/log/cloudflared.log"
}

# 卸载函数
uninstall() {
    log_step "卸载 Cloudflare Tunnel..."
    
    echo -n "  停止服务... "
    sudo systemctl stop cloudflared.service 2>/dev/null && echo -e "${GREEN}完成${NC}"
    
    echo -n "  禁用开机自启... "
    sudo systemctl disable cloudflared.service 2>/dev/null && echo -e "${GREEN}完成${NC}"
    
    echo -n "  删除服务文件... "
    sudo rm -f /etc/systemd/system/cloudflared.service
    echo -e "${GREEN}完成${NC}"
    
    echo -n "  删除脚本文件... "
    sudo rm -f /usr/local/bin/cloudflared-smart.sh
    echo -e "${GREEN}完成${NC}"
    
    sudo systemctl daemon-reload
    
    log_success "卸载完成"
    
    read -p "是否删除 cloudflared 二进制文件? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo rm -f $(which cloudflared)
        log_info "cloudflared 已删除"
    fi
}

# 主函数
main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--token)
                CLOUDFLARE_TOKEN="$2"
                shift 2
                ;;
            --uninstall)
                check_root
                uninstall
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    check_root
    show_title
    check_token
    detect_os
    check_and_uninstall
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

# 帮助信息
show_help() {
    cat << EOF
Cloudflare Tunnel 安装脚本 v${VERSION}

用法: sudo $0 [选项]

选项:
    -t, --token TOKEN      设置 Cloudflare Tunnel Token
    --uninstall            卸载服务
    -h, --help             显示帮助

示例:
    sudo $0 -t "your-token-here"
    sudo $0 --uninstall

说明:
    脚本会自动检测并卸载旧服务
    安装后自动启动并设置开机自启
    智能连接: IPv6 优先，失败自动切换 IPv4

GitHub: https://github.com/Cuscito/cloudflare-tunnel-installer
EOF
}

# 运行
main "$@"
EOF

chmod +x scripts/install-cloudflared.sh
