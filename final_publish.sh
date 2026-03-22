#!/bin/bash
set -e

PROJECT_DIR="/var/www/crystal"
cd "$PROJECT_DIR"

echo ">>> 1. 正在将 Node.js 20 强升逻辑与入口智能嗅探固化进 install.sh 源码..."

cat << 'EOF_SCRIPT' > install.sh
#!/bin/bash
set -e
export LANG=C
export LC_ALL=C

clear
echo "============================================="
echo " Crystal Radar - Ultimate Auto Deployment "
echo "============================================="
echo ""
read -p "Input Domain or IP [eg: 154.31.157.42]: " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then
    DOMAIN_NAME="localhost"
fi

PROJECT_DIR="/var/www/crystal"
echo "Starting deployment..."

echo "[1/4] Installing System Dependencies..."
if [ -f /etc/debian_version ]; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y git curl wget unzip nginx nodejs npm >/dev/null 2>&1
elif [ -f /etc/redhat-release ]; then
    yum install -y epel-release >/dev/null 2>&1
    yum install -y git curl wget unzip nginx nodejs npm >/dev/null 2>&1
    systemctl enable nginx >/dev/null 2>&1 || true
fi

echo "[2/4] Upgrading to Node.js v20 & Installing PM2..."
npm install -g n >/dev/null 2>&1
n 20 >/dev/null 2>&1
hash -r
npm install -g pm2 >/dev/null 2>&1 || true

echo "[3/4] Compiling Core Engines (Taking 1-2 mins)..."
cd "$PROJECT_DIR/backend"
rm -rf node_modules package-lock.json
npm install >/dev/null 2>&1
pm2 stop crystal-api >/dev/null 2>&1 || true

# 智能嗅探启动入口，彻底消灭 Script not found 报错
if [ -f "server.js" ]; then
    pm2 start server.js --name "crystal-api" >/dev/null 2>&1
elif [ -f "app.js" ]; then
    pm2 start app.js --name "crystal-api" >/dev/null 2>&1
elif [ -f "index.js" ]; then
    pm2 start index.js --name "crystal-api" >/dev/null 2>&1
else
    MAIN_FILE=$(grep '"main"' package.json | head -n 1 | awk -F'"' '{print $4}')
    pm2 start "$MAIN_FILE" --name "crystal-api" >/dev/null 2>&1
fi
pm2 save >/dev/null 2>&1 || true

cd "$PROJECT_DIR/frontend"
rm -rf node_modules package-lock.json
npm install >/dev/null 2>&1
npm run build >/dev/null 2>&1

echo "[4/4] Configuring Nginx Routing..."
CONF_FILE="/etc/nginx/conf.d/crystal.conf"
echo "server {" > "$CONF_FILE"
echo "    listen 80;" >> "$CONF_FILE"
echo "    server_name $DOMAIN_NAME;" >> "$CONF_FILE"
echo "    location / {" >> "$CONF_FILE"
echo "        root $PROJECT_DIR/frontend/dist;" >> "$CONF_FILE"
echo "        index index.html;" >> "$CONF_FILE"
echo "        try_files \$uri \$uri/ /index.html;" >> "$CONF_FILE"
echo "    }" >> "$CONF_FILE"
echo "    location /api/ {" >> "$CONF_FILE"
echo "        proxy_pass [http://127.0.0.1:3000/](http://127.0.0.1:3000/);" >> "$CONF_FILE"
echo "        proxy_set_header Host \$host;" >> "$CONF_FILE"
echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$CONF_FILE"
echo "        proxy_buffering off;" >> "$CONF_FILE"
echo "        proxy_read_timeout 300s;" >> "$CONF_FILE"
echo "    }" >> "$CONF_FILE"
echo "}" >> "$CONF_FILE"

if [ -f /etc/nginx/sites-enabled/default ]; then
    rm -f /etc/nginx/sites-enabled/default
fi
systemctl restart nginx >/dev/null 2>&1 || true

clear
echo "============================================="
echo " Deployment Successful!"
echo " URL: http://$DOMAIN_NAME"
echo "============================================="
echo " Next Steps:"
echo " 1. Open the URL in your browser."
echo " 2. Click 'Config' (Top Right) to set your API Key."
echo "============================================="
EOF_SCRIPT

chmod +x install.sh
sed -i 's/\r$//' install.sh

echo ">>> 2. 正在重写 README.md：注入全自动【上帝指令】..."
cat << 'EOF_README' > README.md
# 🔮 Crystal Radar (人机协同精准雷达)

> 一款专为 B2B 硬件销售打造的**商业情报狙击 SaaS 系统**。采用顶级流体毛玻璃视觉，结合 AI 与官网物理强扒引擎，实现秒级企业研报与图文缝合。

## 🚀 终极小白“无脑一行流”部署法

**无需预装 Git，无需懂代码！** 只要您购买了一台**全新的 Ubuntu/Debian/CentOS 服务器**，请直接全选复制下方这一整段“上帝指令”，粘贴到您的服务器终端并回车：

```bash
if [ -f /etc/debian_version ]; then apt-get update -y && apt-get install -y git curl; else yum install -y git curl; fi && rm -rf /var/www/crystal && git clone -b crystal https://github.com/xiasummer740/crystal.git /var/www/crystal && cd /var/www/crystal && bash install.sh
```

> **执行后，终端会自动询问：**
> 👉 `Input Domain or IP [eg: 154.31.157.42]:` 
> 输入您解析好的域名（或直接输入 IP）并回车。
> 接下来请去喝杯咖啡（约2分钟），系统会自动完成 Git安装、源码下载、Node.js 20 升级、Nginx 路由接管和进程守护！

## 💡 唤醒 AI 神经元
在浏览器输入您刚才绑定的域名或 IP，进入系统。
点击右上角的 **【配置】** 按钮，填入您的 API Key（推荐使用 DeepSeek / OpenAI 等），点击保存，雷达即可开火！

## ✨ 核心杀手锏
1. **零外援·官网底层强扒**：穿透 Vue/React 懒加载，提取真图与产品交叉缝合。
2. **TCP 防爆与 OOM 保护**：15款核心产品安全限流，绝不断连。
3. **英文规格书极速破译**：秒解芯片 PDF，提取外接晶振硬性指标。
4. **GeoQ/高德免墙沙盘**：自带 HTTP `no-referrer` 隐身斗篷，碾碎防盗链。
EOF_README

echo ">>> 3. 正在提交并强推至 GitHub..."
git add install.sh README.md
git commit -m "🚀 [GodMode] 彻底解决纯裸机无 Git 问题，集成 Node20 原地强升，发布单行上帝指令" || true
git push origin crystal -f

echo "========================================================="
echo " ✅ 终极同步完成！完美的 README 和防爆安装器已推送！"
echo "========================================================="
