const fs = require('fs');
const path = require('path');
const cheerio = require('cheerio');
const configPath = path.join(__dirname, '../config/llm.json');

const getUrl = (b64) => Buffer.from(b64, 'base64').toString('utf8');

/**
 * JSON 修复器：处理 AI 输出中常见的格式问题
 */
function repairJSON(str) {
    let s = str.trim();
    // 移除 markdown 代码块标记
    s = s.replace(/^```json\s*/i, '').replace(/```\s*$/g, '').trim();
    // 提取最外层 { ... } 对象
    const firstBrace = s.indexOf('{');
    const lastBrace = s.lastIndexOf('}');
    if (firstBrace === -1 || lastBrace === -1) return null;
    s = s.substring(firstBrace, lastBrace + 1);
    // 修复尾部逗号（最常见错误）
    s = s.replace(/,(\s*[}\]])/g, '$1');
    // 修复缺失引号的 key（单引号 key 或裸 key）
    s = s.replace(/([{,]\s*)(\w+)(\s*:)/g, '$1"$2"$3');
    // 修复单引号值
    s = s.replace(/:\s*'([^']*)'/g, ':"$1"');
    return s;
}

/**
 * 安全解析 JSON，含多层降级修复
 */
function safeParseJSON(str) {
    // 第一轮：标准解析
    try { return JSON.parse(str); } catch (e) {}

    // 第二轮：修复后解析
    const repaired = repairJSON(str);
    if (repaired) {
        try { return JSON.parse(repaired); } catch (e) {}
    }

    // 第三轮：暴力截断——只取完整的最外层对象
    try {
        for (let i = str.lastIndexOf('}'); i > str.indexOf('{'); i = str.lastIndexOf('}', i - 1)) {
            const candidate = str.substring(str.indexOf('{'), i + 1);
            try { return JSON.parse(candidate); } catch(e) {}
        }
    } catch(e) {}

    return null;
}

const scrapeDirectSite = async (website, domain) => {
    let content = "";
    let urlsToTry = [];

    // 如果有官网，先试官网
    if (website && website.trim() !== '' && website !== '未查明') {
        const cleanWeb = website.startsWith('http') ? website : `http://${website}`;
        urlsToTry.push(cleanWeb);
    }
    // 如果有域名，试产品页
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

const readConfig = () => {
    // 环境变量优先
    if (process.env.LLM_API_KEY) {
        return {
            provider: process.env.LLM_PROVIDER || 'deepseek',
            baseUrl: process.env.LLM_BASE_URL || getUrl('aHR0cHM6Ly9hcGkuZGVlcHNlZWsuY29t'),
            apiKey: process.env.LLM_API_KEY,
            model: process.env.LLM_MODEL || 'deepseek-chat'
        };
    }
    try {
        if (!fs.existsSync(configPath)) return null;
        return JSON.parse(fs.readFileSync(configPath, 'utf8'));
    } catch (e) {
        return null;
    }
};

// 请求去重锁
const pendingSearches = new Map();
const SEARCH_LOCK_TTL = 120 * 1000;

function acquireSearchLock(key) {
  if (pendingSearches.has(key)) {
    const elapsed = Date.now() - pendingSearches.get(key);
    if (elapsed < SEARCH_LOCK_TTL) return false;
  }
  pendingSearches.set(key, Date.now());
  return true;
}

function releaseSearchLock(key) {
  pendingSearches.delete(key);
}

// 搜索结果缓存（24小时）
const searchCache = new Map();
const CACHE_TTL = 24 * 60 * 60 * 1000;

function getCachedResult(key) {
  const cached = searchCache.get(key);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    return cached.data;
  }
  searchCache.delete(key);
  return null;
}

function setCachedResult(key, data) {
  if (searchCache.size > 100) {
    const oldest = searchCache.keys().next().value;
    searchCache.delete(oldest);
  }
  searchCache.set(key, { data, timestamp: Date.now() });
}

