#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"
FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在重写后端检索引擎：注入【双轨递进图片嗅探引擎】极大提升型号图抓取率..."

cat << 'EOF' > "$BACKEND_DIR/controllers/searchController.js"
const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');
const cheerio = require('cheerio');
const configPath = path.join(__dirname, '../config/llm.json');

const getUrl = (b64) => Buffer.from(b64, 'base64').toString('utf8');
const PROVIDERS = {
    'deepseek': getUrl('aHR0cHM6Ly9hcGkuZGVlcHNlZWsuY29t'),
    'qwen': getUrl('aHR0cHM6Ly9kYXNoc2NvcGUuYWxpeXVuY3MuY29tL2NvbXBhdGlibGUtbW9kZS92MQ=='),
    'moonshot': getUrl('aHR0cHM6Ly9hcGkubW9vbnNob3QuY24vdjE='),
    'zhipu': getUrl('aHR0cHM6Ly9vcGVuLmJpZ21vZGVsLmNuL2FwaS9wYWFzL3Y0'),
    'openai': getUrl('aHR0cHM6Ly9hcGkub3BlbmFpLmNvbS92MQ==')
};

const proxyImage = (req, res) => {
    if (!req.query.url) return res.status(200).end();
    try {
        const client = req.query.url.startsWith('https') ? https : http;
        client.get(req.query.url, { headers: { 'User-Agent': 'Mozilla/5.0' }, rejectUnauthorized: false }, (stream) => {
            if (stream.statusCode !== 200) return res.status(200).end();
            res.setHeader('Content-Type', stream.headers['content-type'] || 'image/jpeg');
            stream.pipe(res);
        }).on('error', () => res.status(200).end()).setTimeout(4000, () => res.status(200).end());
    } catch (e) { res.status(200).end(); }
};

// 【双轨递进嗅探引擎】：最大化获取对应型号图
const fetchRealImage = async (company, modelName, domain = '') => {
    const fetchImg = async (searchQuery) => {
        try {
            const url = `https://cn.bing.com/images/search?q=${encodeURIComponent(searchQuery)}&first=1`;
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 3000);
            const res = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0' }, signal: controller.signal });
            clearTimeout(timeoutId);
            if(res.ok) {
                const text = await res.text();
                const match = text.match(/murl&quot;:&quot;(.*?)&quot;/);
                if (match && match[1]) return match[1];
            }
        } catch(e) {}
        return null;
    };
    
    // 清理型号名称，去除 AI 加的标签
    const cleanModel = modelName.replace(/\[.*?\]/g, '').replace(/\(.*?\)/g, '').trim();

    // 轨道 1：强制官网内网搜图 (高精度)
    if (domain) {
        const domainUrl = await fetchImg(`site:${domain} "${cleanModel}"`);
        if (domainUrl) return domainUrl;
    }
    
    // 轨道 2：全网强语义比对兜底 (高召回)
    return await fetchImg(`"${company}" "${cleanModel}" 官方 产品 实物`);
};

const fetchMatrixQuery = async (query, limit = 6) => {
    try {
        const url = `https://cn.bing.com/search?q=${encodeURIComponent(query)}`;
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 6000);
        const res = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0' }, signal: controller.signal });
        clearTimeout(timeoutId);
        if (res.ok) {
            const $ = cheerio.load(await res.text());
            let context = '';
            $('#b_results li.b_algo').slice(0, limit).each((i, el) => {
                const title = $(el).find('h2').text();
                const snippet = $(el).find('.b_caption p').text() || $(el).find('p').text();
                if (title && snippet) context += `[${title}]\n${snippet}\n\n`;
            });
            return context;
        }
    } catch(e) {}
    return "";
};

