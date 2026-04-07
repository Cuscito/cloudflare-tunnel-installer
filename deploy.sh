#!/bin/bash
# vless-cf-tunnel.sh - 直接在VPS上一键安装VLESS + Cloudflare Tunnel

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║     VLESS + Cloudflare Tunnel + TLS 一键安装脚本         ║
║         流量经过Cloudflare CDN + Tunnel穿透              ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用root用户运行此脚本"
        exit 1
    fi
}

check_system() {
    log_info "检查系统环境..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    else
        log_error "无法识别系统"
        exit 1
    fi
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) log_error "不支持的架构: $ARCH"; exit 1 ;;
    esac
    log_success "系统: $OS, 架构: $ARCH"
}

get_user_input() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}       请输入配置信息                  ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    while true; do
        read -p "$(echo -e ${YELLOW}请输入您的Cloudflare域名 (例: vless.example.com): ${NC})" DOMAIN
        if [[ -n "$DOMAIN" ]]; then
            break
        fi
    done
    
    echo -e "${BLUE}获取Cloudflare API Token步骤:${NC}"
    echo -e "  1. 访问 https://dash.cloudflare.com/profile/api-tokens"
    echo -e "  2. 点击 'Create Token'"
    echo -e "  3. 选择 'Edit zone DNS' 模板"
    echo -e "  4. 选择您的域名"
    echo -e "  5. 点击 'Continue to summary' -> 'Create Token'"
    echo ""
    
    while true; do
        read -p "$(echo -e ${YELLOW}请输入Cloudflare API Token: ${NC})" API_TOKEN
        if [[ -n "$API_TOKEN" ]]; then
            break
        fi
    done
    
    echo -e "${BLUE}获取Cloudflare Tunnel Token步骤:${NC}"
    echo -e "  1. 访问 https://one.dash.cloudflare.com/"
    echo -e "  2. 进入 'Networks' -> 'Tunnels'"
    echo -e "  3. 点击 'Create a tunnel'"
    echo -e "  4. 输入名称 (例: vless-tunnel)"
    echo -e "  5. 点击 'Save tunnel'"
    echo -e "  6. 选择 'Docker' 或 'Linux'"
    echo -e "  7. 复制 'cloudflared service install' 命令中的Token"
    echo ""
    
    while true; do
        read -p "$(echo -e ${YELLOW}请输入Cloudflare Tunnel Token: ${NC})" TUNNEL_TOKEN
        if [[ -n "$TUNNEL_TOKEN" ]]; then
            break
        fi
    done
    
    read -p "$(echo -e ${YELLOW}是否自动配置防火墙? (y/n, 默认y): ${NC})" CONFIG_FIREWALL
    CONFIG_FIREWALL=${CONFIG_FIREWALL:-y}
    
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${GREEN}配置信息确认:${NC}"
    echo -e "  域名: ${BLUE}$DOMAIN${NC}"
    echo -e "  API Token: ${BLUE}${API_TOKEN:0:20}...${NC}"
    echo -e "  Tunnel Token: ${BLUE}${TUNNEL_TOKEN:0:30}...${NC}"
    echo -e "  配置防火墙: ${BLUE}$CONFIG_FIREWALL${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}确认以上信息正确? (y/n, 默认y): ${NC})" CONFIRM
    CONFIRM=${CONFIRM:-y}
    
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        log_error "安装已取消"
        exit 0
    fi
}

install_dependencies() {
    log_info "安装系统依赖..."
    if command -v apt &> /dev/null; then
        apt update -y
        apt install -y curl wget openssl jq ufw systemd
    else
        log_error "不支持的包管理器"
        exit 1
    fi
    log_success "依赖安装完成"
}

install_cloudflared() {
    log_info "安装Cloudflared..."
    wget -q --show-progress "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}" -O /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
    log_success "Cloudflared安装成功"
}

install_xray() {
    log_info "安装Xray核心..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    log_success "Xray安装成功"
}

configure_dns() {
    log_info "配置Cloudflare DNS记录..."
    VPS_IP=$(curl -s ifconfig.me)
    ZONE_NAME=$(echo "$DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
        log_error "无法获取Zone ID"
        exit 1
    fi
    
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$DOMAIN\",\"content\":\"$VPS_IP\",\"ttl\":120,\"proxied\":true}" \
        > /dev/null
    
    log_success "DNS记录配置完成"
}

configure_tunnel() {
    log_info "配置Cloudflare Tunnel..."
    mkdir -p /etc/cloudflared
    echo "$TUNNEL_TOKEN" > /etc/cloudflared/tunnel.json
    TUNNEL_ID=$(echo "$TUNNEL_TOKEN" | cut -d: -f1)
    
    cat > /etc/cloudflared/config.yml <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: /etc/cloudflared/tunnel.json
ingress:
  - hostname: ${DOMAIN}
    service: https://localhost:8443
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF

    cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target
[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run
Restart=always
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable cloudflared
    log_success "Cloudflare Tunnel配置完成"
}

generate_cert() {
    log_info "生成TLS证书..."
    mkdir -p /etc/ssl/{certs,private}
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/cloudflare.key \
        -out /etc/ssl/certs/cloudflare.crt \
        -subj "/CN=${DOMAIN}" \
        -addext "subjectAltName=DNS:${DOMAIN}" 2>/dev/null
    log_success "TLS证书生成完成"
}

configure_xray() {
    log_info "配置Xray VLESS..."
    UUID=$(cat /proc/sys/kernel/random/uuid)
    WS_PATH=$(tr -dc 'a-z0-9' < /dev/urandom | fold -w 16 | head -n 1)
    
    cat > /usr/local/etc/xray/config.json <<EOF
{
  "inbounds": [
    {
      "port": 8443,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "${UUID}","flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificateFile": "/etc/ssl/certs/cloudflare.crt",
          "keyFile": "/etc/ssl/private/cloudflare.key"
        },
        "wsSettings": {
          "path": "/${WS_PATH}",
          "headers": {"Host": "${DOMAIN}"}
        }
      }
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

    systemctl restart xray
    
    VLESS_LINK="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2F${WS_PATH}&flow=xtls-rprx-vision"
    
    cat > /root/vless_info.txt <<EOF
域名: $DOMAIN
UUID: $UUID
路径: /$WS_PATH
链接: $VLESS_LINK
EOF
    
    log_success "Xray配置完成"
}

configure_firewall() {
    if [[ "$CONFIG_FIREWALL" == "y" ]]; then
        log_info "配置防火墙..."
        if command -v ufw &> /dev/null; then
            ufw allow 22/tcp
            ufw allow 443/tcp
            ufw --force enable
        fi
        log_success "防火墙配置完成"
    fi
}

start_services() {
    log_info "启动服务..."
    systemctl start cloudflared
    systemctl start xray
    sleep 3
    log_success "服务启动完成"
}

output_info() {
    clear
    echo -e "${GREEN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║             🎉 安装成功！VLESS节点已配置完成 🎉              ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    cat /root/vless_info.txt
    echo ""
    echo -e "${GREEN}客户端导入链接:${NC}"
    echo -e "${YELLOW}$(cat /root/vless_info.txt | grep "链接:" | cut -d' ' -f2)${NC}"
}

main() {
    check_root
    check_system
    get_user_input
    install_dependencies
    install_cloudflared
    install_xray
    configure_dns
    configure_tunnel
    generate_cert
    configure_xray
    configure_firewall
    start_services
    output_info
}

main