const SYSTEM_PROMPT = `你是电子行业商业分析师。你的任务是根据企业公开信息，分析其晶振（谐振器/振荡器）需求，输出结构化JSON。

## 输出规则（严格遵守）
1. 只输出JSON，不要任何markdown代码块标记
2. 不要任何额外说明文字
3. 所有字段必须按要求填充，不确定的留空字符串""，不要填null

## JSON Schema
{
  "company": "公司全称",
  "website": "官方网站URL",
  "address": "注册地址",
  "coordinates": [经度, 纬度],
  "type": "业务类型（简短标签）",
  "profile": "企业深度分析（包含主营、优势、供应链画像、晶振需求预判，3-5句话）",
  "products": [
    {
      "name": "产品型号/名称",
      "imageUrl": "官网图片URL（没有就填空字符串）",
      "chipPlatform": "芯片架构组合",
      "crystals": [
        { "freq": "频率", "package": "封装", "loadCap": "负载电容", "tolerance": "频偏", "function": "功能说明（一句话）" }
      ]
    }
  ],
  "crystalSummary": {
    "freqAggregation": [
      { "freq": "25MHz", "count": 3, "devices": ["产品A", "产品B"] }
    ],
    "monthlyEstimate": "月均估算用量",
    "salesAngle": "销售切入点建议"
  },
  "strategy": "销售策略（3-5句话）"
}

## 示例

输入：深圳市大疆创新科技有限公司
输出：{
  "company": "深圳市大疆创新科技有限公司",
  "type": "无人机/航拍设备",
  "products": [
    {
      "name": "Mavic 3 Pro",
      "chipPlatform": "Ambarella H22 + STM32F7",
      "crystals": [
        {"freq": "24MHz", "package": "3225", "loadCap": "12pF", "tolerance": "±10ppm", "function": "主控芯片提供参考时钟"},
        {"freq": "32.768KHz", "package": "3215", "loadCap": "12.5pF", "tolerance": "±20ppm", "function": "RTC实时时钟"}
      ]
    }
  ],
  "crystalSummary": {
    "freqAggregation": [
      {"freq": "24MHz", "count": 2, "devices": ["Mavic 3 Pro", "Ronin 4D"]},
      {"freq": "32.768KHz", "count": 3, "devices": ["Mavic 3 Pro", "Ronin 4D", "Action 3"]}
    ],
    "monthlyEstimate": "100K-500K pcs",
    "salesAngle": "主推24MHz和32.768K，这两个频点用量最大"
  },
  "strategy": "建议从Mavic系列的24MHz切入..."
}`;


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

        const config = readConfig();
        if (!config || !config.apiKey) { sendEvent({ error: '请先在设置中配置 API Key！' }); return res.end(); }

        // 请求去重
        const lockKey = companyName.trim();
        if (!acquireSearchLock(lockKey)) {
          sendEvent({ error: '该公司正在搜索中，请勿重复提交' });
          return res.end();
        }
        res.on('close', () => releaseSearchLock(lockKey));
        res.on('finish', () => releaseSearchLock(lockKey));

        // 检查缓存
        const cachedData = getCachedResult(lockKey);
        if (cachedData) {
          sendEvent({ status: '命中缓存，直接返回上次结果' });
          sendEvent({ fullData: cachedData });
          res.write('data: [DONE]\n\n');
          return res.end();
        }

        let targetDomain = website ? website.replace(/^(?:https?:\/\/)?(?:www\.)?/i, "").split('/')[0] : '';
        const exact = `"${companyName}"`;

        sendEvent({ status: '启动高精雷达：正在潜入目标官网抓取图文矩阵...' });

        const [ direct_html_data, official_tech, b2b_trade ] = await Promise.all([
            scrapeDirectSite(website, targetDomain),
            fetchMatrixQuery(`${targetDomain ? `site:${targetDomain}` : exact} "解决方案"`),
            fetchMatrixQuery(`${exact} "主营产品"`)
        ]);

        if (!direct_html_data && !official_tech && !b2b_trade) {
            sendEvent({ status: '官网无数据，尝试搜索引擎广度抓取...' });
        }

        sendEvent({ status: '官网底层特征抽取完毕，AI神经元正在进行降维重组...' });

        const userContent = `目标公司：${companyName}

官网数据：${direct_html_data || "无"}

搜索引擎结果：
${official_tech || ""}
${b2b_trade || ""}`;

        let safeBaseUrl = config.baseUrl || getUrl('aHR0cHM6Ly9hcGkuZGVlcHNlZWsuY29t');
        // 防御：Markdown 链接 [text](url) → 提取 url
        const mdLink = safeBaseUrl.match(/\[.*?\]\((.+?)\)/);
        if (mdLink) safeBaseUrl = mdLink[1];
        safeBaseUrl = safeBaseUrl.replace(/[\[\]\(\)]/g, '').split(' ')[0].trim().replace(/\/+$/, '');

        sendEvent({ status: '大模型图文缝合中，正在为您渲染顶级数据报告...' });

        // 使用非流式请求 + response_format 保证 JSON 格式稳定
        const response = await fetch(`${safeBaseUrl}/chat/completions`, {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${(config.apiKey || '').trim()}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                model: (config.model || '').trim() || 'deepseek-chat',
                messages: [
                    { role: "system", content: SYSTEM_PROMPT },
                    { role: "user", content: userContent }
                ],
                temperature: 0.2,
                max_tokens: 8000,
                response_format: { type: "json_object" }
            }),
            signal: AbortSignal.timeout(180000)
        });

        if (!response.ok) {
            sendEvent({ error: `大模型拒绝 (HTTP ${response.status})` });
            return res.end();
        }

        const data = await response.json();
        const rawContent = data.choices?.[0]?.message?.content || '';

        sendEvent({ status: '清洗数据骨架，即将点亮雷达...' });

        const resultData = safeParseJSON(rawContent);
        if (!resultData) {
            sendEvent({ error: "AI 输出格式异常，请重试。最后100字符: " + rawContent.slice(-100) });
            return res.end();
        }

        if (!Array.isArray(resultData.coordinates) || resultData.coordinates.length !== 2) {
            resultData.coordinates = [39.9042, 116.4074];
        }

        // 写入缓存
        setCachedResult(lockKey, resultData);
        sendEvent({ fullData: resultData });
        res.write('data: [DONE]\n\n');
        res.end();

    } catch (error) {
        sendEvent({ error: `处理异常: ${error.message}` });
        res.end();
    }
};

