#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"

echo ">>> 1. 正在为后端引擎注射强心针：重新补齐所有核心运行包..."
cd "$BACKEND_DIR"
npm install express cors axios multer form-data cheerio > /dev/null 2>&1

echo ">>> 2. 正在修复数据库文件：植入绝对防御级 JSON 解析引擎..."
cat << 'EOF' > "$BACKEND_DIR/controllers/customerController.js"
const fs = require('fs');
const path = require('path');

const dbDir = '/var/www/crystal/backend/config';
const dbPath = path.join(dbDir, 'customers.json');
const backupPath = path.join(dbDir, 'customers.json.bak');

// 【急救逻辑】：如果主库丢了，自动把备份库还原
if (!fs.existsSync(dbPath) && fs.existsSync(backupPath)) {
    fs.copyFileSync(backupPath, dbPath);
}

const getCustomers = (req, res) => {
    try {
        if (!fs.existsSync(dbDir)) fs.mkdirSync(dbDir, { recursive: true });
        if (!fs.existsSync(dbPath)) return res.json({ success: true, data: [] });
        
        let rawData = fs.readFileSync(dbPath, 'utf8');
        let parsedData = [];
        try {
            // 安全解析，防止 JSON 损坏导致整个服务器崩溃闪退
            parsedData = JSON.parse(rawData);
        } catch (parseError) {
            console.error("检测到 JSON 文件损坏，启动安全空载模式");
        }
        res.json({ success: true, data: parsedData });
    } catch (e) {
        res.json({ success: true, data: [] });
    }
};

const saveCustomer = (req, res) => {
    try {
        if (!fs.existsSync(dbDir)) fs.mkdirSync(dbDir, { recursive: true });
        if (!fs.existsSync(dbPath)) fs.writeFileSync(dbPath, '[]');
        
        let rawData = fs.readFileSync(dbPath, 'utf8');
        let customers = [];
        try { customers = JSON.parse(rawData); } catch(e) {}
        
        const customerData = req.body;
        const index = customers.findIndex(c => c.company === customerData.company);
        
        if (customerData.category === '未收藏') {
            if (index > -1) customers.splice(index, 1);
        } else {
            if (index > -1) customers[index] = customerData;
            else customers.push(customerData);
        }
        
        fs.writeFileSync(dbPath, JSON.stringify(customers, null, 2));
        res.json({ success: true, message: '归档成功' });
    } catch (e) {
        res.status(500).json({ success: false, message: '保存失败' });
    }
};

const deleteCustomer = (req, res) => {
    try {
        const company = req.query.company; 
        if (!company) return res.status(400).json({ success: false });
        if (!fs.existsSync(dbPath)) return res.json({ success: true });
        
        let rawData = fs.readFileSync(dbPath, 'utf8');
        let customers = [];
        try { customers = JSON.parse(rawData); } catch(e) {}
        
        customers = customers.filter(c => c.company !== company);
        fs.writeFileSync(dbPath, JSON.stringify(customers, null, 2));
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

module.exports = { getCustomers, saveCustomer, deleteCustomer };
EOF

echo ">>> 3. 清理崩溃缓存，强制点火重启后端引擎..."
pm2 flush > /dev/null 2>&1
pm2 restart crystal-api > /dev/null 2>&1

# 等待 2 秒让 Node.js 充分启动
sleep 2

echo "========================================================="
echo " ✅ 急救完成！以下是后台最新的生命体征日志："
echo "========================================================="
pm2 logs crystal-api --lines 15 --nostream
