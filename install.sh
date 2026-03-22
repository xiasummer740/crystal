#!/bin/bash
set -e
export LANG=C
export LC_ALL=C
export PATH=$PATH:/usr/sbin:/sbin:/usr/local/bin

clear
echo "============================================="
echo " Crystal Radar - Secure Deployment "
echo "============================================="
echo ""
read -p "Input Domain or IP [eg: crystal.taikon.top]: " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then DOMAIN_NAME="localhost"; fi

PROJECT_DIR="/var/www/crystal"

echo "[1/6] Allocating 2GB Swap Memory..."
if [ $(free -m | awk '/^Swap:/ {print $2}') -eq 0 ]; then
    dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1
    swapon /swapfile || true
fi

echo "[2/6] Installing Dependencies & OpenSSL..."
if [ -f /etc/debian_version ]; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y git curl wget unzip nginx nodejs npm iptables procps openssl >/dev/null 2>&1
else
    yum install -y epel-release >/dev/null 2>&1
    yum install -y git curl wget unzip nginx nodejs npm iptables procps openssl >/dev/null 2>&1
    systemctl enable nginx || true
fi

echo "[3/6] Configuring Firewall (Port 80 & 443)..."
if command -v ufw >/dev/null 2>&1; then ufw allow 80/tcp >/dev/null 2>&1 || true; ufw allow 443/tcp >/dev/null 2>&1 || true; fi
if command -v firewall-cmd >/dev/null 2>&1; then 
    firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true; 
    firewall-cmd --add-port=443/tcp --permanent >/dev/null 2>&1 || true; 
    firewall-cmd --reload >/dev/null 2>&1 || true; 
fi
if command -v iptables >/dev/null 2>&1; then 
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true; 
    iptables -I INPUT -p tcp --dport 443 -j ACCEPT >/dev/null 2>&1 || true; 
fi

echo "[4/6] Upgrading Node.js to v20 & PM2..."
npm install -g n >/dev/null 2>&1
n 20 >/dev/null 2>&1
hash -r
npm install -g pm2 >/dev/null 2>&1 || true

echo "[5/6] Compiling Engines (Please wait)..."
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

echo "[6/6] Generating SSL Cert & Isolated Nginx Config..."
# 自动生成十年有效期的自签证书
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/crystal.key \
  -out /etc/nginx/ssl/crystal.crt \
  -subj "/C=CN/ST=BJ/L=BJ/O=CrystalRadar/CN=$DOMAIN_NAME" >/dev/null 2>&1

mkdir -p /etc/nginx/conf.d
CONF_FILE="/etc/nginx/conf.d/crystal.conf"

# 【核心防爆】：逐行写入，绝对隔离回车符，且不删除其他项目配置
echo "server {" > "$CONF_FILE"
echo "    listen 80;" >> "$CONF_FILE"
echo "    server_name $DOMAIN_NAME;" >> "$CONF_FILE"
echo "    return 301 https://\$host\$request_uri;" >> "$CONF_FILE"
echo "}" >> "$CONF_FILE"
echo "server {" >> "$CONF_FILE"
echo "    listen 443 ssl;" >> "$CONF_FILE"
echo "    server_name $DOMAIN_NAME;" >> "$CONF_FILE"
echo "    ssl_certificate /etc/nginx/ssl/crystal.crt;" >> "$CONF_FILE"
echo "    ssl_certificate_key /etc/nginx/ssl/crystal.key;" >> "$CONF_FILE"
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

# 清洗自身可能的杂质
sed -i 's/\r//g' "$CONF_FILE"

nginx -t || { echo "Nginx syntax error! Check $CONF_FILE"; exit 1; }
systemctl restart nginx || true

echo "============================================="
echo " Deployment Successful! "
echo " Please open: https://$DOMAIN_NAME"
echo " (Note: Accept the self-signed SSL warning in browser)"
echo "============================================="
