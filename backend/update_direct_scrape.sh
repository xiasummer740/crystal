#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"

echo ">>> 1. 正在重构后端检索引擎：注入【官网物理直连源码抓取 (Direct Scrape)】探针..."

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

// 【核心破壁 1】：官网物理直连探针。不依赖搜索引擎，直接抓取目标网站源码！
const scrapeDirectSite = async (domain) => {
    if (!domain) return "";
    let content = "";
    // 尝试抓取首页和产品中心页
    const urlsToTry = [
        `http://www.${domain}`, 
        `https://www.${domain}`, 
        `http://www.${domain}/product`,
        `http://www.${domain}/products`
    ];

    for (let u of urlsToTry) {
        try {
            const controller = new AbortController();
            const id = setTimeout(() => controller.abort(), 4000); // 单个页面最多等4秒
            const res = await fetch(u, { 
                headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'}, 
                signal: controller.signal,
                redirect: 'follow'
            });
            clearTimeout(id);
            if (res.ok) {
                const html = await res.text();
                const $ = cheerio.load(html);
                // 剔除无用的脚本、样式和页脚，只保留核心文字内容
                $('script, style, noscript, nav, footer, header').remove();
                let text = $('body').text().replace(/\s+/g, ' ').trim();
                if (text.length > 200) {
                    content += `[来源URL: ${u} 源码提取]: ` + text.substring(0, 3000) + " | \n";
                    break; // 只要成功抓到一个含有大量内容的页面，就跳出循环，加快速度
                }
            }
        } catch(e) { 
            // 忽略目标网站拒绝连接的报错，继续尝试下一个URL
        }
    }
    return content.substring(0, 6000); // 最多只截取前 6000 字防止大模型爆显存
};

// 【图片高容错嗅探】：放宽匹配条件，只要有图就抓
const fetchRealImage = async (company, modelName, domain = '') => {
    const fetchImg = async (searchQuery) => {
        try {
            const url = `https://cn.bing.com/images/search?q=${encodeURIComponent(searchQuery)}&first=1`;
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 3500);
            const res = await fetch(url, { 
                headers: { 'User-Agent': 'Mozilla/5.0' }, 
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
    
    // 轨道 1：强搜官网图库
    if (domain) {
        const domainUrl = await fetchImg(`site:${domain} ${cleanModel}`);
        if (domainUrl) return domainUrl;
    }
    
    // 轨道 2：公司名+型号强匹配
    const companyUrl = await fetchImg(`"${company}" "${cleanModel}" 产品图`);
    if (companyUrl) return companyUrl;
    
    // 轨道 3：全网盲抓型号（最高容错率）
    return await fetchImg(`${cleanModel} 官方 产品 设备 实物`);
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

        sendEvent({ status: '> 🚀 启动双引擎：正在物理直连强扒官网源码，同步发射必应探针...' });

        // 【核心破壁 2】：同时发动物理直连和搜索引擎！
        const [
            direct_html_data,
            official_products, official_tech, b2b_trade, recruitment, contacts_info
        ] = await Promise.all([
            scrapeDirectSite(targetDomain), // 直接扒取目标网站HTML！
            fetchMatrixQuery(`${targetDomain ? `site:${targetDomain}` : exact} "产品中心" OR "型号"` , 8),
            fetchMatrixQuery(`${targetDomain ? `site:${targetDomain}` : exact} "解决方案" OR "技术架构"`),
            fetchMatrixQuery(`${exact} (site:1688.com OR site:hc360.com) "主营产品" "规格"`),
            fetchMatrixQuery(`${exact} 招聘 硬件工程师 OR 研发`),
            fetchMatrixQuery(`${exact} "联系人" OR "采购" OR "邮箱" 招标`)
        ]);

        sendEvent({ status: '> ✅ 物理源码提取完毕，正在唤醒大模型进行精准解析...' });

        const prompt = `你是顶级商业侦探。剖析对象：【${companyName}】。
底牌：【地址】: ${address} | 【网址】: ${website} | 【工商范围】: ${userProfile}

【重点！官网底层物理源码直扒数据】：
这段数据是我们直接黑进该网站首页抓取的纯文本。请你**极其仔细**地阅读这段数据，里面藏着最真实的产品型号！
${direct_html_data || "官网反爬太强，源码提取失败，请参考下方搜索数据。"}

【全网搜索引擎探针数据】：
[搜索引擎-官网产品]: ${official_products}
[搜索引擎-官网技术]: ${official_tech}
[B2B商城供货]: ${b2b_trade}
[招聘需求]: ${recruitment}
[关键联系人]: ${contacts_info}

【极速流式输出核心指令】：
1. 业务类型打上 [生产制造型] 或 [贸易销售型] 后缀。
2. 仔细阅读【官网底层物理源码直扒数据】和【搜索引擎-官网产品】。**把所有明确提到的具体设备型号全部提取出来（不少于6款，尽可能多）**，并在名字前加 [真实抓取] 或 [AI推演]。绝不要自己编造不存在的假名字！
3. 芯片架构和晶振必须详细推演。在 crystals 的 function 字段中，必须分两句话：“为什么需要它：...”以及“如果没有它：...”。
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
      "name": "[真实抓取] 具体设备名称及官方型号 (若为推演则标[AI推演])",
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
        const timeoutId = setTimeout(() => controller.abort(), 120000); 
        
        const response = await fetch(targetUrl, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${(config.apiKey || '').trim()}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model: (config.model || '').trim() || 'deepseek-chat',
                messages: [{ role: "user", content: prompt }],
                temperature: 0.1, // 降到极低温度，强迫大模型照抄源码里的产品型号，禁止发散想象
                stream: true 
            }),
            signal: controller.signal
        });
        clearTimeout(timeoutId);

        if (!response.ok) {
            sendEvent({ error: `大模型节点异常 (HTTP ${response.status})` });
            return res.end();
        }

        sendEvent({ status: '> 🧠 AI神经元对接成功，开始实时解析底层源码...' });

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

        sendEvent({ status: '> 🔍 型号提取完毕，正在唤醒全网高敏实物图鉴匹配引擎...' });
        
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

echo ">>> 2. 重启底层接口，物理直连爬虫上线..."
cd "$BACKEND_DIR"
pm2 flush > /dev/null
pm2 restart crystal-api > /dev/null

echo "========================================================="
echo " ✅ 物理直连官网源码探针 & 图片高敏引擎 挂载完毕！"
echo "========================================================="
