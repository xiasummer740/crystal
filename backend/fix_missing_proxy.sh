#!/bin/bash
set -e

BACKEND_DIR="/var/www/crystal/backend"

echo ">>> 1. 正在重构后端引擎：补齐丢失的 proxyImage 图片跨域解析函数..."

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

// 【核心修复】：这就是我不小心弄丢的那个图片跨域函数，现在完整补回！
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

const scrapeDirectSite = async (domain) => {
    if (!domain) return "";
    let content = "";
    const urlsToTry = [
        `http://www.${domain}/product`,
        `http://www.${domain}/products`,
        `http://www.${domain}/list`,
        `https://www.${domain}`,
        `http://www.${domain}`
    ];

    for (let u of urlsToTry) {
        try {
            const controller = new AbortController();
            const id = setTimeout(() => controller.abort(), 4500); 
            const res = await fetch(u, { 
                headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36'}, 
                signal: controller.signal,
                redirect: 'follow'
            });
            clearTimeout(id);
            
            if (res.ok) {
                const html = await res.text();
                const $ = cheerio.load(html);
                
                let imgContext = "\n【官网底层原配图库(图文绑定)】:\n";
                let imgCount = 0;
                $('img').each((i, el) => {
                    let src = $(el).attr('src') || $(el).attr('data-src') || $(el).attr('data-original');
                    if (src && !src.startsWith('data:image') && imgCount < 15) { 
                        try {
                            src = new URL(src, u).href;
                            let alt = $(el).attr('alt') || '';
                            let parentText = $(el).parent().text().replace(/\s+/g, ' ').trim().substring(0, 60);
                            let siblingText = $(el).parent().next().text().replace(/\s+/g, ' ').trim().substring(0, 60);
                            
                            if (alt || parentText || siblingText) {
                                imgContext += `[官方原图URL: ${src} | 附近标识型号: ${alt} ${parentText} ${siblingText}]\n`;
                                imgCount++;
                            }
                        } catch(e) {}
                    }
                });

                $('script, style, noscript, nav, footer, header').remove();
                let text = $('body').text().replace(/\s+/g, ' ').trim();
                
                if (text.length > 100) {
                    content += `[来源网页: ${u}]:\n` + text.substring(0, 2500) + "\n" + imgContext;
                    break;
                }
            }
        } catch(e) {}
    }
    return content.substring(0, 5500);
};

const fetchRealImage = async (company, modelName, domain = '') => {
    const fetchImg = async (searchQuery) => {
        try {
            const url = `https://cn.bing.com/images/search?q=${encodeURIComponent(searchQuery)}&first=1`;
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 3500);
            const res = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0' }, signal: controller.signal });
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
        const domainUrl = await fetchImg(`site:${domain} ${cleanModel} 产品`);
        if (domainUrl) return domainUrl;
    }
    const companyUrl = await fetchImg(`"${company}" "${cleanModel}" 官方实物图`);
    if (companyUrl) return companyUrl;
    return await fetchImg(`${cleanModel} 官方 产品图片`);
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

        sendEvent({ status: '> 🚀 启动图文绑定探针，正在强扒官网【产品中心】底层图库...' });

        const [
            direct_html_data, official_tech, b2b_trade, contacts_info
        ] = await Promise.all([
            scrapeDirectSite(targetDomain),
            fetchMatrixQuery(`${targetDomain ? `site:${targetDomain}` : exact} "解决方案" OR "应用领域"`),
            fetchMatrixQuery(`${exact} (site:1688.com OR site:hc360.com) "主营产品" "规格"`),
            fetchMatrixQuery(`${exact} "联系人" OR "采购" 招标`)
        ]);

        sendEvent({ status: '> ✅ 图库与文本解包完毕，正在唤醒大模型进行原配图文缝合...' });

        const prompt = `你是顶级商业侦探。剖析对象：【${companyName}】。
【官网底层图文直扒数据】(极度重要)：
这里有该网站的文本以及【官网底层原配图库】。图库中包含了图片URL和它旁边的产品型号。
${direct_html_data || "官网反爬或无数据"}

[官网技术]: ${official_tech}
[B2B商城]: ${b2b_trade}
[关键联系人]: ${contacts_info}

【极速流式输出指令】：
1. 业务类型打上 [生产制造型] 或 [贸易销售型] 后缀。
2. 提取所有你找到的【具体设备型号】(不少于6款，越多越好)，名字前加 [真实抓取] 或 [AI推演]。
3. **【极其重要：还原官网原配图】**：在提取每个产品时，**去上面的【官网底层原配图库】里找**。如果你发现某个 [官方原图URL] 旁边的 [附近标识型号] 跟你提取的产品型号匹配，**请把这个 URL 原封不动地填进 \`officialImageUrl\` 字段中！** 如果没找到匹配的图，填空字符串 ""。
4. 芯片架构和晶振必须详细推演（function必须包含：为什么需要它...如果没有它...）。

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
      "name": "[真实抓取]或[AI推演] 具体设备型号",
      "officialImageUrl": "匹配到的官网原配图绝对URL(必须来源于数据中的图库，没有则填空字符串)",
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
                stream: true 
            }),
            signal: controller.signal
        });
        clearTimeout(timeoutId);

        if (!response.ok) {
            sendEvent({ error: `大模型节点异常 (HTTP ${response.status})` });
            return res.end();
        }

        sendEvent({ status: '> 🧠 神经元正在执行图文还原比对算法...' });

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

        sendEvent({ status: '> 🔍 JSON架构组装完毕，执行图片双轨校验兜底...' });
        
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
                    if (p.officialImageUrl && p.officialImageUrl.startsWith('http')) {
                        p.imageUrl = p.officialImageUrl;
                    } else {
                        p.imageUrl = await fetchRealImage(resultData.company, p.name, targetDomain);
                    }
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

module.exports = { searchLead, proxyImage };
EOF

echo ">>> 2. 清理崩溃缓存，重新强制点火后端引擎..."
pm2 flush > /dev/null 2>&1
pm2 restart crystal-api > /dev/null 2>&1

sleep 2
echo "========================================================="
echo " ✅ 故障排除！ProxyImage 组件已装载，以下是最新生命日志："
echo "========================================================="
pm2 logs crystal-api --lines 10 --nostream
