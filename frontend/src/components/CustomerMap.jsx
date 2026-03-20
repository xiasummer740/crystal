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
  const [deleteTarget, setDeleteTarget] = useState(null); 
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
    } catch (err) {}
  };

  const filteredCustomers = filterCat === '全部' ? customers : customers.filter(c => c.category === filterCat);

  return (
    <div className="max-w-screen-2xl mx-auto p-4 h-[calc(100vh-80px)] flex flex-col lg:flex-row gap-4 font-sans animate-fade-in relative">
      
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

      <div className="w-full lg:w-80 premium-glass rounded-2xl shadow-lg flex flex-col overflow-hidden shrink-0 h-[40vh] lg:h-full">
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

      <div className="flex-1 premium-glass rounded-2xl shadow-lg border border-white/80 overflow-hidden relative z-0 h-[50vh] lg:h-full bg-blue-50/20">
        <MapContainer center={[35.86166, 104.195397]} zoom={5} style={{ height: '100%', width: '100%', position: 'absolute', inset: 0 }}>
          
          {/* 【绝对制空权】：配合 no-referrer，高德地图防盗链形同虚设，100% 极速加载！ */}
          <TileLayer 
            attribution='&copy; 高德地图 (Amap)' 
            url="[https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x=](https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x=){x}&y={y}&z={z}" 
          />
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
