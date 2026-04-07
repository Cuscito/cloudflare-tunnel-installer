#!/bin/bash

##############################################################################
# Cloudflare Tunnel 一键安装脚本
# 支持 Ubuntu, Debian, CentOS, RHEL, Fedora, Rocky Linux, AlmaLinux
# GitHub: https://github.com/你的用户名/cloudflare-tunnel-installer
##############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VERSION="1.0.0"

# 显示帮助
show_help() {
    cat << EOF
Cloudflare Tunnel 安装脚本 v${VERSION}

用法: sudo $0 -t TOKEN [选项]

选项:
    -t, --token TOKEN       Cloudflare Tunnel Token (必需)
    --force-ipv4            强制使用 IPv4
    --force-ipv6            强制使用 IPv6
    --uninstall             卸载服务
    -h, --help              显示帮助

示例:
    sudo $0 -t "your-token-here"
    sudo $0 -t "your-token" --force-ipv4
    sudo $0 --uninstall
EOF
}

# 检测系统
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo -e "${GREEN}[INFO]${NC} 检测到系统: $NAME"
    fi
}

# 安装 cloudflared
install_cloudflared() {
    echo -e "${BLUE}[1/4]${NC} 安装 cloudflared..."
    
    if command -v cloudflared &> /dev/null; then
        echo -e "${GREEN}[INFO]${NC} cloudflared 已安装: $(cloudflared --version)"
        return
    fi
    
    if command -v apt &> /dev/null; then
        curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | sudo gpg --dearmor | sudo tee /usr/share/keyrings/cloudflare-archive-keyring.gpg > /dev/null
        echo 'deb [signed-by=/usr/share/keyrings/cloudflare-archive-keyring.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list > /dev/null
        sudo apt-get update -qq && sudo apt-get install -y cloudflared
    elif command -v yum &> /dev/null; then
        sudo tee /etc/yum.repos.d/cloudflared.repo > /dev/null << REPO
[cloudflared]
name=Cloudflare cloudflared
baseurl=https://pkg.cloudflare.com/cloudflared/el/7/\$basearch
enabled=1
gpgcheck=1
gpgkey=https://pkg.cloudflare.com/cloudflare-public-v2.gpg
REPO
        sudo yum install -y cloudflared
    else
        sudo curl -fsSL -o /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
        sudo chmod +x /usr/local/bin/cloudflared
    fi
    
    echo -e "${GREEN}[INFO]${NC} cloudflared 安装完成"
}

# 创建智能连接脚本
create_smart_script() {
    echo -e "${BLUE}[2/4]${NC} 创建智能连接脚本..."
    
    if [[ "$FORCE_IPV6" == "true" ]]; then
        sudo tee /usr/local/bin/cloudflared-smart.sh > /dev/null << SCRIPT
#!/bin/bash
exec cloudflared tunnel --edge-ip-version 6 --protocol http2 --no-autoupdate run --token ${CLOUDFLARE_TOKEN}
SCRIPT
    elif [[ "$FORCE_IPV4" == "true" ]]; then
        sudo tee /usr/local/bin/cloudflared-smart.sh > /dev/null << SCRIPT
#!/bin/bash
exec cloudflared tunnel --protocol http2 --retries 5 --no-autoupdate run --token ${CLOUDFLARE_TOKEN}
SCRIPT
    else
        sudo tee /usr/local/bin/cloudflared-smart.sh > /dev/null << 'SCRIPT'
#!/bin/bash
TOKEN="'"${CLOUDFLARE_TOKEN}"'"

# 检测 IPv6 并尝试连接
if [ -f /proc/net/if_inet6 ]; then
    if ping -6 -c 1 -W 2 2606:4700::1111 >/dev/null 2>&1; then
        if timeout 30 cloudflared tunnel --edge-ip-version 6 --protocol http2 run --token $TOKEN 2>/dev/null; then
            exec cloudflared tunnel --edge-ip-version 6 --protocol http2 --no-autoupdate run --token $TOKEN
        fi
    fi
fi

# 使用 IPv4
exec cloudflared tunnel --protocol http2 --retries 5 --no-autoupdate run --token $TOKEN
SCRIPT
    fi
    
    sudo chmod +x /usr/local/bin/cloudflared-smart.sh
    echo -e "${GREEN}[INFO]${NC} 脚本创建完成"
}

# 创建 systemd 服务
create_systemd_service() {
    echo -e "${BLUE}[3/4]${NC} 创建 systemd 服务..."
    
    sudo tee /etc/systemd/system/cloudflared.service > /dev/null << SERVICE
[Unit]
Description=Cloudflare Tunnel
After=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10s
ExecStart=/usr/local/bin/cloudflared-smart.sh

[Install]
WantedBy=multi-user.target
SERVICE
    
    echo -e "${GREEN}[INFO]${NC} 服务创建完成"
}

# 启动服务
start_service() {
    echo -e "${BLUE}[4/4]${NC} 启动服务..."
    
    sudo systemctl daemon-reload
    sudo systemctl enable cloudflared.service
    sudo systemctl start cloudflared.service
    
    sleep 3
}

# 卸载服务
uninstall_service() {
    echo -e "${YELLOW}[INFO]${NC} 卸载 Cloudflare Tunnel..."
    sudo systemctl stop cloudflared.service 2>/dev/null
    sudo systemctl disable cloudflared.service 2>/dev/null
    sudo rm -f /etc/systemd/system/cloudflared.service
    sudo rm -f /usr/local/bin/cloudflared-smart.sh
    echo -e "${GREEN}[INFO]${NC} 卸载完成"
    exit 0
}

# 主函数
main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--token)
                CLOUDFLARE_TOKEN="$2"
                shift 2
                ;;
            --force-ipv4)
                FORCE_IPV4="true"
                shift
                ;;
            --force-ipv6)
                FORCE_IPV6="true"
                shift
                ;;
            --uninstall)
                uninstall_service
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}[ERROR]${NC} 未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$CLOUDFLARE_TOKEN" ]]; then
        echo -e "${RED}[ERROR]${NC} 请提供 Cloudflare Token"
        show_help
        exit 1
    fi
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Cloudflare Tunnel 安装脚本 v${VERSION}${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    detect_os
    install_cloudflared
    create_smart_script
    create_systemd_service
    start_service
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ 安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    sudo systemctl status cloudflared.service --no-pager
}

main "$@"
