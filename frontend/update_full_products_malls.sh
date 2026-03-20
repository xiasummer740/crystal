#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"
FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在重构后端：解除产品数量封印、升级官网图片定向狙击与深度BOM指令..."

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

// 【核心升级：定向图片狙击引擎】优先在用户提供的官网域名内搜图
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

    // 1. 如果有域名，先强制定向该域名搜图，保证是官网原图
    if (domain) {
        const domainUrl = await fetchImg(`site:${domain} ${query}`);
        if (domainUrl) return domainUrl;
    }
    // 2. 如果官网没搜到，再进行全网泛搜兜底
    return await fetchImg(query);
};

const fetchMatrixQuery = async (query, limit = 8) => { // 将抓取条数提升到8，容纳更多产品
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
            official_products,
            official_tech,
            b2b_trade,
            vertical_portal,
            recruitment,
            bidding
        ] = await Promise.all([
            fetchMatrixQuery(`${siteQueryStr} "产品中心" OR "所有产品" OR "型号"` , 10), // 专门给官网产品开高并发，抓10条
            fetchMatrixQuery(`${siteQueryStr} "解决方案" OR "技术架构"`),
            fetchMatrixQuery(`${exact} (site:1688.com OR site:hc360.com) "主营产品"`),
            fetchMatrixQuery(`${exact} (site:elecfans.com OR site:hqew.com) "产品型号" OR "参数"`),
            fetchMatrixQuery(`${exact} 招聘 硬件工程师`),
            fetchMatrixQuery(`${exact} 招标 采购项目清单`)
        ]);

        const prompt = `你是一个顶级商业侦探与电子架构师。
用户已经人工验证并提供了以下该公司的绝对真实底牌数据：
【公司全称】: ${companyName}
【注册地址】: ${address || '无'}
【官方网站】: ${website || '无'}
【人工填写的工商经营范围/简介】: ${userProfile || '无'}

同时，我通过定向爬虫，潜入了官网及全网为你带回了以下真实产品数据：
[官网产品线深潜]: ${official_products}
[官网技术方案]: ${official_tech}
[B2B外围数据]: ${b2b_trade}
[垂直门户技术交流]: ${vertical_portal}
[直聘网研发方向]: ${recruitment}

【终极解封任务要求】：
1. **无限量产品提取**：仔细阅读 [官网产品线深潜] 的数据，**把你能找到的所有具体硬件设备名称或型号全部提取出来！有多少写多少，上不封顶！绝对不要只写3个！**
2. **全景BOM芯片剖析**：针对每个产品，不要只写一个单调的主控。你必须写出它的【核心芯片架构组合】（例如：主控MCU STM32G4 + 以太网PHY + 独立DSP算法芯片）。如果数据里没写，请利用你的顶级专家知识，结合该设备的用途进行强行推演（标明推演）。
3. **坐标测绘**：推算 [纬度, 经度]。

输出严格JSON:
{
  "company": "${companyName}",
  "website": "${website || '未查明'}",
  "address": "整理并输出详细地址",
  "coordinates": [纬度浮点数, 经度浮点数],
  "type": "精准业务类型",
  "profile": "结合用户输入和抓取数据，撰写一篇高度专业的硬核企业背景与技术实力剖析。",
  "commonChipPlatforms": [
    {"brand": "品牌", "model": "型号", "application": "应用场景"}
  ],
  "products": [
    {
      "name": "具体设备名称或详细型号(有多少列多少！不要遗漏！)",
      "chipPlatform": "芯片架构组合(如：主控MCU + 通信芯片 + 电源管理。需极其硬核，若为推演加注标明)",
      "crystals": [
        {"freq": "频率", "package": "封装", "loadCap": "电容", "tolerance": "频偏", "function": "核心功能"}
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
                // 传入 targetDomain，触发官网图片定向狙击
                const query = `${p.name.replace(/\(.*?\)/g, '')} 产品`;
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

echo ">>> 2. 正在重构前端：引入全球IC商城矩阵与深度产品渲染..."

cat << 'EOF' > "$FRONTEND_DIR/src/components/ResultDisplay.jsx"
import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { useStore } from '../store';
import { Building2, Cpu, Zap, Lightbulb, Link as LinkIcon, Info, Box, Layers, Copy, Check, MapPin, Star, ShoppingCart, Globe2 } from 'lucide-react';

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
    } catch (err) {
      console.error("保存收藏失败");
    }
  };

  return (
    <div className="max-w-6xl mx-auto p-4 space-y-8 animate-fade-in mt-4 font-sans">
      
      <div className="bg-white p-6 rounded-2xl shadow-md border-t-4 border-blue-600 relative group">
        <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-4 border-b pb-4">
            <div 
              className="group/copy flex items-center gap-2 cursor-pointer hover:bg-blue-50 p-2 -ml-2 rounded-lg transition-colors"
              onClick={() => handleCopy(data.company, 'companyName')}
              title="点击一键复制公司全称"
            >
              <Building2 className="text-blue-600" size={28}/> 
              <h2 className="text-2xl font-black text-blue-900">{data.company}</h2>
              {copiedId === 'companyName' ? <Check size={18} className="text-green-500 animate-pulse"/> : <Copy size={16} className="text-blue-300 opacity-0 group-hover/copy:opacity-100 transition-opacity"/>}
            </div>

            <div className="flex items-center gap-2 bg-blue-50 px-4 py-2 rounded-xl border border-blue-200 shadow-sm">
               <Star size={20} className={category !== '未收藏' ? 'text-yellow-500 fill-yellow-500' : 'text-gray-400'} />
               <span className="text-sm font-bold text-blue-800">客户库归档：</span>
               <select value={category} onChange={handleCategoryChange} className="bg-white border border-blue-300 text-blue-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block p-1.5 font-bold outline-none cursor-pointer">
                   <option value="未收藏">未收藏</option>
                   <option value="A类客户">🔥 A类客户 (紧急重点)</option>
                   <option value="B类客户">⭐ B类客户 (持续跟进)</option>
                   <option value="C类客户">📌 C类客户 (普通储备)</option>
                   <option value="意向客户">🤝 意向客户</option>
                   <option value="合作客户">✅ 合作客户</option>
               </select>
            </div>
        </div>

        <div className="space-y-4 text-sm text-gray-800">
          <p className="flex items-center gap-3"><span className="font-semibold w-20 text-gray-500 tracking-wide">注册地址:</span> <span className="text-base text-gray-800 font-bold flex items-center gap-1"><MapPin size={18} className="text-red-500"/>{data.address || '未查明'}</span></p>
          <p className="flex items-center gap-3">
            <span className="font-semibold w-20 text-gray-500 tracking-wide">官方网站:</span> 
            <a href={siteUrl} target="_blank" rel="noopener noreferrer" className="flex items-center gap-1 text-blue-600 hover:text-blue-800 hover:underline font-bold text-base">
              <LinkIcon size={18} /> {data.website}
            </a>
          </p>
          <p className="flex items-center gap-3"><span className="font-semibold w-20 text-gray-500 tracking-wide">业务类型:</span> <span className="bg-blue-100 text-blue-800 px-3 py-1 rounded-md text-sm font-bold shadow-sm">{data.type}</span></p>
          
          <div className="mt-6 p-5 bg-blue-50 rounded-xl border border-blue-100 relative hover:shadow-inner transition-all">
             <button onClick={() => handleCopy(data.profile, 'profile')} className="absolute top-4 right-4 text-blue-400 hover:text-blue-700 p-1.5 bg-white rounded-md shadow-sm border border-blue-100 transition-colors">
               {copiedId === 'profile' ? <Check size={16} className="text-green-600"/> : <Copy size={16}/>}
             </button>
             <div className="flex gap-3 items-start">
                 <Info className="text-blue-500 flex-shrink-0 mt-1" size={22} />
                 <p className="leading-loose text-gray-700 text-base tracking-wide pr-8 text-justify">{data.profile}</p>
             </div>
          </div>
        </div>
      </div>

      {/* 【核心升级：全球化 IC 寻源矩阵】 */}
      {data.commonChipPlatforms && Array.isArray(data.commonChipPlatforms) && (
        <div className="bg-white p-6 rounded-2xl shadow-md border-t-4 border-purple-600">
          <h2 className="text-2xl font-black flex items-center gap-2 mb-6 text-purple-900 border-b pb-4">
            <Layers className="text-purple-600" size={28}/> 全球IC商城查价与原厂规格书直连
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
                    {/* 国际巨头专区 */}
                    <div className="flex items-center gap-2">
                       <Globe2 size={12} className="text-gray-400"/>
                       <a href={`https://www.digikey.cn/zh/products/result?keywords=${encodedModel}`} target="_blank" className="text-[11px] font-bold text-red-700 bg-red-50 hover:bg-red-100 px-2 py-1 rounded shadow-sm border border-red-200 transition-colors">DigiKey 得捷</a>
                       <a href={`https://www.mouser.cn/c/?q=${encodedModel}`} target="_blank" className="text-[11px] font-bold text-blue-700 bg-blue-50 hover:bg-blue-100 px-2 py-1 rounded shadow-sm border border-blue-200 transition-colors">Mouser 贸泽</a>
                    </div>
                    {/* 国内龙头专区 */}
                    <div className="flex items-center gap-2 flex-wrap">
                      <ShoppingCart size={12} className="text-gray-400"/>
                      <a href={`https://so.szlcsc.com/global.html?k=${encodedModel}`} target="_blank" className="text-[11px] font-bold text-blue-600 bg-blue-50 hover:bg-blue-100 px-2 py-1 rounded shadow-sm border border-blue-200">立创商城</a>
                      <a href={`https://www.hqchip.com/search/${encodedModel}.html`} target="_blank" className="text-[11px] font-bold text-orange-600 bg-orange-50 hover:bg-orange-100 px-2 py-1 rounded shadow-sm border border-orange-200">华秋商城</a>
                      <a href={`https://s.hqew.com/${encodedModel}.html`} target="_blank" className="text-[11px] font-bold text-indigo-600 bg-indigo-50 hover:bg-indigo-100 px-2 py-1 rounded shadow-sm border border-indigo-200">华强电子网</a>
                      <a href={`https://www.allchips.com/search?keyword=${encodedModel}`} target="_blank" className="text-[11px] font-bold text-red-500 bg-red-50 hover:bg-red-100 px-2 py-1 rounded shadow-sm border border-red-100">硬之城</a>
                      <a href={`https://cn.bing.com/search?q=${encodeURIComponent(chip.brand + ' ' + chip.model + ' datasheet pdf')}`} target="_blank" className="text-[11px] font-bold text-gray-700 bg-yellow-100 hover:bg-yellow-200 px-2 py-1 rounded shadow-sm border border-yellow-300 ml-auto">PDF直达</a>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* 【全面展示无上限产品】 */}
      <div className="space-y-6">
        <div className="flex items-center justify-between px-2">
            <h2 className="text-2xl font-black flex items-center gap-2 text-indigo-900">
              <Cpu className="text-indigo-600" size={28}/> 终端实物拆解与全系晶振 BOM 映射
            </h2>
            <span className="text-sm font-bold text-indigo-500 bg-indigo-50 px-3 py-1 rounded-full border border-indigo-100">共发现 {data.products?.length || 0} 款主打设备</span>
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
                <div className="w-full bg-indigo-50 p-4 rounded-xl border border-indigo-100 shadow-sm text-left">
                  <p className="text-xs text-indigo-600 font-bold mb-1 uppercase">全景芯片架构拆解 (BOM推演)</p>
                  <p className="text-sm font-extrabold text-indigo-900 leading-relaxed">{product.chipPlatform}</p>
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
                      <tr><th className="p-4 font-bold uppercase w-1/4">频率</th><th className="p-4 font-bold uppercase w-1/4">参数</th><th className="p-4 font-bold uppercase w-1/2">核心作用</th></tr>
                    </thead>
                    <tbody className="divide-y divide-gray-100 bg-white">
                      {product.crystals?.map((c, cIdx) => (
                        <tr key={cIdx} className="hover:bg-orange-50/60">
                          <td className="p-4 font-black text-orange-600 text-lg">{c.freq}</td>
                          <td className="p-4"><div className="font-bold text-gray-800">{c.package}</div><div className="text-gray-500 text-xs mt-1">CL:{c.loadCap} | Tol:{c.tolerance}</div></td>
                          <td className="p-4 text-gray-700 leading-relaxed text-justify">{c.function}</td>
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
    </div>
  );
}
EOF

echo ">>> 3. 全面编译生效前端并重启后台引擎..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ 产品解封与全球寻源矩阵上线！网站定向抓图已就绪！"
echo "========================================================="
