#!/bin/bash
# ===================================================
# Crystal Radar (晶振智能雷达) - 全自动化两步部署脚本
# ===================================================
set -e

echo "🚀 第一步：正在全自动化构建运行环境 (Node.js & PM2 & 依赖)..."

# 1. 检查并安装 Node.js 和 PM2
if ! command -v node > /dev/null; then
    curl -fsSL [https://deb.nodesource.com/setup_20.x](https://deb.nodesource.com/setup_20.x) | bash -
    apt-get install -y nodejs
fi
if ! command -v pm2 > /dev/null; then
    npm install pm2 -g
fi

# 2. 编译并启动后端 (Backend)
echo "📦 正在装载后端数据探针与 AI 神经元..."
cd "$(dirname "$0")/backend"
npm install
pm2 start ./index.js --name "crystal-api"
pm2 save

# 3. 编译前端 (Frontend)
echo "🎨 正在构建前端流体毛玻璃 UI 与高德沙盘..."
cd "$(dirname "$0")/frontend"
npm install
npm run build

echo "========================================================="
echo "✅ 部署完成！"
echo "👉 第二步：请配置 Nginx 将域名指向 frontend/dist 目录，并将 /api 代理至本地 3000 端口。"
echo "👉 然后在浏览器打开网页，点击右上角【配置】输入您的 API Key 即可启动系统！"
echo "========================================================="
