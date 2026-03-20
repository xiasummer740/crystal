#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"
FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在重写后端：注入【全量数据持久化保存】与【生产/销售鉴别指令】..."

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
        res.json({ success: true, data: JSON.parse(rawData || '[]') });
    } catch (e) {
        res.json({ success: true, data: [] });
    }
};

const saveCustomer = (req, res) => {
    try {
        if (!fs.existsSync(dbDir)) fs.mkdirSync(dbDir, { recursive: true });
        if (!fs.existsSync(dbPath)) fs.writeFileSync(dbPath, '[]');
        
        let customers = JSON.parse(fs.readFileSync(dbPath, 'utf8') || '[]');
        const customerData = req.body; // 【核心升级】：接收并保存该客户的完整分析报告
        
        const index = customers.findIndex(c => c.company === customerData.company);
        if (customerData.category === '未收藏') {
            if (index > -1) customers.splice(index, 1);
        } else {
            if (index > -1) customers[index] = customerData;
            else customers.push(customerData);
        }
        
        fs.writeFileSync(dbPath, JSON.stringify(customers, null, 2));
        res.json({ success: true, message: '全量档案已归档保存' });
    } catch (e) {
        res.status(500).json({ success: false, message: '档案保存失败' });
    }
};

const deleteCustomer = (req, res) => {
    try {
        const { company } = req.body;
        if (!fs.existsSync(dbPath)) return res.json({ success: true });
        let customers = JSON.parse(fs.readFileSync(dbPath, 'utf8'));
        customers = customers.filter(c => c.company !== company);
        fs.writeFileSync(dbPath, JSON.stringify(customers, null, 2));
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

module.exports = { getCustomers, saveCustomer, deleteCustomer };
EOF

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

const fetchRealImage = async (query, domain = '') => {
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
    if (domain) {
        const domainUrl = await fetchImg(`site:${domain} ${query}`);
        if (domainUrl) return domainUrl;
    }
    return await fetchImg(query);
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
爬虫：
[官网产品]: ${official_products}
[官网技术]: ${official_tech}
[B2B产品]: ${b2b_trade}
[联系人]: ${contacts_info}

【核心指令】：
1. **类型判别**：在 \`type\` 字段中，必须根据其“工商范围”明确判定并标注后缀。如果是研发、制造，则标注 **[生产制造型]**；如果是代理、批发、销售，则标注 **[贸易销售型]**。
2. **防偷懒提取与来源标注**：在 \`products.name\` 字段中，必须把你看到的所有硬件产品全部列出来（不低于6个，若有）。并且，**名字前必须加上标签**：如果是从爬虫数据里看到的，加上 \`[真实抓取]\`；如果是你根据范围推演的，加上 \`[AI推演]\`。
3. 产品BOM及频率必须详细推演，绝不留空。
4. 决策人若无确切姓名，则 keyContacts 必须输出空数组 []。

输出严格JSON:
{
  "company": "${companyName}",
  "website": "${website || '未查明'}",
  "address": "整理输出详细地址",
  "coordinates": [纬度, 经度],
  "type": "精准业务类型 (必须带有 [生产制造型] 或 [贸易销售型] 后缀)",
  "profile": "硬核企业背景分析（不少于350字）。",
  "keyContacts": [
    {"name": "姓名(未查明则置空数组)", "title": "职务", "contact": "联系方式", "context": "来源"}
  ],
  "commonChipPlatforms": [
    {"brand": "品牌", "model": "型号", "application": "应用场景"}
  ],
  "products": [
    {
      "name": "[真实抓取]或[AI推演] 具体设备名称",
      "chipPlatform": "详细的芯片架构组合(如：主控采用xxx，通信采用xxx)",
      "crystals": [
        {"freq": "频率", "package": "封装", "loadCap": "电容", "tolerance": "频偏", "function": "核心作用解析(客观阐述为什么需要它)"}
      ]
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
                const cleanName = p.name.replace(/\[.*?\]/g, '').replace(/\(.*?\)/g, '').trim();
                const query = `"${resultData.company}" "${cleanName}" 产品`;
                const imgUrl = await fetchRealImage(query, targetDomain);
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

echo ">>> 2. 正在重构前端全局样式：注入水波纹特效与毛玻璃(Glassmorphism)底纹..."

cat << 'EOF' > "$FRONTEND_DIR/src/index.css"
@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  margin: 0;
  font-family: 'Inter', system-ui, -apple-system, sans-serif;
  -webkit-font-smoothing: antialiased;
  /* 动态渐变深邃蓝紫背景 */
  background: linear-gradient(-45deg, #e0e7ff, #f3e8ff, #eef2ff, #f8fafc);
  background-size: 400% 400%;
  animation: gradientBG 15s ease infinite;
}

@keyframes gradientBG {
  0% { background-position: 0% 50%; }
  50% { background-position: 100% 50%; }
  100% { background-position: 0% 50%; }
}

/* 极致毛玻璃材质卡片 */
.glass-panel {
  background: rgba(255, 255, 255, 0.65);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border: 1px solid rgba(255, 255, 255, 0.4);
  box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.07);
}

/* 鼠标水波纹扩散特效 */
.mouse-ripple {
  position: fixed;
  width: 20px;
  height: 20px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(138, 43, 226, 0.6) 0%, rgba(138, 43, 226, 0) 70%);
  transform: translate(-50%, -50%) scale(1);
  pointer-events: none;
  animation: rippleAnim 0.8s ease-out forwards;
  z-index: 9999;
}

@keyframes rippleAnim {
  to { transform: translate(-50%, -50%) scale(6); opacity: 0; }
}
EOF

echo ">>> 3. 正在重写前端组件：增加水波纹挂载、档案库页面、及毛玻璃UI应用..."

cat << 'EOF' > "$FRONTEND_DIR/src/App.jsx"
import React, { useEffect } from 'react';
import Header from './components/Header';
import SearchLead from './components/SearchLead';
import ResultDisplay from './components/ResultDisplay';
import PdfTranslator from './components/PdfTranslator';
import CustomerMap from './components/CustomerMap';
import CustomerDatabase from './components/CustomerDatabase'; // 新增档案库
import SettingsModal from './components/SettingsModal';
import { useStore } from './store';

function RippleEffect() {
  useEffect(() => {
    let throttleTimer;
    const handleMouseMove = (e) => {
      if (throttleTimer) return;
      throttleTimer = setTimeout(() => {
        const ripple = document.createElement('div');
        ripple.className = 'mouse-ripple';
        ripple.style.left = `${e.clientX}px`;
        ripple.style.top = `${e.clientY}px`;
        document.body.appendChild(ripple);
        setTimeout(() => ripple.remove(), 800);
        throttleTimer = null;
      }, 50); // 控制波纹生成频率
    };
    window.addEventListener('mousemove', handleMouseMove);
    return () => window.removeEventListener('mousemove', handleMouseMove);
  }, []);
  return null;
}

export default function App() {
  const { activeTab } = useStore();
  
  return (
    <div className="min-h-screen flex flex-col relative text-gray-800">
      <RippleEffect />
      <Header />
      <SettingsModal />
      
      <main className="flex-1 w-full relative z-10">
        {activeTab === 'search' && (
          <div className="w-full absolute inset-0 overflow-y-auto pb-20">
            <SearchLead />
            <ResultDisplay />
          </div>
        )}
        
        {activeTab === 'pdf' && (
          <div className="w-full absolute inset-0 overflow-y-auto pb-20">
            <PdfTranslator />
          </div>
        )}
        
        {activeTab === 'map' && (
          <div className="w-full absolute inset-0 overflow-hidden">
            <CustomerMap />
          </div>
        )}

        {/* 新增：客户档案库页面 */}
        {activeTab === 'database' && (
          <div className="w-full absolute inset-0 overflow-y-auto pb-20">
            <CustomerDatabase />
          </div>
        )}
      </main>
    </div>
  );
}
EOF

cat << 'EOF' > "$FRONTEND_DIR/src/components/Header.jsx"
import React from 'react';
import { Settings, Search, FileText, Map as MapIcon, Database as DbIcon } from 'lucide-react';
import { useStore } from '../store';

export default function Header() {
  const { setSettingsOpen, activeTab, setActiveTab } = useStore();
  
  return (
    <header className="glass-panel text-blue-900 shadow-sm sticky top-0 z-40 border-b border-white/50">
      <div className="max-w-7xl mx-auto px-4 h-auto min-h-[64px] flex flex-wrap justify-between items-center py-2 gap-y-3">
        <h1 className="text-xl font-black tracking-tight flex items-center gap-2">
          <div className="w-8 h-8 bg-blue-600 text-white rounded-lg flex items-center justify-center font-bold shadow-md">XT</div>
          晶振智能雷达
        </h1>
        
        <div className="flex flex-wrap bg-white/40 p-1.5 rounded-xl gap-1 border border-white/60 shadow-inner">
          <button onClick={() => setActiveTab('search')} className={`px-4 py-1.5 rounded-lg text-sm font-bold flex items-center gap-2 transition-all ${activeTab === 'search' ? 'bg-blue-600 text-white shadow-md' : 'text-blue-800 hover:bg-white/50'}`}>
            <Search size={16}/> 侦测控制台
          </button>
          <button onClick={() => setActiveTab('database')} className={`px-4 py-1.5 rounded-lg text-sm font-bold flex items-center gap-2 transition-all ${activeTab === 'database' ? 'bg-blue-600 text-white shadow-md' : 'text-blue-800 hover:bg-white/50'}`}>
            <DbIcon size={16}/> 客户档案库
          </button>
          <button onClick={() => setActiveTab('map')} className={`px-4 py-1.5 rounded-lg text-sm font-bold flex items-center gap-2 transition-all ${activeTab === 'map' ? 'bg-blue-600 text-white shadow-md' : 'text-blue-800 hover:bg-white/50'}`}>
            <MapIcon size={16}/> 全局作战地图
          </button>
          <button onClick={() => setActiveTab('pdf')} className={`px-4 py-1.5 rounded-lg text-sm font-bold flex items-center gap-2 transition-all ${activeTab === 'pdf' ? 'bg-blue-600 text-white shadow-md' : 'text-blue-800 hover:bg-white/50'}`}>
            <FileText size={16}/> 规格书翻译
          </button>
        </div>

        <button onClick={() => setSettingsOpen(true)} className="flex items-center space-x-1 bg-white hover:bg-blue-50 px-3 py-1.5 rounded-lg border border-blue-200 transition-colors text-sm font-bold shadow-sm text-blue-700">
          <Settings size={16} /><span>配置</span>
        </button>
      </div>
    </header>
  );
}
EOF

cat << 'EOF' > "$FRONTEND_DIR/src/components/CustomerDatabase.jsx"
import React, { useEffect, useState } from 'react';
import axios from 'axios';
import { useStore } from '../store';
import { FolderOpen, MapPin, Building2, Trash2, ChevronRight } from 'lucide-react';

export default function CustomerDatabase() {
  const [customers, setCustomers] = useState([]);
  const { setActiveTab, setResult, triggerRefresh, refreshTrigger } = useStore();

  useEffect(() => {
    axios.get('/api/customers').then(res => setCustomers(res.data.data || []));
  }, [refreshTrigger]);

  const handleView = (cust) => {
    setResult(cust); // 将保存的完整报告塞回状态机
    setActiveTab('search'); // 跳转回分析页面，报告原样重现！
  };

  const handleDelete = async (e, company) => {
    e.stopPropagation();
    if (window.confirm(`确定销毁【${company}】的绝密档案吗？`)) {
      try {
        await axios.delete('/api/customers', { data: { company } });
        triggerRefresh();
      } catch (err) {}
    }
  };

  return (
    <div className="max-w-6xl mx-auto p-4 mt-6 animate-fade-in font-sans">
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
               <h3 className="font-black text-lg text-blue-900 group-hover:text-blue-600 pr-6 leading-tight">{cust.company}</h3>
               <button onClick={(e) => handleDelete(e, cust.company)} className="absolute top-4 right-4 text-gray-400 hover:text-red-500 transition-colors p-1 bg-white/50 rounded-md backdrop-blur-sm"><Trash2 size={16}/></button>
             </div>
             
             <div className="inline-block px-2.5 py-1 rounded shadow-sm text-white text-xs font-bold mb-4" style={{
                 backgroundColor: cust.category==='A类客户'?'#ef4444':cust.category==='B类客户'?'#f97316':cust.category==='C类客户'?'#eab308':cust.category==='意向客户'?'#3b82f6':'#22c55e'
             }}>
                 {cust.category} | {cust.type}
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

# 批量将已有组件的底色替换为 glass-panel，实现整体 UI 毛玻璃化
sed -i 's/className="bg-white/className="glass-panel/g' "$FRONTEND_DIR/src/components/SearchLead.jsx"
sed -i 's/className="bg-white/className="glass-panel/g' "$FRONTEND_DIR/src/components/ResultDisplay.jsx"

echo ">>> 4. 编译全栈生态并重启底层引擎..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ 全局毛玻璃波纹 UI、客户全量档案库、产品真伪标识 上线完毕！"
echo "========================================================="
