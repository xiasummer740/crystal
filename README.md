# 🔮 Crystal Radar (人机协同精准雷达)

> 一款专为 B2B 硬件销售打造的**商业情报狙击 SaaS 系统**。采用顶级流体毛玻璃视觉，结合 AI 与官网物理强扒引擎，实现秒级企业研报与图文缝合。

## 🚀 极简两步部署 (小白专属)

无论您使用的是全新纯净的 Ubuntu、Debian 还是 CentOS 服务器，只需复制以下两步指令即可点亮全套雷达系统：

### 步骤 1：准备环境并下载源码
因为纯净的新服务器可能没有下载工具，请先执行这一步来获取代码：

**对于 Ubuntu / Debian 系统（绝大多数用户）：**
```bash
apt-get update -y && apt-get install -y git curl
git clone -b crystal https://github.com/xiasummer740/crystal.git
cd crystal
```

**对于 CentOS / RedHat 系统：**
```bash
yum install -y git curl
git clone -b crystal https://github.com/xiasummer740/crystal.git
cd crystal
```

### 步骤 2：执行全自动安装向导
源码下载完毕后，执行终极安装脚本：
```bash
bash install.sh
```
> **安装向导会自动问您：**
> 👉 `Input Domain or IP [eg: 154.31.157.42]:` 
> 输入您解析好的域名（或直接输入 IP）并回车。
> 接下来请去喝杯水，系统会自动为您安装 Node.js 20、配置 Nginx 路由代理、映射端口并启动防爆守护进程。

---

## 💡 唤醒 AI 神经元
在浏览器输入您刚才绑定的域名或 IP，进入系统。
点击右上角的 **【配置】** 按钮，填入您的 API Key（推荐使用 DeepSeek / OpenAI 等），点击保存，雷达即可开火！

## ✨ 核心杀手锏
1. **零外援·官网底层强扒**：穿透 Vue/React 懒加载，提取真图与产品交叉缝合。
2. **TCP 防爆与 OOM 保护**：15款核心产品安全限流，绝不断连。
3. **英文规格书极速破译**：秒解芯片 PDF，提取外接晶振硬性指标。
4. **GeoQ/高德免墙沙盘**：自带 HTTP `no-referrer` 隐身斗篷，碾碎防盗链。
