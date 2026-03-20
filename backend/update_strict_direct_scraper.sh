#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"
FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在重构后端：切除决策人与外援搜图，注入【零外援·官网暴力强扒引擎】..."

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

// 【零外援核心引擎】：暴力解构 HTML 树，提取所有可见与隐藏的图片
const scrapeDirectSite = async (website, domain) => {
    let content = "";
    
    // 1. 优先抓取用户直接填入的确切网址，如果没有，则尝试产品中心变体
    let urlsToTry = [];
    if (website && website.trim() !== '' && website !== '未查明') {
        const cleanWeb = website.startsWith('http') ? website : `http://${website}`;
        urlsToTry.push(cleanWeb);
    }
    if (domain) {
        urlsToTry.push(`http://www.${domain}/product`);
        urlsToTry.push(`http://www.${domain}/products`);
        urlsToTry.push(`http://www.${domain}/list`);
        urlsToTry.push(`https://www.${domain}`);
    }

    for (let u of urlsToTry) {
        try {
            const controller = new AbortController();
            const id = setTimeout(() => controller.abort(), 6000); 
            const res = await fetch(u, { 
                headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36'}, 
                signal: controller.signal,
                redirect: 'follow'
            });
            clearTimeout(id);
            
            if (res.ok) {
                const html = await res.text();
                const $ = cheerio.load(html);
                
                let imgContext = "\n【官网真实提取图库】(大模型必须从此图库中匹配imageUrl):\n";
                let imgCount = 0;
                
                // 深度扫描所有图片和背景图，穿透懒加载
                $('img, [style*="background"]').each((i, el) => {
                    let src = $(el).attr('data-src') || $(el).attr('data-original') || $(el).attr('data-lazy-src') || $(el).attr('v-lazy') || $(el).attr('src');
                    
                    // 解析 CSS 背景图
                    if (!src) {
                        let style = $(el).attr('style');
                        if (style) {
                            let bgMatch = style.match(/url\(['"]?(.*?)['"]?\)/);
                            if (bgMatch) src = bgMatch[1];
                        }
                    }

                    if (src && !src.startsWith('data:image') && imgCount < 60) { // 扩大到 60 张，宁滥勿缺
                        try {
                            src = new URL(src, u).href; // 转换为绝对路径
                            // 暴力提取图片周围 100 个字符内的所有文本，极大概率包含产品型号
                            let alt = $(el).attr('alt') || $(el).attr('title') || '';
                            let parentText = $(el).parent().text().replace(/\s+/g, ' ').trim().substring(0, 50);
                            let nextText = $(el).parent().next().text().replace(/\s+/g, ' ').trim().substring(0, 50);
                            let prevText = $(el).parent().prev().text().replace(/\s+/g, ' ').trim().substring(0, 50);
                            
                            let contextText = `${alt} ${parentText} ${nextText} ${prevText}`.trim();
                            if (contextText.length > 2) {
                                imgContext += `[图:${src} | 旁白:${contextText}]\n`;
                                imgCount++;
                            }
                        } catch(e) {}
                    }
                });

                $('script, style, noscript, nav, footer, header').remove();
                let text = $('body').text().replace(/\s+/g, ' ').trim();
                
                if (text.length > 100 || imgCount > 0) {
                    content += `[抓取网址: ${u}]\n【官网文字内容】:\n` + text.substring(0, 3000) + "\n" + imgContext;
                    break; // 抓到一个核心页就退出，保证速度
                }
            }
        } catch(e) {}
    }
    return content.substring(0, 8000); // 放宽文本容量
};

const fetchMatrixQuery = async (query, limit = 5) => {
    try {
        const url = `https://cn.bing.com/search?q=${encodeURIComponent(query)}`;
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 5000);
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
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.flushHeaders();

    const sendEvent = (data) => {
        res.write(`data: ${JSON.stringify(data)}\n\n`);
    };

    try {
        const { companyName, address, website, profile: userProfile } = req.body;
        if (!companyName) { sendEvent({ error: '请输入公司名称' }); return res.end(); }
        if (!fs.existsSync(configPath)) { sendEvent({ error: '请先配置 API' }); return res.end(); }
        const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));

        let targetDomain = '';
        if (website && website.trim() !== '') {
            targetDomain = website.replace(/^(?:https?:\/\/)?(?:www\.)?/i, "").split('/')[0];
        }
        const exact = `"${companyName}"`;

        sendEvent({ status: '> 🚀 启动零外援强扒引擎：深度解析官网 DOM 树与懒加载图库...' });

        // 【大幅减负】：去掉了招聘、联系人的爬虫搜索
        const [
            direct_html_data, official_tech, b2b_trade
        ] = await Promise.all([
            scrapeDirectSite(website, targetDomain), 
            fetchMatrixQuery(`${targetDomain ? `site:${targetDomain}` : exact} "解决方案" OR "应用领域"`),
            fetchMatrixQuery(`${exact} (site:1688.com OR site:hc360.com) "主营产品" "规格"`)
        ]);

        sendEvent({ status: '> ✅ 官网图文剥离完毕，正在唤醒大模型组装无限量产品矩阵...' });

        const prompt = `你是顶级商业侦探。剖析对象：【${companyName}】。
【极其重要：官网底层真扒数据】：
以下内容是我直接用爬虫潜入该网站提取的源码文本，以及【官网真实提取图库】。
${direct_html_data || "官网无法访问或提取失败"}

[官网技术]: ${official_tech}
[B2B商城]: ${b2b_trade}

【零外援极速输出铁律】：
1. 提取所有你找到的【具体设备型号】。**无数量上限，官网上有多少就提取多少！**
2. **【绝对的图文匹配铁律】**：对于提取出的每个产品，必须去上面的【官网真实提取图库】中寻找配图。如果你发现某张图的 [旁白] 中包含该产品的型号或名称，**立刻把这个 [图:URL] 的 URL 填入 \`imageUrl\` 中**！如果没有找到匹配的，必须填空字符串 ""，绝不允许自己伪造链接！
3. 芯片架构和晶振必须推演（function必须写出：为什么需要它...如果没有它...）。
4. 必须输出绝对合法完整的 JSON，禁止非法引号导致断裂。

输出严格JSON:
{
  "company": "${companyName}",
  "website": "${website || '未查明'}",
  "address": "整理输出",
  "coordinates": [纬度, 经度],
  "type": "精准业务类型 (带 [生产制造型] 或 [贸易销售型] 标签)",
  "profile": "硬核企业分析(约300字)",
  "commonChipPlatforms": [{"brand": "品牌", "model": "型号", "application": "应用场景"}],
  "products": [
    {
      "name": "[真实抓取] 具体设备型号",
      "imageUrl": "严格从图库中匹配的官网原图绝对URL (没有则填空字符串)",
      "chipPlatform": "芯片架构组合(必须详尽推演)",
      "crystals": [{"freq": "频率", "package": "封装", "loadCap": "电容", "tolerance": "频偏", "function": "包含：为什么需要它...如果没有它..."}]
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
        const timeoutId = setTimeout(() => controller.abort(), 90000); 
        
        const response = await fetch(targetUrl, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${(config.apiKey || '').trim()}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model: (config.model || '').trim() || 'deepseek-chat',
                messages: [{ role: "user", content: prompt }],
                temperature: 0.1, 
                max_tokens: 4096, 
                stream: true 
            }),
            signal: controller.signal
        });
        clearTimeout(timeoutId);

        if (!response.ok) {
            sendEvent({ error: `大模型节点异常 (HTTP ${response.status})` });
            return res.end();
        }

        sendEvent({ status: '> 🧠 神经元正在将官网图片URL与产品型号强行缝合...' });

        let fullJsonStr = '';
        const decoder = new TextDecoder('utf-8');
        
        for await (const chunk of response.body) {
            const decoded = decoder.decode(chunk, { stream: true });
            const lines = decoded.split('\n');
            for (const line of lines) {
                if (line.startsWith('data: ') && line.trim() !== 'data: [DONE]') {
                    try {
                        const parsed = JSON.parse(line.slice(6));
                        const content = parsed.choices[0]?.delta?.content || '';
                        if (content) {
                            fullJsonStr += content;
                            sendEvent({ chunk: content });
                        }
                    } catch(e) {}
                }
            }
        }

        sendEvent({ status: '> 🔍 JSON组装完毕，正在清洗数据结构...' });
        
        let cleanStr = fullJsonStr.replace(/```json/gi, '').replace(/```/g, '').trim();
        const firstBrace = cleanStr.indexOf('{');
        const lastBrace = cleanStr.lastIndexOf('}');
        if (firstBrace !== -1 && lastBrace !== -1) {
            cleanStr = cleanStr.substring(firstBrace, lastBrace + 1);
        }

        let resultData;
        try {
            resultData = JSON.parse(cleanStr);
        } catch (parseErr) {
            sendEvent({ error: "大模型生成超载被截断，请重试！" });
            return res.end();
        }

        if (!Array.isArray(resultData.coordinates) || resultData.coordinates.length !== 2) {
            resultData.coordinates = [39.9042, 116.4074]; 
        }

        // 因为不再依赖必应兜底搜图，直接将处理好的数据返回！零延迟！
        sendEvent({ fullData: resultData });
        res.write('data: [DONE]\n\n');
        res.end();

    } catch (error) {
        sendEvent({ error: `处理异常: ${error.message}` });
        res.end();
    }
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

module.exports = { searchLead, proxyImage };
EOF

echo ">>> 2. 正在重写前端 UI：彻底剔除【关键决策人】模块..."

cat << 'EOF' > "$FRONTEND_DIR/src/components/ResultDisplay.jsx"
import React, { useState, useEffect } from 'react';
import axios from 'axios';
import * as XLSX from 'xlsx';
import { useStore } from '../store';
import { Building2, Cpu, Zap, Lightbulb, Link as LinkIcon, Info, Box, Layers, Copy, Check, MapPin, Star, ShoppingCart, Globe2, FileText, Download, Table2 } from 'lucide-react';

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

  const safeWebsite = (data.website && typeof data.website === 'string' && data.website !== '未查明' && data.website !== '无') ? data.website : '';
  const siteUrl = safeWebsite ? (safeWebsite.startsWith('http') ? safeWebsite : `https://${safeWebsite}`) : '#';

  const handleCopy = (text, id) => {
    if (!text) return;
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

  if (Array.isArray(data.products)) {
    data.products.forEach(p => {
      if (Array.isArray(p.crystals)) {
        p.crystals.forEach(c => {
          const key = `${c.freq || '未知'}|${c.package || '未知'}`;
          if (!bomMap.has(key)) {
            bomMap.set(key, {
              freq: c.freq || '-',
              package: c.package || '-',
              params: `CL:${c.loadCap || '-'} | Tol:${c.tolerance || '-'}`,
              function: c.function || '',
              devices: new Set([p.name || '未知设备']),
              chips: new Set([p.chipPlatform || '未知架构'])
            });
          } else {
            bomMap.get(key).devices.add(p.name || '未知设备');
            bomMap.get(key).chips.add(p.chipPlatform || '未知架构');
          }
        });
      }
    });
  }

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
    XLSX.writeFile(wb, `${data.company || '未知企业'}_晶振BOM聚合分析.xlsx`);
  };

  return (
    <div className="max-w-6xl mx-auto p-4 space-y-8 animate-fade-in mt-4 font-sans text-gray-800">
      
      <div className="glass-panel p-6 rounded-2xl relative group overflow-hidden border-t-4 border-blue-500" onMouseDown={(e) => window.createRipple && window.createRipple(e, e.currentTarget)}>
        <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-4 border-b border-gray-100 pb-4 relative z-10">
            <div className="group/copy flex items-center gap-2 cursor-pointer hover:bg-blue-50/50 p-2 -ml-2 rounded-lg transition-colors" onClick={() => handleCopy(data.company, 'companyName')}>
              <Building2 className="text-blue-600" size={28}/> 
              <h2 className="text-2xl font-black text-blue-900">{data.company || '未知企业'}</h2>
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
          <p className="flex items-center gap-3">
            <span className="font-semibold w-20 text-gray-500">官方网站:</span> 
            {safeWebsite ? (
              <a href={siteUrl} target="_blank" rel="noopener noreferrer" className="flex items-center gap-1 text-blue-600 hover:text-blue-800 hover:underline font-bold text-base">
                <LinkIcon size={18} /> {safeWebsite}
              </a>
            ) : (
              <span className="text-gray-400 font-bold">未查明</span>
            )}
          </p>
          <p className="flex items-center gap-3"><span className="font-semibold w-20 text-gray-500">业务类型:</span> <span className="bg-blue-100/80 text-blue-800 px-3 py-1 rounded-md text-sm font-bold shadow-sm border border-blue-200/50">{data.type || '未定义'}</span></p>
          <div className="mt-6 p-5 bg-blue-50/50 rounded-xl relative border border-blue-100">
             <div className="flex gap-3 items-start"><Info className="text-blue-500 flex-shrink-0 mt-1" size={22} /><p className="leading-loose text-base text-justify">{data.profile || '暂无企业简介'}</p></div>
          </div>
        </div>
      </div>

      {/* 【执行切除】：决策人模块已被彻底剔除 */}

      {Array.isArray(data.commonChipPlatforms) && data.commonChipPlatforms.length > 0 && (
        <div className="glass-panel p-6 rounded-2xl relative overflow-hidden glass-hover-fx border-t-4 border-purple-500">
          <h2 className="text-2xl font-black flex items-center gap-2 mb-6 text-purple-900 border-b border-gray-100 pb-4"><Layers className="text-purple-600" size={28}/> 全球IC商城查价直连</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 relative z-10">
            {data.commonChipPlatforms.map((chip, idx) => {
              const enc = encodeURIComponent(chip.model || '');
              return (
                <div key={idx} className="bg-purple-50/60 rounded-xl p-5 relative flex flex-col justify-between border border-purple-100">
                  <div>
                    <span className="inline-block px-2 py-1 bg-purple-200 text-purple-900 text-xs font-bold rounded mb-2 shadow-sm">{chip.brand || '未知品牌'}</span>
                    <h3 className="text-lg font-black text-gray-900 mb-1 tracking-tight">{chip.model || '未知型号'}</h3>
                    <p className="text-sm text-gray-600 leading-relaxed mb-4">{chip.application || '通用场景'}</p>
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
                      <a href={`https://cn.bing.com/search?q=${encodeURIComponent((chip.model || '') + ' datasheet pdf')}`} target="_blank" className="text-[11px] font-bold text-gray-700 bg-yellow-100 hover:bg-yellow-200 border border-yellow-300 px-2 py-1 rounded shadow-sm ml-auto flex items-center gap-1"><FileText size={10}/> PDF直搜</a>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {Array.isArray(data.products) && data.products.length > 0 && (
        <div className="space-y-6">
          <div className="flex items-center justify-between px-2">
              <h2 className="text-2xl font-black flex items-center gap-2 text-indigo-900"><Cpu className="text-indigo-600" size={28}/> 终端实物全景图鉴</h2>
              <span className="text-sm font-bold text-indigo-700 bg-indigo-100 px-3 py-1 rounded-full shadow-sm border border-indigo-200">挖掘出 {data.products.length} 款产品</span>
          </div>
          
          {data.products.map((product, idx) => (
            <div key={idx} className="glass-panel p-6 rounded-2xl overflow-hidden glass-hover-fx" onMouseDown={(e) => window.createRipple && window.createRipple(e, e.currentTarget)}>
              <div className="flex flex-col lg:flex-row gap-8 relative z-10">
                <div className="lg:w-1/3 flex flex-col items-center text-center space-y-4">
                  <div className="w-full h-64 rounded-xl bg-white/60 border border-gray-100 relative overflow-hidden flex flex-col items-center justify-center shadow-inner group">
                    {/* 直接使用官网原图 URL，经过 proxy 解决跨域 */}
                    {product.imageUrl ? (
                      <img src={`/api/image-proxy?url=${encodeURIComponent(product.imageUrl)}`} alt={product.name || '产品图片'} className="w-full h-full object-contain p-2 group-hover:scale-110 transition-transform duration-700" onError={(e) => { e.target.style.display='none'; e.target.nextSibling.style.display='flex'; }}/>
                    ) : null}
                    <div className="absolute inset-0 flex-col items-center justify-center text-gray-400" style={{ display: product.imageUrl ? 'none' : 'flex' }}>
                      <Box size={48} className="mb-2 opacity-30"/>
                      <span className="text-sm font-bold px-4">{product.name || '官网未能成功抓取到此型号的图片'}</span>
                    </div>
                  </div>
                  <h3 className="text-xl font-black text-gray-900 leading-tight">{product.name || '未知设备'}</h3>
                  <div className="w-full bg-indigo-50/80 p-5 rounded-xl text-left border border-indigo-100 shadow-sm">
                    <p className="text-xs text-indigo-700 font-bold mb-2 uppercase border-b border-indigo-200 pb-2">芯片架构拆解 (BOM推演)</p>
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
                        {Array.isArray(product.crystals) && product.crystals.map((c, cIdx) => (
                          <tr key={cIdx} className="hover:bg-orange-50/60 transition-colors">
                            <td className="p-4 font-black text-orange-600 text-lg whitespace-nowrap">{c.freq || '-'}</td>
                            <td className="p-4"><div className="font-bold text-gray-800">{c.package || '-'}</div><div className="text-gray-500 text-xs mt-1">CL:{c.loadCap || '-'} | Tol:{c.tolerance || '-'}</div></td>
                            <td className="p-4 text-gray-700 leading-relaxed text-justify bg-orange-50/30" dangerouslySetInnerHTML={{__html: (c.function || '-').replace(/(为什么需要.*?：|如果没有.*?：)/g, '<strong class="text-orange-700">$1</strong>')}}></td>
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
      )}

      {data.strategy && (
        <div className="glass-panel p-6 rounded-2xl relative overflow-hidden glass-hover-fx border-t-4 border-green-500">
          <h2 className="text-xl font-black flex items-center gap-2 mb-4 text-green-800 border-b border-gray-100 pb-3"><Lightbulb className="text-green-600" size={24}/> AI FAE 极速选型建议</h2>
          <p className="leading-loose font-medium text-base text-justify bg-green-50/80 p-4 rounded-xl relative z-10 text-gray-800 border border-green-100">{data.strategy}</p>
        </div>
      )}

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
                <tr><th className="p-3 font-bold border-b border-gray-200">汇总频率</th><th className="p-3 font-bold border-b border-gray-200">封装参数</th><th className="p-3 font-bold border-b border-gray-200">应用设备 (折叠合并)</th><th className="p-3 font-bold border-b border-gray-200">涉及主控 (推演)</th></tr>
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

echo ">>> 3. 全局重编生效，重启底层物理强扒引擎..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ 关键决策人已摘除！官网强扒零外援图库已全量实装！"
echo "========================================================="
