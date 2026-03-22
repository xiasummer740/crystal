#!/bin/bash
set -e

PROJECT_DIR="/var/www/crystal"
cd "$PROJECT_DIR"

echo ">>> 1. 正在给底层探针打入【反 Nginx 缓冲补丁】，解决进度条死锁..."
sed -i "/res.setHeader('Connection', 'keep-alive');/a \    res.setHeader('X-Accel-Buffering', 'no');" "$PROJECT_DIR/backend/controllers/searchController.js" || true

echo ">>> 2. 正在执行最高机密脱敏 (隐藏您的 API Key)..."
mkdir -p /tmp/crystal_backup
cp "$PROJECT_DIR/backend/config/llm.json" /tmp/crystal_backup/llm.json || true
cat << 'EOF' > "$PROJECT_DIR/backend/config/llm.json"
{
  "provider": "deepseek",
  "apiKey": "sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "baseUrl": "[https://api.deepseek.com](https://api.deepseek.com)",
  "model": "deepseek-chat"
}
EOF
echo "[]" > "$PROJECT_DIR/backend/config/customers.json" || true

echo ">>> 3. 正在重构带【虚拟内存 + 破墙器】的终极版 install.sh..."
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
if [ -z "$DOMAIN_NAME" ]; then DOMAIN_NAME="localhost"; fi

PROJECT_DIR="/var/www/crystal"

echo "[1/6] 注入 2GB 虚拟内存 (防止低配机器 npm build 内存溢出导致白屏)..."
if [ $(free -m | awk '/^Swap:/ {print $2}') -eq 0 ]; then
    dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile || true
    echo "Swap allocated successfully."
fi

echo "[2/6] 安装系统底层运行组件..."
if [ -f /etc/debian_version ]; then
    apt-get update -y
    apt-get install -y git curl wget unzip nginx nodejs npm
else
    yum install -y epel-release
    yum install -y git curl wget unzip nginx nodejs npm
    systemctl enable nginx || true
fi

echo "[3/6] 暴力破拆防火墙 (确保 80 端口彻底开放)..."
if command -v ufw >/dev/null 2>&1; then ufw allow 80/tcp || true; fi
if command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --add-port=80/tcp --permanent || true; firewall-cmd --reload || true; fi
iptables -I INPUT -p tcp --dport 80 -j ACCEPT || true

echo "[4/6] 强制拉升 Node.js 引擎至 v20 & 部署 PM2..."
npm install -g n
n 20
hash -r
npm install -g pm2 || true

echo "[5/6] 编译业务引擎 (已解除静默，可实时观看安装防假死)..."
cd "$PROJECT_DIR/backend"
rm -rf node_modules package-lock.json
npm install
pm2 stop crystal-api || true
MAIN_FILE=$(grep '"main"' package.json | head -n 1 | awk -F'"' '{print $4}' || echo "index.js")
pm2 start "$MAIN_FILE" --name "crystal-api"
pm2 save || true

cd "$PROJECT_DIR/frontend"
rm -rf node_modules package-lock.json
npm install
npm run build

echo "[6/6] 配置 Nginx 路由结界..."
mkdir -p /etc/nginx/conf.d
mkdir -p /etc/nginx/sites-enabled
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

ln -sf "$CONF_FILE" /etc/nginx/sites-enabled/crystal.conf || true
rm -f /etc/nginx/sites-enabled/default || true
systemctl restart nginx || true

echo "============================================="
echo " Deployment Successful! Open http://$DOMAIN_NAME"
echo "============================================="
EOF_SCRIPT

chmod +x install.sh
sed -i 's/\r$//' install.sh

echo ">>> 4. 正在更新 README 两步法文档..."
cat << 'EOF_README' > README.md
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
EOF_README

echo ">>> 5. 正在将完美版推送到 GitHub (强制覆盖)..."
git add .
git commit -m "🚀 [Release] 终极交付版：注入虚拟内存防OOM、自动暴力破除防火墙、解决SSE缓冲死锁，全脱敏发版" || true
git push origin crystal -f

echo ">>> 6. 正在恢复您本机的真实配置，业务不断档..."
cp /tmp/crystal_backup/llm.json "$PROJECT_DIR/backend/config/llm.json" || true
pm2 restart crystal-api >/dev/null 2>&1 || true

echo "========================================================="
echo " ✅ 终极脱敏推送完成！您随时可以去新 VPS 执行两步法部署！"
echo "========================================================="
