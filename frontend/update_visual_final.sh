#!/bin/bash
set -e

FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在重构前端雷达控制台：恢复深色实体文字与高对比度输入框..."

cat << 'EOF' > "$FRONTEND_DIR/src/components/SearchLead.jsx"
import React, { useState } from 'react';
import axios from 'axios';
import { Search, Loader2, Database, MapPin, Globe, FileText } from 'lucide-react';
import { useStore } from '../store';

export default function SearchLead() {
  const { setLoading, setResult, setError, loading } = useStore();
  
  const [formData, setFormData] = useState({
    companyName: '',
    address: '',
    website: '',
    profile: ''
  });

  const handleChange = (e) => {
    setFormData({ ...formData, [e.target.name]: e.target.value });
  };

  const handleSearch = async () => {
    if (!formData.companyName.trim()) {
      setError('公司全称必须填写！');
      return;
    }
    setLoading(true);
    setError(null);
    setResult(null);

    try {
      const response = await axios.post('/api/search', formData);
      setResult(response.data.data);
    } catch (err) {
      setError(err.response?.data?.message || '服务器连接失败');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-4xl mx-auto p-4 mt-6 animate-fade-in font-sans">
      <div className="glass-panel rounded-2xl shadow-xl p-6 md:p-8 border-t-4 border-blue-500 relative z-10" onMouseDown={(e) => window.createRipple(e, e.currentTarget)}>
        <div className="text-center mb-8 relative z-10">
          <h2 className="text-3xl font-black text-gray-800 tracking-tight flex items-center justify-center gap-2">
            <Database className="text-blue-600" size={32}/> 人机协同精准雷达
          </h2>
          <p className="text-gray-500 mt-2 font-medium">输入确切企业底牌，AI 定向深潜全网与目标官网，挖掘硬核产品线</p>
        </div>

        <div className="space-y-5 relative z-10">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
            <div className="space-y-1.5 md:col-span-2">
              <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><Search size={14} className="text-blue-500"/> 目标公司全称 <span className="text-red-500">*</span></label>
              <input type="text" name="companyName" value={formData.companyName} onChange={handleChange} placeholder="请输入目标企业完整全称，例：深圳市某某智能科技有限公司" className="w-full p-4 bg-white/80 border border-gray-200 shadow-sm rounded-xl focus:ring-2 focus:ring-blue-500 outline-none font-black text-gray-900 text-lg placeholder-gray-400 transition-all backdrop-blur-sm" />
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><MapPin size={14} className="text-red-500"/> 注册/办公地址 (用于地图作战标点)</label>
              <input type="text" name="address" value={formData.address} onChange={handleChange} placeholder="例：广东省深圳市南山区某某大道某某大厦" className="w-full p-3 bg-white/80 border border-gray-200 shadow-sm rounded-lg focus:ring-2 focus:ring-blue-500 outline-none font-bold text-gray-800 placeholder-gray-400 transition-all backdrop-blur-sm" />
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><Globe size={14} className="text-teal-500"/> 官方网站 (AI 将定向潜入该网站抓取)</label>
              <input type="text" name="website" value={formData.website} onChange={handleChange} placeholder="例：[www.example.com](https://www.example.com)" className="w-full p-3 bg-white/80 border border-gray-200 shadow-sm rounded-lg focus:ring-2 focus:ring-blue-500 outline-none font-bold text-gray-800 placeholder-gray-400 transition-all backdrop-blur-sm" />
            </div>
          </div>
          <div className="space-y-1.5">
            <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><FileText size={14} className="text-purple-500"/> 工商经营范围 / 企业简介 (极其重要)</label>
            <textarea name="profile" value={formData.profile} onChange={handleChange} rows="3" placeholder="请将企查查/天眼查中的【经营范围】直接粘贴至此。AI 将结合此范围与官网数据，实施像素级精准推演..." className="w-full p-4 bg-white/80 border border-gray-200 shadow-sm rounded-xl focus:ring-2 focus:ring-blue-500 outline-none font-bold text-gray-800 placeholder-gray-400 text-sm leading-relaxed transition-all resize-none backdrop-blur-sm"></textarea>
          </div>

          <button onClick={handleSearch} disabled={loading} className="w-full mt-6 bg-gradient-to-r from-blue-600 to-indigo-600 text-white font-black text-lg p-4 rounded-xl shadow-lg hover:shadow-2xl hover:scale-[1.01] transition-all flex items-center justify-center gap-2 disabled:opacity-70 disabled:scale-100 disabled:cursor-not-allowed border border-blue-400/50">
            {loading ? <><Loader2 className="animate-spin" size={24} /> 探针全网深潜中，这需要一点时间...</> : <><Search size={24} /> 提交底牌并开始深挖产品</>}
          </button>
        </div>
      </div>
    </div>
  );
}
EOF

echo ">>> 2. 正在升级全局 CSS：注入超大水波纹特效与流体拖尾..."

cat << 'EOF' > "$FRONTEND_DIR/src/index.css"
@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  --fluid-x: 50%;
  --fluid-y: 50%;
}

