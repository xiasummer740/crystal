#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"
FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在重构后端 CRM 控制器：修复 DELETE 请求的 Query 传参断点..."

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
        if (!rawData || rawData.trim() === '') rawData = '[]';
        res.json({ success: true, data: JSON.parse(rawData) });
    } catch (e) {
        res.json({ success: true, data: [] });
    }
};

const saveCustomer = (req, res) => {
    try {
        if (!fs.existsSync(dbDir)) fs.mkdirSync(dbDir, { recursive: true });
        if (!fs.existsSync(dbPath)) fs.writeFileSync(dbPath, '[]');

        let rawData = fs.readFileSync(dbPath, 'utf8');
        let customers = JSON.parse(rawData || '[]');
        const customer = req.body;
        
        const index = customers.findIndex(c => c.company === customer.company);
        if (customer.category === '未收藏') {
            if (index > -1) customers.splice(index, 1);
        } else {
            if (index > -1) customers[index] = customer;
            else customers.push(customer);
        }
        
        fs.writeFileSync(dbPath, JSON.stringify(customers, null, 2));
        res.json({ success: true, message: '收藏状态更新成功' });
    } catch (e) {
        res.status(500).json({ success: false, message: '数据库写入失败' });
    }
};

// 【核心修复】：改用 req.query 获取删除目标，规避 Body 丢失 Bug
const deleteCustomer = (req, res) => {
    try {
        const company = req.query.company; 
        if (!company) return res.status(400).json({ success: false, message: '未提供目标公司' });
        
        if (!fs.existsSync(dbPath)) return res.json({ success: true });
        
        let customers = JSON.parse(fs.readFileSync(dbPath, 'utf8') || '[]');
        const initialLength = customers.length;
        
        // 过滤剔除目标客户
        customers = customers.filter(c => c.company !== company);
        
        if (customers.length !== initialLength) {
            fs.writeFileSync(dbPath, JSON.stringify(customers, null, 2));
        }
        
        res.json({ success: true, message: '档案销毁成功' });
    } catch (e) {
        console.error("删除报错:", e);
        res.status(500).json({ success: false, message: '删除失败' });
    }
};

module.exports = { getCustomers, saveCustomer, deleteCustomer };
EOF

echo ">>> 2. 正在重构前端【客户档案库】与【地图控制台】：注入自定义毛玻璃确认弹窗..."

cat << 'EOF' > "$FRONTEND_DIR/src/components/CustomerDatabase.jsx"
import React, { useEffect, useState } from 'react';
import axios from 'axios';
import { useStore } from '../store';
import { FolderOpen, MapPin, Trash2, ChevronRight, AlertTriangle, X } from 'lucide-react';

