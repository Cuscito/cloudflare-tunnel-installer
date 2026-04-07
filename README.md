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
