#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"
FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在重构后端检索引擎：注入【强行推演】与【空数组省略】指令..."

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

        const [
            official_products, official_tech, b2b_trade,
            vertical_portal, recruitment, contacts_info
        ] = await Promise.all([
            fetchMatrixQuery(`${siteQueryStr} "产品中心" OR "型号"` , 10),
            fetchMatrixQuery(`${siteQueryStr} "解决方案" OR "技术架构"`),
            fetchMatrixQuery(`${exact} (site:1688.com OR site:hc360.com) "主营产品"`),
            fetchMatrixQuery(`${exact} (site:elecfans.com OR site:hqew.com)`),
            fetchMatrixQuery(`${exact} 招聘 硬件工程师 OR 研发`),
            fetchMatrixQuery(`${exact} "联系人" OR "采购" OR "邮箱" 招标`)
        ]);

        const prompt = `你是顶级商业侦探。剖析对象：【${companyName}】。

底牌：
【地址】: ${address || ''}
【网址】: ${website || ''}
【工商范围】: ${userProfile || ''}

爬虫：
[产品]: ${official_products}
[技术]: ${official_tech}
[B2B]: ${b2b_trade}
[招聘]: ${recruitment}
[联系人]: ${contacts_info}

【核心指令 - 拒绝未知废话】：
1. **决策人处理**：如果爬虫数据中确实找不到任何有价值的人名或电话，**请直接将 keyContacts 输出为空数组 []，绝对禁止输出包含 "未知"、"未查明" 的假数据！**
2. **产品与芯片必须推演**：如果爬虫数据里没有具体的芯片架构，**你绝对禁止写 "未知"**。你必须基于设备的用途，动用你的专家知识库，强行推演出一套标准的 BOM 架构组合（标明推演）。

输出严格JSON:
{
  "company": "${companyName}",
  "website": "${website || '未查明'}",
  "address": "整理输出详细地址",
  "coordinates": [纬度, 经度],
  "type": "精准业务类型",
  "profile": "硬核企业背景分析（不少于350字）。",
  "keyContacts": [
    {"name": "真实姓名(找不到此人则必须保持整个数组为空[])", "title": "职务", "contact": "电话/邮箱", "context": "线索来源"}
  ],
  "commonChipPlatforms": [
    {"brand": "品牌", "model": "型号", "application": "应用场景"}
  ],
  "products": [
    {
      "name": "具体设备名称",
      "chipPlatform": "详细的芯片架构组合(绝不允许填未知！必须详细推演！如：主控采用xxx，通信采用xxx)",
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

echo ">>> 2. 正在重构前端 UI：注入【宁缺毋滥隐藏机制】过滤未知数据..."

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

  // 【核心过滤机制】：如果全是“未知”的占位符，直接把这个数组过滤为空，不予显示
  const validContacts = data.keyContacts?.filter(c => 
    c.name && c.name.indexOf('未知') === -1 && c.name.indexOf('未查明') === -1 && c.name !== '无'
  );

  return (
    <div className="max-w-6xl mx-auto p-4 space-y-8 animate-fade-in mt-4 font-sans">
      
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

      {/* 【宁缺毋滥】：只有真正找到了非未知的人名时，才渲染该卡片 */}
      {validContacts && validContacts.length > 0 && (
        <div className="bg-white p-6 rounded-2xl shadow-md border-t-4 border-amber-500">
          <h2 className="text-xl font-black flex items-center gap-2 mb-5 text-amber-900 border-b pb-3">
            <Users className="text-amber-600" size={24}/> 关键决策人线索侦测
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
             {validContacts.map((contact, idx) => (
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
                      <tr><th className="p-4 font-bold uppercase w-1/4">频率</th><th className="p-4 font-bold uppercase w-1/4">参数</th><th className="p-4 font-bold uppercase w-1/2">核心作用解析</th></tr>
                    </thead>
                    <tbody className="divide-y divide-gray-100 bg-white">
                      {product.crystals?.map((c, cIdx) => (
                        <tr key={cIdx} className="hover:bg-orange-50/60 transition-colors">
                          <td className="p-4 font-black text-orange-600 text-lg whitespace-nowrap">{c.freq}</td>
                          <td className="p-4"><div className="font-bold text-gray-800">{c.package}</div><div className="text-gray-500 text-xs mt-1">CL:{c.loadCap} | Tol:{c.tolerance}</div></td>
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

echo ">>> 3. 全面编译生效并重启后台引擎..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ 编译警告无视完毕！隐藏未知信息与BOM强制推演上线！"
echo "========================================================="
