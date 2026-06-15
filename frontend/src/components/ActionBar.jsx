import React from 'react';
import axios from 'axios';
import * as XLSX from 'xlsx';
import { useStore } from '../store';
import { Heart, Mail, FileSpreadsheet, MapPin, ClipboardCopy } from 'lucide-react';

export default function ActionBar() {
  const { searchResult: data, setGeneratedEmail, triggerRefresh } = useStore();

  if (!data?.company) return null;

  // --- 收藏客户 ---
  const handleFavorite = async () => {
    try {
      await axios.post('/api/customers', { ...data, category: 'B类客户' });
      triggerRefresh();
      alert('已收藏到客户档案！');
    } catch {
      alert('收藏失败，请重试');
    }
  };

  // --- 生成开发信 ---
  const handleGenerateEmail = () => {
    const products = data.products || [];
    const productList = products.map(p => `- ${p.name}（${p.chipPlatform || '架构待定'}）`).join('\n');
    const crystalSummary = [...new Set(products.flatMap(p => (p.crystals || []).map(c => c.freq)))].join('、');

    const email = `尊敬的${data.company}采购负责人：

您好！我司是专业晶振（频率元件）供应商，了解到贵司主营${data.type || '电子智能终端设备'}，
在以下产品中需要使用晶振方案：

${productList}

涉及晶振频点包括：${crystalSummary || '26MHz、32.768KHz等多种频点'}
我司可提供对应频点的高性价比晶振，支持3225/2520/2016等多种封装，温漂±10ppm以内。
如有兴趣，欢迎随时联系，我司可免费送样测试。

顺颂商祺！
[您的名字]
[晶振销售 | 公司名称]
[联系电话]`;

    setGeneratedEmail(email);
  };

  // --- 导出Excel ---
  const aggregatedBomList = [];
  const bomMap = new Map();

  if (Array.isArray(data.products)) {
    data.products.forEach(p => {
      if (Array.isArray(p.crystals)) {
        p.crystals.forEach(c => {
          const key = `${c.freq || '未知'}|${c.package || '未知'}`;
          if (!bomMap.has(key)) {
            bomMap.set(key, {
              freq: c.freq || '-',
              package: c.package || '-',
              params: `CL:${c.loadCap || '-'} | Tol:${c.tolerance || '-'}`,
              function: c.function || '',
              devices: new Set([p.name || '未知设备']),
              chips: new Set([p.chipPlatform || '未知架构'])
            });
          } else {
            bomMap.get(key).devices.add(p.name || '未知设备');
            bomMap.get(key).chips.add(p.chipPlatform || '未知架构');
          }
        });
      }
    });
  }

  bomMap.forEach(v => {
    aggregatedBomList.push({
      freq: v.freq,
      package: v.package,
      params: v.params,
      function: v.function,
      devices: Array.from(v.devices).join(' \n '),
      chips: Array.from(v.chips).join(' \n ')
    });
  });

  const handleExportExcel = () => {
    const worksheetData = [
      ['晶振频率', '封装及参数', '应用此频点的终端设备', '涉及的主控架构(推演)', '核心作用解析'],
      ...aggregatedBomList.map(item => [item.freq, `${item.package} (${item.params})`, item.devices, item.chips, item.function])
    ];
    const ws = XLSX.utils.aoa_to_sheet(worksheetData);
    ws['!cols'] = [{ wch: 15 }, { wch: 25 }, { wch: 35 }, { wch: 40 }, { wch: 50 }];
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "聚合BOM分析表");
    XLSX.writeFile(wb, `${data.company || '未知企业'}_晶振BOM聚合分析.xlsx`);
  };

  // --- 查看地图 ---
  const handleViewMap = () => {
    const { setActiveTab } = useStore.getState();
    setActiveTab('map');
    setTimeout(() => window.dispatchEvent(new CustomEvent('focus-customer', { detail: data })), 300);
  };

  // --- 复制摘要 ---
  const handleCopySummary = () => {
    const text = `${data.company}\n${data.address || ''}\n${data.website || ''}\n${data.type || ''}`;
    navigator.clipboard.writeText(text);
    alert('公司摘要已复制到剪贴板！');
  };

  const actions = [
    { icon: Heart, label: '收藏客户', color: 'amber', onClick: handleFavorite },
    { icon: Mail, label: '生成开发信', color: 'indigo', onClick: handleGenerateEmail },
    { icon: FileSpreadsheet, label: '导出Excel', color: 'cyan', onClick: handleExportExcel },
    { icon: MapPin, label: '查看地图', color: 'rose', onClick: handleViewMap },
    { icon: ClipboardCopy, label: '复制摘要', color: 'teal', onClick: handleCopySummary },
  ];

  const colorClasses = {
    amber: 'bg-amber-500 hover:bg-amber-600 shadow-amber-500/30 focus:ring-amber-400',
    indigo: 'bg-indigo-500 hover:bg-indigo-600 shadow-indigo-500/30 focus:ring-indigo-400',
    cyan: 'bg-cyan-500 hover:bg-cyan-600 shadow-cyan-500/30 focus:ring-cyan-400',
    rose: 'bg-rose-500 hover:bg-rose-600 shadow-rose-500/30 focus:ring-rose-400',
    teal: 'bg-teal-500 hover:bg-teal-600 shadow-teal-500/30 focus:ring-teal-400',
  };

  return (
    <div className="glass-panel rounded-2xl p-4 flex flex-col items-center gap-4">
      <div className="text-xs font-bold text-gray-500 tracking-wider uppercase mb-1">快捷操作</div>
      {actions.map((action, idx) => {
        const Icon = action.icon;
        return (
          <button
            key={idx}
            onClick={action.onClick}
            title={action.label}
            className={`flex flex-col items-center justify-center gap-1 w-14 h-14 rounded-xl text-white shadow-lg ${colorClasses[action.color]} focus:outline-none focus:ring-2 focus:ring-offset-2 transition-all duration-200 hover:scale-110 active:scale-95`}
          >
            <Icon size={20} />
            <span className="text-[10px] font-bold leading-tight">{action.label}</span>
          </button>
        );
      })}
    </div>
  );
}