const ALLOWED_IMAGE_HOSTS = [
    'img.', 'image.', 'cdn.', 'pic.', 'static.',
    'www.', 'm.', 'upload.'
];

const proxyImage = (req, res) => {
    if (!req.query.url) return res.status(200).end();
    try {
        const urlObj = new URL(req.query.url);

        // 安全校验：只代理图片请求，拦截 SSRF
        const host = urlObj.hostname;
        const isAllowed = ALLOWED_IMAGE_HOSTS.some(prefix => host.startsWith(prefix))
            || /\.(png|jpg|jpeg|gif|svg|webp|bmp)$/i.test(urlObj.pathname);

        if (!isAllowed) {
            return res.status(200).end();
        }

        const client = urlObj.protocol === 'https:' ? require('https') : require('http');
        client.get(req.query.url, {
            headers: { 'User-Agent': 'Mozilla/5.0', 'Referer': urlObj.origin },
            rejectUnauthorized: false,
            timeout: 4000
        }, (stream) => {
            if (stream.statusCode !== 200) return res.status(200).end();
            res.setHeader('Content-Type', stream.headers['content-type'] || 'image/jpeg');
            stream.pipe(res);
        }).on('error', () => res.status(200).end());
    } catch (e) { res.status(200).end(); }
};

module.exports = { searchLead, proxyImage };
