#!/bin/bash
set -e

echo "=== 拉取最新代码 ==="
git pull

echo "=== 安装后端依赖 ==="
cd backend && npm install

echo "=== 安装前端依赖并构建 ==="
cd ../frontend && npm install && npm run build

echo "=== 加载环境变量 ==="
set -a
source ../.env 2>/dev/null || echo "⚠️  无 .env 文件，使用系统环境变量"
set +a

echo "=== 重启服务 ==="
cd ../backend
pm2 startOrRestart ../ecosystem.config.js

echo "=== 健康检查 ==="
sleep 3
curl -s http://localhost:3001/api/health && echo " ✅ 部署成功" || echo " ❌ 部署失败，请检查日志"
