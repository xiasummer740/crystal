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
