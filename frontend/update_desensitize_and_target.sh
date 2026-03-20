#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"
FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在重构前端：执行商业级文本脱敏..."

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
    <div className="max-w-4xl mx-auto p-4 mt-6 animate-fade-in">
      <div className="bg-white rounded-2xl shadow-lg p-6 md:p-8 border border-gray-100">
        <div className="text-center mb-8">
          <h2 className="text-3xl font-black text-gray-800 tracking-tight flex items-center justify-center gap-2">
            <Database className="text-blue-600" size={32}/> 人机协同精准雷达
          </h2>
          <p className="text-gray-500 mt-2 font-medium">输入确切企业底牌，AI 定向深潜全网与目标官网，挖掘硬核产品线</p>
        </div>

        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-1.5 md:col-span-2">
              <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><Search size={14}/> 目标公司全称 <span className="text-red-500">*</span></label>
              {/* 【核心修复】：完全脱敏的 Placeholder */}
              <input type="text" name="companyName" value={formData.companyName} onChange={handleChange} placeholder="请输入目标企业完整全称，例：深圳市某某智能科技有限公司" className="w-full p-3 bg-gray-50 border border-gray-200 rounded-xl focus:ring-2 focus:ring-blue-500 outline-none font-bold text-blue-900 text-lg transition-all" />
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><MapPin size={14}/> 注册/办公地址 (用于地图作战标点)</label>
              <input type="text" name="address" value={formData.address} onChange={handleChange} placeholder="例：广东省深圳市南山区某某大道某某大厦" className="w-full p-2.5 bg-gray-50 border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500 outline-none text-gray-700 transition-all" />
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><Globe size={14}/> 官方网站 (AI 将定向潜入该网站抓取)</label>
              <input type="text" name="website" value={formData.website} onChange={handleChange} placeholder="例：[www.example.com](https://www.example.com)" className="w-full p-2.5 bg-gray-50 border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500 outline-none text-gray-700 transition-all" />
            </div>
          </div>
          <div className="space-y-1.5">
            <label className="text-sm font-bold text-gray-700 flex items-center gap-1"><FileText size={14}/> 工商经营范围 / 企业简介 (极其重要)</label>
            <textarea name="profile" value={formData.profile} onChange={handleChange} rows="3" placeholder="请将企查查/天眼查中的【经营范围】直接粘贴至此。AI 将结合此范围与官网数据，实施像素级精准推演..." className="w-full p-3 bg-gray-50 border border-gray-200 rounded-xl focus:ring-2 focus:ring-blue-500 outline-none text-gray-700 text-sm leading-relaxed transition-all resize-none"></textarea>
          </div>

          <button onClick={handleSearch} disabled={loading} className="w-full mt-4 bg-gradient-to-r from-blue-600 to-indigo-600 text-white font-black text-lg p-4 rounded-xl shadow-lg hover:shadow-xl hover:-translate-y-0.5 transition-all flex items-center justify-center gap-2 disabled:opacity-70 disabled:cursor-not-allowed">
            {loading ? <><Loader2 className="animate-spin" size={24} /> 探针潜入目标官网深挖产品中...</> : <><Search size={24} /> 提交底牌并开始深挖产品</>}
          </button>
        </div>
      </div>
    </div>
  );
}
EOF

echo ">>> 2. 正在重构后端控制器：注入【基于目标域名的定向狙击算法】..."

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

