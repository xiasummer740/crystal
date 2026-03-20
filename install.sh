#!/bin/bash
set -e

# Force Unix line endings and basic locale
export LANG=C
export LC_ALL=C

clear
echo "========================================================="
echo " Crystal Radar - Auto Deployment Engine"
echo "========================================================="
echo ""
read -p "Please input your Domain [eg: crystal.taikon.top, or IP]: " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then
    DOMAIN_NAME="localhost"
fi

PROJECT_DIR="$PWD"
echo "Starting deployment..."

echo "[1/4] Installing Base Environment (Nginx & Curl)..."
if [ -f /etc/debian_version ]; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl wget git unzip nginx >/dev/null 2>&1
elif [ -f /etc/redhat-release ]; then
    yum install -y epel-release >/dev/null 2>&1
    yum install -y curl wget git unzip nginx >/dev/null 2>&1
    systemctl enable nginx >/dev/null 2>&1 || true
fi

echo "[2/4] Installing Node.js & PM2..."
curl -fsSL [https://deb.nodesource.com/setup_20.x](https://deb.nodesource.com/setup_20.x) | bash - >/dev/null 2>&1
if [ -f /etc/debian_version ]; then
    apt-get install -y nodejs >/dev/null 2>&1
else
    yum install -y nodejs >/dev/null 2>&1
fi
npm install pm2 -g >/dev/null 2>&1 || true

echo "[3/4] Compiling Core Engines (Taking 1-2 mins)..."
cd "$PROJECT_DIR/backend"
npm install >/dev/null 2>&1
pm2 stop crystal-api >/dev/null 2>&1 || true
pm2 start ./index.js --name "crystal-api" >/dev/null 2>&1
pm2 save >/dev/null 2>&1 || true

cd "$PROJECT_DIR/frontend"
npm install >/dev/null 2>&1
npm run build >/dev/null 2>&1

echo "[4/4] Configuring Nginx Routing..."
NGINX_CONF="/etc/nginx/conf.d/crystal.conf"

echo "server {" > "$NGINX_CONF"
echo "    listen 80;" >> "$NGINX_CONF"
echo "    server_name $DOMAIN_NAME;" >> "$NGINX_CONF"
echo "    location / {" >> "$NGINX_CONF"
echo "        root $PROJECT_DIR/frontend/dist;" >> "$NGINX_CONF"
echo "        index index.html;" >> "$NGINX_CONF"
echo "        try_files \$uri \$uri/ /index.html;" >> "$NGINX_CONF"
echo "    }" >> "$NGINX_CONF"
echo "    location /api/ {" >> "$NGINX_CONF"
echo "        proxy_pass [http://127.0.0.1:3000/](http://127.0.0.1:3000/);" >> "$NGINX_CONF"
echo "        proxy_set_header Host \$host;" >> "$NGINX_CONF"
echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$NGINX_CONF"
echo "        proxy_buffering off;" >> "$NGINX_CONF"
echo "        proxy_read_timeout 300s;" >> "$NGINX_CONF"
echo "    }" >> "$NGINX_CONF"
echo "}" >> "$NGINX_CONF"

if [ -f /etc/nginx/sites-enabled/default ]; then
    rm -f /etc/nginx/sites-enabled/default
fi

systemctl restart nginx >/dev/null 2>&1 || true

clear
echo "========================================================="
echo " Deployment Successful!"
echo " URL: http://$DOMAIN_NAME"
echo "========================================================="
echo " Next Steps:"
echo " 1. Open the URL in your browser."
echo " 2. Click 'Config' (Top Right) to set your API Key."
echo "========================================================="
