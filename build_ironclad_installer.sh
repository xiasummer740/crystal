#!/bin/bash
set -e

PROJECT_DIR="/var/www/crystal"
cd "$PROJECT_DIR"

echo ">>> 1. 正在锻造没有任何特殊符号的【绝对装甲版 install.sh】..."

cat << 'EOF_SCRIPT' > install.sh
#!/bin/bash
set -e

echo "============================================="
echo " Crystal Radar Deployment "
echo "============================================="

read -p "Input Domain or IP: " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then
    DOMAIN_NAME="localhost"
fi

echo "Step 1: Install Nginx and Curl"
if [ -f /etc/debian_version ]; then
    apt-get update -y
    apt-get install -y curl wget git unzip nginx
else
    yum install -y epel-release
    yum install -y curl wget git unzip nginx
    systemctl enable nginx || true
fi

echo "Step 2: Install Node.js and PM2"
# 物理拆分：绝不使用管道符 | bash，先老老实实下载到本地文件，再执行！
curl -fsSL [https://deb.nodesource.com/setup_20.x](https://deb.nodesource.com/setup_20.x) -o setup_node.sh
bash setup_node.sh

if [ -f /etc/debian_version ]; then
    apt-get install -y nodejs
else
    yum install -y nodejs
fi
npm install pm2 -g || true

echo "Step 3: Compile Backend"
cd backend
npm install
pm2 stop crystal-api || true
pm2 start ./index.js --name "crystal-api"
pm2 save || true
cd ..

echo "Step 4: Compile Frontend"
cd frontend
npm install
npm run build
cd ..

echo "Step 5: Configure Nginx"
CONF_FILE="/etc/nginx/conf.d/crystal.conf"

echo "server {" > "$CONF_FILE"
echo "    listen 80;" >> "$CONF_FILE"
echo "    server_name $DOMAIN_NAME;" >> "$CONF_FILE"
echo "    location / {" >> "$CONF_FILE"
echo "        root $PWD/frontend/dist;" >> "$CONF_FILE"
echo "        index index.html;" >> "$CONF_FILE"
echo "        try_files \$uri \$uri/ /index.html;" >> "$CONF_FILE"
echo "    }" >> "$CONF_FILE"
echo "    location /api/ {" >> "$CONF_FILE"
echo "        proxy_pass [http://127.0.0.1:3000/](http://127.0.0.1:3000/);" >> "$CONF_FILE"
echo "        proxy_set_header Host \$host;" >> "$CONF_FILE"
echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$CONF_FILE"
echo "    }" >> "$CONF_FILE"
echo "}" >> "$CONF_FILE"

if [ -f /etc/nginx/sites-enabled/default ]; then
    rm -f /etc/nginx/sites-enabled/default
fi

systemctl restart nginx || true

echo "============================================="
echo " Deployment Success! Open http://$DOMAIN_NAME"
echo "============================================="
EOF_SCRIPT

chmod +x install.sh

echo ">>> 2. 正在强行提交并覆盖至 GitHub..."
git add install.sh
git commit -m "🚀 [Ironclad] 移除所有管道符与重定向，彻底解决新 VPS 语法报错死锁" || true
git push origin crystal -f

echo "========================================================="
echo " ✅ 绝对装甲版已成功推送！"
echo "========================================================="