const searchLead = async (req, res) => {
    try {
        const { companyName, address, website, profile: userProfile } = req.body;
        if (!companyName) return res.status(400).json({ success: false, message: '请输入公司名称' });
        if (!fs.existsSync(configPath)) return res.status(400).json({ success: false, message: '请先配置 API' });
        const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));

        let targetDomain = '';
        if (website && website.trim() !== '') {
            targetDomain = website.replace(/^(?:https?:\/\/)?(?:www\.)?/i, "").split('/')[0];
        }
        const exact = `"${companyName}"`;
        const siteQueryStr = targetDomain ? `site:${targetDomain}` : exact;

        const [
            official_products, official_tech, b2b_trade, recruitment, contacts_info
        ] = await Promise.all([
            fetchMatrixQuery(`${siteQueryStr} "产品中心" OR "型号"` , 15),
            fetchMatrixQuery(`${siteQueryStr} "解决方案" OR "技术架构"`),
            fetchMatrixQuery(`${exact} (site:1688.com OR site:hc360.com) "主营产品"`),
            fetchMatrixQuery(`${exact} 招聘 硬件工程师 OR 研发`),
            fetchMatrixQuery(`${exact} "联系人" OR "采购" OR "邮箱" 招标`)
        ]);

        const prompt = `你是顶级商业侦探。剖析对象：【${companyName}】。
底牌：【地址】: ${address} | 【网址】: ${website} | 【工商范围】: ${userProfile}
情报：[官网产品]: ${official_products} | [技术]: ${official_tech} | [B2B]: ${b2b_trade} | [招聘]: ${recruitment} | [联系人]: ${contacts_info}

【核心指令】：
1. 提取所有你找到的硬件产品，有多少列多少，不封顶！产品名必须带上具体型号。
2. 芯片架构和晶振参数不准留空，没有就推演。
3. 业务类型打上 [生产制造型] 或 [贸易销售型] 标签。

输出严格JSON:
{
  "company": "${companyName}",
  "website": "${website || '未查明'}",
  "address": "整理输出地址",
  "coordinates": [纬度, 经度],
  "type": "精准业务类型带标签",
  "profile": "硬核企业分析不少于350字",
  "keyContacts": [{"name": "姓名(未查明置空数组)", "title": "职务", "contact": "联系方式", "context": "来源"}],
  "commonChipPlatforms": [{"brand": "品牌", "model": "型号", "application": "应用场景"}],
  "products": [
    {
      "name": "具体设备名称(型号)",
      "chipPlatform": "芯片架构组合(使用顿号或分号连贯书写，必须推演满)",
      "crystals": [{"freq": "频率", "package": "封装", "loadCap": "电容", "tolerance": "频偏", "function": "核心作用解析(客观阐述功能)"}]
    }
  ],
  "strategy": "销售策略建议"
}`;

        let safeBaseUrl = config.baseUrl;
        if (config.provider && PROVIDERS[config.provider]) safeBaseUrl = PROVIDERS[config.provider];
        safeBaseUrl = (safeBaseUrl || '').replace(/[\[\]\(\)]/g, '').split(' ')[0].trim().replace(/\/+$/, '');
        if (!safeBaseUrl.startsWith('http')) safeBaseUrl = getUrl('aHR0cHM6Ly9hcGkuZGVlcHNlZWsuY29t');
        
        const targetUrl = `${safeBaseUrl}/chat/completions`;
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 120000); 

        const response = await fetch(targetUrl, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${(config.apiKey || '').trim()}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model: (config.model || '').trim() || 'deepseek-chat',
                messages: [{ role: "user", content: prompt }],
                temperature: 0.3, 
                response_format: { type: "json_object" }
            }),
            signal: controller.signal
        });
        clearTimeout(timeoutId);

        if (!response.ok) return res.status(500).json({ success: false, message: `大模型拒绝 HTTP ${response.status}` });
        const data = await response.json();
        let content = data.choices[0].message.content.replace(/```json/g, '').replace(/```/g, '').trim();
        const resultData = JSON.parse(content);

        if (!Array.isArray(resultData.coordinates) || resultData.coordinates.length !== 2) {
            resultData.coordinates = [39.9042, 116.4074]; 
        }

        if (resultData.products && Array.isArray(resultData.products)) {
            const enrichedProducts = await Promise.all(resultData.products.map(async (p) => {
                if (p.name.includes('推演')) return { ...p, imageUrl: null };
                // 调用新的双轨搜图算法
                const imgUrl = await fetchRealImage(resultData.company, p.name, targetDomain);
                return { ...p, imageUrl: imgUrl };
            }));
            resultData.products = enrichedProducts;
        }

        res.json({ success: true, data: resultData });
    } catch (error) {
        res.status(500).json({ success: false, message: `系统异常: ${error.message}` });
    }
};

