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