body {
  margin: 0;
  font-family: 'Inter', system-ui, -apple-system, sans-serif;
  -webkit-font-smoothing: antialiased;
  background-color: #f1f5f9; /* 明亮的极地灰 */
  overflow-x: hidden;
  color: #1e293b;
}

/* 超大广角流体互动背景 */
body::before {
  content: '';
  position: fixed;
  top: 0; left: 0; right: 0; bottom: 0;
  background: 
    radial-gradient(circle at var(--fluid-x) var(--fluid-y), rgba(59, 130, 246, 0.4) 0%, rgba(147, 197, 253, 0.1) 30%, transparent 70%),
    radial-gradient(circle at 10% 90%, rgba(167, 139, 250, 0.35) 0%, transparent 60%),
    radial-gradient(circle at 90% 10%, rgba(52, 211, 153, 0.3) 0%, transparent 60%);
  z-index: -1;
  transition: background 0.1s ease-out; /* 降低延迟，让跟随更敏捷 */
  pointer-events: none;
}

/* 优质浅色毛玻璃材质 */
.glass-panel {
  background: rgba(255, 255, 255, 0.75) !important;
  backdrop-filter: blur(24px) saturate(150%) !important;
  -webkit-backdrop-filter: blur(24px) saturate(150%) !important;
  border: 1px solid rgba(255, 255, 255, 0.9) !important;
  box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.05) !important;
}

/* 卡片悬浮液态呼吸感 */
.glass-hover-fx {
  transition: all 0.4s cubic-bezier(0.25, 0.8, 0.25, 1);
}
.glass-hover-fx:hover {
  background: rgba(255, 255, 255, 0.95) !important;
  transform: translateY(-2px);
  box-shadow: 0 15px 35px rgba(59, 130, 246, 0.15) !important;
}

/* ================= 物理水波特效区 ================= */

/* 1. 鼠标滑动时的巨大水波拖尾 */
.wave-trail {
  position: fixed;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(96, 165, 250, 0.5) 0%, rgba(147, 197, 253, 0) 70%);
  pointer-events: none;
  transform: translate(-50%, -50%) scale(0.2);
  animation: waveTrailAnim 1.2s ease-out forwards;
  z-index: -1;
}
@keyframes waveTrailAnim {
  0% { transform: translate(-50%, -50%) scale(0.2); opacity: 0.8; }
  100% { transform: translate(-50%, -50%) scale(4); opacity: 0; }
}

/* 2. 点击卡片时的爆炸涟漪 (范围加大两倍) */
.mouse-ripple {
  position: absolute;
  border-radius: 50%;
  transform: scale(0);
  animation: ripple 0.8s cubic-bezier(0.2, 0.8, 0.2, 1);
  background-color: rgba(59, 130, 246, 0.3); 
  pointer-events: none;
  z-index: 50;
}
@keyframes ripple {
  to { transform: scale(10); opacity: 0; }
}
EOF

