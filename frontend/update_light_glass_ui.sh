#!/bin/bash
set -e

FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在重写全局 CSS：切换为【苹果级浅色霜化玻璃 (Light Frosted Glass)】..."

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
  background-color: #f8fafc; /* 清爽浅灰白底色 */
  overflow-x: hidden;
  color: #1e293b; /* 恢复全局深色清晰字体 */
}

/* 浅色优雅流体互动光影背景 */
body::before {
  content: '';
  position: fixed;
  top: 0; left: 0; right: 0; bottom: 0;
  background: 
    radial-gradient(circle at var(--fluid-x) var(--fluid-y), rgba(147, 197, 253, 0.4) 0%, transparent 40%),
    radial-gradient(circle at 20% 80%, rgba(196, 181, 253, 0.3) 0%, transparent 50%),
    radial-gradient(circle at 80% 20%, rgba(167, 243, 208, 0.3) 0%, transparent 50%);
  z-index: -1;
  transition: background 0.3s ease;
  pointer-events: none;
}

/* 苹果级浅色毛玻璃卡片 */
.glass-panel {
  background: rgba(255, 255, 255, 0.75) !important; /* 提高白底比例，确保文字极度清晰 */
  backdrop-filter: blur(20px) saturate(150%) !important;
  -webkit-backdrop-filter: blur(20px) saturate(150%) !important;
  border: 1px solid rgba(255, 255, 255, 0.9) !important;
  box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.06) !important;
}

/* 互动水波纹涟漪扩散特效 (淡蓝色波纹) */
.mouse-ripple {
  position: absolute;
  border-radius: 50%;
  transform: scale(0);
  animation: ripple 0.6s linear;
  background-color: rgba(59, 130, 246, 0.15); 
  pointer-events: none;
  z-index: 50;
}
@keyframes ripple {
  to { transform: scale(4); opacity: 0; }
}

/* 卡片悬浮液态呼吸感 */
.glass-hover-fx {
  transition: all 0.4s cubic-bezier(0.25, 0.8, 0.25, 1);
}
.glass-hover-fx:hover {
  background: rgba(255, 255, 255, 0.95) !important; /* 悬浮时变得更白更实 */
  transform: translateY(-2px);
  box-shadow: 0 15px 35px rgba(56, 189, 248, 0.12) !important;
}
EOF

echo ">>> 2. 正在重构主应用入口：恢复深色文本基调..."

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

// 全局流体力学背景追踪器
function FluidBackground() {
  useEffect(() => {
    let rafId;
    const handleMouseMove = (e) => {
      cancelAnimationFrame(rafId);
      rafId = requestAnimationFrame(() => {
        const x = (e.clientX / window.innerWidth) * 100;
        const y = (e.clientY / window.innerHeight) * 100;
        document.documentElement.style.setProperty('--fluid-x', `${x}%`);
        document.documentElement.style.setProperty('--fluid-y', `${y}%`);
      });
    };
    window.addEventListener('mousemove', handleMouseMove);
    return () => window.removeEventListener('mousemove', handleMouseMove);
  }, []);
  return null;
}

// 注入点击水波纹特效工具
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

echo ">>> 3. 正在全面恢复 ResultDisplay 的高对比度原色，保留玻璃面板与水波纹..."

cat << 'EOF' > "$FRONTEND_DIR/src/components/ResultDisplay.jsx"
import React, { useState, useEffect } from 'react';
import axios from 'axios';
import * as XLSX from 'xlsx';
import { useStore } from '../store';
import { Building2, Cpu, Zap, Lightbulb, Link as LinkIcon, Info, Box, Layers, Copy, Check, MapPin, Star, ShoppingCart, Globe2, FileText, Download, Table2, Users } from 'lucide-react';

