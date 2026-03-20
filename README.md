# 🔮 Crystal Radar (人机协同精准雷达)

> 一款专为 B2B 硬件原厂/代理商销售打造的**商业情报狙击与分析 SaaS 系统**。采用顶级流体毛玻璃 (Premium Glassmorphism) 视觉架构，结合大模型 (LLM) 与底层物理强扒探针，实现秒级企业研报生成。

## ✨ 核心杀手锏

1. **零外援·官网底层强扒引擎 (Zero-Fallback Scraper)**
   - 彻底告别传统搜索引擎搜图的误差！直接物理直连目标企业官网，穿透 Vue/React 懒加载 (`data-src`, `v-lazy`) 及 CSS 背景图结界，强行提取底层源码与图片绝对链接。
   - **图文缝合技术**：AI 神经元自动将扒取到的原配图库与产品型号进行交叉匹配，实现 100% 精确的实物图鉴渲染。
2. **防爆裂解析与重组管线 (TCP & OOM Protection)**
   - **TCP 碎片重组缓冲器**：突破单次海量数据输出的网络切割问题，告别“无限转圈死锁”。
   - **Max_Tokens 限流安全阀**：配合底层正则洗脱技术，完美解决 JSON 半路截断导致的渲染崩溃。
3. **英文规格书极速破译器 (Datasheet Translator)**
   - 拖拽式 PDF 解析，自动提炼“主控型号、晶振硬性要求、实战销售建议”。
   - 告别报错，输出为结构化、高颜值 SaaS 彩色数据舱面板。
4. **国家级高定地图沙盘 (Anti-Leech Map)**
   - 采用国内测绘级极速瓦片源与高德 (Amap) 绝对主干节点。
   - 注入 HTTP `no-referrer` 隐身斗篷与 Tailwind CSS 防压缩结界，彻底粉碎大厂“防盗链”拦截，瞬间铺设私域客户兵力地图。

## 🚀 极简两步部署 (Two-Step Deployment)

无论您是全新的 Ubuntu/Debian 还是 CentOS 服务器，只需两步即可点亮整套雷达系统：

### 步骤 1：一键初始化全栈环境
在项目根目录执行自动化脚本，它会自动为您安装 Node.js、PM2，并编译好所有前后端引擎：
```bash
sudo bash install.sh
```

### 步骤 2：UI 界面唤醒神经元
打开您的系统网页，点击右上角的 **【配置】** 按钮。
选择您的 AI 供应商（DeepSeek / 阿里千问 / OpenAI等），填入您的 API Key，点击保存。**雷达即可正式发车！**

## 🛡️ 技术栈声明
- **前端**：React (Vite) + Tailwind CSS + Zustand + React-Leaflet
- **后端**：Node.js (Express) + Cheerio (DOM 嗅探)
- **数据库**：ACID 防御级 JSON 解析引擎
