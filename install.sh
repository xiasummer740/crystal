#!/bin/bash
set -e
export LANG=C
export LC_ALL=C
# 【修复】：把系统级目录强行加入环境变量，解决 iptables 找不到的问题
export PATH=$PATH:/usr/sbin:/sbin:/usr/local/bin

clear
echo "============================================="
echo " Crystal Radar - Ultimate Auto Deployment "
echo "============================================="
echo ""
read -p "Input Domain or IP [eg: 198.51.100.1]: " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then DOMAIN_NAME="localhost"; fi

PROJECT_DIR="/var/www/crystal"

echo "[1/6] Allocating 2GB Swap Memory..."
if [ $(free -m | awk '/^Swap:/ {print $2}') -eq 0 ]; then
    dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1
    swapon /swapfile || true
fi

echo "[2/6] Installing System Dependencies..."
if [ -f /etc/debian_version ]; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y git curl wget unzip nginx nodejs npm iptables procps >/dev/null 2>&1
else
    yum install -y epel-release >/dev/null 2>&1
    yum install -y git curl wget unzip nginx nodejs npm iptables procps >/dev/null 2>&1
    systemctl enable nginx || true
fi

echo "[3/6] Configuring Firewall..."
if command -v ufw >/dev/null 2>&1; then ufw allow 80/tcp >/dev/null 2>&1 || true; fi
if command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true; firewall-cmd --reload >/dev/null 2>&1 || true; fi
if command -v iptables >/dev/null 2>&1; then iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true; fi

echo "[4/6] Upgrading Node.js to v20 & Installing PM2..."
npm install -g n >/dev/null 2>&1
n 20 >/dev/null 2>&1
hash -r
npm install -g pm2 >/dev/null 2>&1 || true

echo "[5/6] Compiling Engines (Please wait 1-2 mins)..."
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

echo "[6/6] Configuring Nginx..."
rm -f /etc/nginx/sites-enabled/default || true
rm -f /etc/nginx/sites-available/default || true
rm -f /etc/nginx/conf.d/default.conf || true
rm -f /etc/nginx/sites-enabled/crystal.conf || true

mkdir -p /etc/nginx/conf.d
CONF_FILE="/etc/nginx/conf.d/crystal.conf"

# 【核心防爆】：使用严格单引号封闭 EOF_NGINX，杜绝一切变量解析错误
cat > "$CONF_FILE" << 'EOF_NGINX'
server {
    listen 80;
    server_name _DOMAIN_;
    location / {
        root _ROOT_/frontend/dist;
        index index.html;
        try_files $uri $uri/ /index.html;
    }
    location /api/ {
        proxy_pass [http://127.0.0.1:3000/](http://127.0.0.1:3000/);
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_buffering off;
        proxy_read_timeout 300s;
    }
}
EOF_NGINX

# 替换真实变量，并使用 sed 强行刮除所有可能存在的不可见 \r 回车符
sed -i "s|_DOMAIN_|$DOMAIN_NAME|g" "$CONF_FILE"
sed -i "s|_ROOT_|$PROJECT_DIR|g" "$CONF_FILE"
sed -i 's/\r//g' "$CONF_FILE"

# 语法自检
nginx -t || { echo "Nginx syntax error! Check $CONF_FILE"; exit 1; }
systemctl restart nginx || true

echo "============================================="
echo " Deployment Successful! Open http://$DOMAIN_NAME"
echo "============================================="
