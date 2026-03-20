#!/bin/bash
set -e

PROJECT_DIR="/var/www/crystal"

echo ">>> 1. 正在重写真正的【全自动交互式部署引擎】(install.sh)..."

cat << 'EOF_SCRIPT' > "$PROJECT_DIR/install.sh"
#!/bin/bash
# ==========================================================
# Crystal Radar (晶振智能雷达) - 纯净 VPS 终极一键部署脚本
# ==========================================================
set -e

# --- 1. 交互式收集部署信息 ---
clear
echo "========================================================="
echo " 🔮 欢迎使用 Crystal Radar 全自动部署引导"
echo "========================================================="
echo ""
read -p "👉 请输入您要绑定的域名 (例如 crystal.taikon.top，如果没有请填 IP): " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then
    DOMAIN_NAME="localhost"
fi

PROJECT_DIR="$(pwd)"
echo -e "\n⏳ 收到指令！开始在纯净系统上为您建造雷达基站..."

# --- 2. 自动识别系统并安装底层依赖 (Nginx/Curl/Git) ---
echo "⚙️ [1/4] 正在安装底层运行环境 (Nginx & 依赖)..."
if [ -f /etc/debian_version ]; then
    apt-get update -y > /dev/null 2>&1
    apt-get install -y curl wget git unzip nginx > /dev/null 2>&1
elif [ -f /etc/redhat-release ]; then
    yum install -y epel-release > /dev/null 2>&1
    yum install -y curl wget git unzip nginx > /dev/null 2>&1
    systemctl enable nginx
fi

# --- 3. 自动安装 Node.js & PM2 ---
echo "⚙️ [2/4] 正在安装 Node.js 引擎与 PM2 守护进程..."
if ! command -v node > /dev/null; then
    curl -fsSL [https://deb.nodesource.com/setup_20.x](https://deb.nodesource.com/setup_20.x) | bash - > /dev/null 2>&1
    apt-get install -y nodejs > /dev/null 2>&1 || yum install -y nodejs > /dev/null 2>&1
fi
if ! command -v pm2 > /dev/null; then
    npm install pm2 -g > /dev/null 2>&1
fi

# --- 4. 自动编译与启动雷达前后端 ---
echo "📦 [3/4] 正在组装并点燃雷达数据引擎 (约需1-2分钟)..."
cd "$PROJECT_DIR/backend"
npm install > /dev/null 2>&1
pm2 stop crystal-api > /dev/null 2>&1 || true
pm2 start ./index.js --name "crystal-api" > /dev/null 2>&1
pm2 save > /dev/null 2>&1

cd "$PROJECT_DIR/frontend"
npm install > /dev/null 2>&1
npm run build > /dev/null 2>&1

# --- 5. 全自动 Nginx 路由接管配置 ---
echo "🌐 [4/4] 正在为您全自动配置 Nginx 反向代理与域名映射..."
NGINX_CONF="/etc/nginx/conf.d/crystal.conf"

cat << EOF_NGINX > "$NGINX_CONF"
server {
    listen 80;
    server_name $DOMAIN_NAME;

    # 前端静态文件代理
    location / {
        root $PROJECT_DIR/frontend/dist;
        index index.html index.htm;
        try_files \$uri \$uri/ /index.html;
    }

    # 后端 API 接口反向代理映射
    location /api/ {
        proxy_pass [http://127.0.0.1:3000/](http://127.0.0.1:3000/);
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # 允许流式响应不被 Nginx 截断
        proxy_buffering off;
        proxy_read_timeout 300s;
    }
}
EOF_NGINX

# 移除默认的 Nginx 页面防冲突 (Ubuntu/Debian 专属)
rm -f /etc/nginx/sites-enabled/default

# 重启 Nginx
systemctl restart nginx

# --- 6. 竣工撒花 ---
clear
echo "========================================================="
echo " 🎉 晶振智能雷达 (Crystal Radar) 部署大功告成！"
echo "========================================================="
echo " 🌐 您的专属访问地址: http://$DOMAIN_NAME"
echo ""
echo " 👉 下一步操作："
echo " 1. 请在浏览器打开上述网址。"
echo " 2. 点击右上角【配置】，填入您的 AI 密钥，雷达即可开火！"
echo ""
echo " (进阶提示：如果需要 HTTPS，请使用 certbot --nginx 自动签发证书)"
echo "========================================================="
EOF_SCRIPT

chmod +x "$PROJECT_DIR/install.sh"

echo ">>> 2. 正在重写白皮书 (README.md) 匹配终极两步部署法..."

cat << 'EOF_README' > "$PROJECT_DIR/README.md"
# 🔮 Crystal Radar (人机协同精准雷达)

> 一款专为 B2B 硬件销售打造的**商业情报狙击 SaaS 系统**。采用顶级流体毛玻璃视觉，结合 AI 与官网物理强扒引擎，实现秒级企业研报与图文缝合。

## 🚀 终极傻瓜式一键部署

无论您购买的是阿里云、腾讯云还是海外的纯净 VPS（Ubuntu/Debian/CentOS 均可），完全不需要懂编程或 Nginx 配置，只需两步即可点亮雷达：

### 步骤 1：下载雷达源码
登录您的全新 VPS 终端，执行克隆命令下载代码（请确保服务器已安装 git）：
```bash
git clone https://github.com/您的用户名/crystal.git
cd crystal
```

### 步骤 2：执行全自动交互式安装
在代码目录中运行一键安装脚本：
```bash
sudo bash install.sh
```
> **安装向导会自动问您：**
> 👉 `请输入您要绑定的域名 (如果没有请填 IP):` 
> 输入您解析好的域名（如 `radar.yourdomain.com`）并回车。

喝口水的时间（约 2 分钟），脚本会自动为您安装底层环境、配置 Nginx 路由代理、映射 3000 端口并启动防爆守护进程。

### 步骤 3：唤醒 AI 神经元
在浏览器输入您刚才绑定的域名，进入系统。
点击右上角的 **【配置】** 按钮，填入您的 API Key（支持 DeepSeek / 阿里千问 / OpenAI等），点击保存，雷达即可正式发车！

## ✨ 核心杀手锏
1. **零外援·官网底层强扒**：穿透 Vue/React 懒加载，提取真图与产品交叉缝合。
2. **TCP 防爆与 OOM 保护**：15款核心产品安全限流，绝不断连。
3. **英文规格书极速破译**：秒解芯片 PDF，提取外接晶振硬性指标。
4. **GeoQ/高德免墙沙盘**：自带 HTTP `no-referrer` 隐身斗篷，碾碎防盗链。
EOF_README

echo ">>> 3. 正在将完美版自动运维脚本推送到您的 GitHub 仓库..."
cd "$PROJECT_DIR"
git add install.sh README.md
git commit -m "🚀 [DevOps] 彻底重写 install.sh：实现全自动化 Nginx 路由接管与交互式域名绑定，真正实现小白级纯净 VPS 一键部署" || true
git push origin crystal

echo "========================================================="
echo " ✅ 终极补丁已提交并 Push 至 GitHub！"
echo " 现在，任何人只要拿到这个库，执行 bash install.sh 就能全自动建站了！"
echo "========================================================="
