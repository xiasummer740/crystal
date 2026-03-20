#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"
FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在重构后端图片嗅探引擎：加入高匿伪装与三级降维破盾算法..."

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

// 【核心修复】：三级降维高敏图片嗅探，带高匿 User-Agent 防拦截
const fetchRealImage = async (company, modelName, domain = '') => {
    const fetchImg = async (searchQuery) => {
        try {
            const url = `https://cn.bing.com/images/search?q=${encodeURIComponent(searchQuery)}&first=1`;
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 4000);
            const res = await fetch(url, { 
                headers: { 
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'
                }, 
                signal: controller.signal 
            });
            clearTimeout(timeoutId);
            if(res.ok) {
                const text = await res.text();
                // 兼容必应的两种图片 JSON 返回格式
                const match = text.match(/murl&quot;:&quot;(.*?)&quot;/) || text.match(/murl":"(.*?)"/);
                if (match && match[1]) return match[1];
            }
        } catch(e) { console.error("抓图防盾触发:", e.message); }
        return null;
    };
    
    // 清理掉大模型生成的标签，只保留纯净型号
    const cleanModel = modelName.replace(/\[.*?\]/g, '').replace(/\(.*?\)/g, '').trim();

    // 轨道 1：强搜官网 (去掉双引号死限制)
    if (domain) {
        const domainUrl = await fetchImg(`site:${domain} ${cleanModel} 产品`);
        if (domainUrl) return domainUrl;
    }
    
    // 轨道 2：公司名 + 型号 (精准全网查找)
    const companyUrl = await fetchImg(`${company} ${cleanModel}`);
    if (companyUrl) return companyUrl;
    
    // 轨道 3：全网强行兜底抓取 (极高容错率)
    return await fetchImg(`${cleanModel} 官方 实物图片`);
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
            official_products, official_tech, b2b_trade, recruitment, contacts_info
        ] = await Promise.all([
            fetchMatrixQuery(`${siteQueryStr} "产品中心" OR "型号"` , 10),
            fetchMatrixQuery(`${siteQueryStr} "解决方案" OR "技术架构"`),
            fetchMatrixQuery(`${exact} (site:1688.com OR site:hc360.com) "主营产品"`),
            fetchMatrixQuery(`${exact} 招聘 硬件工程师 OR 研发`),
            fetchMatrixQuery(`${exact} "联系人" OR "采购" OR "邮箱" 招标`)
        ]);

        const prompt = `你是顶级商业侦探。剖析对象：【${companyName}】。
底牌：【地址】: ${address} | 【网址】: ${website} | 【工商范围】: ${userProfile}
爬虫：[产品]: ${official_products} | [技术]: ${official_tech} | [B2B]: ${b2b_trade} | [招聘]: ${recruitment} | [联系人]: ${contacts_info}

【核心指令】：
1. 根据工商范围打上 [生产制造型] 或 [贸易销售型] 后缀标签。
2. 列出找到的所有产品(不低于6款)，名字前加 [真实抓取] 或 [AI推演]。
3. 芯片必须推演，不准留白。如果无联系人则置空数组。

输出严格JSON:
{
  "company": "${companyName}",
  "website": "${website || '未查明'}",
  "address": "整理输出详细地址",
  "coordinates": [纬度, 经度],
  "type": "精准业务类型 (必须带有 [生产制造型] 或 [贸易销售型] 后缀)",
  "profile": "硬核企业分析不少于350字",
  "keyContacts": [{"name": "真实姓名(未查明置空数组)", "title": "职务", "contact": "联系方式", "context": "来源"}],
  "commonChipPlatforms": [{"brand": "品牌", "model": "型号", "application": "应用场景"}],
  "products": [
    {
      "name": "[真实抓取]或[AI推演] 具体设备名称",
      "chipPlatform": "芯片架构组合(使用分号连贯书写)",
      "crystals": [{"freq": "频率", "package": "封装", "loadCap": "电容", "tolerance": "频偏", "function": "核心作用解析"}]
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
                // 执行全新破盾爬虫
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

echo ">>> 2. 正在重构前端雷达台与 CSS：修复【闪烁污染】并隔离涟漪特效..."

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
  background-color: #f8fafc;
  overflow-x: hidden;
  color: #1e293b;
}

body::before {
  content: '';
  position: fixed;
  top: 0; left: 0; right: 0; bottom: 0;
  background: 
    radial-gradient(circle at var(--fluid-x) var(--fluid-y), rgba(147, 197, 253, 0.4) 0%, transparent 40%),
    radial-gradient(circle at 20% 80%, rgba(196, 181, 253, 0.3) 0%, transparent 50%),
    radial-gradient(circle at 80% 20%, rgba(167, 243, 208, 0.3) 0%, transparent 50%);
  z-index: -1;
  transition: background 0.1s ease-out;
  pointer-events: none;
}

.glass-panel {
  background: rgba(255, 255, 255, 0.75) !important;
  backdrop-filter: blur(20px) saturate(150%) !important;
  -webkit-backdrop-filter: blur(20px) saturate(150%) !important;
  border: 1px solid rgba(255, 255, 255, 0.9) !important;
  box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.06) !important;
}

.glass-hover-fx {
  transition: all 0.4s cubic-bezier(0.25, 0.8, 0.25, 1);
}
.glass-hover-fx:hover {
  background: rgba(255, 255, 255, 0.95) !important;
  transform: translateY(-2px);
  box-shadow: 0 15px 35px rgba(56, 189, 248, 0.12) !important;
}

/* ================= 物理水波特效区 ================= */

.wave-trail {
  position: fixed;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(96, 165, 250, 0.4) 0%, rgba(147, 197, 253, 0) 70%);
  pointer-events: none;
  transform: translate(-50%, -50%) scale(0.2);
  animation: waveTrailAnim 1.2s ease-out forwards;
  z-index: -1;
}
@keyframes waveTrailAnim {
  0% { transform: translate(-50%, -50%) scale(0.2); opacity: 0.8; }
  100% { transform: translate(-50%, -50%) scale(3); opacity: 0; }
}

/* 【核心修复】：缩小点击时的涟漪系数，彻底消除巨型圆圈造成的闪屏感 */
.mouse-ripple {
  position: absolute;
  border-radius: 50%;
  transform: scale(0);
  animation: clickRipple 0.6s ease-out;
  background-color: rgba(59, 130, 246, 0.15); 
  pointer-events: none;
  z-index: 50;
}
@keyframes clickRipple {
  to { transform: scale(2.5); opacity: 0; } /* 从 10 倍缩小到 2.5 倍，确保波纹在按钮内部荡漾 */
}
EOF

cat << 'EOF' > "$FRONTEND_DIR/src/components/SearchLead.jsx"
import React, { useState } from 'react';
import axios from 'axios';
import { Search, Loader2, Database, MapPin, Globe, FileText } from 'lucide-react';
import { useStore } from '../store';

export default function SearchLead() {
  const { setLoading, setResult, setError, loading } = useStore();
  
  const [formData, setFormData] = useState({
    companyName: '',
    address: '',
    website: '',
    profile: ''
  });

  const handleChange = (e) => {
    setFormData({ ...formData, [e.target.name]: e.target.value });
  };

  const handleSearch = async () => {
    if (!formData.companyName.trim()) {
      setError('公司全称必须填写！');
      return;
    }
    setLoading(true);
    setError(null);
    setResult(null);

    try {
      const response = await axios.post('/api/search', formData);
      setResult(response.data.data);
    } catch (err) {
      setError(err.response?.data?.message || '服务器连接失败');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-4xl mx-auto p-4 mt-6 animate-fade-in font-sans">
      {/* 【核心修复】：移除了大卡片上的 onMouseDown 涟漪事件，彻底告别误触闪屏 */}
      <div className="glass-panel rounded-2xl shadow-xl p-6 md:p-8 border-t-4 border-blue-500 relative z-10 overflow-hidden">
        <div className="text-center mb-8 relative z-10">
          <h2 className="text-3xl font-black text-gray-800 tracking-tight flex items-center justify-center gap-2">
            <Database className="text-blue-600" size={32}/> 人机协同精准雷达
          </h2>
          <p className="text-gray-500 mt-2 font-medium">输入确切企业底牌，AI 定向深潜全网与目标官网，挖掘硬核产品线</p>
        </div>

        <div className="space-y-5 relative z-10">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
            <div className="space-y-1.5 md:col-span-2">
              <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><Search size={14} className="text-blue-500"/> 目标公司全称 <span className="text-red-500">*</span></label>
              <input type="text" name="companyName" value={formData.companyName} onChange={handleChange} placeholder="请输入目标企业完整全称，例：深圳市某某智能科技有限公司" className="w-full p-4 bg-white/80 border border-gray-200 shadow-sm rounded-xl focus:ring-2 focus:ring-blue-500 outline-none font-black text-gray-900 text-lg placeholder-gray-400 transition-all backdrop-blur-sm" />
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><MapPin size={14} className="text-red-500"/> 注册/办公地址 (用于地图作战标点)</label>
              <input type="text" name="address" value={formData.address} onChange={handleChange} placeholder="例：广东省深圳市南山区某某大道某某大厦" className="w-full p-3 bg-white/80 border border-gray-200 shadow-sm rounded-lg focus:ring-2 focus:ring-blue-500 outline-none font-bold text-gray-800 placeholder-gray-400 transition-all backdrop-blur-sm" />
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><Globe size={14} className="text-teal-500"/> 官方网站 (AI 将定向潜入该网站抓取)</label>
              <input type="text" name="website" value={formData.website} onChange={handleChange} placeholder="例：[www.example.com](https://www.example.com)" className="w-full p-3 bg-white/80 border border-gray-200 shadow-sm rounded-lg focus:ring-2 focus:ring-blue-500 outline-none font-bold text-gray-800 placeholder-gray-400 transition-all backdrop-blur-sm" />
            </div>
          </div>
          <div className="space-y-1.5">
            <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><FileText size={14} className="text-purple-500"/> 工商经营范围 / 企业简介 (极其重要)</label>
            <textarea name="profile" value={formData.profile} onChange={handleChange} rows="3" placeholder="请将企查查/天眼查中的【经营范围】直接粘贴至此。AI 将结合此范围与官网数据，实施像素级精准推演..." className="w-full p-4 bg-white/80 border border-gray-200 shadow-sm rounded-xl focus:ring-2 focus:ring-blue-500 outline-none font-bold text-gray-800 placeholder-gray-400 text-sm leading-relaxed transition-all resize-none backdrop-blur-sm"></textarea>
          </div>

          {/* 【核心保留】：波纹只保留在按钮上，且由于 scale 缩小，波纹会完美限制在按钮内部 */}
          <button 
            onMouseDown={(e) => window.createRipple && window.createRipple(e, e.currentTarget)}
            onClick={handleSearch} 
            disabled={loading} 
            className="w-full mt-6 bg-gradient-to-r from-blue-600 to-indigo-600 text-white font-black text-lg p-4 rounded-xl shadow-lg hover:shadow-2xl hover:scale-[1.01] transition-all flex items-center justify-center gap-2 disabled:opacity-70 disabled:scale-100 disabled:cursor-not-allowed border border-blue-400/50 relative overflow-hidden"
          >
            {loading ? <><Loader2 className="animate-spin" size={24} /> 探针全网深潜中，这需要一点时间...</> : <><Search size={24} /> 提交底牌并开始深挖产品</>}
          </button>
        </div>
      </div>
    </div>
  );
}
EOF

echo ">>> 3. 全面编译渲染前端与重启后台接口..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ 雷达台闪屏彻底消灭！全网强力找图引擎已加载！"
echo "========================================================="