echo ">>> 3. 正在重构入口文件：挂载【物理流体拖尾粒子生成器】..."

cat << 'EOF' > "$FRONTEND_DIR/src/App.jsx"
import React, { useEffect } from 'react';
import Header from './components/Header';
import SearchLead from './components/SearchLead';
import ResultDisplay from './components/ResultDisplay';
import PdfTranslator from './components/PdfTranslator';
import CustomerMap from './components/CustomerMap';
import CustomerDatabase from './components/CustomerDatabase';
import SettingsModal from './components/SettingsModal';
import { useStore } from './store';

// 全局流体力学背景与波纹拖尾引擎
function FluidBackground() {
  useEffect(() => {
    let rafId;
    let lastSpawnTime = 0;
    
    const handleMouseMove = (e) => {
      cancelAnimationFrame(rafId);
      rafId = requestAnimationFrame(() => {
        // 1. 移动底部光晕巨幕
        const x = (e.clientX / window.innerWidth) * 100;
        const y = (e.clientY / window.innerHeight) * 100;
        document.documentElement.style.setProperty('--fluid-x', `${x}%`);
        document.documentElement.style.setProperty('--fluid-y', `${y}%`);

        // 2. 鼠标划动生成水波涟漪粒子 (每 60 毫秒生成一个)
        const now = Date.now();
        if (now - lastSpawnTime > 60) {
          const wave = document.createElement('div');
          wave.className = 'wave-trail';
          
          // 随机生成 100px 到 200px 左右的初始波纹大小
          const size = Math.random() * 100 + 100; 
          wave.style.width = `${size}px`;
          wave.style.height = `${size}px`;
          wave.style.left = `${e.clientX}px`;
          wave.style.top = `${e.clientY}px`;
          
          document.body.appendChild(wave);
          
          // 动画结束后清理 DOM 节点
          setTimeout(() => wave.remove(), 1200);
          lastSpawnTime = now;
        }
      });
    };
    
    window.addEventListener('mousemove', handleMouseMove);
    return () => window.removeEventListener('mousemove', handleMouseMove);
  }, []);
  return null;
}

// 点击水波纹挂载器
window.createRipple = function(event, element) {
  const circle = document.createElement("span");
  const diameter = Math.max(element.clientWidth, element.clientHeight);
  const radius = diameter / 2;
  circle.style.width = circle.style.height = `${diameter}px`;
  circle.style.left = `${event.clientX - element.getBoundingClientRect().left - radius}px`;
  circle.style.top = `${event.clientY - element.getBoundingClientRect().top - radius}px`;
  circle.classList.add("mouse-ripple");
  
  const existing = element.querySelector('.mouse-ripple');
  if (existing) existing.remove();
  
  element.appendChild(circle);
};

export default function App() {
  const { activeTab } = useStore();
  
  return (
    <div className="min-h-screen flex flex-col relative text-gray-800">
      <FluidBackground />
      <Header />
      <SettingsModal />
      
      <main className="flex-1 w-full relative z-10">
        {activeTab === 'search' && (
          <div className="w-full absolute inset-0 overflow-y-auto pb-20 scroll-smooth">
            <SearchLead />
            <ResultDisplay />
          </div>
        )}
        {activeTab === 'pdf' && <div className="w-full absolute inset-0 overflow-y-auto pb-20"><PdfTranslator /></div>}
        {activeTab === 'map' && <div className="w-full absolute inset-0 overflow-hidden"><CustomerMap /></div>}
        {activeTab === 'database' && <div className="w-full absolute inset-0 overflow-y-auto pb-20"><CustomerDatabase /></div>}
      </main>
    </div>
  );
}
EOF

echo ">>> 4. 重新打包渲染前台界面..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

echo "========================================================="
echo " ✅ 雷达台高对比度修复完毕！超大流体波纹已激活！"
echo "========================================================="
