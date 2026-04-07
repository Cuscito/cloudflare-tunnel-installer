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
- [📄 许可证](#-许可证)

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
使用示例
bash
# 基本安装（替换为您的实际 Token）
curl -fsSL https://raw.githubusercontent.com/Cuscito/cloudflare-tunnel-installer/main/scripts/install-cloudflared.sh | sudo bash -s -- "eyJhIjoi..."

# 查看帮助
curl -fsSL https://raw.githubusercontent.com/Cuscito/cloudflare-tunnel-installer/main/scripts/install-cloudflared.sh | bash -s -- -h

# 卸载服务（需要先下载脚本）
wget https://raw.githubusercontent.com/Cuscito/cloudflare-tunnel-installer/main/scripts/install-cloudflared.sh
sudo bash install-cloudflared.sh --uninstall
📝 详细说明
安装流程
脚本会自动执行以下步骤：

text
1. 检测系统类型 (Ubuntu/Debian/CentOS/RHEL/Fedora)
2. 清理旧服务 (停止、禁用、删除配置文件)
3. 安装 cloudflared (自动选择包管理器或二进制下载)
4. 创建智能连接脚本 (IPv6 优先，失败自动切换 IPv4)
5. 创建 systemd 服务 (开机自启、自动重启)
6. 启动服务并验证状态
7. 显示连接信息和常用命令
智能连接逻辑
text
启动
  ↓
检测 IPv6 支持
  ↓
IPv6 可用？ ──否──→ 使用 IPv4 连接
  ↓ 是
尝试 IPv6 连接
  ↓
连接成功？ ──否──→ 使用 IPv4 连接
  ↓ 是
使用 IPv6 连接
文件结构
安装后会在系统中创建以下文件：

文件路径	说明
/usr/local/bin/cloudflared-smart.sh	智能连接脚本
/etc/systemd/system/cloudflared.service	systemd 服务文件
/var/log/cloudflared.log	运行日志
/var/log/cloudflared-install.log	安装日志
🔧 管理命令
服务管理
bash
# 查看服务状态
sudo systemctl status cloudflared

# 启动服务
sudo systemctl start cloudflared

# 停止服务
sudo systemctl stop cloudflared

# 重启服务
sudo systemctl restart cloudflared

# 查看是否开机自启
sudo systemctl is-enabled cloudflared
日志查看
bash
# 查看实时日志
sudo journalctl -u cloudflared -f

# 查看最近 50 行日志
sudo journalctl -u cloudflared -n 50

# 查看智能切换日志
sudo tail -f /var/log/cloudflared.log

# 查看安装日志
sudo cat /var/log/cloudflared-install.log
连接测试
bash
# 查看当前使用的协议 (IPv6/IPv4)
sudo journalctl -u cloudflared -n 20 | grep -E "IPv[46]"

# 测试 IPv6 连通性
ping6 -c 4 2606:4700::1111

# 手动测试连接
sudo /usr/local/bin/cloudflared-smart.sh "your-token"
📊 运行效果
安装成功界面
text
╔══════════════════════════════════════════════════════════════╗
║     Cloudflare Tunnel 一键安装脚本 v2.4.0                    ║
║     https://github.com/Cuscito/cloudflare-tunnel-installer  ║
╚══════════════════════════════════════════════════════════════╝

[STEP] 检测系统类型...
[INFO] 系统: Ubuntu (Debian系列)

[STEP] 清理旧服务...
[✓] 清理完成

[STEP] 安装 cloudflared...
  添加 GPG 密钥... ✓
  添加软件源... ✓
  更新软件包列表... ✓
  安装 cloudflared... ✓
[✓] cloudflared 安装完成: cloudflared version 2026.3.0

[STEP] 创建智能连接脚本...
[✓] 智能连接脚本创建完成

[STEP] 创建 systemd 服务...
[✓] systemd 服务创建完成

[STEP] 启动服务...
  重新加载 systemd... ✓
  启用开机自启... ✓
  启动 cloudflared... ✓

[STEP] 测试连接状态...
  ✓ Tunnel 已成功注册

[STEP] 检查服务状态...

[✓] 服务运行中

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📡 当前连接状态:
  ✓ 当前使用: IPv6
  📍 边缘节点: connIndex=0 ip=2606:4700:a0::5
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

● cloudflared.service - Cloudflare Tunnel
     Loaded: loaded (/etc/systemd/system/cloudflared.service; enabled)
     Active: active (running) since Tue 2026-04-07 17:25:15 UTC
   Main PID: 15782 (cloudflared)
      Tasks: 10 (limit: 4600)
     Memory: 15.5M

╔══════════════════════════════════════════════════════════════╗
║                    安装完成！                                ║
╚══════════════════════════════════════════════════════════════╝

[INFO] Cloudflare Tunnel 已安装并启动
[INFO] 开机自启: 已启用

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 常用管理命令:
  查看状态: sudo systemctl status cloudflared
  查看日志: sudo journalctl -u cloudflared -f
  查看连接: sudo tail -f /var/log/cloudflared.log
  重启服务: sudo systemctl restart cloudflared
  停止服务: sudo systemctl stop cloudflared
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 故障排查
服务启动失败
bash
# 查看详细错误日志
sudo journalctl -u cloudflared -n 50 --no-pager

# 检查 Token 是否正确
sudo cat /usr/local/bin/cloudflared-smart.sh | grep TOKEN

# 手动测试连接
sudo cloudflared tunnel --protocol http2 run --token "your-token"
IPv6 连接问题
bash
# 检查 IPv6 支持
cat /proc/net/if_inet6

# 测试 IPv6 路由
ip -6 route show

# 测试 IPv6 DNS
nslookup -type=AAAA cloudflared.com 2606:4700::1111
端口被占用
bash
# 检查端口占用
sudo netstat -tlnp | grep 443
sudo ss -tlnp | grep 443

# 检查防火墙
sudo ufw status
sudo iptables -L -n
网络连接问题
bash
# 测试 Cloudflare 连通性
curl -I https://pkg.cloudflare.com

# 测试 DNS 解析
nslookup cloudflared.com

# 检查代理设置
echo $http_proxy
echo $https_proxy
🗑️ 卸载方法
方法一：使用脚本卸载
bash
# 下载脚本
wget https://raw.githubusercontent.com/Cuscito/cloudflare-tunnel-installer/main/scripts/install-cloudflared.sh

# 运行卸载
sudo bash install-cloudflared.sh --uninstall
方法二：完全手动卸载
bash
# 停止并禁用服务
sudo systemctl stop cloudflared.service
sudo systemctl disable cloudflared.service

# 删除服务文件
sudo rm -f /etc/systemd/system/cloudflared.service

# 删除脚本文件
sudo rm -f /usr/local/bin/cloudflared-smart.sh
sudo rm -f /usr/local/bin/cloudflared
sudo rm -f /usr/bin/cloudflared

# 删除日志文件
sudo rm -f /var/log/cloudflared.log
sudo rm -f /var/log/cloudflared-install.log

# 卸载 cloudflared 包
sudo apt-get remove -y cloudflared        # Debian/Ubuntu
sudo yum remove -y cloudflared            # CentOS/RHEL

# 删除软件源
sudo rm -f /etc/apt/sources.list.d/cloudflared.list
sudo rm -f /etc/yum.repos.d/cloudflared.repo

# 重新加载 systemd
sudo systemctl daemon-reload
一键完全卸载
bash
sudo systemctl stop cloudflared.service 2>/dev/null; sudo systemctl disable cloudflared.service 2>/dev/null; sudo rm -f /etc/systemd/system/cloudflared.service; sudo rm -f /usr/local/bin/cloudflared-smart.sh; sudo rm -f /usr/local/bin/cloudflared; sudo rm -f /usr/bin/cloudflared; sudo rm -f /var/log/cloudflared.log; sudo rm -f /var/log/cloudflared-install.log; sudo apt-get remove -y cloudflared 2>/dev/null; sudo apt-get autoremove -y 2>/dev/null; sudo rm -f /etc/apt/sources.list.d/cloudflared.list; sudo rm -f /usr/share/keyrings/cloudflare-archive-keyring.gpg; sudo systemctl daemon-reload; echo "✓ 卸载完成"
❓ 常见问题
Q1: 如何获取 Cloudflare Tunnel Token？
登录 Cloudflare Zero Trust

进入 Networks → Tunnels

点击 Create a tunnel

选择类型，命名后创建

复制显示的 Token

Q2: 如何查看当前使用的是 IPv6 还是 IPv4？
bash
sudo journalctl -u cloudflared -n 50 | grep -E "IPv[46]"
输出示例：

IPv6 连接成功 → 使用 IPv6

使用 IPv4 连接 → 使用 IPv4

Q3: 如何强制使用 IPv4？
编辑智能脚本：

bash
sudo nano /usr/local/bin/cloudflared-smart.sh
注释掉 IPv6 检测部分，直接使用 IPv4：

bash
# 直接使用 IPv4
exec cloudflared tunnel --protocol http2 --retries 5 --no-autoupdate run --token $TOKEN
然后重启服务：

bash
sudo systemctl restart cloudflared
Q4: 安装后没有自动连接？
bash
# 检查服务状态
sudo systemctl status cloudflared

# 查看日志找出原因
sudo journalctl -u cloudflared -n 50

# 重启服务
sudo systemctl restart cloudflared
Q5: Token 过期了怎么办？
在 Cloudflare 控制台重新生成 Token

更新脚本中的 Token：

bash
sudo nano /usr/local/bin/cloudflared-smart.sh
# 修改 TOKEN 变量
重启服务：

bash
sudo systemctl restart cloudflared
Q6: 如何更新到最新版本？
bash
# 重新运行安装脚本（会自动覆盖）
curl -fsSL https://raw.githubusercontent.com/Cuscito/cloudflare-tunnel-installer/main/scripts/install-cloudflared.sh | sudo bash -s -- "YOUR_TOKEN"
Q7: 服务一直在重启怎么办？
bash
# 查看重启次数
sudo systemctl status cloudflared | grep "restart"

# 查看详细错误
sudo journalctl -u cloudflared -n 100 --no-pager

# 常见原因：
# 1. Token 无效或过期
# 2. 网络连接问题
# 3. 防火墙阻止
📄 许可证
MIT License - 详见 LICENSE 文件

🤝 贡献
欢迎提交 Issue 和 Pull Request！

GitHub Issues

GitHub Pull Requests

📞 联系方式
作者: Cuscito

GitHub: @Cuscito

项目地址: cloudflare-tunnel-installer

<div align="center">
⭐ 如果这个项目对您有帮助，请给个 Star 支持一下！

</div> ```
