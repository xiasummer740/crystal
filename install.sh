#!/bin/bash
set -e
export LANG=C
export LC_ALL=C

clear
echo "============================================="
echo " Crystal Radar - Ultimate Auto Deployment "
echo "============================================="
echo ""
# 【脱敏修复】：将提示词里的真实 IP 替换为通用占位符
read -p "Input Domain or IP [eg: 198.51.100.1]: " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then DOMAIN_NAME="localhost"; fi

PROJECT_DIR="/var/www/crystal"

echo "[1/6] 注入 2GB 虚拟内存 (防止低配机器 npm build 内存溢出)..."
if [ $(free -m | awk '/^Swap:/ {print $2}') -eq 0 ]; then
    dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1
    swapon /swapfile || true
    echo "Swap allocated successfully."
fi

echo "[2/6] 安装系统底层运行组件..."
if [ -f /etc/debian_version ]; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y git curl wget unzip nginx nodejs npm iptables >/dev/null 2>&1
else
    yum install -y epel-release >/dev/null 2>&1
    yum install -y git curl wget unzip nginx nodejs npm iptables >/dev/null 2>&1
    systemctl enable nginx || true
fi

echo "[3/6] 暴力破拆防火墙 (确保 80 端口彻底开放)..."
if command -v ufw >/dev/null 2>&1; then ufw allow 80/tcp >/dev/null 2>&1 || true; fi
if command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true; firewall-cmd --reload >/dev/null 2>&1 || true; fi
iptables -I INPUT -p tcp --dport 80 -j ACCEPT || true

echo "[4/6] 强制拉升 Node.js 引擎至 v20 & 部署 PM2..."
npm install -g n >/dev/null 2>&1
n 20 >/dev/null 2>&1
hash -r
npm install -g pm2 >/dev/null 2>&1 || true

echo "[5/6] 编译业务引擎 (可能需要 1-2 分钟，请耐心等待)..."
cd "$PROJECT_DIR/backend"
rm -rf node_modules package-lock.json
npm install >/dev/null 2>&1
pm2 stop crystal-api >/dev/null 2>&1 || true
MAIN_FILE=$(grep '"main"' package.json | head -n 1 | awk -F'"' '{print $4}' || echo "index.js")
pm2 start "$MAIN_FILE" --name "crystal-api" >/dev/null 2>&1
pm2 save >/dev/null 2>&1 || true

cd "$PROJECT_DIR/frontend"
rm -rf node_modules package-lock.json
npm install >/dev/null 2>&1
npm run build >/dev/null 2>&1

echo "[6/6] 配置 Nginx 路由结界..."
# 【核心修复】：彻底清理一切可能导致冲突的旧配置
rm -f /etc/nginx/sites-enabled/default || true
rm -f /etc/nginx/sites-available/default || true
rm -f /etc/nginx/conf.d/default.conf || true
rm -f /etc/nginx/sites-enabled/crystal.conf || true

mkdir -p /etc/nginx/conf.d
CONF_FILE="/etc/nginx/conf.d/crystal.conf"

cat > "$CONF_FILE" << EOF_NGINX
server {
    listen 80;
    server_name $DOMAIN_NAME;
    location / {
        root $PROJECT_DIR/frontend/dist;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
    location /api/ {
        proxy_pass [http://127.0.0.1:3000/](http://127.0.0.1:3000/);
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_buffering off;
        proxy_read_timeout 300s;
    }
}
EOF_NGINX

# 语法自检，确保不再带病启动
nginx -t || { echo "Nginx 配置文件存在错误，部署终止！"; exit 1; }
systemctl restart nginx || true

echo "============================================="
echo " Deployment Successful! Open http://$DOMAIN_NAME"
echo "============================================="
