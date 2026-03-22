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
