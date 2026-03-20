import React, { useState, useEffect } from 'react';
import { Search, Database, MapPin, Globe, FileText, Activity } from 'lucide-react';
import { useStore } from '../store';

export default function SearchLead() {
  const { setLoading, setResult, setError, loading, streamStatus, setStreamStatus, clearStream } = useStore();
  const [formData, setFormData] = useState({ companyName: '', address: '', website: '', profile: '' });
  
  // 【核心修复 1】：百分比进度状态
  const [progress, setProgress] = useState(0);

  const handleChange = (e) => setFormData({ ...formData, [e.target.name]: e.target.value });

  // 进度条平滑递增动画池
  useEffect(() => {
    if (!loading) {
      setProgress(0);
      return;
    }
    const timer = setInterval(() => {
      setProgress(prev => {
        if (prev >= 95) return 95; // 在没有完成前，最多卡在95%，等待最后一步满格
        return prev + 1; // 每秒平滑走 1%
      });
    }, 800);
    return () => clearInterval(timer);
  }, [loading]);

  const handleSearch = async () => {
    if (!formData.companyName.trim()) { setError('公司全称必须填写！'); return; }
    if (!formData.website.trim()) { setError('官方网站必须填写！探针需要目标网址进行底层图文强扒。'); return; }

    setLoading(true); 
    setError(null); 
    setResult(null); 
    clearStream();
    setProgress(5); // 初始点火进度

    try {
      const response = await fetch('/api/search', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData)
      });

      const reader = response.body.getReader();
      const decoder = new TextDecoder('utf-8');
      let buffer = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        let eolIndex;
        while ((eolIndex = buffer.indexOf('\n\n')) >= 0) {
          const message = buffer.slice(0, eolIndex).trim();
          buffer = buffer.slice(eolIndex + 2);
          if (message.startsWith('data: ')) {
            const dataStr = message.substring(6).trim(); 
            if (dataStr === '[DONE]') { 
              setProgress(100); // 结束瞬间打满100%
              setTimeout(() => setLoading(false), 500);
              return; 
            }
            try {
              const parsed = JSON.parse(dataStr);
              if (parsed.error) { setError(parsed.error); setLoading(false); return; }
              if (parsed.status) {
                setStreamStatus(parsed.status);
                // 根据后台回传的状态节点，实施“阶梯式进度跃进”
                if (parsed.status.includes('潜入目标官网')) setProgress(25);
                if (parsed.status.includes('降维重组')) setProgress(60);
                if (parsed.status.includes('渲染顶级数据')) setProgress(85);
              }
              if (parsed.fullData) { 
                setProgress(100); 
                setResult(parsed.fullData); 
                setTimeout(() => setLoading(false), 300); // 延时一点让用户看到 100% 满格的爽感
                return; 
              }
            } catch (e) {}
          }
        }
      }
      setLoading(false);
    } catch (err) {
      setError('网络连接断开或解析超时，请重试');
      setLoading(false);
    }
  };

  return (
    <div className="max-w-4xl mx-auto p-4 mt-8 animate-fade-in font-sans">
      
      <div className="premium-glass rounded-[2rem] p-8 md:p-10 relative z-10 overflow-hidden group">
        
        {/* 【核心修复 2】：去掉了底下繁杂的小字副标题，极简，大气 */}
        <div className="text-center mb-10 relative z-10">
          <div className="inline-flex items-center justify-center p-4 bg-white/60 backdrop-blur-md rounded-2xl shadow-[0_8px_30px_rgb(0,0,0,0.08)] mb-6 border border-white/80 group-hover:scale-105 transition-transform duration-500">
            <Database className="text-blue-600 drop-shadow-md" size={40}/>
          </div>
          <h2 className="text-4xl md:text-5xl font-black tracking-tight mb-2">
            <span className="text-gradient-fluid">人机协同精准雷达</span>
          </h2>
        </div>

        <div className="space-y-6 relative z-10">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="space-y-2 md:col-span-2">
              <label className="text-sm font-black text-slate-700 flex items-center gap-1.5 ml-1"><Search size={16} className="text-blue-500"/> 目标公司全称 <span className="text-red-500">*</span></label>
              <input type="text" name="companyName" value={formData.companyName} onChange={handleChange} placeholder="例：深圳市某某科技有限公司" className="w-full p-4 bg-white/70 border border-white/80 shadow-[inset_0_2px_4px_rgba(0,0,0,0.02)] rounded-xl focus:ring-4 focus:ring-blue-500/20 focus:bg-white outline-none font-black text-slate-800 text-lg transition-all" />
            </div>
            <div className="space-y-2">
              <label className="text-sm font-black text-slate-700 flex items-center gap-1.5 ml-1"><MapPin size={16} className="text-rose-500"/> 注册/办公地址</label>
              <input type="text" name="address" value={formData.address} onChange={handleChange} className="w-full p-4 bg-white/70 border border-white/80 shadow-[inset_0_2px_4px_rgba(0,0,0,0.02)] rounded-xl focus:ring-4 focus:ring-blue-500/20 focus:bg-white outline-none font-bold text-slate-800 transition-all" />
            </div>
            <div className="space-y-2">
              <label className="text-sm font-black text-slate-700 flex items-center gap-1.5 ml-1"><Globe size={16} className="text-teal-500"/> 官方网站 <span className="text-red-500">*</span></label>
              <input type="text" name="website" value={formData.website} onChange={handleChange} placeholder="例：[www.example.com](https://www.example.com)" className="w-full p-4 bg-white/70 border border-white/80 shadow-[inset_0_2px_4px_rgba(0,0,0,0.02)] rounded-xl focus:ring-4 focus:ring-blue-500/20 focus:bg-white outline-none font-bold text-slate-800 transition-all" />
            </div>
          </div>
          <div className="space-y-2">
            <label className="text-sm font-black text-slate-700 flex items-center gap-1.5 ml-1"><FileText size={16} className="text-indigo-500"/> 工商经营范围 / 简介</label>
            <textarea name="profile" value={formData.profile} onChange={handleChange} rows="3" className="w-full p-4 bg-white/70 border border-white/80 shadow-[inset_0_2px_4px_rgba(0,0,0,0.02)] rounded-xl focus:ring-4 focus:ring-blue-500/20 focus:bg-white outline-none font-bold text-slate-800 leading-relaxed resize-none transition-all"></textarea>
          </div>

          {loading && (
             <div className="mt-8 p-6 bg-white/40 backdrop-blur-2xl rounded-2xl border border-white/60 shadow-[0_8px_30px_rgb(0,0,0,0.06)] relative overflow-hidden">
               <div className="absolute top-0 left-1/2 -translate-x-1/2 w-2/3 h-1 bg-gradient-to-r from-transparent via-blue-400 to-transparent opacity-60"></div>
               
               <div className="flex justify-between items-center mb-5">
                 <div className="flex items-center gap-3">
                    <div className="relative flex h-3.5 w-3.5">
                      <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-blue-400 opacity-75"></span>
                      <span className="relative inline-flex rounded-full h-3.5 w-3.5 bg-blue-500 shadow-[0_0_10px_rgba(59,130,246,0.8)]"></span>
                    </div>
                    <span className="font-black text-transparent bg-clip-text bg-gradient-to-r from-blue-700 to-indigo-600 tracking-wider text-sm md:text-base">
                      {streamStatus || '引擎唤醒中...'}
                    </span>
                 </div>
                 <div className="flex items-center gap-1.5 text-[10px] md:text-xs font-black text-blue-600 bg-blue-100/80 px-3 py-1.5 rounded-full shadow-sm border border-blue-200/50">
                    <Activity size={12} className="animate-pulse"/> IN PROGRESS
                 </div>
               </div>

               {/* 高级流光轨道与真实长度填充 */}
               <div className="h-3 w-full bg-slate-200/60 rounded-full overflow-hidden relative shadow-inner flex items-center">
                  <div 
                    className="h-full bg-gradient-to-r from-blue-500 via-cyan-400 to-indigo-500 shadow-[0_0_10px_rgba(56,189,248,0.5)] transition-all duration-500 ease-out relative"
                    style={{ width: `${progress}%` }}
                  >
                    {/* Cyber Scan 扫描光栅附着在进度条内部 */}
                    <div className="absolute top-0 left-0 h-full w-full bg-gradient-to-r from-transparent via-white to-transparent opacity-60 animate-cyber-scan blur-[1px]"></div>
                  </div>
               </div>
               
               {/* 百分比数字显示 */}
               <div className="mt-3 text-right">
                  <span className="text-xl font-black text-blue-600 tracking-tighter">
                     {progress}<span className="text-sm font-bold text-slate-400 ml-0.5">%</span>
                  </span>
               </div>
             </div>
          )}

          {!loading && (
            <button 
              onMouseDown={(e) => window.createRipple && window.createRipple(e, e.currentTarget)}
              onClick={handleSearch} 
              className="w-full mt-8 bg-gradient-to-r from-blue-600 via-indigo-600 to-cyan-500 hover:from-blue-500 hover:via-indigo-500 hover:to-cyan-400 text-white font-black text-lg p-5 rounded-[1.25rem] shadow-[0_10px_30px_rgba(59,130,246,0.3)] hover:shadow-[0_15px_40px_rgba(59,130,246,0.5)] hover:-translate-y-1 transition-all duration-300 flex items-center justify-center gap-3 relative overflow-hidden"
            >
              <Search size={24} className="animate-pulse" /> 启动全景雷达与图文重组
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
