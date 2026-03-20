#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"
FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在为后端安装工业级关系型数据库与 ORM 引擎..."
cd "$BACKEND_DIR"
npm install sequelize sqlite3 --save > /dev/null 2>&1

echo ">>> 2. 正在重构后端数据库模型：从 JSON 跃迁至 SQLite (包含热迁移逻辑)..."
mkdir -p "$BACKEND_DIR/models"

cat << 'EOF' > "$BACKEND_DIR/models/Customer.js"
const { Sequelize, DataTypes } = require('sequelize');
const path = require('path');

const sequelize = new Sequelize({
    dialect: 'sqlite',
    storage: path.join(__dirname, '../../backend/config/database.sqlite'),
    logging: false
});

const Customer = sequelize.define('Customer', {
    company: { type: DataTypes.STRING, unique: true, primaryKey: true },
    address: DataTypes.STRING,
    website: DataTypes.STRING,
    type: DataTypes.STRING,
    category: DataTypes.STRING,
    profile: DataTypes.TEXT,
    coordinates: DataTypes.JSON,
    keyContacts: DataTypes.JSON,
    commonChipPlatforms: DataTypes.JSON,
    products: DataTypes.JSON,
    strategy: DataTypes.TEXT
});

module.exports = { sequelize, Customer };
EOF

cat << 'EOF' > "$BACKEND_DIR/controllers/customerController.js"
const fs = require('fs');
const path = require('path');
const { Customer, sequelize } = require('../models/Customer');

const dbDir = '/var/www/crystal/backend/config';
const oldJsonPath = path.join(dbDir, 'customers.json');
const backupJsonPath = path.join(dbDir, 'customers.json.bak');

// 【无缝迁移引擎】：首次启动将旧 JSON 安全汇入 SQLite
const migrateOldData = async () => {
    try {
        await sequelize.sync();
        if (fs.existsSync(oldJsonPath)) {
            const rawData = fs.readFileSync(oldJsonPath, 'utf8');
            if (rawData && rawData.trim() !== '') {
                const oldCustomers = JSON.parse(rawData);
                for (const cust of oldCustomers) {
                    await Customer.upsert(cust);
                }
            }
            fs.renameSync(oldJsonPath, backupJsonPath);
            console.log("✅ 历史 JSON 档案已安全跃迁至 SQLite 关系型数据库！");
        }
    } catch (e) {
        console.error("数据迁移异常:", e);
    }
};
migrateOldData();

const getCustomers = async (req, res) => {
    try {
        const customers = await Customer.findAll();
        res.json({ success: true, data: customers });
    } catch (e) {
        res.json({ success: true, data: [] });
    }
};

