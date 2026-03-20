#!/bin/bash
# Crystal Radar Auto Installer
set -e

clear
echo "========================================================="
echo " Crystal Radar 智能自动部署系统启动"
echo "========================================================="
echo ""
read -p "👉 请输入您要绑定的域名 [例如 crystal.taikon.top，如果没有请填 IP]: " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then
    DOMAIN_NAME="localhost"
fi

PROJECT_DIR="$PWD"
echo -e "\n⏳ 收到指令！开始为您建造雷达基站..."

echo "⚙️ [1/4] 正在安装底层运行环境 [Nginx & 依赖]..."
if [ -f /etc/debian_version ]; then
    apt-get update -y
    apt-get install -y curl wget git unzip nginx
elif [ -f /etc/redhat-release ]; then
    yum install -y epel-release
    yum install -y curl wget git unzip nginx
    systemctl enable nginx
fi

echo "⚙️ [2/4] 正在安装 Node.js 引擎与 PM2 守护进程..."
if ! type node > /dev/null 2>&1; then
    curl -fsSL [https://deb.nodesource.com/setup_20.x](https://deb.nodesource.com/setup_20.x) | bash -
    apt-get install -y nodejs || yum install -y nodejs
fi
if ! type pm2 > /dev/null 2>&1; then
    npm install pm2 -g
fi

echo "📦 [3/4] 正在编译并点燃前后端引擎 [请耐心等待 1-2 分钟]..."
cd "$PROJECT_DIR/backend"
npm install
pm2 stop crystal-api || true
pm2 start ./index.js --name "crystal-api"
pm2 save

cd "$PROJECT_DIR/frontend"
npm install
npm run build

echo "🌐 [4/4] 正在为您全自动配置 Nginx 反向代理与域名映射..."
NGINX_CONF="/etc/nginx/conf.d/crystal.conf"

cat << EOF_NGINX > "$NGINX_CONF"
server {
    listen 80;
    server_name $DOMAIN_NAME;

    location / {
        root $PROJECT_DIR/frontend/dist;
        index index.html index.htm;
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass [http://127.0.0.1:3000/](http://127.0.0.1:3000/);
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_buffering off;
        proxy_read_timeout 300s;
    }
}
EOF_NGINX

# 移除默认配置防冲突
if [ -f /etc/nginx/sites-enabled/default ]; then
    rm -f /etc/nginx/sites-enabled/default
fi

systemctl restart nginx

clear
echo "========================================================="
echo " 🎉 晶振智能雷达部署大功告成！"
echo "========================================================="
echo " 🌐 您的专属访问地址: http://$DOMAIN_NAME"
echo ""
echo " 👉 下一步操作："
echo " 1. 请在浏览器打开上述网址。"
echo " 2. 点击右上角【配置】，填入您的 AI 密钥即可使用！"
echo "========================================================="
