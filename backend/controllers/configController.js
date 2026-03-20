const fs = require('fs');
const path = require('path');
const configPath = path.join(__dirname, '../config/llm.json');

// 使用 Base64 彻底致盲剪贴板的 URL 识别
const getUrl = (b64) => Buffer.from(b64, 'base64').toString('utf8');

const PROVIDERS = {
    'deepseek': getUrl('aHR0cHM6Ly9hcGkuZGVlcHNlZWsuY29t'),
    'qwen': getUrl('aHR0cHM6Ly9kYXNoc2NvcGUuYWxpeXVuY3MuY29tL2NvbXBhdGlibGUtbW9kZS92MQ=='),
    'moonshot': getUrl('aHR0cHM6Ly9hcGkubW9vbnNob3QuY24vdjE='),
    'zhipu': getUrl('aHR0cHM6Ly9vcGVuLmJpZ21vZGVsLmNuL2FwaS9wYWFzL3Y0'),
    'openai': getUrl('aHR0cHM6Ly9hcGkub3BlbmFpLmNvbS92MQ==')
};

const getDefaultConfig = () => ({
    provider: 'deepseek',
    baseUrl: getUrl('aHR0cHM6Ly9hcGkuZGVlcHNlZWsuY29t'),
    apiKey: '',
    model: 'deepseek-chat'
});

const readConfig = () => {
    try {
        if (!fs.existsSync(configPath)) return getDefaultConfig();
        const content = fs.readFileSync(configPath, 'utf8');
        if (!content.trim()) return getDefaultConfig();
        return { ...getDefaultConfig(), ...JSON.parse(content) };
    } catch (e) {
        return getDefaultConfig();
    }
};

const getConfig = (req, res) => {
    const conf = readConfig();
    res.json({ success: true, data: { ...conf, apiKey: conf.apiKey ? '********' : '' } });
};

const saveConfig = (req, res) => {
    try {
        const conf = readConfig();
        const { provider, baseUrl, apiKey, model } = req.body;
        
        const newConfig = {
            provider: provider || conf.provider,
            baseUrl: baseUrl || conf.baseUrl,
            apiKey: apiKey === '********' ? conf.apiKey : (apiKey || conf.apiKey),
            model: model || conf.model
        };
        
        fs.writeFileSync(configPath, JSON.stringify(newConfig, null, 2));
        res.json({ success: true, message: '配置已保存' });
    } catch (error) {
        res.status(500).json({ success: false, message: '保存配置失败' });
    }
};

const testConfig = async (req, res) => {
    try {
        const config = readConfig();
        
        let safeBaseUrl = config.baseUrl;
        if (config.provider && PROVIDERS[config.provider]) {
            safeBaseUrl = PROVIDERS[config.provider];
        }
        if (!safeBaseUrl || typeof safeBaseUrl !== 'string') {
             safeBaseUrl = getUrl('aHR0cHM6Ly9hcGkuZGVlcHNlZWsuY29t');
        }
        
        // 强力清除所有不可见字符和可能的残留括号
        safeBaseUrl = safeBaseUrl.replace(/[\[\]\(\)]/g, '').split(' ')[0].trim().replace(/\/+$/, '');
        
        if (!safeBaseUrl.startsWith('http')) {
            safeBaseUrl = getUrl('aHR0cHM6Ly9hcGkuZGVlcHNlZWsuY29t');
        }

        const targetUrl = `${safeBaseUrl}/chat/completions`;
        const safeKey = (config.apiKey || '').trim();
        const safeModel = (config.model || '').trim() || 'deepseek-chat';

        if (!safeKey) return res.status(400).json({ success: false, message: 'API Key 不能为空' });

        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 12000);

        const response = await fetch(targetUrl, {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${safeKey}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                model: safeModel,
                messages: [{ role: "user", content: "Hi" }],
                max_tokens: 5
            }),
            signal: controller.signal
        });
        clearTimeout(timeoutId);

        if (!response.ok) {
            return res.status(400).json({ success: false, message: `鉴权被拒 (HTTP ${response.status})` });
        }
        
        const data = await response.json();
        if (data && data.choices) {
            res.json({ success: true, message: '极速直连成功！' });
        } else {
            res.status(400).json({ success: false, message: '数据格式异常' });
        }
    } catch (error) {
        res.status(500).json({ success: false, message: `拦截: ${error.message}` });
    }
};

module.exports = { getConfig, saveConfig, testConfig };