const saveCustomer = async (req, res) => {
    try {
        const data = req.body;
        if (data.category === '未收藏') {
            await Customer.destroy({ where: { company: data.company } });
        } else {
            await Customer.upsert(data);
        }
        res.json({ success: true, message: '数据已安全硬核写入' });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

const deleteCustomer = async (req, res) => {
    try {
        const company = req.query.company; 
        if (!company) return res.status(400).json({ success: false });
        await Customer.destroy({ where: { company: company } });
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

module.exports = { getCustomers, saveCustomer, deleteCustomer };
EOF

echo ">>> 3. 正在重写后端检索引擎：开启 Server-Sent Events (SSE) 流式打字机通道..."

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
    // 【流式 SSE 核心协议开启】
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.flushHeaders();

    const sendEvent = (data) => {
        res.write(`data: ${JSON.stringify(data)}\n\n`);
    };

    try {
        const { companyName, address, website, profile: userProfile } = req.body;
        if (!companyName) {
            sendEvent({ error: '请输入公司名称' });
            return res.end();
        }

        if (!fs.existsSync(configPath)) {
            sendEvent({ error: '请先配置 API' });
            return res.end();
        }
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

        const prompt = `你是顶级商业侦探。剖析对象：【${companyName}】。
底牌：【地址】: ${address} | 【网址】: ${website} | 【工商范围】: ${userProfile}
情报：[官网产品]: ${official_products} | [技术]: ${official_tech} | [B2B]: ${b2b_trade} | [招聘]: ${recruitment} | [联系人]: ${contacts_info}

【极速流式输出核心指令】：
1. 业务类型打上 [生产制造型] 或 [贸易销售型] 后缀标签。
2. 提取找到的所有产品(不少于6款)，名字前加 [真实抓取] 或 [AI推演]。
3. 芯片架构和晶振必须详细推演，绝不留白。如果无确切联系人则置空数组。

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
      "crystals": [{"freq": "频率", "package": "封装", "loadCap": "电容", "tolerance": "频偏", "function": "核心作用"}]
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
        
        // 开启大模型的流式模式 stream: true
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

        // 解析打字机数据流
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
                            sendEvent({ chunk: content }); // 吐出每一个字符给前端打字机
                        }
                    } catch(e) {}
                }
            }
        }

        sendEvent({ status: '> 🔍 JSON架构组装完毕，启动全网高敏实物图鉴匹配...' });
        
        // JSON 整理
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

        // 发送最终完整数据，渲染 UI
        sendEvent({ fullData: resultData });
        res.write('data: [DONE]\n\n');
        res.end();

    } catch (error) {
        console.error("系统抛出异常:", error);
        sendEvent({ error: `处理异常: ${error.message}` });
        res.end();
    }
};

module.exports = { searchLead, proxyImage };
EOF

echo ">>> 4. 正在重构前端雷达控制台：注入【赛博朋克流式终端 UI】..."

cat << 'EOF' > "$FRONTEND_DIR/src/store.js"
import { create } from 'zustand';

export const useStore = create((set) => ({
  activeTab: 'search',
  setActiveTab: (tab) => set({ activeTab: tab }),
  
  settingsOpen: false,
  setSettingsOpen: (open) => set({ settingsOpen: open }),
  
  searchResult: null,
  setResult: (res) => set({ searchResult: res }),
  
  loading: false,
  setLoading: (state) => set({ loading: state }),
  
  error: null,
  setError: (err) => set({ error: err }),

  refreshTrigger: 0,
  triggerRefresh: () => set((state) => ({ refreshTrigger: state.refreshTrigger + 1 })),

  // 新增流式状态
  streamStatus: '',
  setStreamStatus: (status) => set({ streamStatus: status }),
  
  streamText: '',
  setStreamText: (text) => set({ streamText: text }),
  clearStream: () => set({ streamStatus: '', streamText: '' })
}));
EOF

cat << 'EOF' > "$FRONTEND_DIR/src/components/SearchLead.jsx"
import React, { useState, useRef, useEffect } from 'react';
import { Search, Loader2, Database, MapPin, Globe, FileText, Terminal } from 'lucide-react';
import { useStore } from '../store';

export default function SearchLead() {
  const { setLoading, setResult, setError, loading, streamStatus, streamText, setStreamStatus, setStreamText, clearStream } = useStore();
  const terminalRef = useRef(null);

  const [formData, setFormData] = useState({
    companyName: '',
    address: '',
    website: '',
    profile: ''
  });

  const handleChange = (e) => setFormData({ ...formData, [e.target.name]: e.target.value });

  // 自动滚动终端到底部
  useEffect(() => {
    if (terminalRef.current) {
      terminalRef.current.scrollTop = terminalRef.current.scrollHeight;
    }
  }, [streamText, streamStatus]);

  const handleSearch = async () => {
    if (!formData.companyName.trim()) {
      setError('公司全称必须填写！');
      return;
    }
    setLoading(true);
    setError(null);
    setResult(null);
    clearStream();

    try {
      const response = await fetch('/api/search', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData)
      });

      const reader = response.body.getReader();
      const decoder = new TextDecoder('utf-8');
      let accumulatedText = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        
        const chunk = decoder.decode(value, { stream: true });
        const lines = chunk.split('\n');
        
        for (const line of lines) {
          if (line.startsWith('data: ')) {
            const dataStr = line.replace('data: ', '').trim();
            if (dataStr === '[DONE]') break;
            
            try {
              const parsed = JSON.parse(dataStr);
              if (parsed.error) {
                setError(parsed.error);
                setLoading(false);
                return;
              }
              if (parsed.status) {
                setStreamStatus(parsed.status);
              }
              if (parsed.chunk) {
                accumulatedText += parsed.chunk;
                setStreamText(accumulatedText);
              }
              if (parsed.fullData) {
                setResult(parsed.fullData);
                setLoading(false);
                return;
              }
            } catch (e) {}
          }
        }
      }
    } catch (err) {
      setError('网络连接断开，请重试');
      setLoading(false);
    }
  };

  return (
    <div className="max-w-4xl mx-auto p-4 mt-6 animate-fade-in font-sans">
      <div className="glass-panel rounded-2xl shadow-xl p-6 md:p-8 border-t-4 border-blue-500 relative z-10 overflow-hidden">
        <div className="text-center mb-8 relative z-10">
          <h2 className="text-3xl font-black text-gray-800 tracking-tight flex items-center justify-center gap-2">
            <Database className="text-blue-600" size={32}/> 人机协同精准雷达
          </h2>
          <p className="text-gray-500 mt-2 font-medium">输入底牌，AI 实施像素级精准推演</p>
        </div>

        <div className="space-y-5 relative z-10">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
            <div className="space-y-1.5 md:col-span-2">
              <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><Search size={14} className="text-blue-500"/> 目标公司全称 <span className="text-red-500">*</span></label>
              <input type="text" name="companyName" value={formData.companyName} onChange={handleChange} placeholder="例：深圳市某某科技有限公司" className="w-full p-4 bg-white/80 border border-gray-200 shadow-sm rounded-xl focus:ring-2 focus:ring-blue-500 outline-none font-black text-gray-900 text-lg transition-all" />
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><MapPin size={14} className="text-red-500"/> 注册/办公地址</label>
              <input type="text" name="address" value={formData.address} onChange={handleChange} className="w-full p-3 bg-white/80 border border-gray-200 shadow-sm rounded-lg focus:ring-2 focus:ring-blue-500 outline-none font-bold text-gray-800" />
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><Globe size={14} className="text-teal-500"/> 官方网站 (定向抓取)</label>
              <input type="text" name="website" value={formData.website} onChange={handleChange} className="w-full p-3 bg-white/80 border border-gray-200 shadow-sm rounded-lg focus:ring-2 focus:ring-blue-500 outline-none font-bold text-gray-800" />
            </div>
          </div>
          <div className="space-y-1.5">
            <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><FileText size={14} className="text-purple-500"/> 工商经营范围 / 简介</label>
            <textarea name="profile" value={formData.profile} onChange={handleChange} rows="3" className="w-full p-4 bg-white/80 border border-gray-200 shadow-sm rounded-xl focus:ring-2 focus:ring-blue-500 outline-none font-bold text-gray-800 text-sm leading-relaxed resize-none"></textarea>
          </div>

          {/* 骇客级打字机终端层 */}
          {loading && (
             <div className="mt-6 bg-[#0f172a] rounded-xl p-4 shadow-inner border border-gray-800 font-mono text-sm relative overflow-hidden">
               <div className="flex items-center gap-2 mb-3 border-b border-gray-700 pb-2">
                 <Terminal size={16} className="text-green-400" />
                 <span className="text-green-400 font-bold tracking-widest">{streamStatus || '> 系统初始化...'}</span>
                 <Loader2 size={14} className="text-green-400 animate-spin ml-auto" />
               </div>
               <div ref={terminalRef} className="h-40 overflow-y-auto text-green-300/80 whitespace-pre-wrap leading-relaxed">
                 {streamText || '等待数据流注入...'}
                 <span className="animate-pulse inline-block w-2 h-4 bg-green-400 ml-1 translate-y-1"></span>
               </div>
             </div>
          )}

          {!loading && (
            <button 
              onMouseDown={(e) => window.createRipple && window.createRipple(e, e.currentTarget)}
              onClick={handleSearch} 
              className="w-full mt-6 bg-gradient-to-r from-blue-600 to-indigo-600 text-white font-black text-lg p-4 rounded-xl shadow-lg hover:shadow-2xl hover:scale-[1.01] transition-all flex items-center justify-center gap-2 relative overflow-hidden border border-blue-400/50"
            >
              <Search size={24} /> 启动全景雷达与流式解析
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
EOF

echo ">>> 4. 正在编译生效全套商业级架构..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ 数据库 SQLite 平滑升级完成！流式终端打字机炫酷实装！"
echo "========================================================="
