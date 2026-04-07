# cloudflare-tunnel-installer
One-click installer for Cloudflare Tunnel with IPv6/IPv4 auto-switch
# Cloudflare Tunnel 一键安装脚本

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

一键安装 Cloudflare Tunnel，支持 IPv6/IPv4 智能切换和开机自启。

## ✨ 特性

- 🚀 **一键安装** - 自动安装 cloudflared 并配置服务
- 🔄 **智能切换** - 优先使用 IPv6，失败自动切换 IPv4
- 🔧 **多系统支持** - Ubuntu, Debian, CentOS, RHEL, Fedora 等
- 📦 **开机自启** - 配置 systemd 服务，自动重启

## 🚀 快速开始

### 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/Cuscito/cloudflare-tunnel-installer/main/scripts/install-cloudflared.sh | sudo bash -s -- -t "YOUR_TOKEN"
参数说明
参数	说明
-t, --token TOKEN	Cloudflare Tunnel Token (必需)
--force-ipv4	强制使用 IPv4
--force-ipv6	强制使用 IPv6
--uninstall	卸载服务
# 基本安装
sudo bash install-cloudflared.sh -t "your-token"

# 强制 IPv4
sudo bash install-cloudflared.sh -t "your-token" --force-ipv4

# 卸载
sudo bash install-cloudflared.sh --uninstall
📦 管理命令
安装完成后：
# 查看状态
sudo systemctl status cloudflared

# 查看日志
sudo journalctl -u cloudflared -f

# 重启服务
sudo systemctl restart cloudflared

# 停止服务
sudo systemctl stop cloudflared

📝 日志文件
服务日志: sudo journalctl -u cloudflared -f

智能切换日志: sudo tail -f /var/log/cloudflared.log

❓ 常见问题
如何获取 Token？
登录 Cloudflare Zero Trust → Networks → Tunnels → 创建 Tunnel → 复制 Token

如何查看当前使用的 IP 协议？
sudo journalctl -u cloudflared -n 50 | grep -E "IPv[46]"
📄 许可证
MIT License

🤝 贡献
欢迎提交 Issue 和 Pull Request！
