import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { X, Save, Key, Server, Loader2, CheckCircle2 } from 'lucide-react';
import { useStore } from '../store';

export default function SettingsModal() {
  const { settingsOpen, setSettingsOpen } = useStore();
  const [config, setConfig] = useState({ provider: 'deepseek', apiKey: '', baseUrl: '', model: '' });
  const [saving, setSaving] = useState(false);
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState(null);

  useEffect(() => {
    if (settingsOpen) {
      axios.get('/api/config').then(res => {
        if (res.data.data) setConfig(res.data.data);
      });
    }
  }, [settingsOpen]);

  if (!settingsOpen) return null;

  const handleSave = async () => {
    setSaving(true);
    try {
      await axios.post('/api/config', config);
      setSettingsOpen(false);
    } catch (err) {
      alert('保存失败');
    } finally {
      setSaving(false);
    }
  };

  const handleTest = async () => {
    setTesting(true);
    setTestResult(null);
    try {
      const res = await axios.get('/api/config/test');
      setTestResult({ success: res.data.success, msg: res.data.message });
    } catch (err) {
      setTestResult({ success: false, msg: '连接彻底失败，请检查网络或配置' });
    } finally {
      setTesting(false);
    }
  };

  // 【核心修复】：加上 z-[9999] 保证弹窗在最顶层
  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-md animate-fade-in font-sans">
      <div className="glass-panel p-8 rounded-2xl shadow-2xl max-w-lg w-full transform transition-all border-t-4 border-blue-500">
        
        <div className="flex justify-between items-center mb-6 border-b border-gray-200/50 pb-4">
          <h2 className="text-2xl font-black text-gray-800 flex items-center gap-2">
             <Server className="text-blue-600"/> 核心引擎配置
          </h2>
          <button onClick={() => setSettingsOpen(false)} className="text-gray-400 hover:text-red-500 bg-gray-100/50 hover:bg-red-50 p-2 rounded-lg transition-colors">
            <X size={20} />
          </button>
        </div>

        <div className="space-y-5">
          <div className="space-y-1.5">
            <label className="text-sm font-bold text-gray-700 flex items-center gap-1">供应商</label>
            <select
              value={config.provider}
              onChange={(e) => setConfig({...config, provider: e.target.value})}
              className="w-full p-3 bg-white/80 border border-gray-300 rounded-lg outline-none font-bold text-gray-800"
            >
              <option value="deepseek">DeepSeek 官方</option>
              <option value="qwen">阿里通义千问</option>
              <option value="moonshot">Kimi (月之暗面)</option>
              <option value="zhipu">智谱 GLM</option>
              <option value="openai">OpenAI (自定义)</option>
            </select>
          </div>

          <div className="space-y-1.5">
            <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><Key size={14}/> API Key</label>
            <input 
              type="password" 
              value={config.apiKey} 
              onChange={(e) => setConfig({...config, apiKey: e.target.value})}
              className="w-full p-3 bg-white/80 border border-gray-300 rounded-lg outline-none font-mono"
              placeholder="sk-..."
            />
          </div>

          {config.provider === 'openai' && (
             <>
                <div className="space-y-1.5">
                  <label className="text-sm font-bold text-gray-700">Base URL (含 /v1)</label>
                  <input type="text" value={config.baseUrl} onChange={(e) => setConfig({...config, baseUrl: e.target.value})} className="w-full p-3 bg-white/80 border border-gray-300 rounded-lg outline-none" placeholder="[https://api.openai.com/v1](https://api.openai.com/v1)" />
                </div>
                <div className="space-y-1.5">
                  <label className="text-sm font-bold text-gray-700">模型名称</label>
                  <input type="text" value={config.model} onChange={(e) => setConfig({...config, model: e.target.value})} className="w-full p-3 bg-white/80 border border-gray-300 rounded-lg outline-none" placeholder="gpt-4o-mini" />
                </div>
             </>
          )}

          {testResult && (
            <div className={`p-3 rounded-lg text-sm font-bold flex items-center gap-2 ${testResult.success ? 'bg-green-100 text-green-700 border border-green-200' : 'bg-red-100 text-red-700 border border-red-200'}`}>
              {testResult.success ? <CheckCircle2 size={16}/> : <X size={16}/>}
              {testResult.msg}
            </div>
          )}

          <div className="flex gap-3 pt-4">
             <button onClick={handleTest} disabled={testing} className="flex-1 py-3 bg-gray-100 hover:bg-gray-200 text-gray-800 font-bold rounded-xl transition-all border border-gray-300 flex items-center justify-center gap-2">
                {testing ? <Loader2 className="animate-spin" size={18}/> : <Server size={18}/>} 连通性测试
             </button>
             <button onClick={handleSave} disabled={saving} className="flex-1 py-3 bg-blue-600 hover:bg-blue-700 text-white font-bold rounded-xl shadow-md transition-all flex items-center justify-center gap-2">
                {saving ? <Loader2 className="animate-spin" size={18}/> : <Save size={18}/>} 保存配置
             </button>
          </div>

        </div>
      </div>
    </div>
  );
}
