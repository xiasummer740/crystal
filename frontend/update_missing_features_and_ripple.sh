#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"
FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在重构后端检索引擎：恢复【生产/销售鉴别】与【抓取/推演溯源】指令..."

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

        // 【核心恢复】：强制要求进行 类型判定 和 真实性溯源打标！
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

【核心找回指令】：
1. **类型判别**：在 \`type\` 字段中，必须根据其“工商范围”明确判定。如果是研发、制造，则必须标注 **[生产制造型]**；如果是代理、批发、纯销售，则必须标注 **[贸易销售型]**。
2. **防偷懒提取与溯源打标**：在 \`products.name\` 字段中，必须把你看到的所有硬件产品全部列出来（不低于6个，若有）。**并且名字前必须加上标签**：如果是从爬虫数据里看到的，加上 \`[真实抓取]\`；如果是你根据范围强行推演的，加上 \`[AI推演]\`。
3. **决策人宁缺毋滥**：如果确实找不到人名，请将 keyContacts 设为空数组 []。
4. **芯片必须推演**：如果没抓到具体芯片，你必须强行推演一套合理的芯片架构组合。

输出严格JSON:
{
  "company": "${companyName}",
  "website": "${website || '未查明'}",
  "address": "整理输出详细地址",
  "coordinates": [纬度, 经度],
  "type": "精准业务类型 (必须带有 [生产制造型] 或 [贸易销售型] 后缀)",
  "profile": "硬核企业背景分析（不少于350字）。",
  "keyContacts": [
    {"name": "真实姓名(未查明则置空数组)", "title": "职务", "contact": "联系方式", "context": "线索来源"}
  ],
  "commonChipPlatforms": [
    {"brand": "品牌", "model": "型号", "application": "应用场景"}
  ],
  "products": [
    {
      "name": "[真实抓取]或[AI推演] 具体设备名称",
      "chipPlatform": "详细的芯片架构组合(绝不允许填未知！必须详细写出！)",
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

echo ">>> 2. 正在重构前端 UI：为雷达台加装 overflow-hidden 结界，修复闪屏..."

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
      {/* 【核心修复】：加入 overflow-hidden，防止内部波纹扩散至卡片外导致闪屏 */}
      <div className="glass-panel rounded-2xl shadow-xl p-6 md:p-8 border-t-4 border-blue-500 relative z-10 overflow-hidden" onMouseDown={(e) => window.createRipple && window.createRipple(e, e.currentTarget)}>
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

          <button onClick={handleSearch} disabled={loading} className="w-full mt-6 bg-gradient-to-r from-blue-600 to-indigo-600 text-white font-black text-lg p-4 rounded-xl shadow-lg hover:shadow-2xl hover:scale-[1.01] transition-all flex items-center justify-center gap-2 disabled:opacity-70 disabled:scale-100 disabled:cursor-not-allowed border border-blue-400/50 relative z-20">
            {loading ? <><Loader2 className="animate-spin" size={24} /> 探针全网深潜中，这需要一点时间...</> : <><Search size={24} /> 提交底牌并开始深挖产品</>}
          </button>
        </div>
      </div>
    </div>
  );
}
EOF

echo ">>> 3. 全面编译生效前台并重启后台引擎..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ 雷达台防溢出修复完毕！真实/推演标签 与 生产/销售标识王者归来！"
echo "========================================================="