module.exports = { searchLead, proxyImage };
EOF

echo ">>> 2. 正在重构前端全局样式：注入【流体玻璃光感引擎 (Fluid Glassmorphism)】..."

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
  background-color: #0f172a; /* 深邃夜空底色 */
  overflow-x: hidden;
}

/* 全局流体互动光影背景 */
body::before {
  content: '';
  position: fixed;
  top: 0; left: 0; right: 0; bottom: 0;
  background: 
    radial-gradient(circle at var(--fluid-x) var(--fluid-y), rgba(56, 189, 248, 0.4) 0%, transparent 40%),
    radial-gradient(circle at 20% 80%, rgba(139, 92, 246, 0.3) 0%, transparent 50%),
    radial-gradient(circle at 80% 20%, rgba(59, 130, 246, 0.3) 0%, transparent 50%);
  z-index: -1;
  transition: background 0.3s ease;
  pointer-events: none;
}

/* 极致全透明玻璃面板 */
.glass-panel {
  background: rgba(255, 255, 255, 0.08) !important;
  backdrop-filter: blur(24px) saturate(150%) !important;
  -webkit-backdrop-filter: blur(24px) saturate(150%) !important;
  border: 1px solid rgba(255, 255, 255, 0.15) !important;
  box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.2) !important;
  color: #f8fafc;
}

/* 覆盖 Tailwind 默认的白色背景，实现全玻璃化 */
.glass-panel input, .glass-panel textarea, .glass-panel select, .glass-panel table, .glass-panel th, .glass-panel td {
  background: rgba(255, 255, 255, 0.05) !important;
  border-color: rgba(255, 255, 255, 0.1) !important;
  color: #f1f5f9 !important;
}

.glass-panel .text-gray-800, .glass-panel .text-blue-900, .glass-panel .text-gray-700, .glass-panel .text-indigo-900 {
  color: #ffffff !important;
}
.glass-panel .text-gray-500, .glass-panel .text-gray-600 {
  color: #cbd5e1 !important;
}

/* 互动水波纹涟漪扩散特效 */
.mouse-ripple {
  position: absolute;
  border-radius: 50%;
  transform: scale(0);
  animation: ripple 0.6s linear;
  background-color: rgba(255, 255, 255, 0.4);
  pointer-events: none;
}
@keyframes ripple {
  to { transform: scale(4); opacity: 0; }
}

/* 卡片悬浮液态呼吸感 */
.glass-hover-fx {
  transition: all 0.4s cubic-bezier(0.25, 0.8, 0.25, 1);
}
.glass-hover-fx:hover {
  background: rgba(255, 255, 255, 0.15) !important;
  transform: translateY(-2px);
  box-shadow: 0 15px 35px rgba(56, 189, 248, 0.2) !important;
}
EOF

