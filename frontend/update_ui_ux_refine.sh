#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"
FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在重写后端控制器：注入【小白化人话指令】与【全局晶振清单】..."

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
        const res = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }, signal: controller.signal });
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
            official_products, official_tech, b2b_trade,
            vertical_portal, recruitment, bidding
        ] = await Promise.all([
            fetchMatrixQuery(`${siteQueryStr} "产品中心" OR "所有产品" OR "型号"` , 10),
            fetchMatrixQuery(`${siteQueryStr} "解决方案" OR "技术架构"`),
            fetchMatrixQuery(`${exact} (site:1688.com OR site:hc360.com) "主营产品"`),
            fetchMatrixQuery(`${exact} (site:elecfans.com OR site:hqew.com) "产品型号" OR "参数"`),
            fetchMatrixQuery(`${exact} 招聘 硬件工程师`),
            fetchMatrixQuery(`${exact} 招标 采购项目清单`)
        ]);

        const prompt = `你是一个顶级商业侦探与电子架构师。剖析对象：【${companyName}】。

底牌数据：
【注册地址】: ${address || '无'}
【官方网站】: ${website || '无'}
【工商经营范围】: ${userProfile || '无'}

爬虫数据：
[官网产品]: ${official_products}
[官网技术]: ${official_tech}
[B2B外围]: ${b2b_trade}
[垂直门户]: ${vertical_portal}
[直聘网]: ${recruitment}
[招投标]: ${bidding}

【极致细化与小白化铁律】：
1. **全局晶振选型看板**：你需要把这家公司所有可能用到的晶振规格，统一提取出来，放在 \`globalCrystals\` 数组里，作为右侧看板的数据！
2. **BOM必须分行**：在 \`chipPlatform\` 中，**必须**使用换行符 \`\\n\` 进行排版，如 "1. 主控: xxx\\n2. 通信: xxx"，严禁挤成一坨！
3. **小白级核心作用解释**：在 \`function\` 字段，你必须用通俗易懂的“大白话”向不懂技术的销售解释！格式必须包含：“**为什么需要**：xxx。**如果没有它**：机器会xxx故障。”
4. 提取 3~6 个具体硬件。若未查到实机则结合经营范围强行推演（加注推演）。

输出严格JSON:
{
  "company": "${companyName}",
  "website": "${website || '未查明'}",
  "address": "整理输出详细地址",
  "coordinates": [纬度, 经度],
  "type": "精准业务类型",
  "profile": "结合底牌与爬虫数据，撰写至少350字的硬核企业背景分析。",
  "commonChipPlatforms": [
    {"brand": "品牌", "model": "型号", "application": "应用场景"}
  ],
  "globalCrystals": [
    {"freq": "频率(如 32.768kHz)", "package": "常用封装", "reason": "为什么这家公司大量需要这款晶振？(通俗一句话)"}
  ],
  "products": [
    {
      "name": "具体设备名称(如有推演需标明)",
      "chipPlatform": "芯片架构组合(必须使用 \\n 换行符列出1. 2. 3.清单)",
      "crystals": [
        {"freq": "频率", "package": "封装", "loadCap": "电容", "tolerance": "频偏", "function": "通俗易懂的解释：为什么需要它？如果没有它会怎样？(字数不低于40字)"}
      ]
    }
  ],
  "strategy": "基于原厂晶振销售的极度硬核切入策略"
}`;

        let safeBaseUrl = config.baseUrl;
        if (config.provider && PROVIDERS[config.provider]) safeBaseUrl = PROVIDERS[config.provider];
        safeBaseUrl = (safeBaseUrl || '').replace(/[\[\]\(\)]/g, '').split(' ')[0].trim().replace(/\/+$/, '');
        if (!safeBaseUrl.startsWith('http')) safeBaseUrl = getUrl('aHR0cHM6Ly9hcGkuZGVlcHNlZWsuY29t');
        
        const targetUrl = `${safeBaseUrl}/chat/completions`;
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 90000); 

        const response = await fetch(targetUrl, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${(config.apiKey || '').trim()}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model: (config.model || '').trim() || 'deepseek-chat',
                messages: [{ role: "user", content: prompt }],
                temperature: 0.2, 
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
                const query = `${p.name.replace(/\(.*?\)/g, '')} 产品实物图`;
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

echo ">>> 2. 正在重构前端：引入【右侧晶振看板】与【BOM物理换行】..."

cat << 'EOF' > "$FRONTEND_DIR/src/components/ResultDisplay.jsx"
import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { useStore } from '../store';
import { Building2, Cpu, Zap, Lightbulb, Link as LinkIcon, Info, Box, Layers, Copy, Check, MapPin, Star, ShoppingCart, Globe2, Activity } from 'lucide-react';

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

  return (
    <div className="max-w-7xl mx-auto p-4 mt-4 font-sans animate-fade-in">
      
      <div className="flex flex-col lg:flex-row gap-6 items-start">
        
        {/* 左侧主体内容区 (占据大约 3/4 宽度) */}
        <div className="w-full lg:w-3/4 space-y-8">
          
          {/* 企业画像 */}
          <div className="bg-white p-6 rounded-2xl shadow-md border-t-4 border-blue-600 relative">
            <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-4 border-b pb-4">
                <div className="group/copy flex items-center gap-2 cursor-pointer hover:bg-blue-50 p-2 -ml-2 rounded-lg transition-colors" onClick={() => handleCopy(data.company, 'companyName')} title="点击复制">
                  <Building2 className="text-blue-600" size={28}/> 
                  <h2 className="text-2xl font-black text-blue-900">{data.company}</h2>
                  {copiedId === 'companyName' ? <Check size={18} className="text-green-500 animate-pulse"/> : <Copy size={16} className="text-blue-300 opacity-0 group-hover/copy:opacity-100"/>}
                </div>
                <div className="flex items-center gap-2 bg-blue-50 px-4 py-2 rounded-xl border border-blue-200 shadow-sm">
                   <Star size={20} className={category !== '未收藏' ? 'text-yellow-500 fill-yellow-500' : 'text-gray-400'} />
                   <span className="text-sm font-bold text-blue-800">归档：</span>
                   <select value={category} onChange={handleCategoryChange} className="bg-white border border-blue-300 text-blue-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block p-1.5 font-bold outline-none cursor-pointer">
                       <option value="未收藏">未收藏</option>
                       <option value="A类客户">🔥 A类</option>
                       <option value="B类客户">⭐ B类</option>
                       <option value="C类客户">📌 C类</option>
                       <option value="意向客户">🤝 意向</option>
                       <option value="合作客户">✅ 合作</option>
                   </select>
                </div>
            </div>

            <div className="space-y-4 text-sm text-gray-800">
              <p className="flex items-center gap-3"><span className="font-semibold w-20 text-gray-500">注册地址:</span> <span className="text-base text-gray-800 font-bold flex items-center gap-1"><MapPin size={18} className="text-red-500"/>{data.address || '未查明'}</span></p>
              <p className="flex items-center gap-3"><span className="font-semibold w-20 text-gray-500">官方网站:</span> <a href={siteUrl} target="_blank" rel="noopener noreferrer" className="flex items-center gap-1 text-blue-600 hover:underline font-bold text-base"><LinkIcon size={18} /> {data.website}</a></p>
              <p className="flex items-center gap-3"><span className="font-semibold w-20 text-gray-500">业务类型:</span> <span className="bg-blue-100 text-blue-800 px-3 py-1 rounded-md text-sm font-bold shadow-sm">{data.type}</span></p>
              
              <div className="mt-6 p-5 bg-blue-50 rounded-xl border border-blue-100 relative">
                 <div className="flex gap-3 items-start">
                     <Info className="text-blue-500 flex-shrink-0 mt-1" size={22} />
                     <p className="leading-loose text-gray-700 text-base text-justify">{data.profile}</p>
                 </div>
              </div>
            </div>
          </div>

          {/* 实物产品与BOM拆解 */}
          <div className="space-y-6">
            <div className="flex items-center justify-between px-2">
                <h2 className="text-2xl font-black flex items-center gap-2 text-indigo-900"><Cpu className="text-indigo-600" size={28}/> 终端实物拆解与晶振 BOM</h2>
                <span className="text-sm font-bold text-indigo-500 bg-indigo-50 px-3 py-1 rounded-full border border-indigo-100">共发现 {data.products?.length || 0} 款主打设备</span>
            </div>
            
            {data.products && data.products.map((product, idx) => (
              <div key={idx} className="bg-white p-6 rounded-2xl shadow-sm border border-gray-100">
                <div className="flex flex-col lg:flex-row gap-6">
                  <div className="lg:w-1/3 flex flex-col items-center text-center space-y-4">
                    <div className="w-full h-48 rounded-xl border border-gray-100 bg-gray-50 flex items-center justify-center overflow-hidden">
                      {product.imageUrl ? (
                        <img src={`/api/image-proxy?url=${encodeURIComponent(product.imageUrl)}`} alt={product.name} className="max-w-full max-h-full object-contain p-2" onError={(e) => { e.target.style.display='none'; e.target.nextSibling.style.display='flex'; }}/>
                      ) : null}
                      <div className="absolute inset-0 flex-col items-center justify-center text-gray-400 bg-gray-50" style={{ display: product.imageUrl ? 'none' : 'flex' }}>
                        <Box size={32} className="mb-2 opacity-30"/>
                        <span className="text-xs font-bold px-4">{product.name}</span>
                      </div>
                    </div>
                    <h3 className="text-lg font-black text-gray-900 leading-tight">{product.name}</h3>
                    
                    {/* 【核心修复：BOM换行显示，解决挤在一起的问题】 */}
                    <div className="w-full bg-indigo-50 p-4 rounded-xl border border-indigo-100 shadow-sm text-left">
                      <p className="text-xs text-indigo-600 font-bold mb-2 uppercase border-b border-indigo-200 pb-1">全景芯片架构拆解</p>
                      <p className="text-sm font-extrabold text-indigo-900 leading-loose whitespace-pre-wrap">{product.chipPlatform}</p>
                    </div>
                  </div>

                  <div className="lg:w-2/3 flex flex-col">
                    <div className="flex items-center gap-2 mb-4 border-b border-gray-100 pb-2">
                      <Zap className="text-orange-500" size={20} />
                      <h4 className="font-black text-gray-900 text-lg">晶振白话文解析</h4>
                    </div>
                    <div className="overflow-hidden rounded-xl border border-gray-200 shadow-sm">
                      <table className="w-full text-left text-sm">
                        <thead className="bg-gray-100 text-gray-700 border-b border-gray-200">
                          <tr><th className="p-3 font-bold uppercase w-1/4">频率</th><th className="p-3 font-bold uppercase w-1/4">参数</th><th className="p-3 font-bold uppercase w-1/2">小白秒懂：核心作用</th></tr>
                        </thead>
                        <tbody className="divide-y divide-gray-100 bg-white">
                          {product.crystals?.map((c, cIdx) => (
                            <tr key={cIdx} className="hover:bg-orange-50 transition-colors">
                              <td className="p-3 font-black text-orange-600 text-lg">{c.freq}</td>
                              <td className="p-3"><div className="font-bold text-gray-800">{c.package}</div><div className="text-gray-500 text-[10px] mt-1">CL:{c.loadCap} | {c.tolerance}</div></td>
                              {/* 【核心升级：用dangerouslySetInnerHTML配合正则，高亮加粗文字，让小白更容易读懂】 */}
                              <td className="p-3 text-gray-700 leading-relaxed text-justify text-sm bg-orange-50/30 border-l border-orange-100" dangerouslySetInnerHTML={{__html: c.function.replace(/(为什么需要.*?：|如果没有它.*?：)/g, '<strong class="text-orange-700">$1</strong>')}}></td>
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
            <h2 className="text-xl font-black flex items-center gap-2 mb-4 text-green-900 border-b pb-3"><Lightbulb className="text-green-600" size={24}/> AI FAE 销售战术</h2>
            <p className="text-gray-800 leading-loose font-medium text-base text-justify bg-green-50 p-4 rounded-xl border border-green-100">{data.strategy}</p>
          </div>
        </div>

        {/* 右侧悬浮侧边栏 (占据大约 1/4 宽度) */}
        <div className="w-full lg:w-1/4 space-y-6 lg:sticky lg:top-20">
          
          {/* 全局晶振综合展示区 */}
          <div className="bg-gradient-to-br from-orange-50 to-amber-50 p-5 rounded-2xl shadow-lg border border-orange-200">
            <h2 className="text-lg font-black flex items-center gap-2 text-orange-900 mb-4 border-b border-orange-200 pb-2">
              <Activity className="text-orange-600" size={24}/> 全局晶振需求清单
            </h2>
            <div className="space-y-4">
              {data.globalCrystals?.map((gc, idx) => (
                <div key={idx} className="bg-white p-3 rounded-xl border border-orange-100 shadow-sm hover:shadow-md transition-shadow">
                  <div className="flex justify-between items-center mb-1">
                    <span className="text-lg font-black text-orange-600">{gc.freq}</span>
                    <span className="text-xs font-bold bg-gray-100 text-gray-600 px-2 py-0.5 rounded">{gc.package}</span>
                  </div>
                  <p className="text-xs text-gray-600 leading-relaxed text-justify">{gc.reason}</p>
                </div>
              ))}
              {(!data.globalCrystals || data.globalCrystals.length === 0) && (
                <p className="text-sm text-gray-500 text-center py-4">系统暂未提取到全局清单</p>
              )}
            </div>
          </div>

          {/* 国际/国内商城快速查价通道 */}
          <div className="bg-white p-5 rounded-2xl shadow-md border border-gray-200">
            <h2 className="text-base font-black flex items-center gap-2 text-gray-800 mb-4 border-b pb-2">
              <Layers className="text-blue-500" size={20}/> 核心主控与寻源直达
            </h2>
            <div className="space-y-4">
              {data.commonChipPlatforms?.map((chip, idx) => {
                const enc = encodeURIComponent(chip.model);
                return (
                  <div key={idx} className="bg-gray-50 p-3 rounded-lg border border-gray-100">
                    <div className="font-bold text-gray-900 text-sm mb-1">{chip.brand} <span className="text-blue-600">{chip.model}</span></div>
                    <div className="flex flex-wrap gap-1.5 mt-2">
                      <a href={`https://www.digikey.cn/zh/products/result?keywords=${enc}`} target="_blank" className="text-[10px] font-bold text-red-700 bg-red-100 hover:bg-red-200 px-1.5 py-0.5 rounded transition-colors">DigiKey</a>
                      <a href={`https://www.mouser.cn/c/?q=${enc}`} target="_blank" className="text-[10px] font-bold text-blue-700 bg-blue-100 hover:bg-blue-200 px-1.5 py-0.5 rounded transition-colors">Mouser</a>
                      <a href={`https://so.szlcsc.com/global.html?k=${enc}`} target="_blank" className="text-[10px] font-bold text-blue-600 bg-blue-50 hover:bg-blue-100 px-1.5 py-0.5 rounded border border-blue-200">立创</a>
                      <a href={`https://www.hqchip.com/search/${enc}.html`} target="_blank" className="text-[10px] font-bold text-orange-600 bg-orange-50 hover:bg-orange-100 px-1.5 py-0.5 rounded border border-orange-200">华秋</a>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

        </div>

      </div>
    </div>
  );
}
EOF

echo ">>> 3. 正在重构前端地图：加入【左侧 CRM 列表与平滑飞跃(FlyTo)联动】..."

cat << 'EOF' > "$FRONTEND_DIR/src/components/CustomerMap.jsx"
import React, { useEffect, useState } from 'react';
import axios from 'axios';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { useStore } from '../store';
import { Search, MapPin, Building2 } from 'lucide-react';

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

// 【核心黑科技：地图飞行控制器】监听 targetCenter 变化，自动飞跃到目标点
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
  const [targetCenter, setTargetCenter] = useState(null); // 控制地图视角的靶点
  const { refreshTrigger } = useStore();

  useEffect(() => {
    axios.get('/api/customers').then(res => setCustomers(res.data.data || []));
  }, [refreshTrigger]);

  const filteredCustomers = filterCat === '全部' ? customers : customers.filter(c => c.category === filterCat);

  return (
    <div className="max-w-screen-2xl mx-auto p-4 h-[calc(100vh-80px)] flex flex-col lg:flex-row gap-4 font-sans animate-fade-in">
      
      {/* 【核心重构：左侧 CRM 客户控制台】 */}
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
                   className="bg-white p-3 rounded-xl border border-gray-100 shadow-sm hover:shadow-md hover:border-blue-300 cursor-pointer transition-all active:scale-95 group"
                 >
                   <div className="font-bold text-sm text-gray-800 group-hover:text-blue-600 truncate">{cust.company}</div>
                   <div className="flex items-center gap-1 text-[10px] text-gray-500 mt-2 truncate">
                      <MapPin size={12} className="text-red-400 shrink-0"/> {cust.address}
                   </div>
                 </div>
               ))
            )}
         </div>
      </div>

      {/* 右侧大地图区域 */}
      <div className="flex-1 bg-white rounded-2xl shadow-lg border-4 border-white overflow-hidden relative z-0 h-[50vh] lg:h-full">
        <MapContainer center={[35.86166, 104.195397]} zoom={5} style={{ height: '100%', width: '100%', position: 'absolute', inset: 0 }}>
          <TileLayer attribution='&copy; OpenStreetMap' url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
          <MapController targetCenter={targetCenter} /> {/* 挂载飞行器 */}
          
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

echo ">>> 4. 正在编译生效前端重置..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ 双栏结构、通俗化翻译、左侧 CRM 地图联动飞行 完美实装！"
echo "========================================================="