export default function ResultDisplay() {
  const { searchResult: data, error, triggerRefresh } = useStore();
  const [copiedId, setCopiedId] = useState(null);
  const [category, setCategory] = useState('未收藏');

  useEffect(() => {
    if (data?.company) {
      axios.get('/api/customers').then(res => {
         const existing = res.data.data.find(c => c.company === data.company);
         setCategory(existing ? existing.category : '未收藏');
      }).catch(() => {});
    }
  }, [data]);

  if (error) return <div className="max-w-6xl mx-auto p-4 text-red-500 text-center font-bold glass-panel rounded-xl mt-4">{error}</div>;
  if (!data) return null;

  const siteUrl = data.website.startsWith('http') ? data.website : ['h', 't', 't', 'p', 's', '://', data.website].join('');

  const handleCopy = (text, id) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const handleCategoryChange = async (e) => {
    const newCat = e.target.value;
    setCategory(newCat);
    try {
      await axios.post('/api/customers', { ...data, category: newCat });
      triggerRefresh();
    } catch (err) {}
  };

  const aggregatedBomList = [];
  const bomMap = new Map();

  data.products?.forEach(p => {
    p.crystals?.forEach(c => {
      const key = `${c.freq}|${c.package}`;
      if (!bomMap.has(key)) {
        bomMap.set(key, {
          freq: c.freq,
          package: c.package,
          params: `CL:${c.loadCap} | Tol:${c.tolerance}`,
          function: c.function,
          devices: new Set([p.name]),
          chips: new Set([p.chipPlatform])
        });
      } else {
        bomMap.get(key).devices.add(p.name);
        bomMap.get(key).chips.add(p.chipPlatform);
      }
    });
  });

  bomMap.forEach(v => {
    aggregatedBomList.push({
      freq: v.freq,
      package: v.package,
      params: v.params,
      function: v.function,
      devices: Array.from(v.devices).join(' \n '),
      chips: Array.from(v.chips).join(' \n ')
    });
  });

  const exportToExcel = () => {
    const worksheetData = [
      ['晶振频率', '封装及参数', '应用此频点的终端设备', '涉及的主控架构(推演)', '核心作用解析'],
      ...aggregatedBomList.map(item => [item.freq, `${item.package} (${item.params})`, item.devices, item.chips, item.function])
    ];
    const ws = XLSX.utils.aoa_to_sheet(worksheetData);
    ws['!cols'] = [ { wch: 15 }, { wch: 25 }, { wch: 35 }, { wch: 40 }, { wch: 50 } ];
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "聚合BOM分析表");
    XLSX.writeFile(wb, `${data.company}_晶振BOM聚合分析.xlsx`);
  };

  const validContacts = data.keyContacts?.filter(c => c.name && c.name.indexOf('未知') === -1 && c.name.indexOf('未查明') === -1 && c.name !== '无');

  return (
    <div className="max-w-6xl mx-auto p-4 space-y-8 animate-fade-in mt-4 font-sans text-gray-800">
      
      {/* 1. 企业全景 */}
      <div className="glass-panel p-6 rounded-2xl relative group overflow-hidden border-t-4 border-blue-500" onMouseDown={(e) => window.createRipple(e, e.currentTarget)}>
        <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-4 border-b border-gray-100 pb-4 relative z-10">
            <div className="group/copy flex items-center gap-2 cursor-pointer hover:bg-blue-50/50 p-2 -ml-2 rounded-lg transition-colors" onClick={() => handleCopy(data.company, 'companyName')}>
              <Building2 className="text-blue-600" size={28}/> 
              <h2 className="text-2xl font-black text-blue-900">{data.company}</h2>
              {copiedId === 'companyName' ? <Check size={18} className="text-green-500 animate-pulse"/> : <Copy size={16} className="text-blue-300 opacity-0 group-hover/copy:opacity-100 transition-opacity"/>}
            </div>
            <div className="flex items-center gap-2 bg-white/60 px-4 py-2 rounded-xl shadow-sm border border-blue-100">
               <Star size={20} className={category !== '未收藏' ? 'text-yellow-500 fill-yellow-500' : 'text-gray-400'} />
               <span className="text-sm font-bold text-blue-800">客户归档：</span>
               <select value={category} onChange={handleCategoryChange} className="bg-transparent border-none text-blue-900 text-sm font-bold outline-none cursor-pointer">
                   <option value="未收藏">未收藏</option>
                   <option value="A类客户">🔥 A类客户</option>
                   <option value="B类客户">⭐ B类客户</option>
                   <option value="C类客户">📌 C类客户</option>
                   <option value="意向客户">🤝 意向客户</option>
                   <option value="合作客户">✅ 合作客户</option>
               </select>
            </div>
        </div>
        <div className="space-y-4 text-sm relative z-10 text-gray-700">
          <p className="flex items-center gap-3"><span className="font-semibold w-20 text-gray-500">注册地址:</span> <span className="font-bold flex items-center gap-1 text-gray-800"><MapPin size={18} className="text-red-500"/>{data.address || '未查明'}</span></p>
          <p className="flex items-center gap-3"><span className="font-semibold w-20 text-gray-500">官方网站:</span> <a href={siteUrl} target="_blank" rel="noopener noreferrer" className="flex items-center gap-1 text-blue-600 hover:text-blue-800 hover:underline font-bold"><LinkIcon size={18} /> {data.website}</a></p>
          <p className="flex items-center gap-3"><span className="font-semibold w-20 text-gray-500">业务类型:</span> <span className="bg-blue-100/80 text-blue-800 px-3 py-1 rounded-md text-sm font-bold shadow-sm border border-blue-200/50">{data.type}</span></p>
          <div className="mt-6 p-5 bg-blue-50/50 rounded-xl relative border border-blue-100">
             <div className="flex gap-3 items-start"><Info className="text-blue-500 flex-shrink-0 mt-1" size={22} /><p className="leading-loose text-base text-justify">{data.profile}</p></div>
          </div>
        </div>
      </div>

      {/* 2. 关键决策人 */}
      {validContacts && validContacts.length > 0 && (
        <div className="glass-panel p-6 rounded-2xl relative overflow-hidden glass-hover-fx border-t-4 border-amber-500">
          <h2 className="text-xl font-black flex items-center gap-2 mb-5 text-amber-900 border-b border-gray-100 pb-3"><Users className="text-amber-600" size={24}/> 关键决策人侦测</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 relative z-10">
             {validContacts.map((contact, idx) => (
               <div key={idx} className="bg-amber-50/60 p-4 rounded-xl flex flex-col gap-2 border border-amber-100">
                  <div className="flex justify-between items-start">
                     <div><span className="font-black text-lg text-amber-900">{contact.name}</span><span className="ml-2 text-xs font-bold bg-amber-100 text-amber-800 px-2 py-0.5 rounded">{contact.title}</span></div>
                  </div>
                  <div className="text-sm font-mono bg-white/70 px-3 py-1.5 rounded mt-1 text-gray-700 border border-gray-200/50">联络: {contact.contact}</div>
                  <div className="text-xs text-gray-500 mt-1">情报来源: {contact.context}</div>
               </div>
             ))}
          </div>
        </div>
      )}

      {/* 3. 寻源矩阵 */}
      {data.commonChipPlatforms && Array.isArray(data.commonChipPlatforms) && (
        <div className="glass-panel p-6 rounded-2xl relative overflow-hidden glass-hover-fx border-t-4 border-purple-500">
          <h2 className="text-2xl font-black flex items-center gap-2 mb-6 text-purple-900 border-b border-gray-100 pb-4"><Layers className="text-purple-600" size={28}/> 全球IC商城查价直连</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 relative z-10">
            {data.commonChipPlatforms.map((chip, idx) => {
              const enc = encodeURIComponent(chip.model);
              return (
                <div key={idx} className="bg-purple-50/60 rounded-xl p-5 relative flex flex-col justify-between border border-purple-100">
                  <div>
                    <span className="inline-block px-2 py-1 bg-purple-200 text-purple-900 text-xs font-bold rounded mb-2 shadow-sm">{chip.brand}</span>
                    <h3 className="text-lg font-black text-gray-900 mb-1 tracking-tight">{chip.model}</h3>
                    <p className="text-sm text-gray-600 leading-relaxed mb-4">{chip.application}</p>
                  </div>
                  <div className="mt-2 pt-3 border-t border-purple-200/50 space-y-2">
                    <div className="flex items-center gap-2">
                       <Globe2 size={12} className="text-gray-400"/>
                       <a href={`https://www.digikey.cn/zh/products/result?keywords=${enc}`} target="_blank" className="text-[11px] font-bold text-red-700 bg-red-100 hover:bg-red-200 px-2 py-1 rounded shadow-sm">DigiKey</a>
                       <a href={`https://www.mouser.cn/c/?q=${enc}`} target="_blank" className="text-[11px] font-bold text-blue-700 bg-blue-100 hover:bg-blue-200 px-2 py-1 rounded shadow-sm">Mouser</a>
                       <a href={`https://www.semiee.com/search?keyword=${enc}`} target="_blank" className="text-[11px] font-bold text-teal-800 bg-teal-100 hover:bg-teal-200 px-2 py-1 rounded shadow-sm ml-auto flex items-center gap-1"><FileText size={10}/>半岛小芯</a>
                    </div>
                    <div className="flex items-center gap-2 flex-wrap">
                      <ShoppingCart size={12} className="text-gray-400"/>
                      <a href={`https://so.szlcsc.com/global.html?k=${enc}`} target="_blank" className="text-[11px] font-bold text-blue-700 bg-blue-100 hover:bg-blue-200 px-2 py-1 rounded shadow-sm">立创</a>
                      <a href={`https://www.hqchip.com/search/${enc}.html`} target="_blank" className="text-[11px] font-bold text-orange-700 bg-orange-100 hover:bg-orange-200 px-2 py-1 rounded shadow-sm">华秋</a>
                      <a href={`https://s.hqew.com/${enc}.html`} target="_blank" className="text-[11px] font-bold text-indigo-700 bg-indigo-100 hover:bg-indigo-200 px-2 py-1 rounded shadow-sm">华强</a>
                      <a href={`https://www.allchips.com/search?keyword=${enc}`} target="_blank" className="text-[11px] font-bold text-red-600 bg-red-100 hover:bg-red-200 px-2 py-1 rounded shadow-sm">硬之城</a>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* 4. 产品展示区 */}
      <div className="space-y-6">
        <div className="flex items-center justify-between px-2">
            <h2 className="text-2xl font-black flex items-center gap-2 text-indigo-900"><Cpu className="text-indigo-600" size={28}/> 终端实物拆解</h2>
            <span className="text-sm font-bold text-indigo-700 bg-indigo-100 px-3 py-1 rounded-full shadow-sm border border-indigo-200">挖掘出 {data.products?.length || 0} 款产品</span>
        </div>
        
        {data.products && data.products.map((product, idx) => (
          <div key={idx} className="glass-panel p-6 rounded-2xl overflow-hidden glass-hover-fx" onMouseDown={(e) => window.createRipple(e, e.currentTarget)}>
            <div className="flex flex-col lg:flex-row gap-8 relative z-10">
              <div className="lg:w-1/3 flex flex-col items-center text-center space-y-4">
                <div className="w-full h-64 rounded-xl bg-white/60 border border-gray-100 relative overflow-hidden flex flex-col items-center justify-center shadow-inner">
                  {product.imageUrl ? (
                    <img src={`/api/image-proxy?url=${encodeURIComponent(product.imageUrl)}`} alt={product.name} className="w-full h-full object-contain p-2 hover:scale-110 transition-transform duration-700" onError={(e) => { e.target.style.display='none'; e.target.nextSibling.style.display='flex'; }}/>
                  ) : null}
                  <div className="absolute inset-0 flex-col items-center justify-center text-gray-400" style={{ display: product.imageUrl ? 'none' : 'flex' }}>
                    <Box size={48} className="mb-2 opacity-30"/>
                    <span className="text-sm font-bold px-4">{product.name}</span>
                  </div>
                </div>
                <h3 className="text-xl font-black text-gray-900 leading-tight">{product.name}</h3>
                <div className="w-full bg-indigo-50/80 p-5 rounded-xl text-left border border-indigo-100 shadow-sm">
                  <p className="text-xs text-indigo-700 font-bold mb-2 uppercase border-b border-indigo-200 pb-2">芯片架构拆解 (BOM)</p>
                  <p className="text-sm font-extrabold text-indigo-900 leading-loose whitespace-pre-wrap">{product.chipPlatform || '分析中...'}</p>
                </div>
              </div>
              <div className="lg:w-2/3 flex flex-col justify-center">
                <div className="flex items-center gap-2 mb-5 border-b border-gray-100 pb-3">
                  <Zap className="text-orange-500" size={24} />
                  <h4 className="font-black text-gray-900 text-lg">晶振解析</h4>
                </div>
                <div className="overflow-hidden rounded-xl bg-white/60 border border-gray-200 shadow-sm">
                  <table className="w-full text-left text-sm">
                    <thead className="bg-gray-100 text-gray-700 border-b border-gray-200">
                      <tr><th className="p-4 font-bold uppercase w-1/4">频率</th><th className="p-4 font-bold uppercase w-1/4">参数</th><th className="p-4 font-bold uppercase w-1/2">核心作用解析</th></tr>
                    </thead>
                    <tbody className="divide-y divide-gray-100">
                      {product.crystals?.map((c, cIdx) => (
                        <tr key={cIdx} className="hover:bg-orange-50/60 transition-colors">
                          <td className="p-4 font-black text-orange-600 text-lg whitespace-nowrap">{c.freq}</td>
                          <td className="p-4"><div className="font-bold text-gray-800">{c.package}</div><div className="text-gray-500 text-xs mt-1">CL:{c.loadCap} | Tol:{c.tolerance}</div></td>
                          <td className="p-4 text-gray-700 leading-relaxed text-justify bg-orange-50/30">{c.function}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* 5. 战术建议 */}
      <div className="glass-panel p-6 rounded-2xl relative overflow-hidden glass-hover-fx border-t-4 border-green-500">
        <h2 className="text-xl font-black flex items-center gap-2 mb-4 text-green-800 border-b border-gray-100 pb-3"><Lightbulb className="text-green-600" size={24}/> AI FAE 极速选型建议</h2>
        <p className="leading-loose font-medium text-base text-justify bg-green-50/80 p-4 rounded-xl relative z-10 text-gray-800 border border-green-100">{data.strategy}</p>
      </div>

      {/* 6. 聚合表 */}
      {aggregatedBomList.length > 0 && (
        <div className="glass-panel p-6 rounded-2xl relative overflow-hidden glass-hover-fx border-t-4 border-cyan-500">
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-6 border-b border-gray-100 pb-4 gap-4 relative z-10">
            <h2 className="text-2xl font-black flex items-center gap-2 text-cyan-900"><Table2 className="text-cyan-600" size={28}/> 晶振BOM聚合分析表</h2>
            <button onClick={exportToExcel} className="flex items-center gap-2 bg-cyan-600 hover:bg-cyan-700 text-white px-5 py-2.5 rounded-lg shadow-md transition-all font-bold text-sm">
              <Download size={18} /> 导出聚合 Excel
            </button>
          </div>
          <div className="overflow-x-auto rounded-xl bg-white/60 border border-gray-200 relative z-10 shadow-sm">
            <table className="w-full text-left text-sm">
              <thead className="bg-gray-100 text-gray-700">
                <tr><th className="p-3 font-bold border-b border-gray-200">汇总频率</th><th className="p-3 font-bold border-b border-gray-200">封装参数</th><th className="p-3 font-bold border-b border-gray-200">应用设备 (折叠合并)</th><th className="p-3 font-bold border-b border-gray-200">涉及主控 (折叠合并)</th></tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {aggregatedBomList.map((item, idx) => (
                  <tr key={idx} className="hover:bg-cyan-50/50 transition-colors text-gray-800">
                    <td className="p-3 font-black text-orange-600 text-lg align-top">{item.freq}</td>
                    <td className="p-3 align-top"><div className="font-bold">{item.package}</div><div className="text-xs mt-1 text-gray-500">{item.params}</div></td>
                    <td className="p-3 font-bold align-top whitespace-pre-wrap leading-loose text-blue-900">{item.devices}</td>
                    <td className="p-3 text-gray-600 align-top whitespace-pre-wrap leading-relaxed max-w-[250px]">{item.chips}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
EOF

echo ">>> 4. 重新打包渲染前台界面..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

echo "========================================================="
echo " ✅ 苹果级浅色霜化玻璃 UI 恢复完毕！高对比度图文王者归来！"
echo "========================================================="
