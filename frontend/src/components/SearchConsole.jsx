import React, { useState } from 'react';
import { Search, MapPin, Globe, AlertCircle } from 'lucide-react';
import { useStore } from '../store';
import PhaseBoard from './PhaseBoard';
import ResultDisplay from './ResultDisplay';
import ActionBar from './ActionBar';

export default function SearchConsole() {
  const {
    loading, setLoading, setResult, setError, error,
    setStreamStatus, clearStream,
    setPhaseStatus, resetPhases,
    searchResult: data,
  } = useStore();

  const [formData, setFormData] = useState({
    companyName: '',
    website: '',
    address: '',
  });

  const handleChange = (e) => {
    const { name, value } = e.target;
    if (name === 'companyName' && value.length > 100) return;
    setFormData((prev) => ({ ...prev, [name]: value }));
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      handleSearch();
    }
  };

  const handleSearch = async () => {
    if (!formData.companyName.trim()) {
      setError('公司全称必须填写！');
      return;
    }

    setLoading(true);
    setError(null);
    setResult(null);
    clearStream();
    resetPhases();

    const payload = {
      companyName: formData.companyName.trim(),
      website: formData.website.trim(),
      address: formData.address.trim(),
    };

    try {
      const response = await fetch('/api/search', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
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

          if (!message.startsWith('data: ')) continue;

          const dataStr = message.slice(6).trim();

          if (dataStr === '[DONE]') {
            setPhaseStatus('done', 'success');
            setLoading(false);
            return;
          }

          try {
            const parsed = JSON.parse(dataStr);

            if (parsed.error) {
              setError(parsed.error);
              setLoading(false);
              return;
            }

            if (parsed.status) {
              setStreamStatus(parsed.status);

              if (parsed.status.includes('官网')) {
                setPhaseStatus('website', 'running');
              }
              if (parsed.status.includes('搜索')) {
                setPhaseStatus('website', 'success');
                setPhaseStatus('search', 'running');
              }
              if (parsed.status.includes('降维') || parsed.status.includes('AI') || parsed.status.includes('大模型')) {
                setPhaseStatus('search', 'success');
                setPhaseStatus('ai', 'running');
              }
              if (parsed.status.includes('清洗') || parsed.status.includes('渲染')) {
                setPhaseStatus('ai', 'success');
                setPhaseStatus('done', 'running');
              }
            }

            if (parsed.fullData) {
              setPhaseStatus('ai', 'success');
              setPhaseStatus('done', 'success');
              setResult(parsed.fullData);
              setLoading(false);
              return;
            }
          } catch {
            // skip non-JSON lines
          }
        }
      }

      setLoading(false);
    } catch (err) {
      setError('网络连接断开或解析超时，请重试');
      setLoading(false);
    }
  };

  const showPhaseBoard = loading;
  const showActionBar = !loading && data;
  const showError = error && !data;

  return (
    <div className="max-w-6xl mx-auto p-4 mt-8 animate-fade-in font-sans">
      <div className="flex gap-6 items-start">
        {/* Left Sidebar: PhaseBoard */}
        {showPhaseBoard && (
          <div className="sticky top-4 w-56 flex-shrink-0">
            <PhaseBoard />
          </div>
        )}

        {/* Center: Search Form + Result */}
        <div className="flex-1 min-w-0">
          {/* Error Banner */}
          {showError && (
            <div className="flex items-center gap-3 p-4 mb-6 bg-red-50 border border-red-200 rounded-xl text-red-700 font-bold text-sm">
              <AlertCircle size={20} className="text-red-500 flex-shrink-0" />
              <span>{error}</span>
            </div>
          )}

          {/* Search Form */}
          <div className="premium-glass rounded-[2rem] p-8 md:p-10 relative z-10 overflow-hidden group">
            <div className="text-center mb-8 relative z-10">
              <div className="inline-flex items-center justify-center p-4 bg-white/60 backdrop-blur-md rounded-2xl shadow-[0_8px_30px_rgb(0,0,0,0.08)] mb-6 border border-white/80 group-hover:scale-105 transition-transform duration-500">
                <Search className="text-blue-600 drop-shadow-md" size={36} />
              </div>
              <h2 className="text-3xl md:text-4xl font-black tracking-tight">
                <span className="text-gradient-fluid">人机协同精准雷达</span>
              </h2>
            </div>

            <div className="space-y-5 relative z-10">
              <div className="space-y-2">
                <label className="text-sm font-black text-slate-700 flex items-center gap-1.5 ml-1">
                  <Search size={16} className="text-blue-500" /> 目标公司全称 <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  name="companyName"
                  value={formData.companyName}
                  onChange={handleChange}
                  onKeyDown={handleKeyDown}
                  maxLength={100}
                  placeholder="例：深圳市某某科技有限公司"
                  className="w-full p-4 bg-white/70 border border-white/80 shadow-[inset_0_2px_4px_rgba(0,0,0,0.02)] rounded-xl focus:ring-4 focus:ring-blue-500/20 focus:bg-white outline-none font-black text-slate-800 text-lg transition-all"
                />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
                <div className="space-y-2">
                  <label className="text-sm font-black text-slate-700 flex items-center gap-1.5 ml-1">
                    <Globe size={16} className="text-teal-500" /> 官方网站
                  </label>
                  <input
                    type="text"
                    name="website"
                    value={formData.website}
                    onChange={handleChange}
                    onKeyDown={handleKeyDown}
                    placeholder="www.example.com"
                    className="w-full p-4 bg-white/70 border border-white/80 shadow-[inset_0_2px_4px_rgba(0,0,0,0.02)] rounded-xl focus:ring-4 focus:ring-blue-500/20 focus:bg-white outline-none font-bold text-slate-800 transition-all"
                  />
                </div>
                <div className="space-y-2">
                  <label className="text-sm font-black text-slate-700 flex items-center gap-1.5 ml-1">
                    <MapPin size={16} className="text-rose-500" /> 注册 / 办公地址
                  </label>
                  <input
                    type="text"
                    name="address"
                    value={formData.address}
                    onChange={handleChange}
                    onKeyDown={handleKeyDown}
                    placeholder="例：广东省深圳市南山区"
                    className="w-full p-4 bg-white/70 border border-white/80 shadow-[inset_0_2px_4px_rgba(0,0,0,0.02)] rounded-xl focus:ring-4 focus:ring-blue-500/20 focus:bg-white outline-none font-bold text-slate-800 transition-all"
                  />
                </div>
              </div>

              <button
                onClick={handleSearch}
                disabled={loading || !formData.companyName.trim()}
                className="w-full mt-4 bg-gradient-to-r from-blue-600 via-indigo-600 to-cyan-500 hover:from-blue-500 hover:via-indigo-500 hover:to-cyan-400 text-white font-black text-lg p-5 rounded-[1.25rem] shadow-[0_10px_30px_rgba(59,130,246,0.3)] hover:shadow-[0_15px_40px_rgba(59,130,246,0.5)] hover:-translate-y-1 transition-all duration-300 flex items-center justify-center gap-3 relative overflow-hidden disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:translate-y-0 disabled:hover:shadow-[0_10px_30px_rgba(59,130,246,0.3)]"
              >
                <Search size={24} /> 启动全景雷达与图文重组
              </button>

              <p className="text-xs text-slate-400 text-center mt-1 font-bold">按 Ctrl+Enter 快速提交</p>
            </div>
          </div>

          {/* Result Display */}
          {data && <ResultDisplay />}
        </div>

        {/* Right Sidebar: ActionBar */}
        {showActionBar && (
          <div className="sticky top-4 w-48 flex-shrink-0">
            <ActionBar />
          </div>
        )}
      </div>
    </div>
  );
}
