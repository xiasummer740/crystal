import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';
const resources = {
  zh: { translation: { "title": "晶振销售线索匹配系统", "search_placeholder": "输入公司名称...", "search_btn": "深度分析", "company_info": "企业信息分析", "tech_platform": "主流芯片方案与产品", "crystal_match": "推荐晶振型号参数", "strategy": "销售策略建议", "loading": "分析中...", "lang_switch": "English", "freq": "标称频率", "package": "封装", "loadCap": "负载电容", "tolerance": "频偏", "app": "应用场景" } },
  en: { translation: { "title": "Crystal Sales Lead System", "search_placeholder": "Enter company name...", "search_btn": "Deep Analyze", "company_info": "Enterprise Info", "tech_platform": "Chip Platforms & Products", "crystal_match": "Recommended Crystals", "strategy": "Sales Strategy", "loading": "Analyzing...", "lang_switch": "中文", "freq": "Frequency", "package": "Package", "loadCap": "Load Cap", "tolerance": "Tolerance", "app": "Application" } }
};
i18n.use(initReactI18next).init({ resources, lng: "zh", fallbackLng: "zh", interpolation: { escapeValue: false } });
export default i18n;
