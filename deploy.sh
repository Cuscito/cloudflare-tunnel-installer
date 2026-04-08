#!/bin/bash
# Cloudflare Tunnel + VLESS + WebSocket 易用性增强版
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
error_exit() { echo -e "${RED}✗ 错误：$1${NC}" >&2; exit 1; }
show_ok() { echo -e "${GREEN}✓ $1${NC}"; }
show_info() { echo -e "${BLUE}→ $1${NC}"; }
show_warn() { echo -e "${YELLOW}⚠ $1${NC}"; }

# 非交互模式：如果环境变量全部设置，则跳过所有询问
if [ -n "$CF_API_TOKEN" ] || [ -n "$CF_EMAIL" ] && [ -n "$CF_API_KEY" ]; then
    NONINTERACTIVE=true
    show_info "检测到环境变量，启用非交互模式"
else
    NONINTERACTIVE=false
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Cloudflare Tunnel + VLESS 易用版${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ---------- 备份旧配置 ----------
BACKUP_DIR="/tmp/cf-vless-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
if [ -d ~/.cloudflared ] || [ -d /usr/local/etc/xray ]; then
    show_info "备份旧配置到 $BACKUP_DIR"
    cp -r ~/.cloudflared "$BACKUP_DIR/" 2>/dev/null || true
    sudo cp -r /usr/local/etc/xray "$BACKUP_DIR/" 2>/dev/null || true
fi

# ---------- 认证方式 ----------
if [ "$NONINTERACTIVE" = false ]; then
    echo -e "${YELLOW}选择 Cloudflare 认证方式：${NC}"
    echo "1) API Token (推荐)"
    echo "2) Global API Key"
    read -p "输入选项 (1/2) [默认 1]: " AUTH_METHOD
    AUTH_METHOD=${AUTH_METHOD:-1}
else
    AUTH_METHOD="1"
fi

if [ "$AUTH_METHOD" = "1" ]; then
    if [ -z "$CF_API_TOKEN" ]; then
        read -p "API Token: " API_TOKEN
    else
        API_TOKEN="$CF_API_TOKEN"
        show_info "使用环境变量 CF_API_TOKEN"
    fi
    export CF_API_TOKEN="$API_TOKEN"
else
    if [ -z "$CF_EMAIL" ] || [ -z "$CF_API_KEY" ]; then
        read -p "账户邮箱: " CF_EMAIL
        read -p "Global API Key: " CF_API_KEY
    else
        show_info "使用环境变量 CF_EMAIL 和 CF_API_KEY"
    fi
    export CF_EMAIL CF_API_KEY
fi

# ---------- 基本配置（带智能默认值）----------
if [ "$NONINTERACTIVE" = false ]; then
    read -p "隧道名称 (自定义) [默认 tunnel-$(date +%s)]: " TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-tunnel-$(date +%s)}
    read -p "完整子域名 (如 proxy.example.com): " TUNNEL_HOST
    read -p "WebSocket 端口 [默认 8080]: " WS_PORT
    WS_PORT=${WS_PORT:-8080}
    read -p "WebSocket 路径 [默认 /ws]: " WS_PATH
    WS_PATH=${WS_PATH:-/ws}
    [[ $WS_PATH != /* ]] && WS_PATH="/$WS_PATH"
    DEFAULT_UUID=$(cat /proc/sys/kernel/random/uuid)
    read -p "VLESS UUID [回车随机生成]: " UUID
    UUID=${UUID:-$DEFAULT_UUID}
else
    TUNNEL_NAME=${TUNNEL_NAME:-tunnel-$(date +%s)}
    TUNNEL_HOST=${TUNNEL_HOST:?请设置环境变量 TUNNEL_HOST}
    WS_PORT=${WS_PORT:-8080}
    WS_PATH=${WS_PATH:-/ws}
    UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
fi

FAKE_HOST="$TUNNEL_HOST"

if [ "$NONINTERACTIVE" = false ]; then
    echo ""
    echo -e "${YELLOW}确认配置：${NC}"
    echo "隧道名称   : $TUNNEL_NAME"
    echo "子域名     : $TUNNEL_HOST"
    echo "WS 端口    : $WS_PORT"
    echo "WS 路径    : $WS_PATH"
    echo "UUID       : $UUID"
    echo "伪装域名   : $FAKE_HOST (自动)"
    read -p "确认无误？(y/n) " -n 1 -r; echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && error_exit "已取消"
fi

# ---------- 1. 清理 ----------
echo -e "\n${YELLOW}[1/9] 清理冲突服务与残留...${NC}"
read -p "彻底删除旧配置文件？(y/n) [默认 n]: " -n 1 -r; echo
CLEAN_ALL=${REPLY:-n}
if [[ $CLEAN_ALL =~ ^[Yy]$ ]]; then
    sudo systemctl stop xray cloudflared 2>/dev/null || true
    sudo systemctl disable xray cloudflared 2>/dev/null || true
    sudo rm -rf /usr/local/etc/xray
    sudo rm -f /etc/systemd/system/{xray,cloudflared}*.service
    rm -rf ~/.cloudflared
    show_ok "旧配置已清除"
else
    sudo systemctl stop xray cloudflared 2>/dev/null || true
    sudo systemctl disable xray cloudflared 2>/dev/null || true
fi
sudo cloudflared service uninstall 2>/dev/null || true
sudo rm -f /etc/systemd/system/cloudflared*.service /etc/cloudflared/config.yml
sudo systemctl daemon-reload

# ---------- 2. 安装依赖 ----------
echo -e "${YELLOW}[2/9] 安装系统依赖...${NC}"
command -v jq &>/dev/null || { sudo apt update && sudo apt install -y jq; }
command -v unzip &>/dev/null || sudo apt install -y unzip

ARCH=$(uname -m)
case $ARCH in
    x86_64) CF_ARCH="amd64"; XRAY_ARCH="64" ;;
    aarch64) CF_ARCH="arm64"; XRAY_ARCH="arm64-v8a" ;;
    armv7l) CF_ARCH="arm"; XRAY_ARCH="armv7a" ;;
    *) error_exit "不支持的架构: $ARCH" ;;
esac

if ! command -v cloudflared &>/dev/null; then
    show_info "安装 cloudflared..."
    curl -L --fail --retry 3 "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$CF_ARCH" -o cloudflared
    chmod +x cloudflared && sudo mv cloudflared /usr/local/bin/
    show_ok "cloudflared 安装完成"
fi

if ! command -v xray &>/dev/null; then
    show_info "安装 Xray-core..."
    curl -L --fail --retry 3 "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$XRAY_ARCH.zip" -o xray.zip
    unzip -o xray.zip -d /tmp/xray
    sudo mv /tmp/xray/xray /usr/local/bin/
    sudo chmod +x /usr/local/bin/xray
    rm -rf xray.zip /tmp/xray
    show_ok "Xray-core 安装完成"
fi

# ---------- 3. Cloudflare 证书 ----------
echo -e "${YELLOW}[3/9] 配置 Cloudflare 证书...${NC}"
mkdir -p ~/.cloudflared
if [ ! -f ~/.cloudflared/cert.pem ] || ! grep -q "BEGIN CERTIFICATE" ~/.cloudflared/cert.pem 2>/dev/null; then
    show_warn "需要登录 Cloudflare 获取证书"
    rm -f ~/.cloudflared/cert.pem
    cloudflared tunnel login || error_exit "登录失败，请重试"
fi
show_ok "证书就绪"

# ---------- 4. 隧道 ----------
echo -e "${YELLOW}[4/9] 管理 Cloudflare 隧道...${NC}"
EXISTING_ID=$(cloudflared tunnel list -o json | jq -r '.[] | select(.name=="'$TUNNEL_NAME'") | .id')
if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "null" ]; then
    TUNNEL_ID="$EXISTING_ID"
    show_ok "使用现有隧道: $TUNNEL_ID"
else
    cloudflared tunnel create "$TUNNEL_NAME"
    TUNNEL_ID=$(cloudflared tunnel list -o json | jq -r '.[] | select(.name=="'$TUNNEL_NAME'") | .id')
    show_ok "隧道创建成功: $TUNNEL_ID"
fi

# ---------- 5. DNS ----------
echo -e "${YELLOW}[5/9] 配置 DNS 记录...${NC}"
if cloudflared tunnel route dns "$TUNNEL_NAME" "$TUNNEL_HOST" 2>&1 | grep -q "already exists"; then
    show_warn "DNS 记录已存在"
    read -p "是否覆盖？(y/n) [默认 n]: " -n 1 -r; echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cloudflared tunnel route dns --overwrite-dns "$TUNNEL_NAME" "$TUNNEL_HOST"
        show_ok "DNS 记录已覆盖"
    else
        show_info "保留原有 DNS 记录"
    fi
else
    show_ok "DNS 记录配置成功"
fi

# ---------- 6. cloudflared 配置 ----------
echo -e "${YELLOW}[6/9] 生成 cloudflared 配置...${NC}"
CRED_FILE="$HOME/.cloudflared/$TUNNEL_ID.json"
cat > ~/.cloudflared/config.yml << EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE
edge-ip-version: "4"
protocol: http2

ingress:
  - hostname: $TUNNEL_HOST
    service: http://127.0.0.1:$WS_PORT
  - service: http_status:404
EOF
show_ok "cloudflared 配置已生成"

# ---------- 7. Xray 配置 ----------
echo -e "${YELLOW}[7/9] 生成 Xray 配置...${NC}"
sudo mkdir -p /usr/local/etc/xray
sudo tee /usr/local/etc/xray/config.json > /dev/null << EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $WS_PORT,
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "$UUID", "level": 0 }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": { "path": "$WS_PATH" }
    }
  }],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
EOF
show_ok "Xray 配置已生成"

# ---------- 8. 启动服务 ----------
echo -e "${YELLOW}[8/9] 启动服务...${NC}"
sudo tee /etc/systemd/system/xray.service > /dev/null << 'EOF'
[Unit]
Description=Xray Service
After=network.target
[Service]
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/cloudflared.service > /dev/null << EOF
[Unit]
Description=cloudflared
After=network.target
[Service]
ExecStart=/usr/local/bin/cloudflared --config /root/.cloudflared/config.yml tunnel run $TUNNEL_NAME
Restart=always
RestartSec=10
TimeoutStartSec=600
ExecStartPre=/bin/sleep 5
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable xray cloudflared
sudo systemctl restart xray cloudflared
sleep 3

if systemctl is-active --quiet xray && systemctl is-active --quiet cloudflared; then
    show_ok "所有服务已启动"
else
    show_warn "服务启动异常，查看日志：journalctl -u xray -u cloudflared"
fi

# ---------- 9. 健康检查与输出 ----------
echo -e "\n${YELLOW}[9/9] 连通性自检...${NC}"
WS_TEST=$(curl -s -o /dev/null -w "%{http_code}" -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Host: $TUNNEL_HOST" "http://127.0.0.1:$WS_PORT$WS_PATH")
if [ "$WS_TEST" = "101" ]; then
    show_ok "本地 WebSocket 握手成功"
else
    show_warn "本地测试返回 HTTP $WS_TEST（VLESS 协议下正常）"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} 部署成功！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 表格展示
echo -e "${BLUE}┌─────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│            VLESS 节点配置               │${NC}"
echo -e "${BLUE}├─────────────────────────────────────────┤${NC}"
printf "${BLUE}│${NC} %-12s ${GREEN}%-26s${NC} ${BLUE}│${NC}\n" "地址" "$TUNNEL_HOST"
printf "${BLUE}│${NC} %-12s ${GREEN}%-26s${NC} ${BLUE}│${NC}\n" "端口" "443"
printf "${BLUE}│${NC} %-12s ${GREEN}%-26s${NC} ${BLUE}│${NC}\n" "UUID" "$UUID"
printf "${BLUE}│${NC} %-12s ${GREEN}%-26s${NC} ${BLUE}│${NC}\n" "加密" "none"
printf "${BLUE}│${NC} %-12s ${GREEN}%-26s${NC} ${BLUE}│${NC}\n" "传输" "ws"
printf "${BLUE}│${NC} %-12s ${GREEN}%-26s${NC} ${BLUE}│${NC}\n" "路径" "$WS_PATH"
printf "${BLUE}│${NC} %-12s ${GREEN}%-26s${NC} ${BLUE}│${NC}\n" "TLS" "开启"
printf "${BLUE}│${NC} %-12s ${GREEN}%-26s${NC} ${BLUE}│${NC}\n" "SNI" "$FAKE_HOST"
printf "${BLUE}│${NC} %-12s ${GREEN}%-26s${NC} ${BLUE}│${NC}\n" "Host" "$FAKE_HOST"
printf "${BLUE}│${NC} %-12s ${GREEN}%-26s${NC} ${BLUE}│${NC}\n" "ALPN" "h2,http/1.1"
echo -e "${BLUE}└─────────────────────────────────────────┘${NC}"
echo ""

# 分享链接
SHARE_LINK="vless://$UUID@$TUNNEL_HOST:443?encryption=none&security=tls&sni=$FAKE_HOST&host=$FAKE_HOST&type=ws&path=${WS_PATH}&alpn=h2%2Chttp%2F1.1#${TUNNEL_NAME}"
echo -e "${YELLOW}▶ VLESS 分享链接：${NC}"
echo "$SHARE_LINK"
echo ""

# Clash Meta 配置（同时保存到文件）
CLASH_CONFIG="/tmp/clash-meta-${TUNNEL_NAME}.yaml"
cat > "$CLASH_CONFIG" << YAML_EOF
proxies:
  - name: "$TUNNEL_NAME"
    type: vless
    server: $TUNNEL_HOST
    port: 443
    uuid: $UUID
    network: ws
    tls: true
    udp: true
    servername: "$FAKE_HOST"
    client-fingerprint: chrome
    ws-opts:
      path: "$WS_PATH"
      headers:
        Host: "$FAKE_HOST"
    alpn:
      - h2
      - http/1.1
YAML_EOF
echo -e "${YELLOW}▶ Clash Meta 配置已保存至: ${NC}$CLASH_CONFIG"

# 二维码
if command -v qrencode &>/dev/null; then
    echo -e "${YELLOW}▶ 分享链接二维码：${NC}"
    echo "$SHARE_LINK" | qrencode -t ANSIUTF8
fi

echo ""
echo -e "${GREEN}管理命令：${NC}"
echo "  查看日志: journalctl -u xray -f | journalctl -u cloudflared -f"
echo "  重启服务: sudo systemctl restart xray cloudflared"
echo "  回滚配置: 备份位于 $BACKUP_DIR"
echo ""

# 客户端连接性提示
echo -e "${YELLOW}▶ 客户端连接性检查清单：${NC}"
echo "  1. Cloudflare 仪表盘中 $TUNNEL_HOST 的 DNS 记录必须为 '已代理' (黄云)"
echo "  2. Cloudflare SSL/TLS 设置为 '完全' 或 '完全（严格）'"
echo "  3. 客户端配置的地址、UUID、路径必须与上述输出完全一致"
echo "  4. 如果连接失败，尝试在客户端开启 '允许不安全' 进行测试"
echo ""

main "$@"
