#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"
FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在重构后端检索引擎：恢复【深长篇幅的核心作用解析指令】..."

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

const fetchRealImage = async (company, modelName, domain = '') => {
    const fetchImg = async (searchQuery) => {
        try {
            const url = `https://cn.bing.com/images/search?q=${encodeURIComponent(searchQuery)}&first=1`;
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 3500);
            const res = await fetch(url, { 
                headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' }, 
                signal: controller.signal 
            });
            clearTimeout(timeoutId);
            if(res.ok) {
                const text = await res.text();
                const match = text.match(/murl&quot;:&quot;(.*?)&quot;/) || text.match(/murl":"(.*?)"/);
                if (match && match[1]) return match[1];
            }
        } catch(e) {}
        return null;
    };
    const cleanModel = modelName.replace(/\[.*?\]/g, '').replace(/\(.*?\)/g, '').trim();
    if (domain) {
        const domainUrl = await fetchImg(`site:${domain} ${cleanModel} 产品实物`);
        if (domainUrl) return domainUrl;
    }
    const companyUrl = await fetchImg(`"${company}" ${cleanModel} 官方产品`);
    if (companyUrl) return companyUrl;
    return await fetchImg(`${cleanModel} 官方 实物图片`);
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
        const siteQueryStr = targetDomain ? `site:${targetDomain}` : exact;

        sendEvent({ status: '> 🚀 启动全网嗅探，正在穿透防火墙...' });

        const [
            official_products, official_tech, b2b_trade, recruitment, contacts_info
        ] = await Promise.all([
            fetchMatrixQuery(`${siteQueryStr} "产品中心" OR "型号"` , 8),
            fetchMatrixQuery(`${siteQueryStr} "解决方案" OR "技术架构"`),
            fetchMatrixQuery(`${exact} (site:1688.com OR site:hc360.com) "主营产品"`),
            fetchMatrixQuery(`${exact} 招聘 硬件工程师 OR 研发`),
            fetchMatrixQuery(`${exact} "联系人" OR "采购" OR "邮箱" 招标`)
        ]);

        sendEvent({ status: '> ✅ 情报收集完毕，正在唤醒大模型进行降维打击...' });

        // 【核心修复】：找回必须详细解释“为什么需要、如果没有会怎样”的严苛指令
        const prompt = `你是顶级商业侦探。剖析对象：【${companyName}】。
底牌：【地址】: ${address} | 【网址】: ${website} | 【工商范围】: ${userProfile}
情报：[官网产品]: ${official_products} | [技术]: ${official_tech} | [B2B]: ${b2b_trade} | [招聘]: ${recruitment} | [联系人]: ${contacts_info}

【极速流式输出核心指令】：
1. 业务类型打上 [生产制造型] 或 [贸易销售型] 后缀。
2. 提取找到的所有核心产品，名字前加 [真实抓取] 或 [AI推演]。
3. 芯片架构和晶振必须详细推演。**重中之重：在 crystals 的 function 字段中，必须分两句话详细解释：“为什么需要它：...”以及“如果没有它：...”！绝不准用一句话敷衍了事！**
4. 如果无确切联系人则置空数组。

输出严格JSON:
{
  "company": "${companyName}",
  "website": "${website || '未查明'}",
  "address": "整理输出详细地址",
  "coordinates": [纬度, 经度],
  "type": "精准业务类型 (必须带标签)",
  "profile": "硬核企业分析不少于300字",
  "keyContacts": [{"name": "真实姓名(未查明置空数组)", "title": "职务", "contact": "联系方式", "context": "来源"}],
  "commonChipPlatforms": [{"brand": "品牌", "model": "型号", "application": "应用场景"}],
  "products": [
    {
      "name": "[真实抓取]或[AI推演] 具体设备名称",
      "chipPlatform": "芯片架构组合(必须详尽推演)",
      "crystals": [{"freq": "频率", "package": "封装", "loadCap": "电容", "tolerance": "频偏", "function": "必须包含：【为什么需要它：xxx。如果没有它：发生xxx故障。】这两点详细描述"}]
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
                temperature: 0.3, 
                stream: true 
            }),
            signal: controller.signal
        });
        clearTimeout(timeoutId);

        if (!response.ok) {
            sendEvent({ error: `大模型节点异常 (HTTP ${response.status})` });
            return res.end();
        }

        sendEvent({ status: '> 🧠 AI神经元对接成功，开始实时解析数据流...' });

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

        sendEvent({ status: '> 🔍 JSON架构组装完毕，启动全网高敏实物图鉴匹配...' });
        
        let cleanStr = fullJsonStr.replace(/```json/g, '').replace(/```/g, '').trim();
        const resultData = JSON.parse(cleanStr);

        if (!Array.isArray(resultData.coordinates) || resultData.coordinates.length !== 2) {
            resultData.coordinates = [39.9042, 116.4074]; 
        }

        if (resultData.products && Array.isArray(resultData.products)) {
            for (let i = 0; i < resultData.products.length; i++) {
                let p = resultData.products[i];
                if (p.name.includes('推演')) {
                    p.imageUrl = null;
                } else {
                    p.imageUrl = await fetchRealImage(resultData.company, p.name, targetDomain);
                }
            }
        }

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

echo ">>> 2. 正在重构前端弹窗组件：突破 Z-Index 压制，重见天日..."

cat << 'EOF' > "$FRONTEND_DIR/src/components/SettingsModal.jsx"
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
EOF

echo ">>> 3. 正在重写展示层：恢复【高亮解析文案】与【PDF规格书直连卡片】..."

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

  const validContacts = Array.isArray(data.keyContacts) ? data.keyContacts.filter(c => 
    c && c.name && typeof c.name === 'string' && c.name.indexOf('未知') === -1 && c.name.indexOf('未查明') === -1 && c.name !== '无'
  ) : [];

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

      {validContacts.length > 0 && (
        <div className="glass-panel p-6 rounded-2xl relative overflow-hidden glass-hover-fx border-t-4 border-amber-500">
          <h2 className="text-xl font-black flex items-center gap-2 mb-5 text-amber-900 border-b border-gray-100 pb-3"><Users className="text-amber-600" size={24}/> 关键决策人侦测</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 relative z-10">
             {validContacts.map((contact, idx) => (
               <div key={idx} className="bg-amber-50/60 p-4 rounded-xl flex flex-col gap-2 border border-amber-100">
                  <div className="flex justify-between items-start">
                     <div><span className="font-black text-lg text-amber-900">{contact.name}</span><span className="ml-2 text-xs font-bold bg-amber-100 text-amber-800 px-2 py-0.5 rounded">{contact.title || '职务未知'}</span></div>
                  </div>
                  <div className="text-sm font-mono bg-white/70 px-3 py-1.5 rounded mt-1 text-gray-700 border border-gray-200/50">联络: {contact.contact || '未知'}</div>
                  <div className="text-xs text-gray-500 mt-1">情报来源: {contact.context || '系统挖掘'}</div>
               </div>
             ))}
          </div>
        </div>
      )}

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
                    {/* 【核心修复】：找回黄色的 PDF 规格书直连按钮！ */}
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
              <h2 className="text-2xl font-black flex items-center gap-2 text-indigo-900"><Cpu className="text-indigo-600" size={28}/> 终端实物拆解</h2>
              <span className="text-sm font-bold text-indigo-700 bg-indigo-100 px-3 py-1 rounded-full shadow-sm border border-indigo-200">挖掘出 {data.products.length} 款产品</span>
          </div>
          
          {data.products.map((product, idx) => (
            <div key={idx} className="glass-panel p-6 rounded-2xl overflow-hidden glass-hover-fx" onMouseDown={(e) => window.createRipple && window.createRipple(e, e.currentTarget)}>
              <div className="flex flex-col lg:flex-row gap-8 relative z-10">
                <div className="lg:w-1/3 flex flex-col items-center text-center space-y-4">
                  <div className="w-full h-64 rounded-xl bg-white/60 border border-gray-100 relative overflow-hidden flex flex-col items-center justify-center shadow-inner">
                    {product.imageUrl ? (
                      <img src={`/api/image-proxy?url=${encodeURIComponent(product.imageUrl)}`} alt={product.name || '产品图片'} className="w-full h-full object-contain p-2 hover:scale-110 transition-transform duration-700" onError={(e) => { e.target.style.display='none'; e.target.nextSibling.style.display='flex'; }}/>
                    ) : null}
                    <div className="absolute inset-0 flex-col items-center justify-center text-gray-400" style={{ display: product.imageUrl ? 'none' : 'flex' }}>
                      <Box size={48} className="mb-2 opacity-30"/>
                      <span className="text-sm font-bold px-4">{product.name || '暂无实物图'}</span>
                    </div>
                  </div>
                  <h3 className="text-xl font-black text-gray-900 leading-tight">{product.name || '未知设备'}</h3>
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
                        {Array.isArray(product.crystals) && product.crystals.map((c, cIdx) => (
                          <tr key={cIdx} className="hover:bg-orange-50/60 transition-colors">
                            <td className="p-4 font-black text-orange-600 text-lg whitespace-nowrap">{c.freq || '-'}</td>
                            <td className="p-4"><div className="font-bold text-gray-800">{c.package || '-'}</div><div className="text-gray-500 text-xs mt-1">CL:{c.loadCap || '-'} | Tol:{c.tolerance || '-'}</div></td>
                            {/* 【核心修复】：找回正则高亮替换，让“为什么需要、如果没有”更加醒目易读！ */}
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

echo ">>> 4. 编译全栈生态，完成核心复位..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ 配置弹窗破水而出！详细解说与PDF直连全员归位！"
echo "========================================================="
