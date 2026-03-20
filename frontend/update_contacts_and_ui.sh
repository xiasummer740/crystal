#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"
FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在重构后端 CRM 数据库：注入安全的 Delete (删除) 路由接口..."

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
        if (!rawData || rawData.trim() === '') rawData = '[]';
        res.json({ success: true, data: JSON.parse(rawData) });
    } catch (e) {
        res.json({ success: true, data: [] });
    }
};

const saveCustomer = (req, res) => {
    try {
        if (!fs.existsSync(dbDir)) fs.mkdirSync(dbDir, { recursive: true });
        if (!fs.existsSync(dbPath)) fs.writeFileSync(dbPath, '[]');

        let rawData = fs.readFileSync(dbPath, 'utf8');
        let customers = JSON.parse(rawData || '[]');
        const customer = req.body;
        
        const index = customers.findIndex(c => c.company === customer.company);
        if (customer.category === '未收藏') {
            if (index > -1) customers.splice(index, 1);
        } else {
            if (index > -1) customers[index] = customer;
            else customers.push(customer);
        }
        
        fs.writeFileSync(dbPath, JSON.stringify(customers, null, 2));
        res.json({ success: true, message: '收藏状态更新成功' });
    } catch (e) {
        res.status(500).json({ success: false, message: '数据库写入失败' });
    }
};

// 【新增】：独立的安全删除接口
const deleteCustomer = (req, res) => {
    try {
        const { company } = req.body;
        if (!fs.existsSync(dbPath)) return res.json({ success: true });
        
        let customers = JSON.parse(fs.readFileSync(dbPath, 'utf8'));
        customers = customers.filter(c => c.company !== company);
        fs.writeFileSync(dbPath, JSON.stringify(customers, null, 2));
        
        res.json({ success: true, message: '删除成功' });
    } catch (e) {
        res.status(500).json({ success: false, message: '删除失败' });
    }
};

module.exports = { getCustomers, saveCustomer, deleteCustomer };
EOF

cat << 'EOF' > "$BACKEND_DIR/routes/api.js"
const express = require('express');
const multer = require('multer');
const fs = require('fs');
const router = express.Router();

const { searchLead, proxyImage } = require('../controllers/searchController');
const { getConfig, saveConfig, testConfig } = require('../controllers/configController');
const { translatePdf } = require('../controllers/pdfController');
const { getCustomers, saveCustomer, deleteCustomer } = require('../controllers/customerController');

const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        const dir = '/tmp/pdf_uploads/';
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        cb(null, dir);
    },
    filename: (req, file, cb) => cb(null, Date.now() + '.pdf')
});
const upload = multer({ storage, limits: { fileSize: 200 * 1024 * 1024 } });

router.post('/search', searchLead);
router.get('/config', getConfig);
router.post('/config', saveConfig);
router.get('/config/test', testConfig);
router.get('/image-proxy', proxyImage);
router.post('/translate-pdf', upload.single('file'), translatePdf);

// CRM 路由群
router.get('/customers', getCustomers);
router.post('/customers', saveCustomer);
router.delete('/customers', deleteCustomer); // 挂载删除路由

module.exports = router;
EOF

echo ">>> 2. 正在重写大模型检索引擎：注入【决策人联系方式嗅探抓取】..."

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

