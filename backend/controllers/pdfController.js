const fs = require('fs');
const path = require('path');
const { PdfReader } = require('pdfreader');
const configPath = path.join(__dirname, '../config/llm.json');

const getUrl = (b64) => Buffer.from(b64, 'base64').toString('utf8');

const PROVIDERS = {
    'deepseek': getUrl('aHR0cHM6Ly9hcGkuZGVlcHNlZWsuY29t'),
    'qwen': getUrl('aHR0cHM6Ly9kYXNoc2NvcGUuYWxpeXVuY3MuY29tL2NvbXBhdGlibGUtbW9kZS92MQ=='),
    'moonshot': getUrl('aHR0cHM6Ly9hcGkubW9vbnNob3QuY24vdjE='),
    'zhipu': getUrl('aHR0cHM6Ly9vcGVuLmJpZ21vZGVsLmNuL2FwaS9wYWFzL3Y0'),
    'openai': getUrl('aHR0cHM6Ly9hcGkub3BlbmFpLmNvbS92MQ==')
};

// 【核心改造：Y 轴坐标换行算法】完美还原 PDF 的列表和段落排版
const extractTextFromPDFFile = (filePath) => {
    return new Promise((resolve, reject) => {
        let text = "";
        let aborted = false;
        let currentPage = 0;
        let lastY = 0; // 记录上一行文字的 Y 轴高度

        new PdfReader().parseFileItems(filePath, (err, item) => {
            if (aborted) return;
            if (err) reject(err);
            else if (!item) resolve(text);
            else if (item.page) {
                currentPage = item.page;
                text += `\n\n[--- Page ${currentPage} ---]\n\n`;
                lastY = 0;
            }
            else if (item.text) {
                // 如果当前文字高度与上一个高度差超过 0.2，视为物理换行
                if (lastY && Math.abs(item.y - lastY) > 0.2) {
                    text += "\n";
                }
                text += item.text;
                lastY = item.y;

                if (text.length > 80000) {
                    aborted = true;
                    resolve(text.substring(0, 80000));
                }
            }
        });
    });
};

const translatePdf = async (req, res) => {
    try {
        if (!req.file) return res.status(400).json({ success: false, message: '未接收到 PDF 文件' });
        const filePath = req.file.path; 

        if (!fs.existsSync(configPath)) {
            fs.unlinkSync(filePath);
            return res.status(400).json({ success: false, message: '请先配置 API' });
        }
        const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
        
        let extractedText = "";
        try {
            extractedText = await extractTextFromPDFFile(filePath);
        } catch (parseErr) {
            fs.unlinkSync(filePath);
            return res.status(500).json({ success: false, message: 'PDF引擎解析图纸内容失败' });
        }

        if (fs.existsSync(filePath)) fs.unlinkSync(filePath);

        if (!extractedText.trim()) return res.status(400).json({ success: false, message: '无法提取文字' });

        // 【超级像素级死命令 Prompt】：绝不准许大模型自我概括！
        const prompt = `你是一个资深的电子元器件FAE。我将给你一份英文芯片规格书（Datasheet）的解析文本。
文本中包含了 [--- Page X ---] 的页码标记，以及还原了物理换行排版的文本。请在文本中寻找外部时钟、晶体振荡器（Crystal, Oscillator, HSE, LSE）的要求。

【规格书文本内容】：
"""
${extractedText}
"""

【任务要求】：
输出严格的 JSON 格式：
{
  "chipName": "推测的芯片型号或所属系列(从第一页提取)",
  "hasCrystalRequirement": true/false,
  "summary": "一句话总结该芯片对时钟源的整体要求（中文）",
  "crystalParams": [
    {
      "paramName": "参数名称（如：标称频率 Frequency、负载电容 Load Capacitance等）",
      "value": "具体的数值要求（如 24MHz, 9pF 等）",
      "remark": "原厂对该参数的特殊说明或备注翻译（中文）",
      "pageNumber": "该参数在PDF中出现的具体页码（只填数字，如 18）",
      "originalSnippet": "【极度重要】：必须一字不差（Copy verbatim）地完美复制证明该参数的整个英文段落或列表！绝对严禁自行总结、精简或改写原始英文！必须保留原文的回车换行格式(\\n)。请使用 <mark> 标签高亮核心相关的参数词或数值。"
    }
  ],
  "salesAdvice": "作为晶振销售，看到这份规格书后，你会向客户推荐什么晶振？（中文）"
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
                temperature: 0.0, // 降到绝对零度，确保百分百原文复制
                response_format: { type: "json_object" }
            }),
            signal: controller.signal
        });
        clearTimeout(timeoutId);

        if (!response.ok) return res.status(500).json({ success: false, message: `大模型拒接: HTTP ${response.status}` });

        const data = await response.json();
        let content = data.choices[0].message.content.replace(/```json/g, '').replace(/```/g, '').trim();
        const resultData = JSON.parse(content);

        res.json({ success: true, data: resultData });
    } catch (error) {
        res.status(500).json({ success: false, message: `解析中断: ${error.message}` });
    }
};

module.exports = { translatePdf };