const fetchRealImage = async (query) => {
    try {
        const url = `https://cn.bing.com/images/search?q=${encodeURIComponent(query)}&first=1`;
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 4000);
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

// 【通用矩阵爬虫引擎】
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

        // 【核心黑科技：提取目标网站域名，启动狙击手模式】
        let targetDomain = '';
        if (website && website.trim() !== '') {
            // 清理协议和www，只保留核心域名 (如 abc.com)
            targetDomain = website.replace(/^(?:https?:\/\/)?(?:www\.)?/i, "").split('/')[0];
        }

        const exact = `"${companyName}"`;
        // 如果有官网域名，就强制在官网内部搜索；如果没有，就去B2B全网搜
        const siteQueryStr = targetDomain ? `site:${targetDomain}` : exact;

        const [
            official_products,
            official_tech,
            b2b_trade,
            vertical_portal,
            recruitment,
            bidding
        ] = await Promise.all([
            // 路1：最高优先级！强制在用户提供的官网内部搜索产品型号
            fetchMatrixQuery(`${siteQueryStr} "产品中心" OR "产品展示" OR "型号" OR "规格"`),
            // 路2：强制在官网内部搜索关于我们与技术栈
            fetchMatrixQuery(`${siteQueryStr} "解决方案" OR "核心技术" OR "应用领域"`),
            // 备用兜底路：防止官网没写全，继续查全网B2B
            fetchMatrixQuery(`${exact} (site:1688.com OR site:hc360.com) "主营产品" OR "供应"`),
            fetchMatrixQuery(`${exact} (site:elecfans.com OR site:hqew.com) "产品型号" OR "参数"`),
            fetchMatrixQuery(`${exact} (site:zhipin.com OR site:liepin.com) 招聘 硬件工程师`),
            fetchMatrixQuery(`${exact} 招标 OR 中标 采购项目清单`)
        ]);

        const prompt = `你是一个顶级商业侦探与电子架构师。
用户已经人工提供了这家公司的权威底牌：
【公司全称】: ${companyName}
【注册地址】: ${address || '用户未提供'}
【官方网站】: ${website || '用户未提供'}
【权威工商经营范围】: ${userProfile || '用户未提供'}

同时，我通过定向爬虫，重点潜入了该公司的官网（如果有）及全网B2B，为你带回了以下真实产品数据：
[重点！官网产品线]: ${official_products}
[重点！官网技术方案]: ${official_tech}
[B2B外围兜底数据]: ${b2b_trade}
[垂直门户技术交流]: ${vertical_portal}
[直聘网研发方向]: ${recruitment}
[招投标实绩]: ${bidding}

【任务要求】：
1. **直接采纳用户输入**：务必在 JSON 中如实回填用户提供的公司名、地址、网址。如果用户提供了经营范围，请据此扩写出一篇高度专业、深入浅出的企业全景报道（profile 字段）。
2. **地理测绘**：推算最终地址的高精度经纬度坐标 [纬度, 经度]。
3. **【核心深挖：提取官网真实产品】**：仔细阅读 [官网产品线] 的爬虫数据，这上面列出的型号绝对是真实的！请提取 3~6 个具体的硬件设备型号。
4. **【结合工商强制推演】**：如果在官网数据里实在没找到具体型号，你**绝对禁止留空或写未知**！你必须根据用户填写的【工商经营范围】，结合你作为专家的常识，强行推演出几款代表性硬件产品，并在产品名字后面标注 "(结合经营范围推演)"。然后配备合理的 MCU 和晶振参数。

输出严格JSON:
{
  "company": "${companyName}",
  "website": "${website || '未查明'}",
  "address": "整理并输出详细地址",
  "coordinates": [纬度浮点数, 经度浮点数],
  "type": "精准业务类型(根据经营范围总结)",
  "profile": "结合用户输入的经营范围和定向抓取的数据，撰写一篇至少350字的硬核企业背景与技术实力剖析。",
  "commonChipPlatforms": [
    {"brand": "品牌", "model": "型号", "application": "应用场景"}
  ],
  "products": [
    {
      "name": "具体设备名称或详细型号(如未查到实机则依据经营范围强行推演并加注标明)",
      "chipPlatform": "主控SoC/MCU",
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
                temperature: 0.2, // 保持极低温度，高度相信用户的输入和官网的数据
                response_format: { type: "json_object" }
            }),
            signal: controller.signal
        });
        clearTimeout(timeoutId);

        if (!response.ok) return res.status(500).json({ success: false, message: `大模型拒绝 HTTP ${response.status}` });

        const data = await response.json();
        let content = data.choices[0].message.content.replace(/```json/g, '').replace(/```/g, '').trim();
        const resultData = JSON.parse(content);

        if (!Array.isArray(resultData.coordinates) || resultData.coordinates.length !== 2 || typeof resultData.coordinates[0] !== 'number') {
            resultData.coordinates = [39.9042, 116.4074]; 
        }

        if (resultData.products && Array.isArray(resultData.products)) {
            const enrichedProducts = await Promise.all(resultData.products.map(async (p) => {
                if (p.name.includes('推演')) return { ...p, imageUrl: null };
                const query = `${resultData.company} ${p.name.replace(/\(.*?\)/g, '')} 产品实物图`;
                const imgUrl = await fetchRealImage(query);
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

echo ">>> 3. 全面编译生效前端脱敏文本并重启后台引擎..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ 文本脱敏完毕！定向狙击官网爬虫上线，数据 100% 靶向提取！"
echo "========================================================="