echo ">>> 3. 正在注入流体互动控制器与【BOM频率逆向聚合算法】..."

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
    <div className="min-h-screen flex flex-col relative text-white">
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

  // 【核心数据聚合】：BOM 频率逆向合并算法
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
    <div className="max-w-6xl mx-auto p-4 space-y-8 animate-fade-in mt-4 font-sans text-white">
      
      <div className="glass-panel p-6 rounded-2xl relative group overflow-hidden" onMouseDown={(e) => window.createRipple(e, e.currentTarget)}>
        <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-4 border-b border-white/20 pb-4 relative z-10">
            <div className="group/copy flex items-center gap-2 cursor-pointer hover:bg-white/10 p-2 -ml-2 rounded-lg transition-colors" onClick={() => handleCopy(data.company, 'companyName')}>
              <Building2 className="text-blue-300" size={28}/> 
              <h2 className="text-2xl font-black text-white">{data.company}</h2>
              {copiedId === 'companyName' ? <Check size={18} className="text-green-400 animate-pulse"/> : <Copy size={16} className="text-white/50 opacity-0 group-hover/copy:opacity-100 transition-opacity"/>}
            </div>
            <div className="flex items-center gap-2 glass-panel px-4 py-2 rounded-xl">
               <Star size={20} className={category !== '未收藏' ? 'text-yellow-400 fill-yellow-400' : 'text-white/40'} />
               <span className="text-sm font-bold text-blue-100">客户归档：</span>
               <select value={category} onChange={handleCategoryChange} className="bg-transparent border border-white/30 text-white text-sm rounded-lg focus:ring-blue-400 outline-none cursor-pointer">
                   <option value="未收藏" className="text-black">未收藏</option>
                   <option value="A类客户" className="text-black">🔥 A类客户</option>
                   <option value="B类客户" className="text-black">⭐ B类客户</option>
                   <option value="C类客户" className="text-black">📌 C类客户</option>
                   <option value="意向客户" className="text-black">🤝 意向客户</option>
                   <option value="合作客户" className="text-black">✅ 合作客户</option>
               </select>
            </div>
        </div>
        <div className="space-y-4 text-sm relative z-10">
          <p className="flex items-center gap-3"><span className="font-semibold w-20 text-blue-200">注册地址:</span> <span className="font-bold flex items-center gap-1"><MapPin size={18} className="text-red-400"/>{data.address || '未查明'}</span></p>
          <p className="flex items-center gap-3"><span className="font-semibold w-20 text-blue-200">官方网站:</span> <a href={siteUrl} target="_blank" rel="noopener noreferrer" className="flex items-center gap-1 text-blue-300 hover:text-white hover:underline font-bold"><LinkIcon size={18} /> {data.website}</a></p>
          <p className="flex items-center gap-3"><span className="font-semibold w-20 text-blue-200">业务类型:</span> <span className="glass-panel px-3 py-1 rounded-md text-sm font-bold text-cyan-300">{data.type}</span></p>
          <div className="mt-6 p-5 glass-panel rounded-xl relative">
             <div className="flex gap-3 items-start"><Info className="text-blue-300 flex-shrink-0 mt-1" size={22} /><p className="leading-loose text-base text-justify">{data.profile}</p></div>
          </div>
        </div>
      </div>

      {validContacts && validContacts.length > 0 && (
        <div className="glass-panel p-6 rounded-2xl relative overflow-hidden glass-hover-fx">
          <h2 className="text-xl font-black flex items-center gap-2 mb-5 text-amber-300 border-b border-white/20 pb-3"><Users size={24}/> 关键决策人侦测</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
             {validContacts.map((contact, idx) => (
               <div key={idx} className="glass-panel p-4 rounded-xl flex flex-col gap-2 relative z-10">
                  <div className="flex justify-between items-start">
                     <div><span className="font-black text-lg text-white">{contact.name}</span><span className="ml-2 text-xs font-bold glass-panel px-2 py-0.5 rounded text-amber-200">{contact.title}</span></div>
                  </div>
                  <div className="text-sm font-mono glass-panel px-3 py-1.5 rounded mt-1">联络: {contact.contact}</div>
                  <div className="text-xs text-white/70 mt-1">情报来源: {contact.context}</div>
               </div>
             ))}
          </div>
        </div>
      )}

      {data.commonChipPlatforms && Array.isArray(data.commonChipPlatforms) && (
        <div className="glass-panel p-6 rounded-2xl relative overflow-hidden glass-hover-fx">
          <h2 className="text-2xl font-black flex items-center gap-2 mb-6 text-purple-300 border-b border-white/20 pb-4"><Layers size={28}/> 全球IC商城查价直连</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 relative z-10">
            {data.commonChipPlatforms.map((chip, idx) => {
              const enc = encodeURIComponent(chip.model);
              return (
                <div key={idx} className="glass-panel rounded-xl p-5 relative flex flex-col justify-between">
                  <div>
                    <span className="inline-block px-2 py-1 glass-panel text-xs font-bold rounded mb-2 text-purple-200">{chip.brand}</span>
                    <h3 className="text-lg font-black mb-1 tracking-tight">{chip.model}</h3>
                    <p className="text-sm text-white/70 leading-relaxed mb-4">{chip.application}</p>
                  </div>
                  <div className="mt-2 pt-3 border-t border-white/20 space-y-2">
                    <div className="flex items-center gap-2">
                       <Globe2 size={12} className="text-white/50"/>
                       <a href={`https://www.digikey.cn/zh/products/result?keywords=${enc}`} target="_blank" className="text-[11px] font-bold text-red-300 glass-panel hover:bg-white/20 px-2 py-1 rounded transition-colors">DigiKey</a>
                       <a href={`https://www.mouser.cn/c/?q=${enc}`} target="_blank" className="text-[11px] font-bold text-blue-300 glass-panel hover:bg-white/20 px-2 py-1 rounded transition-colors">Mouser</a>
                       <a href={`https://www.semiee.com/search?keyword=${enc}`} target="_blank" className="text-[11px] font-bold text-teal-300 glass-panel hover:bg-white/20 px-2 py-1 rounded ml-auto flex items-center gap-1"><FileText size={10}/>半岛小芯</a>
                    </div>
                    <div className="flex items-center gap-2 flex-wrap">
                      <ShoppingCart size={12} className="text-white/50"/>
                      <a href={`https://so.szlcsc.com/global.html?k=${enc}`} target="_blank" className="text-[11px] font-bold text-blue-200 glass-panel hover:bg-white/20 px-2 py-1 rounded">立创</a>
                      <a href={`https://www.hqchip.com/search/${enc}.html`} target="_blank" className="text-[11px] font-bold text-orange-300 glass-panel hover:bg-white/20 px-2 py-1 rounded">华秋</a>
                      <a href={`https://s.hqew.com/${enc}.html`} target="_blank" className="text-[11px] font-bold text-indigo-300 glass-panel hover:bg-white/20 px-2 py-1 rounded">华强</a>
                      <a href={`https://www.allchips.com/search?keyword=${enc}`} target="_blank" className="text-[11px] font-bold text-red-300 glass-panel hover:bg-white/20 px-2 py-1 rounded">硬之城</a>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      <div className="space-y-6">
        <div className="flex items-center justify-between px-2">
            <h2 className="text-2xl font-black flex items-center gap-2 text-indigo-300"><Cpu size={28}/> 终端实物拆解</h2>
            <span className="text-sm font-bold text-indigo-200 glass-panel px-3 py-1 rounded-full shadow-sm">挖掘出 {data.products?.length || 0} 款产品</span>
        </div>
        
        {data.products && data.products.map((product, idx) => (
          <div key={idx} className="glass-panel p-6 rounded-2xl overflow-hidden glass-hover-fx" onMouseDown={(e) => window.createRipple(e, e.currentTarget)}>
            <div className="flex flex-col lg:flex-row gap-8 relative z-10">
              <div className="lg:w-1/3 flex flex-col items-center text-center space-y-4">
                <div className="w-full h-64 rounded-xl glass-panel relative overflow-hidden flex flex-col items-center justify-center">
                  {product.imageUrl ? (
                    <img src={`/api/image-proxy?url=${encodeURIComponent(product.imageUrl)}`} alt={product.name} className="w-full h-full object-contain p-2 hover:scale-110 transition-transform duration-700" onError={(e) => { e.target.style.display='none'; e.target.nextSibling.style.display='flex'; }}/>
                  ) : null}
                  <div className="absolute inset-0 flex-col items-center justify-center text-white/40" style={{ display: product.imageUrl ? 'none' : 'flex' }}>
                    <Box size={48} className="mb-2 opacity-30"/>
                    <span className="text-sm font-bold px-4">{product.name}</span>
                  </div>
                </div>
                <h3 className="text-xl font-black leading-tight">{product.name}</h3>
                <div className="w-full glass-panel p-5 rounded-xl text-left">
                  <p className="text-xs text-indigo-300 font-bold mb-2 uppercase border-b border-white/20 pb-2">芯片架构拆解 (BOM)</p>
                  <p className="text-sm font-extrabold leading-loose whitespace-pre-wrap">{product.chipPlatform || '分析中...'}</p>
                </div>
              </div>
              <div className="lg:w-2/3 flex flex-col justify-center">
                <div className="flex items-center gap-2 mb-5 border-b border-white/20 pb-3">
                  <Zap className="text-orange-400" size={24} />
                  <h4 className="font-black text-lg">晶振解析</h4>
                </div>
                <div className="overflow-hidden rounded-xl glass-panel">
                  <table className="w-full text-left text-sm">
                    <thead className="glass-panel border-b border-white/20">
                      <tr><th className="p-4 font-bold uppercase w-1/4">频率</th><th className="p-4 font-bold uppercase w-1/4">参数</th><th className="p-4 font-bold uppercase w-1/2">核心作用解析</th></tr>
                    </thead>
                    <tbody className="divide-y divide-white/10">
                      {product.crystals?.map((c, cIdx) => (
                        <tr key={cIdx} className="hover:bg-white/10 transition-colors">
                          <td className="p-4 font-black text-orange-400 text-lg whitespace-nowrap">{c.freq}</td>
                          <td className="p-4"><div className="font-bold">{c.package}</div><div className="text-white/60 text-xs mt-1">CL:{c.loadCap} | Tol:{c.tolerance}</div></td>
                          <td className="p-4 text-white/80 leading-relaxed text-justify">{c.function}</td>
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

      <div className="glass-panel p-6 rounded-2xl relative overflow-hidden glass-hover-fx">
        <h2 className="text-xl font-black flex items-center gap-2 mb-4 text-green-400 border-b border-white/20 pb-3"><Lightbulb size={24}/> AI FAE 极速选型建议</h2>
        <p className="leading-loose font-medium text-base text-justify glass-panel p-4 rounded-xl relative z-10">{data.strategy}</p>
      </div>

      {/* 【新增】：相同频率聚合排重的 BOM 总表 */}
      {aggregatedBomList.length > 0 && (
        <div className="glass-panel p-6 rounded-2xl relative overflow-hidden glass-hover-fx">
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-6 border-b border-white/20 pb-4 gap-4 relative z-10">
            <h2 className="text-2xl font-black flex items-center gap-2 text-cyan-300"><Table2 size={28}/> 晶振BOM聚合分析表</h2>
            <button onClick={exportToExcel} className="flex items-center gap-2 bg-white/20 hover:bg-white/30 text-white px-5 py-2.5 rounded-lg shadow-md transition-all font-bold text-sm border border-white/30 backdrop-blur-md">
              <Download size={18} /> 导出聚合 Excel
            </button>
          </div>
          <div className="overflow-x-auto rounded-xl glass-panel relative z-10">
            <table className="w-full text-left text-sm">
              <thead className="glass-panel text-white/90">
                <tr><th className="p-3 font-bold border-b border-white/20 text-orange-400">汇总频率</th><th className="p-3 font-bold border-b border-white/20">封装参数</th><th className="p-3 font-bold border-b border-white/20">应用设备 (自动折叠合并)</th><th className="p-3 font-bold border-b border-white/20">涉及主控 (自动折叠合并)</th></tr>
              </thead>
              <tbody className="divide-y divide-white/10">
                {aggregatedBomList.map((item, idx) => (
                  <tr key={idx} className="hover:bg-white/10 transition-colors">
                    <td className="p-3 font-black text-orange-400 text-lg align-top">{item.freq}</td>
                    <td className="p-3 text-white/80 align-top"><div className="font-bold">{item.package}</div><div className="text-xs mt-1 text-white/50">{item.params}</div></td>
                    <td className="p-3 font-bold align-top whitespace-pre-wrap leading-loose text-cyan-100">{item.devices}</td>
                    <td className="p-3 text-white/70 align-top whitespace-pre-wrap leading-relaxed max-w-[250px]">{item.chips}</td>
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

echo ">>> 4. 正在编译剔除残留代码，启动赛博流体架构..."
cd "$FRONTEND_DIR"
# 清理可能残留的 Tailwind 白色背板
sed -i 's/bg-white/glass-panel/g' src/components/SearchLead.jsx || true
sed -i 's/bg-gray-50/glass-panel/g' src/components/SearchLead.jsx || true
sed -i 's/text-gray-800/text-white/g' src/components/SearchLead.jsx || true
sed -i 's/text-gray-700/text-blue-100/g' src/components/SearchLead.jsx || true

npm run build > /dev/null

cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ 全透明流体交互、BOM折叠算法、双轨图库嗅探 全面就绪！"
echo "========================================================="
