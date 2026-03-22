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

const scrapeDirectSite = async (website, domain) => {
    let content = "";
    let urlsToTry = [];
    if (website && website.trim() !== '' && website !== '未查明') {
        const cleanWeb = website.startsWith('http') ? website : `http://${website}`;
        urlsToTry.push(cleanWeb);
    }
    if (domain) {
        urlsToTry.push(`http://www.${domain}/product`);
        urlsToTry.push(`http://www.${domain}/products`);
        urlsToTry.push(`https://www.${domain}`);
    }

    for (let u of urlsToTry) {
        try {
            const controller = new AbortController();
            const id = setTimeout(() => controller.abort(), 6000); 
            const res = await fetch(u, { 
                headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}, 
                signal: controller.signal,
                redirect: 'follow'
            });
            clearTimeout(id);
            if (res.ok) {
                let html = await res.text();
                if (html.length > 1000000) html = html.substring(0, 1000000);
                const $ = cheerio.load(html);
                let imgContext = "\n【官网图库】:\n";
                let imgCount = 0;
                
                $('img, [style*="background"]').each((i, el) => {
                    let src = $(el).attr('data-src') || $(el).attr('data-original') || $(el).attr('data-lazy-src') || $(el).attr('v-lazy') || $(el).attr('src');
                    if (!src) {
                        let style = $(el).attr('style');
                        if (style) {
                            let bgMatch = style.match(/url\(['"]?(.*?)['"]?\)/);
                            if (bgMatch) src = bgMatch[1];
                        }
                    }
                    if (src && !src.startsWith('data:image') && imgCount < 50) {
                        try {
                            src = new URL(src, u).href; 
                            let alt = $(el).attr('alt') || '';
                            let pText = $(el).parent().text().replace(/\s+/g, ' ').trim().substring(0, 30);
                            let cText = `${alt} ${pText}`.trim();
                            if (cText.length > 2) {
                                imgContext += `[图:${src} | 旁白:${cText}]\n`;
                                imgCount++;
                            }
                        } catch(e) {}
                    }
                });
                $('script, style, noscript, nav, footer, header').remove();
                let text = $('body').text().replace(/\s+/g, ' ').trim();
                if (text.length > 100 || imgCount > 0) {
                    content += `[来源: ${u}]\n` + text.substring(0, 3000) + "\n" + imgContext;
                    break; 
                }
            }
        } catch(e) {}
    }
    return content.substring(0, 8000); 
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
    res.setHeader('X-Accel-Buffering', 'no');
    res.flushHeaders();
    const sendEvent = (data) => { try { res.write(`data: ${JSON.stringify(data)}\n\n`); } catch (e) {} };

    try {
        const { companyName, address, website, profile: userProfile } = req.body;
        if (!companyName) { sendEvent({ error: '请输入公司名称' }); return res.end(); }
        if (!fs.existsSync(configPath)) { sendEvent({ error: '请配置API' }); return res.end(); }
        const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));

        let targetDomain = website ? website.replace(/^(?:https?:\/\/)?(?:www\.)?/i, "").split('/')[0] : '';
        const exact = `"${companyName}"`;

        sendEvent({ status: '启动高精雷达：正在潜入目标官网抓取图文矩阵...' });

        const [ direct_html_data, official_tech, b2b_trade ] = await Promise.all([
            scrapeDirectSite(website, targetDomain), 
            fetchMatrixQuery(`${targetDomain ? `site:${targetDomain}` : exact} "解决方案"`),
            fetchMatrixQuery(`${exact} "主营产品"`)
        ]);

        sendEvent({ status: '官网底层特征抽取完毕，AI神经元正在进行降维重组...' });

        // 【核心修复】：追加最高强制约束，最多15款！
        const prompt = `你是顶级商业侦探。目标：【${companyName}】。
【官网底层数据】：${direct_html_data || "无"}
[技术]: ${official_tech}
[B2B]: ${b2b_trade}

【安全限流与极速输出铁律】：
1. 提取所有发现的【具体设备型号】。**【最高警告】：为了防止输出超载截断，最多只允许提取前 15 款最具代表性的产品！绝不允许超过15款！**
2. 绝对图文匹配：提取产品时，必须去【官网图库】寻找。若图的旁白包含该型号，立刻把URL填入 \`imageUrl\`，没找到填 ""。
3. 晶振 function 必须包含：为什么需要它...如果没有它...
4. 确保 JSON 完全闭合！

输出JSON:
{
  "company": "${companyName}",
  "website": "${website || '未查明'}",
  "address": "整理输出",
  "coordinates": [纬度, 经度],
  "type": "精准业务类型",
  "profile": "硬核企业分析",
  "commonChipPlatforms": [{"brand": "品牌", "model": "型号", "application": "应用场景"}],
  "products": [
    {
      "name": "[真实抓取] 具体设备型号",
      "imageUrl": "官网原图URL (没有填空字符串)",
      "chipPlatform": "芯片架构组合",
      "crystals": [{"freq": "频率", "package": "封装", "loadCap": "电容", "tolerance": "频偏", "function": "包含：为什么需要它...如果没有它..."}]
    }
  ],
  "strategy": "销售策略"
}`;

        let safeBaseUrl = config.baseUrl || getUrl('aHR0cHM6Ly9hcGkuZGVlcHNlZWsuY29t');
        safeBaseUrl = safeBaseUrl.replace(/[\[\]\(\)]/g, '').split(' ')[0].trim().replace(/\/+$/, '');
        
        const response = await fetch(`${safeBaseUrl}/chat/completions`, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${(config.apiKey || '').trim()}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model: (config.model || '').trim() || 'deepseek-chat',
                messages: [{ role: "user", content: prompt }],
                temperature: 0.2, 
                max_tokens: 6000, 
                stream: true 
            }),
            signal: AbortSignal.timeout(180000)
        });

        if (!response.ok) { sendEvent({ error: `大模型拒绝 (HTTP ${response.status})` }); return res.end(); }

        sendEvent({ status: '大模型图文缝合中，正在为您渲染顶级数据报告...' });

        let fullJsonStr = '';
        const decoder = new TextDecoder('utf-8');
        for await (const chunk of response.body) {
            const lines = decoder.decode(chunk, { stream: true }).split('\n');
            for (const line of lines) {
                if (line.startsWith('data: ') && line.trim() !== 'data: [DONE]') {
                    try {
                        const parsed = JSON.parse(line.slice(6));
                        const content = parsed.choices[0]?.delta?.content || '';
                        if (content) fullJsonStr += content;
                    } catch(e) {}
                }
            }
        }

        sendEvent({ status: '清洗数据骨架，即将点亮雷达...' });
        
        let cleanStr = fullJsonStr.replace(/```json/gi, '').replace(/```/g, '').trim();
        const firstBrace = cleanStr.indexOf('{');
        const lastBrace = cleanStr.lastIndexOf('}');
        if (firstBrace !== -1 && lastBrace !== -1) cleanStr = cleanStr.substring(firstBrace, lastBrace + 1);

        let resultData;
        try {
            resultData = JSON.parse(cleanStr);
        } catch (e) {
            sendEvent({ error: "由于数据过于庞大，底层引擎进行安全截断。请重新点击检索！" });
            return res.end();
        }

        if (!Array.isArray(resultData.coordinates) || resultData.coordinates.length !== 2) resultData.coordinates = [39.9042, 116.4074]; 

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