const fetchMatrixQuery = async (query, limit = 5) => {
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

        // 【新增联系人嗅探维度】
        const [
            official_products, official_tech, b2b_trade,
            vertical_portal, recruitment, contacts_info
        ] = await Promise.all([
            fetchMatrixQuery(`${siteQueryStr} "产品中心" OR "型号"` , 15),
            fetchMatrixQuery(`${siteQueryStr} "解决方案" OR "技术架构"`),
            fetchMatrixQuery(`${exact} (site:1688.com OR site:hc360.com) "主营产品"`),
            fetchMatrixQuery(`${exact} (site:elecfans.com OR site:hqew.com)`),
            fetchMatrixQuery(`${exact} 招聘 硬件工程师 OR 研发`),
            // 新增：专门抓取招聘负责人、采购、招投标联系人、官网联系方式
            fetchMatrixQuery(`${exact} "联系人" OR "采购" OR "研发经理" OR "联系电话" OR "邮箱" 招标`)
        ]);

        const prompt = `你是顶级商业侦探。剖析对象：【${companyName}】。

底牌：
【地址】: ${address || '无'}
【网址】: ${website || '无'}
【工商范围】: ${userProfile || '无'}

爬虫：
[产品]: ${official_products}
[技术]: ${official_tech}
[B2B]: ${b2b_trade}
[招聘]: ${recruitment}
[关键联系人/招标]: ${contacts_info}

【铁律要求】：
1. **决策人提取 (重中之重)**：仔细检索[关键联系人/招标]和[招聘]数据，提取出该公司的采购、硬件研发负责人、法定代表人或招投标联系人。绝不允许捏造，找不到的字段就写“未知”。
2. **通俗化脱敏**：在 \`function\`（核心作用）字段中，直接清晰客观地阐述其作用，**严禁使用“小白解说”等词汇**。
3. **无限量产品**：提取所有能找到的硬件产品。BOM必须详细。

输出严格JSON:
{
  "company": "${companyName}",
  "website": "${website || '未查明'}",
  "address": "整理输出详细地址",
  "coordinates": [纬度, 经度],
  "type": "精准业务类型",
  "profile": "硬核企业背景分析（不少于350字）。",
  "keyContacts": [
    {"name": "姓名/称呼", "title": "职务/角色(如：采购经理/硬件总监)", "contact": "电话/邮箱/微信", "context": "线索来源或背景(如：某招投标项目联系人/BOSS直聘发布者)"}
  ],
  "commonChipPlatforms": [
    {"brand": "品牌", "model": "型号", "application": "应用场景"}
  ],
  "products": [
    {
      "name": "具体设备名称(有多少列多少)",
      "chipPlatform": "详细的芯片架构组合(如：主控采用xxx，通信采用xxx)",
      "crystals": [
        {"freq": "频率", "package": "封装", "loadCap": "电容", "tolerance": "频偏", "function": "核心作用解析(客观阐述：为什么需要它，如果没有会怎样)"}
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
                const query = `"${resultData.company}" "${p.name.replace(/\(.*?\)/g, '').trim()}" 产品`;
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

echo ">>> 3. 正在重构前端地图与嗅探UI：加装删除防误触与决策人名片..."

cat << 'EOF' > "$FRONTEND_DIR/src/components/CustomerMap.jsx"
import React, { useEffect, useState } from 'react';
import axios from 'axios';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { useStore } from '../store';
import { Search, MapPin, Building2, Trash2 } from 'lucide-react';

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
  const { refreshTrigger, triggerRefresh } = useStore();

  useEffect(() => {
    axios.get('/api/customers').then(res => setCustomers(res.data.data || []));
  }, [refreshTrigger]);

  // 【新增】：安全删除客户功能
  const handleDelete = async (e, company) => {
    e.stopPropagation(); // 绝对防止触发底层的地图飞行点击事件
    if (window.confirm(`确定要将【${company}】移出客户编队吗？`)) {
      try {
        await axios.delete('/api/customers', { data: { company } });
        triggerRefresh(); // 触发全局刷新
      } catch (err) {
        console.error('删除失败');
      }
    }
  };

  const filteredCustomers = filterCat === '全部' ? customers : customers.filter(c => c.category === filterCat);

  return (
    <div className="max-w-screen-2xl mx-auto p-4 h-[calc(100vh-80px)] flex flex-col lg:flex-row gap-4 font-sans animate-fade-in">
      
      <div className="w-full lg:w-80 bg-white rounded-2xl shadow-lg flex flex-col overflow-hidden border border-gray-200 shrink-0 h-[40vh] lg:h-full">
         <div className="p-4 bg-gray-50 border-b border-gray-200">
            <h2 className="text-xl font-black text-gray-800 flex items-center gap-2"><Building2 className="text-blue-600" size={20}/> 客户编队</h2>
            <select value={filterCat} onChange={(e) => setFilterCat(e.target.value)} className="mt-3 w-full p-2 text-sm bg-white border border-gray-300 rounded-lg outline-none font-bold text-gray-700 shadow-sm cursor-pointer">
               <option value="全部">🌍 全部领地 ({customers.length})</option>
               <option value="A类客户">🔥 A类客户</option>
               <option value="B类客户">⭐ B类客户</option>
               <option value="C类客户">📌 C类客户</option>
               <option value="意向客户">🤝 意向客户</option>
               <option value="合作客户">✅ 合作客户</option>
            </select>
         </div>
         <div className="flex-1 overflow-y-auto p-2 space-y-2 bg-gray-50">
            {filteredCustomers.length === 0 ? (
               <p className="text-center text-gray-400 text-sm mt-10">该编队暂无客户</p>
            ) : (
               filteredCustomers.map((cust, idx) => (
                 <div 
                   key={idx} 
                   onClick={() => setTargetCenter(cust.coordinates)}
                   className="bg-white p-3 rounded-xl border border-gray-100 shadow-sm hover:shadow-md hover:border-blue-300 cursor-pointer transition-all active:scale-95 group relative"
                 >
                   <div className="font-bold text-sm text-gray-800 group-hover:text-blue-600 truncate pr-6">{cust.company}</div>
                   <div className="flex items-center gap-1 text-[10px] text-gray-500 mt-2 truncate">
                      <MapPin size={12} className="text-red-400 shrink-0"/> {cust.address}
                   </div>
                   {/* 【新增】：悬浮显示的删除按钮 */}
                   <button 
                     onClick={(e) => handleDelete(e, cust.company)}
                     className="absolute top-3 right-2 text-gray-300 hover:text-red-500 opacity-0 group-hover:opacity-100 transition-opacity p-1"
                     title="删除此客户"
                   >
                     <Trash2 size={16} />
                   </button>
                 </div>
               ))
            )}
         </div>
      </div>

      <div className="flex-1 bg-white rounded-2xl shadow-lg border-4 border-white overflow-hidden relative z-0 h-[50vh] lg:h-full">
        <MapContainer center={[35.86166, 104.195397]} zoom={5} style={{ height: '100%', width: '100%', position: 'absolute', inset: 0 }}>
          <TileLayer attribution='&copy; OpenStreetMap' url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
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
EOF

echo ">>> 4. 正在为前端注入【关键决策人卡片】与【UI去油脱水处理】..."

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

  if (error) return <div className="max-w-6xl mx-auto p-4 text-red-500 text-center font-bold bg-red-50 rounded mt-4">{error}</div>;
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
      await axios.post('/api/customers', {
         company: data.company,
         address: data.address,
         coordinates: data.coordinates,
         type: data.type,
         category: newCat
      });
      triggerRefresh();
    } catch (err) {}
  };

  const flatBomList = [];
  data.products?.forEach(p => {
    p.crystals?.forEach(c => {
      flatBomList.push({
        productName: p.name,
        chipPlatform: p.chipPlatform,
        freq: c.freq,
        package: c.package,
        params: `CL:${c.loadCap} | Tol:${c.tolerance}`,
        function: c.function
      });
    });
  });

  const exportToExcel = () => {
    const worksheetData = [
      ['终端设备名称', '全景芯片架构 (BOM推演)', '标称频率', '封装尺寸', '规格参数', '核心作用解析'],
      ...flatBomList.map(item => [item.productName, item.chipPlatform, item.freq, item.package, item.params, item.function])
    ];
    const ws = XLSX.utils.aoa_to_sheet(worksheetData);
    ws['!cols'] = [ { wch: 25 }, { wch: 40 }, { wch: 15 }, { wch: 15 }, { wch: 20 }, { wch: 50 } ];
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "晶振BOM总表");
    XLSX.writeFile(wb, `${data.company}_晶振BOM需求表.xlsx`);
  };

  return (
    <div className="max-w-6xl mx-auto p-4 space-y-8 animate-fade-in mt-4 font-sans">
      
      {/* 1. 企业全景 */}
      <div className="bg-white p-6 rounded-2xl shadow-md border-t-4 border-blue-600 relative group">
        <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-4 border-b pb-4">
            <div className="group/copy flex items-center gap-2 cursor-pointer hover:bg-blue-50 p-2 -ml-2 rounded-lg transition-colors" onClick={() => handleCopy(data.company, 'companyName')}>
              <Building2 className="text-blue-600" size={28}/> 
              <h2 className="text-2xl font-black text-blue-900">{data.company}</h2>
              {copiedId === 'companyName' ? <Check size={18} className="text-green-500 animate-pulse"/> : <Copy size={16} className="text-blue-300 opacity-0 group-hover/copy:opacity-100 transition-opacity"/>}
            </div>

            <div className="flex items-center gap-2 bg-blue-50 px-4 py-2 rounded-xl border border-blue-200 shadow-sm">
               <Star size={20} className={category !== '未收藏' ? 'text-yellow-500 fill-yellow-500' : 'text-gray-400'} />
               <span className="text-sm font-bold text-blue-800">客户库归档：</span>
               <select value={category} onChange={handleCategoryChange} className="bg-white border border-blue-300 text-blue-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block p-1.5 font-bold outline-none cursor-pointer">
                   <option value="未收藏">未收藏</option>
                   <option value="A类客户">🔥 A类客户</option>
                   <option value="B类客户">⭐ B类客户</option>
                   <option value="C类客户">📌 C类客户</option>
                   <option value="意向客户">🤝 意向客户</option>
                   <option value="合作客户">✅ 合作客户</option>
               </select>
            </div>
        </div>

        <div className="space-y-4 text-sm text-gray-800">
          <p className="flex items-center gap-3"><span className="font-semibold w-20 text-gray-500">注册地址:</span> <span className="text-base text-gray-800 font-bold flex items-center gap-1"><MapPin size={18} className="text-red-500"/>{data.address || '未查明'}</span></p>
          <p className="flex items-center gap-3">
            <span className="font-semibold w-20 text-gray-500">官方网站:</span> 
            <a href={siteUrl} target="_blank" rel="noopener noreferrer" className="flex items-center gap-1 text-blue-600 hover:text-blue-800 hover:underline font-bold text-base">
              <LinkIcon size={18} /> {data.website}
            </a>
          </p>
          <p className="flex items-center gap-3"><span className="font-semibold w-20 text-gray-500">业务类型:</span> <span className="bg-blue-100 text-blue-800 px-3 py-1 rounded-md text-sm font-bold shadow-sm">{data.type}</span></p>
          
          <div className="mt-6 p-5 bg-blue-50 rounded-xl border border-blue-100 relative">
             <div className="flex gap-3 items-start">
                 <Info className="text-blue-500 flex-shrink-0 mt-1" size={22} />
                 <p className="leading-loose text-gray-700 text-base text-justify">{data.profile}</p>
             </div>
          </div>
        </div>
      </div>

      {/* 【新增】：关键决策人线索名片 */}
      {data.keyContacts && data.keyContacts.length > 0 && (
        <div className="bg-white p-6 rounded-2xl shadow-md border-t-4 border-amber-500">
          <h2 className="text-xl font-black flex items-center gap-2 mb-5 text-amber-900 border-b pb-3">
            <Users className="text-amber-600" size={24}/> 关键决策人线索侦测
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
             {data.keyContacts.map((contact, idx) => (
               <div key={idx} className="bg-amber-50/50 p-4 rounded-xl border border-amber-100 flex flex-col gap-2">
                  <div className="flex justify-between items-start">
                     <div>
                       <span className="font-black text-lg text-amber-900">{contact.name}</span>
                       <span className="ml-2 text-xs font-bold bg-amber-100 text-amber-800 px-2 py-0.5 rounded">{contact.title}</span>
                     </div>
                  </div>
                  <div className="text-sm font-mono text-gray-700 bg-white px-3 py-1.5 rounded border border-gray-200 mt-1">联络: {contact.contact}</div>
                  <div className="text-xs text-gray-500 mt-1">情报来源: {contact.context}</div>
               </div>
             ))}
          </div>
        </div>
      )}

      {/* 2. 寻源矩阵 */}
      {data.commonChipPlatforms && Array.isArray(data.commonChipPlatforms) && (
        <div className="bg-white p-6 rounded-2xl shadow-md border-t-4 border-purple-600">
          <h2 className="text-2xl font-black flex items-center gap-2 mb-6 text-purple-900 border-b pb-4">
            <Layers className="text-purple-600" size={28}/> 全球IC商城查价与规格书直连
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
            {data.commonChipPlatforms.map((chip, idx) => {
              const encodedModel = encodeURIComponent(chip.model);
              return (
                <div key={idx} className="bg-purple-50 rounded-xl p-5 border border-purple-100 hover:shadow-lg transition-all relative flex flex-col justify-between">
                  <div>
                    <span className="inline-block px-2 py-1 bg-purple-200 text-purple-800 text-xs font-bold rounded mb-2">{chip.brand}</span>
                    <h3 className="text-lg font-black text-gray-900 mb-1 tracking-tight">{chip.model}</h3>
                    <p className="text-sm text-gray-600 leading-relaxed mb-4">{chip.application}</p>
                  </div>
                  <div className="mt-2 pt-3 border-t border-purple-200/50 space-y-2">
                    <div className="flex items-center gap-2">
                       <Globe2 size={12} className="text-gray-400"/>
                       <a href={`https://www.digikey.cn/zh/products/result?keywords=${encodedModel}`} target="_blank" className="text-[11px] font-bold text-red-700 bg-red-50 hover:bg-red-100 px-2 py-1 rounded shadow-sm border border-red-200">DigiKey</a>
                       <a href={`https://www.mouser.cn/c/?q=${encodedModel}`} target="_blank" className="text-[11px] font-bold text-blue-700 bg-blue-50 hover:bg-blue-100 px-2 py-1 rounded shadow-sm border border-blue-200">Mouser</a>
                       <a href={`https://www.semiee.com/search?keyword=${encodedModel}`} target="_blank" className="text-[11px] font-bold text-teal-700 bg-teal-50 hover:bg-teal-100 px-2 py-1 rounded shadow-sm border border-teal-200 ml-auto flex items-center gap-1"><FileText size={10}/> 半岛小芯</a>
                    </div>
                    <div className="flex items-center gap-2 flex-wrap">
                      <ShoppingCart size={12} className="text-gray-400"/>
                      <a href={`https://so.szlcsc.com/global.html?k=${encodedModel}`} target="_blank" className="text-[11px] font-bold text-blue-600 bg-blue-50 hover:bg-blue-100 px-2 py-1 rounded shadow-sm border border-blue-200">立创</a>
                      <a href={`https://www.hqchip.com/search/${encodedModel}.html`} target="_blank" className="text-[11px] font-bold text-orange-600 bg-orange-50 hover:bg-orange-100 px-2 py-1 rounded shadow-sm border border-orange-200">华秋</a>
                      <a href={`https://s.hqew.com/${encodedModel}.html`} target="_blank" className="text-[11px] font-bold text-indigo-600 bg-indigo-50 hover:bg-indigo-100 px-2 py-1 rounded shadow-sm border border-indigo-200">华强</a>
                      <a href={`https://www.allchips.com/search?keyword=${encodedModel}`} target="_blank" className="text-[11px] font-bold text-red-500 bg-red-50 hover:bg-red-100 px-2 py-1 rounded shadow-sm border border-red-100">硬之城</a>
                      <a href={`https://cn.bing.com/search?q=${encodeURIComponent(chip.model + ' datasheet pdf')}`} target="_blank" className="text-[11px] font-bold text-gray-700 bg-yellow-100 hover:bg-yellow-200 px-2 py-1 rounded shadow-sm border border-yellow-300 ml-auto">PDF直搜</a>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* 3. 硬件产品展示 */}
      <div className="space-y-6">
        <div className="flex items-center justify-between px-2">
            <h2 className="text-2xl font-black flex items-center gap-2 text-indigo-900">
              <Cpu className="text-indigo-600" size={28}/> 终端实物拆解与全系晶振 BOM 映射
            </h2>
            <span className="text-sm font-bold text-indigo-500 bg-indigo-50 px-3 py-1 rounded-full border border-indigo-100 shadow-sm">挖掘出 {data.products?.length || 0} 款全线产品</span>
        </div>
        
        {data.products && data.products.map((product, idx) => (
          <div key={idx} className="bg-white p-6 rounded-2xl shadow-sm hover:shadow-xl transition-shadow border border-gray-100 overflow-hidden">
            <div className="flex flex-col lg:flex-row gap-8">
              <div className="lg:w-1/3 flex flex-col items-center text-center space-y-4">
                <div className="w-full h-64 rounded-xl border border-gray-100 shadow-inner relative overflow-hidden bg-gray-50 flex flex-col items-center justify-center group">
                  {product.imageUrl ? (
                    <img src={`/api/image-proxy?url=${encodeURIComponent(product.imageUrl)}`} alt={product.name} className="w-full h-full object-contain p-2 group-hover:scale-110 transition-transform duration-700" onError={(e) => { e.target.style.display='none'; e.target.nextSibling.style.display='flex'; }}/>
                  ) : null}
                  <div className="absolute inset-0 flex-col items-center justify-center text-gray-400 bg-gray-50" style={{ display: product.imageUrl ? 'none' : 'flex' }}>
                    <Box size={48} className="mb-2 opacity-30"/>
                    <span className="text-sm font-bold px-4 text-center">{product.name}</span>
                  </div>
                </div>
                <h3 className="text-xl font-black text-gray-900 leading-tight">{product.name}</h3>
                <div className="w-full bg-indigo-50 p-5 rounded-xl border border-indigo-100 shadow-sm text-left">
                  <p className="text-xs text-indigo-600 font-bold mb-2 uppercase border-b border-indigo-200 pb-2">全景芯片架构拆解 (BOM推演)</p>
                  <p className="text-sm font-extrabold text-indigo-900 leading-loose whitespace-pre-wrap">{product.chipPlatform || '分析中...'}</p>
                </div>
              </div>
              <div className="lg:w-2/3 flex flex-col justify-center">
                <div className="flex items-center gap-2 mb-5 border-b border-gray-100 pb-3">
                  <Zap className="text-orange-500" size={24} />
                  <h4 className="font-black text-gray-900 text-xl">晶振选型明细</h4>
                </div>
                <div className="overflow-hidden rounded-xl border border-gray-200 shadow-sm">
                  <table className="w-full text-left text-sm">
                    <thead className="bg-gray-100 text-gray-700 border-b border-gray-200">
                      {/* 【脱水去油】：修改为专业表头 */}
                      <tr><th className="p-4 font-bold uppercase w-1/4">频率</th><th className="p-4 font-bold uppercase w-1/4">参数</th><th className="p-4 font-bold uppercase w-1/2">核心作用解析</th></tr>
                    </thead>
                    <tbody className="divide-y divide-gray-100 bg-white">
                      {product.crystals?.map((c, cIdx) => (
                        <tr key={cIdx} className="hover:bg-orange-50/60 transition-colors">
                          <td className="p-4 font-black text-orange-600 text-lg whitespace-nowrap">{c.freq}</td>
                          <td className="p-4"><div className="font-bold text-gray-800">{c.package}</div><div className="text-gray-500 text-xs mt-1">CL:{c.loadCap} | Tol:{c.tolerance}</div></td>
                          {/* 【脱水去油】：直接显示核心作用，不再使用花哨的强行高亮匹配 */}
                          <td className="p-4 text-gray-700 leading-relaxed text-justify bg-orange-50/10">{c.function}</td>
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

      <div className="bg-white p-6 rounded-2xl shadow-lg border-t-4 border-green-500 relative">
        <h2 className="text-xl font-black flex items-center gap-2 mb-4 text-green-900 border-b pb-3"><Lightbulb className="text-green-600" size={24}/> AI FAE 极速选型建议</h2>
        <p className="text-gray-800 leading-loose font-medium text-base text-justify bg-green-50 p-4 rounded-xl border border-green-100">{data.strategy}</p>
      </div>

      {/* 5. 汇总表 */}
      {flatBomList.length > 0 && (
        <div className="bg-white p-6 rounded-2xl shadow-lg border-t-4 border-cyan-500 relative overflow-hidden">
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-6 border-b border-gray-100 pb-4 gap-4">
            <h2 className="text-2xl font-black flex items-center gap-2 text-cyan-900">
              <Table2 className="text-cyan-600" size={28}/> 晶振BOM全景汇总表
            </h2>
            <button onClick={exportToExcel} className="flex items-center gap-2 bg-gradient-to-r from-cyan-600 to-blue-600 text-white px-5 py-2.5 rounded-lg shadow-md hover:shadow-lg hover:-translate-y-0.5 transition-all font-bold text-sm">
              <Download size={18} /> 导出为 Excel
            </button>
          </div>
          <div className="overflow-x-auto rounded-xl border border-gray-200">
            <table className="w-full text-left text-sm whitespace-nowrap">
              <thead className="bg-gray-50 text-gray-700">
                <tr><th className="p-3 font-bold border-b">终端设备名称</th><th className="p-3 font-bold border-b">主控芯片/架构</th><th className="p-3 font-bold border-b text-orange-600">晶振频率</th><th className="p-3 font-bold border-b">封装/参数</th></tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {flatBomList.map((item, idx) => (
                  <tr key={idx} className="hover:bg-cyan-50/30 transition-colors">
                    <td className="p-3 font-bold text-gray-800">{item.productName}</td><td className="p-3 text-gray-600 truncate max-w-[200px]" title={item.chipPlatform}>{item.chipPlatform}</td><td className="p-3 font-black text-orange-600">{item.freq}</td><td className="p-3 text-gray-600">{item.package} <span className="text-gray-400 text-xs ml-1">({item.params})</span></td>
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

echo ">>> 5. 全面编译生效前端并重启后台引擎..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ 关键决策人线索抓取、地图删除保护、文案脱水已全部实装！"
echo "========================================================="
