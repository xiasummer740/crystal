# 🔮 Crystal Radar (人机协同精准雷达)

## 🚀 极简两步部署 (小白专属)

无论您使用的是全新纯净的 Ubuntu、Debian 还是 CentOS 服务器，只需复制以下两步指令即可点亮全套雷达系统：

### 步骤 1：下载源码
请直接全选复制下方这一行指令并回车（它会自动给您安装 git 并下载代码）：

```bash
if [ -f /etc/debian_version ]; then apt-get update -y && apt-get install -y git curl; else yum install -y git curl; fi && rm -rf /var/www/crystal && git clone -b crystal https://github.com/xiasummer740/crystal.git /var/www/crystal
```

### 步骤 2：执行全自动安装向导
源码下载完毕后，执行终极安装脚本：

```bash
cd /var/www/crystal && bash install.sh
```
> **安装向导会自动问您：**
> 👉 `Input Domain or IP:` 输入您的 IP 回车即可。
> 系统将自动分配虚拟内存、放行防火墙并编译雷达。