export default function CustomerDatabase() {
  const [customers, setCustomers] = useState([]);
  const [deleteTarget, setDeleteTarget] = useState(null); // 存放准备删除的目标
  const { setActiveTab, setResult, triggerRefresh, refreshTrigger } = useStore();

  useEffect(() => {
    axios.get('/api/customers').then(res => setCustomers(res.data.data || []));
  }, [refreshTrigger]);

  const handleView = (cust) => {
    setResult(cust); 
    setActiveTab('search'); 
  };

  const triggerDeleteConfirm = (e, company) => {
    e.stopPropagation(); // 防止触发卡片点击的 handleView
    setDeleteTarget(company);
  };

  // 【核心修复】：调用带 Query 的安全删除接口
  const executeDelete = async () => {
    if (!deleteTarget) return;
    try {
      await axios.delete(`/api/customers?company=${encodeURIComponent(deleteTarget)}`);
      setDeleteTarget(null); // 关闭弹窗
      triggerRefresh(); // 刷新列表
    } catch (err) {
      console.error('删除失败');
    }
  };

  return (
    <div className="max-w-6xl mx-auto p-4 mt-6 animate-fade-in font-sans relative">
      
      {/* 【新增】：高级毛玻璃删除确认弹窗 (Modal) */}
      {deleteTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40 backdrop-blur-sm animate-fade-in">
          <div className="glass-panel p-8 rounded-2xl shadow-2xl max-w-sm w-full transform transition-all border-t-4 border-red-500">
            <div className="flex items-center gap-4 mb-6">
              <div className="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center shrink-0">
                <AlertTriangle className="text-red-600" size={24} />
              </div>
              <div>
                <h3 className="text-xl font-black text-gray-900">确认销毁档案？</h3>
                <p className="text-sm text-gray-500 mt-1">此操作不可逆</p>
              </div>
            </div>
            <p className="text-gray-700 font-bold mb-6 bg-white/50 p-3 rounded-lg border border-gray-200 text-center truncate">
              {deleteTarget}
            </p>
            <div className="flex gap-3">
              <button 
                onClick={() => setDeleteTarget(null)} 
                className="flex-1 px-4 py-2.5 bg-gray-100 hover:bg-gray-200 text-gray-700 font-bold rounded-xl transition-colors border border-gray-300"
              >
                取消
              </button>
              <button 
                onClick={executeDelete} 
                className="flex-1 px-4 py-2.5 bg-red-500 hover:bg-red-600 text-white font-bold rounded-xl shadow-md transition-colors flex items-center justify-center gap-1"
              >
                <Trash2 size={16} /> 确认销毁
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="flex items-center gap-3 mb-8">
        <div className="w-12 h-12 bg-blue-600 rounded-xl flex items-center justify-center shadow-lg"><FolderOpen className="text-white" size={24}/></div>
        <div>
          <h2 className="text-3xl font-black text-gray-800">绝密客户档案库</h2>
          <p className="text-gray-500 font-medium mt-1">这里封存了您所有标星收藏过的企业分析全量报告，永不丢失。</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {customers.map((cust, idx) => (
          <div key={idx} onClick={() => handleView(cust)} className="glass-panel rounded-2xl p-5 cursor-pointer hover:-translate-y-1 hover:shadow-xl transition-all group relative border-t-4 border-blue-500">
             <div className="flex justify-between items-start mb-3">
               <h3 className="font-black text-lg text-blue-900 group-hover:text-blue-600 pr-8 leading-tight">{cust.company}</h3>
               {/* 触发自定义弹窗 */}
               <button onClick={(e) => triggerDeleteConfirm(e, cust.company)} className="absolute top-4 right-4 text-gray-400 hover:text-red-500 transition-colors p-1.5 bg-white/60 hover:bg-red-50 rounded-md backdrop-blur-md shadow-sm border border-gray-200/50">
                 <Trash2 size={16}/>
               </button>
             </div>
             
             <div className="inline-block px-2.5 py-1 rounded shadow-sm text-white text-xs font-bold mb-4" style={{
                 backgroundColor: cust.category==='A类客户'?'#ef4444':cust.category==='B类客户'?'#f97316':cust.category==='C类客户'?'#eab308':cust.category==='意向客户'?'#3b82f6':'#22c55e'
             }}>
                 {cust.category} | {cust.type || '目标客户'}
             </div>

             <p className="text-xs text-gray-600 flex items-start gap-1.5 mb-2 line-clamp-2">
               <MapPin size={14} className="text-red-400 shrink-0"/> {cust.address}
             </p>
             
             <div className="mt-4 pt-3 border-t border-gray-200/50 flex justify-between items-center">
               <span className="text-xs font-bold text-gray-500 bg-white/50 px-2 py-1 rounded">已挖掘 {cust.products?.length || 0} 款产品</span>
               <span className="text-sm font-bold text-blue-600 flex items-center gap-1 group-hover:translate-x-1 transition-transform">查阅档案 <ChevronRight size={16}/></span>
             </div>
          </div>
        ))}
        {customers.length === 0 && (
          <div className="col-span-full py-20 text-center text-gray-400 glass-panel rounded-2xl">
            <FolderOpen size={48} className="mx-auto mb-4 opacity-50" />
            <p className="text-lg font-bold">档案库空空如也，快去雷达探测并标星客户吧！</p>
          </div>
        )}
      </div>
    </div>
  );
}
EOF

cat << 'EOF' > "$FRONTEND_DIR/src/components/CustomerMap.jsx"
import React, { useEffect, useState } from 'react';
import axios from 'axios';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { useStore } from '../store';
import { MapPin, Building2, Trash2, AlertTriangle } from 'lucide-react';

const getMarkerIcon = (category) => {
  let color = '#6b7280';
  if (category === 'A类客户') color = '#ef4444';
  else if (category === 'B类客户') color = '#f97316';
  else if (category === 'C类客户') color = '#eab308';
  else if (category === '意向客户') color = '#3b82f6';
  else if (category === '合作客户') color = '#22c55e';

  return L.divIcon({
    className: 'custom-div-icon',
    html: `<div style="background-color:${color}; width:20px; height:20px; border-radius:50%; border:3px solid white; box-shadow: 0 2px 5px rgba(0,0,0,0.5);"></div>`,
    iconSize: [20, 20],
    iconAnchor: [10, 10],
    popupAnchor: [0, -10]
  });
};

function MapController({ targetCenter }) {
  const map = useMap();
  useEffect(() => {
    if (targetCenter && targetCenter.length === 2) {
      map.flyTo(targetCenter, 14, { duration: 1.5 });
    }
  }, [targetCenter, map]);
  return null;
}

export default function CustomerMap() {
  const [customers, setCustomers] = useState([]);
  const [filterCat, setFilterCat] = useState('全部');
  const [targetCenter, setTargetCenter] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null); // 自定义弹窗状态
  const { refreshTrigger, triggerRefresh } = useStore();

  useEffect(() => {
    axios.get('/api/customers').then(res => setCustomers(res.data.data || []));
  }, [refreshTrigger]);

  const triggerDeleteConfirm = (e, company) => {
    e.stopPropagation();
    setDeleteTarget(company);
  };

  const executeDelete = async () => {
    if (!deleteTarget) return;
    try {
      await axios.delete(`/api/customers?company=${encodeURIComponent(deleteTarget)}`);
      setDeleteTarget(null);
      triggerRefresh();
    } catch (err) {
      console.error('删除失败');
    }
  };

  const filteredCustomers = filterCat === '全部' ? customers : customers.filter(c => c.category === filterCat);

  return (
    <div className="max-w-screen-2xl mx-auto p-4 h-[calc(100vh-80px)] flex flex-col lg:flex-row gap-4 font-sans animate-fade-in relative">
      
      {/* 同样在地图页面挂载统一的删除确认模态框 */}
      {deleteTarget && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-slate-900/40 backdrop-blur-sm animate-fade-in">
          <div className="glass-panel p-8 rounded-2xl shadow-2xl max-w-sm w-full transform transition-all border-t-4 border-red-500">
            <div className="flex items-center gap-4 mb-6">
              <div className="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center shrink-0">
                <AlertTriangle className="text-red-600" size={24} />
              </div>
              <div>
                <h3 className="text-xl font-black text-gray-900">确认移出编队？</h3>
                <p className="text-sm text-gray-500 mt-1">坐标将从地图抹除</p>
              </div>
            </div>
            <p className="text-gray-700 font-bold mb-6 bg-white/50 p-3 rounded-lg border border-gray-200 text-center truncate">
              {deleteTarget}
            </p>
            <div className="flex gap-3">
              <button onClick={() => setDeleteTarget(null)} className="flex-1 px-4 py-2.5 bg-gray-100 hover:bg-gray-200 text-gray-700 font-bold rounded-xl transition-colors border border-gray-300">取消</button>
              <button onClick={executeDelete} className="flex-1 px-4 py-2.5 bg-red-500 hover:bg-red-600 text-white font-bold rounded-xl shadow-md transition-colors flex items-center justify-center gap-1">
                <Trash2 size={16} /> 确认移除
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="w-full lg:w-80 glass-panel rounded-2xl shadow-lg flex flex-col overflow-hidden shrink-0 h-[40vh] lg:h-full">
         <div className="p-4 bg-white/40 border-b border-gray-200/50">
            <h2 className="text-xl font-black text-gray-800 flex items-center gap-2"><Building2 className="text-blue-600" size={20}/> 客户编队</h2>
            <select value={filterCat} onChange={(e) => setFilterCat(e.target.value)} className="mt-3 w-full p-2 text-sm bg-white/80 border border-gray-200 rounded-lg outline-none font-bold text-gray-700 shadow-sm cursor-pointer backdrop-blur-md">
               <option value="全部">🌍 全部领地 ({customers.length})</option>
               <option value="A类客户">🔥 A类客户</option>
               <option value="B类客户">⭐ B类客户</option>
               <option value="C类客户">📌 C类客户</option>
               <option value="意向客户">🤝 意向客户</option>
               <option value="合作客户">✅ 合作客户</option>
            </select>
         </div>
         <div className="flex-1 overflow-y-auto p-3 space-y-3 bg-white/20">
            {filteredCustomers.length === 0 ? (
               <p className="text-center text-gray-500 font-bold text-sm mt-10">该编队暂无客户</p>
            ) : (
               filteredCustomers.map((cust, idx) => (
                 <div 
                   key={idx} 
                   onClick={() => setTargetCenter(cust.coordinates)}
                   className="bg-white/80 p-3 rounded-xl border border-gray-100 shadow-sm hover:shadow-md hover:border-blue-300 cursor-pointer transition-all active:scale-95 group relative backdrop-blur-sm"
                 >
                   <div className="font-bold text-sm text-gray-800 group-hover:text-blue-600 truncate pr-8">{cust.company}</div>
                   <div className="flex items-center gap-1 text-[10px] text-gray-500 mt-2 truncate">
                      <MapPin size={12} className="text-red-500 shrink-0"/> {cust.address}
                   </div>
                   <button 
                     onClick={(e) => triggerDeleteConfirm(e, cust.company)}
                     className="absolute top-2 right-2 text-gray-400 hover:text-red-500 bg-white hover:bg-red-50 p-1.5 rounded-md shadow-sm border border-gray-100 opacity-0 group-hover:opacity-100 transition-all"
                     title="删除此客户"
                   >
                     <Trash2 size={14} />
                   </button>
                 </div>
               ))
            )}
         </div>
      </div>

      <div className="flex-1 glass-panel rounded-2xl shadow-lg border-2 border-white/50 overflow-hidden relative z-0 h-[50vh] lg:h-full">
        <MapContainer center={[35.86166, 104.195397]} zoom={5} style={{ height: '100%', width: '100%', position: 'absolute', inset: 0 }}>
          <TileLayer attribution='&copy; OpenStreetMap' url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
          <MapController targetCenter={targetCenter} />
          
          {filteredCustomers.map((cust, idx) => (
            cust.coordinates && cust.coordinates.length === 2 && (
              <Marker key={idx} position={[cust.coordinates[0], cust.coordinates[1]]} icon={getMarkerIcon(cust.category)}>
                <Popup className="font-sans min-w-[200px]">
                  <div className="font-black text-lg text-blue-900 border-b border-gray-200 pb-2 mb-2">{cust.company}</div>
                  <div className="text-xs text-gray-700 mb-3 bg-gray-50 p-2 rounded border border-gray-100">{cust.address}</div>
                  <div className="inline-block px-2 py-1 rounded text-white text-xs font-bold" style={{
                      backgroundColor: cust.category==='A类客户'?'#ef4444':cust.category==='B类客户'?'#f97316':cust.category==='C类客户'?'#eab308':cust.category==='意向客户'?'#3b82f6':'#22c55e'
                  }}>
                      {cust.category}
                  </div>
                </Popup>
              </Marker>
            )
          ))}
        </MapContainer>
      </div>
    </div>
  );
}
EOF

echo ">>> 3. 全面重编生效前端，重启底层数据库接口..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ URL 安全传参删除模式 & 自定义毛玻璃警示弹窗 完美上线！"
echo "========================================================="
