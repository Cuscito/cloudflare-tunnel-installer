# 🌐 Cloudflare Tunnel 一键安装脚本

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/shell-bash-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux-red.svg)](https://www.linux.org/)
[![Version](https://img.shields.io/badge/version-2.4.0-orange.svg)](https://github.com/Cuscito/cloudflare-tunnel-installer)

> 一键安装 Cloudflare Tunnel，支持 IPv6/IPv4 智能切换、开机自启、完整日志记录

## 📖 目录

- [✨ 功能特性](#-功能特性)
- [📋 系统要求](#-系统要求)
- [🚀 快速开始](#-快速开始)
- [📝 详细说明](#-详细说明)
- [🔧 管理命令](#-管理命令)
- [📊 运行效果](#-运行效果)
- [🔍 故障排查](#-故障排查)
- [🗑️ 卸载方法](#️-卸载方法)
- [❓ 常见问题](#-常见问题)

---

## ✨ 功能特性

| 功能 | 说明 |
|:-----|:-----|
| 🚀 **一键安装** | 自动检测系统类型并安装 cloudflared |
| 🔄 **智能切换** | IPv6 优先，失败自动切换 IPv4 |
| 📦 **开机自启** | 配置 systemd 服务，自动重启 |
| 📊 **进度显示** | 彩色输出，实时显示安装进度 |
| 📝 **完整日志** | 详细的安装和运行日志记录 |
| 🔧 **多系统支持** | Ubuntu, Debian, CentOS, RHEL, Fedora 等 |
| 🧹 **自动清理** | 检测并卸载旧服务，避免冲突 |
| 📍 **节点信息** | 显示连接的 Cloudflare 边缘节点 |

---

## 📋 系统要求

- **操作系统**: Linux (x86_64 / ARM64 / ARMv7)
- **权限**: root 或 sudo 权限
- **网络**: 能够访问 GitHub 和 Cloudflare

### 支持的系统

| 系统 | 版本 | 架构 |
|:-----|:-----|:-----|
| Ubuntu | 18.04+ | amd64, arm64, armhf |
| Debian | 10+ | amd64, arm64, armhf |
| CentOS | 7+ | amd64, arm64 |
| RHEL | 7+ | amd64, arm64 |
| Fedora | 35+ | amd64, arm64 |
| Rocky Linux | 8+ | amd64, arm64 |
| AlmaLinux | 8+ | amd64, arm64 |

---

## 🚀 快速开始

### 一键安装命令

```bash
curl -fsSL https://raw.githubusercontent.com/Cuscito/cloudflare-tunnel-installer/main/scripts/install-cloudflared.sh | sudo bash -s -- "YOUR_TOKEN"
