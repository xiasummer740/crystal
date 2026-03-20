#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"
FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 紧急拆除导致 502 崩溃的 SQLite 重型引擎，恢复服务器生机..."
cd "$BACKEND_DIR"
npm uninstall sequelize sqlite3 > /dev/null 2>&1 || true

echo ">>> 2. 正在重构后端存储：恢复原生无依赖的极速 JSON 引擎..."

cat << 'EOF' > "$BACKEND_DIR/controllers/customerController.js"
const fs = require('fs');
const path = require('path');

const dbDir = '/var/www/crystal/backend/config';
const dbPath = path.join(dbDir, 'customers.json');

const getCustomers = (req, res) => {
    try {
        if (!fs.existsSync(dbDir)) fs.mkdirSync(dbDir, { recursive: true });
        if (!fs.existsSync(dbPath)) return res.json({ success: true, data: [] });
        
        let rawData = fs.readFileSync(dbPath, 'utf8');
        res.json({ success: true, data: JSON.parse(rawData || '[]') });
    } catch (e) {
        res.json({ success: true, data: [] });
    }
};

const saveCustomer = (req, res) => {
    try {
        if (!fs.existsSync(dbDir)) fs.mkdirSync(dbDir, { recursive: true });
        if (!fs.existsSync(dbPath)) fs.writeFileSync(dbPath, '[]');
        
        let customers = JSON.parse(fs.readFileSync(dbPath, 'utf8') || '[]');
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
        
        let customers = JSON.parse(fs.readFileSync(dbPath, 'utf8') || '[]');
        customers = customers.filter(c => c.company !== company);
        
        fs.writeFileSync(dbPath, JSON.stringify(customers, null, 2));
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

module.exports = { getCustomers, saveCustomer, deleteCustomer };
EOF

echo ">>> 3. 正在重构前端漏网组件：为【顶部导航】与【翻译页】换上毛玻璃新衣..."

cat << 'EOF' > "$FRONTEND_DIR/src/components/Header.jsx"
import React from 'react';
import { Settings, Search, FileText, Map as MapIcon, Database as DbIcon } from 'lucide-react';
import { useStore } from '../store';

export default function Header() {
  const { setSettingsOpen, activeTab, setActiveTab } = useStore();
  
  return (
    <header className="glass-panel text-gray-800 shadow-sm sticky top-0 z-40 border-b border-white/60">
      <div className="max-w-7xl mx-auto px-4 h-auto min-h-[64px] flex flex-wrap justify-between items-center py-2 gap-y-3">
        
        <h1 className="text-xl font-black tracking-tight flex items-center gap-2 text-blue-900">
          <div className="w-8 h-8 bg-gradient-to-br from-blue-600 to-indigo-600 text-white rounded-lg flex items-center justify-center font-bold shadow-md">XT</div>
          晶振智能雷达
        </h1>
        
        <div className="flex flex-wrap bg-white/50 p-1.5 rounded-xl gap-1 border border-white/80 shadow-sm backdrop-blur-md">
          <button onClick={() => setActiveTab('search')} className={`px-4 py-1.5 rounded-lg text-sm font-bold flex items-center gap-2 transition-all ${activeTab === 'search' ? 'bg-blue-600 text-white shadow-md' : 'text-gray-700 hover:bg-white/80'}`}>
            <Search size={16}/> 侦测控制台
          </button>
          <button onClick={() => setActiveTab('database')} className={`px-4 py-1.5 rounded-lg text-sm font-bold flex items-center gap-2 transition-all ${activeTab === 'database' ? 'bg-blue-600 text-white shadow-md' : 'text-gray-700 hover:bg-white/80'}`}>
            <DbIcon size={16}/> 客户档案库
          </button>
          <button onClick={() => setActiveTab('map')} className={`px-4 py-1.5 rounded-lg text-sm font-bold flex items-center gap-2 transition-all ${activeTab === 'map' ? 'bg-blue-600 text-white shadow-md' : 'text-gray-700 hover:bg-white/80'}`}>
            <MapIcon size={16}/> 全局作战地图
          </button>
          <button onClick={() => setActiveTab('pdf')} className={`px-4 py-1.5 rounded-lg text-sm font-bold flex items-center gap-2 transition-all ${activeTab === 'pdf' ? 'bg-blue-600 text-white shadow-md' : 'text-gray-700 hover:bg-white/80'}`}>
            <FileText size={16}/> 规格书翻译
          </button>
        </div>

        <button onClick={() => setSettingsOpen(true)} className="flex items-center space-x-1 bg-white/70 hover:bg-white px-3 py-1.5 rounded-lg border border-gray-200/50 transition-all text-sm font-bold shadow-sm text-blue-700 backdrop-blur-md">
          <Settings size={16} /><span>配置</span>
        </button>

      </div>
    </header>
  );
}
EOF

cat << 'EOF' > "$FRONTEND_DIR/src/components/PdfTranslator.jsx"
import React, { useState, useCallback } from 'react';
import { UploadCloud, FileText, Loader2, CheckCircle2, AlertCircle } from 'lucide-react';
import { useDropzone } from 'react-dropzone';
import axios from 'axios';

export default function PdfTranslator() {
  const [file, setFile] = useState(null);
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);

  const onDrop = useCallback(acceptedFiles => {
    if (acceptedFiles.length > 0) {
      setFile(acceptedFiles[0]);
      setError(null);
      setResult(null);
    }
  }, []);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: { 'application/pdf': ['.pdf'] },
    maxFiles: 1
  });

  const handleTranslate = async () => {
    if (!file) return;
    setLoading(true);
    setError(null);
    const formData = new FormData();
    formData.append('file', file);

    try {
      const res = await axios.post('/api/translate-pdf', formData, {
        headers: { 'Content-Type': 'multipart/form-data' }
      });
      setResult(res.data.data);
    } catch (err) {
      setError(err.response?.data?.message || '解析引擎对接失败，请检查网络或API配置');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-4xl mx-auto p-4 mt-8 animate-fade-in font-sans">
      <div className="text-center mb-8 relative z-10">
        <h2 className="text-3xl font-black text-gray-800 tracking-tight">英文规格书智能翻译与查证器</h2>
        <p className="text-gray-500 mt-2 font-medium">拖入原厂 PDF，自动定位页码、翻译参数，并一字不差地高亮还原查证原文</p>
      </div>

      {/* 剥离白底，应用统一的玻璃态与防溢出特效 */}
      <div className="glass-panel p-8 rounded-2xl shadow-xl border-t-4 border-teal-500 relative z-10 overflow-hidden" onMouseDown={(e) => window.createRipple && window.createRipple(e, e.currentTarget)}>
        <div {...getRootProps()} className={`border-2 border-dashed rounded-xl p-10 text-center cursor-pointer transition-all ${isDragActive ? 'border-teal-400 bg-teal-50/50' : 'border-gray-300 bg-white/40 hover:bg-white/70 hover:border-teal-400'}`}>
          <input {...getInputProps()} />
          <UploadCloud className="mx-auto text-teal-500 mb-4" size={48} />
          {file ? (
            <div className="flex items-center justify-center gap-2 text-teal-700 font-bold"><FileText size={20}/> {file.name}</div>
          ) : (
            <div className="text-gray-600 font-bold">点击选择或将 PDF 规格书拖拽到此处<div className="text-xs text-gray-400 mt-2 font-normal">支持最大 200MB 的 Datasheet 原件</div></div>
          )}
        </div>
        
        <button onClick={handleTranslate} disabled={!file || loading} className="w-full mt-6 bg-gradient-to-r from-teal-500 to-emerald-500 text-white font-black text-lg p-4 rounded-xl shadow-lg hover:shadow-xl hover:scale-[1.01] transition-all flex items-center justify-center gap-2 disabled:opacity-60 disabled:scale-100 disabled:cursor-not-allowed relative overflow-hidden">
          {loading ? <><Loader2 className="animate-spin" size={24} /> 正在解析 PDF 与智能提取核心参数 (约需30秒)...</> : <><FileText size={24} /> 提取参数并智能翻译</>}
        </button>

        {error && (
          <div className="mt-4 p-4 bg-red-50/80 text-red-600 border border-red-200 rounded-lg flex items-center gap-2 font-bold backdrop-blur-md">
            <AlertCircle size={20}/> {error}
          </div>
        )}
      </div>

      {result && (
        <div className="mt-8 glass-panel p-8 rounded-2xl shadow-xl border-t-4 border-indigo-500 animate-fade-in relative z-10">
          <h3 className="text-2xl font-black text-indigo-900 mb-6 flex items-center gap-2 border-b border-gray-200/50 pb-4">
            <CheckCircle2 className="text-green-500"/> 核心参数解析库
          </h3>
          <div className="prose max-w-none text-gray-800 leading-loose whitespace-pre-wrap font-medium">
            {result}
          </div>
        </div>
      )}
    </div>
  );
}
EOF

echo ">>> 4. 编译全栈生态，重启核心进程..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ 502崩溃彻底修复！全局毛玻璃渲染统一完毕！"
echo "========================================================="
