#!/bin/bash
set -e

FRONTEND_DIR="/var/www/crystal/frontend"

echo ">>> 1. 正在为前端安装 Excel 生成引擎 (SheetJS)..."
cd "$FRONTEND_DIR"
npm install xlsx --save > /dev/null 2>&1

echo ">>> 2. 正在重写 ResultDisplay：注入【BOM 总表】与【一键导出 Excel】..."

cat << 'EOF' > "$FRONTEND_DIR/src/components/ResultDisplay.jsx"
import React, { useState, useEffect } from 'react';
import axios from 'axios';
import * as XLSX from 'xlsx'; // 引入 Excel 库
import { useStore } from '../store';
import { Building2, Cpu, Zap, Lightbulb, Link as LinkIcon, Info, Box, Layers, Copy, Check, MapPin, Star, ShoppingCart, Globe2, FileText, Download, Table2 } from 'lucide-react';

export default function ResultDisplay() {
  const { searchResult: data, error, triggerRefresh } = useStore();
  const [copiedId, setCopiedId] = useState(null);
  const [category, setCategory] = useState('未收藏');

  useEffect(() => {
    if (data?.company) {
      axios.get('/api/customers').then(res => {
         const existing = res.data.data.find(c => c.company === data.company);
         setCategory(existing ? existing.category : '未收藏');
      }).catch(() => {});
    }
  }, [data]);

  if (error) return <div className="max-w-6xl mx-auto p-4 text-red-500 text-center font-bold bg-red-50 rounded mt-4">{error}</div>;
  if (!data) return null;

  const siteUrl = data.website.startsWith('http') ? data.website : ['h', 't', 't', 'p', 's', '://', data.website].join('');

  const handleCopy = (text, id) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const handleCategoryChange = async (e) => {
    const newCat = e.target.value;
    setCategory(newCat);
    try {
      await axios.post('/api/customers', {
         company: data.company,
         address: data.address,
         coordinates: data.coordinates,
         type: data.type,
         category: newCat
      });
      triggerRefresh();
    } catch (err) {}
  };

  // 【核心功能：数据压平与 Excel 导出】
  const flatBomList = [];
  data.products?.forEach(p => {
    p.crystals?.forEach(c => {
      flatBomList.push({
        productName: p.name,
        chipPlatform: p.chipPlatform,
        freq: c.freq,
        package: c.package,
        params: `CL:${c.loadCap} | Tol:${c.tolerance}`,
        function: c.function
      });
    });
  });

  const exportToExcel = () => {
    const worksheetData = [
      ['终端设备名称', '全景芯片架构 (BOM推演)', '标称频率', '封装尺寸', '规格参数', '核心作用解析'],
      ...flatBomList.map(item => [
        item.productName, 
        item.chipPlatform, 
        item.freq, 
        item.package, 
        item.params, 
        item.function
      ])
    ];
    const ws = XLSX.utils.aoa_to_sheet(worksheetData);
    
    // 设置列宽
    ws['!cols'] = [ { wch: 25 }, { wch: 40 }, { wch: 15 }, { wch: 15 }, { wch: 20 }, { wch: 50 } ];

    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "晶振BOM总表");
    XLSX.writeFile(wb, `${data.company}_晶振BOM需求表.xlsx`);
  };

  return (
    <div className="max-w-6xl mx-auto p-4 space-y-8 animate-fade-in mt-4 font-sans">
      
      {/* 1. 企业全景 */}
      <div className="bg-white p-6 rounded-2xl shadow-md border-t-4 border-blue-600 relative group">
        <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-4 border-b pb-4">
            <div 
              className="group/copy flex items-center gap-2 cursor-pointer hover:bg-blue-50 p-2 -ml-2 rounded-lg transition-colors"
              onClick={() => handleCopy(data.company, 'companyName')}
              title="点击一键复制公司全称"
            >
              <Building2 className="text-blue-600" size={28}/> 
              <h2 className="text-2xl font-black text-blue-900">{data.company}</h2>
              {copiedId === 'companyName' ? <Check size={18} className="text-green-500 animate-pulse"/> : <Copy size={16} className="text-blue-300 opacity-0 group-hover/copy:opacity-100 transition-opacity"/>}
            </div>

            <div className="flex items-center gap-2 bg-blue-50 px-4 py-2 rounded-xl border border-blue-200 shadow-sm">
               <Star size={20} className={category !== '未收藏' ? 'text-yellow-500 fill-yellow-500' : 'text-gray-400'} />
               <span className="text-sm font-bold text-blue-800">客户库归档：</span>
               <select value={category} onChange={handleCategoryChange} className="bg-white border border-blue-300 text-blue-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block p-1.5 font-bold outline-none cursor-pointer">
                   <option value="未收藏">未收藏</option>
                   <option value="A类客户">🔥 A类客户 (紧急重点)</option>
                   <option value="B类客户">⭐ B类客户 (持续跟进)</option>
                   <option value="C类客户">📌 C类客户 (普通储备)</option>
                   <option value="意向客户">🤝 意向客户</option>
                   <option value="合作客户">✅ 合作客户</option>
               </select>
            </div>
        </div>

        <div className="space-y-4 text-sm text-gray-800">
          <p className="flex items-center gap-3"><span className="font-semibold w-20 text-gray-500 tracking-wide">注册地址:</span> <span className="text-base text-gray-800 font-bold flex items-center gap-1"><MapPin size={18} className="text-red-500"/>{data.address || '未查明'}</span></p>
          <p className="flex items-center gap-3">
            <span className="font-semibold w-20 text-gray-500 tracking-wide">官方网站:</span> 
            <a href={siteUrl} target="_blank" rel="noopener noreferrer" className="flex items-center gap-1 text-blue-600 hover:text-blue-800 hover:underline font-bold text-base">
              <LinkIcon size={18} /> {data.website}
            </a>
          </p>
          <p className="flex items-center gap-3"><span className="font-semibold w-20 text-gray-500 tracking-wide">业务类型:</span> <span className="bg-blue-100 text-blue-800 px-3 py-1 rounded-md text-sm font-bold shadow-sm">{data.type}</span></p>
          
          <div className="mt-6 p-5 bg-blue-50 rounded-xl border border-blue-100 relative hover:shadow-inner transition-all">
             <button onClick={() => handleCopy(data.profile, 'profile')} className="absolute top-4 right-4 text-blue-400 hover:text-blue-700 p-1.5 bg-white rounded-md shadow-sm border border-blue-100 transition-colors">
               {copiedId === 'profile' ? <Check size={16} className="text-green-600"/> : <Copy size={16}/>}
             </button>
             <div className="flex gap-3 items-start">
                 <Info className="text-blue-500 flex-shrink-0 mt-1" size={22} />
                 <p className="leading-loose text-gray-700 text-base tracking-wide pr-8 text-justify">{data.profile}</p>
             </div>
          </div>
        </div>
      </div>

      {/* 2. 寻源矩阵 */}
      {data.commonChipPlatforms && Array.isArray(data.commonChipPlatforms) && (
        <div className="bg-white p-6 rounded-2xl shadow-md border-t-4 border-purple-600">
          <h2 className="text-2xl font-black flex items-center gap-2 mb-6 text-purple-900 border-b pb-4">
            <Layers className="text-purple-600" size={28}/> 全球IC商城查价与原厂规格书直连
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
            {data.commonChipPlatforms.map((chip, idx) => {
              const encodedModel = encodeURIComponent(chip.model);
              return (
                <div key={idx} className="bg-purple-50 rounded-xl p-5 border border-purple-100 hover:shadow-lg transition-all relative flex flex-col justify-between">
                  <div>
                    <span className="inline-block px-2 py-1 bg-purple-200 text-purple-800 text-xs font-bold rounded mb-2">{chip.brand}</span>
                    <h3 className="text-lg font-black text-gray-900 mb-1 tracking-tight">{chip.model}</h3>
                    <p className="text-sm text-gray-600 leading-relaxed mb-4">{chip.application}</p>
                  </div>
                  <div className="mt-2 pt-3 border-t border-purple-200/50 space-y-2">
                    <div className="flex items-center gap-2">
                       <Globe2 size={12} className="text-gray-400"/>
                       <a href={`https://www.digikey.cn/zh/products/result?keywords=${encodedModel}`} target="_blank" className="text-[11px] font-bold text-red-700 bg-red-50 hover:bg-red-100 px-2 py-1 rounded shadow-sm border border-red-200">DigiKey</a>
                       <a href={`https://www.mouser.cn/c/?q=${encodedModel}`} target="_blank" className="text-[11px] font-bold text-blue-700 bg-blue-50 hover:bg-blue-100 px-2 py-1 rounded shadow-sm border border-blue-200">Mouser 贸泽</a>
                       <a href={`https://www.semiee.com/search?keyword=${encodedModel}`} target="_blank" className="text-[11px] font-bold text-teal-700 bg-teal-50 hover:bg-teal-100 px-2 py-1 rounded shadow-sm border border-teal-200 ml-auto flex items-center gap-1"><FileText size={10}/> 半岛小芯</a>
                    </div>
                    <div className="flex items-center gap-2 flex-wrap">
                      <ShoppingCart size={12} className="text-gray-400"/>
                      <a href={`https://so.szlcsc.com/global.html?k=${encodedModel}`} target="_blank" className="text-[11px] font-bold text-blue-600 bg-blue-50 hover:bg-blue-100 px-2 py-1 rounded shadow-sm border border-blue-200">立创商城</a>
                      <a href={`https://www.hqchip.com/search/${encodedModel}.html`} target="_blank" className="text-[11px] font-bold text-orange-600 bg-orange-50 hover:bg-orange-100 px-2 py-1 rounded shadow-sm border border-orange-200">华秋</a>
                      <a href={`https://s.hqew.com/${encodedModel}.html`} target="_blank" className="text-[11px] font-bold text-indigo-600 bg-indigo-50 hover:bg-indigo-100 px-2 py-1 rounded shadow-sm border border-indigo-200">华强</a>
                      <a href={`https://www.allchips.com/search?keyword=${encodedModel}`} target="_blank" className="text-[11px] font-bold text-red-500 bg-red-50 hover:bg-red-100 px-2 py-1 rounded shadow-sm border border-red-100">硬之城</a>
                      <a href={`https://cn.bing.com/search?q=${encodeURIComponent(chip.model + ' datasheet pdf')}`} target="_blank" className="text-[11px] font-bold text-gray-700 bg-yellow-100 hover:bg-yellow-200 px-2 py-1 rounded shadow-sm border border-yellow-300 ml-auto">PDF直达</a>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* 3. 硬件产品全屏展示 */}
      <div className="space-y-6">
        <div className="flex items-center justify-between px-2">
            <h2 className="text-2xl font-black flex items-center gap-2 text-indigo-900">
              <Cpu className="text-indigo-600" size={28}/> 终端实物拆解与全系晶振 BOM 映射
            </h2>
            <span className="text-sm font-bold text-indigo-500 bg-indigo-50 px-3 py-1 rounded-full border border-indigo-100 shadow-sm">挖掘出 {data.products?.length || 0} 款全线产品</span>
        </div>
        
        {data.products && data.products.map((product, idx) => (
          <div key={idx} className="bg-white p-6 rounded-2xl shadow-sm hover:shadow-xl transition-shadow border border-gray-100 overflow-hidden">
            <div className="flex flex-col lg:flex-row gap-8">
              <div className="lg:w-1/3 flex flex-col items-center text-center space-y-4">
                <div className="w-full h-64 rounded-xl border border-gray-100 shadow-inner relative overflow-hidden bg-gray-50 flex flex-col items-center justify-center group">
                  {product.imageUrl ? (
                    <img src={`/api/image-proxy?url=${encodeURIComponent(product.imageUrl)}`} alt={product.name} className="w-full h-full object-contain p-2 group-hover:scale-110 transition-transform duration-700" onError={(e) => { e.target.style.display='none'; e.target.nextSibling.style.display='flex'; }}/>
                  ) : null}
                  <div className="absolute inset-0 flex-col items-center justify-center text-gray-400 bg-gray-50" style={{ display: product.imageUrl ? 'none' : 'flex' }}>
                    <Box size={48} className="mb-2 opacity-30"/>
                    <span className="text-sm font-bold px-4 text-center">{product.name}</span>
                  </div>
                </div>
                <h3 className="text-xl font-black text-gray-900 leading-tight">{product.name}</h3>
                <div className="w-full bg-indigo-50 p-5 rounded-xl border border-indigo-100 shadow-sm text-left">
                  <p className="text-xs text-indigo-600 font-bold mb-2 uppercase border-b border-indigo-200 pb-2">全景芯片架构拆解 (BOM推演)</p>
                  <p className="text-sm font-extrabold text-indigo-900 leading-loose whitespace-pre-wrap">{product.chipPlatform || '分析中...'}</p>
                </div>
              </div>
              <div className="lg:w-2/3 flex flex-col justify-center">
                <div className="flex items-center gap-2 mb-5 border-b border-gray-100 pb-3">
                  <Zap className="text-orange-500" size={24} />
                  <h4 className="font-black text-gray-900 text-xl">晶振白话文解析</h4>
                </div>
                <div className="overflow-hidden rounded-xl border border-gray-200 shadow-sm">
                  <table className="w-full text-left text-sm">
                    <thead className="bg-gray-100 text-gray-700 border-b border-gray-200">
                      <tr><th className="p-4 font-bold uppercase w-1/4">频率</th><th className="p-4 font-bold uppercase w-1/4">参数</th><th className="p-4 font-bold uppercase w-1/2">小白秒懂：核心作用</th></tr>
                    </thead>
                    <tbody className="divide-y divide-gray-100 bg-white">
                      {product.crystals?.map((c, cIdx) => (
                        <tr key={cIdx} className="hover:bg-orange-50/60 transition-colors">
                          <td className="p-4 font-black text-orange-600 text-lg whitespace-nowrap">{c.freq}</td>
                          <td className="p-4"><div className="font-bold text-gray-800">{c.package}</div><div className="text-gray-500 text-xs mt-1">CL:{c.loadCap} | Tol:{c.tolerance}</div></td>
                          <td className="p-4 text-gray-700 leading-relaxed text-justify bg-orange-50/30 border-l border-orange-100" dangerouslySetInnerHTML={{__html: (c.function || '').replace(/(为什么需要.*?：|如果没有它.*?：)/g, '<strong class="text-orange-700">$1</strong>')}}></td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* 4. AI 战术建议 */}
      <div className="bg-white p-6 rounded-2xl shadow-lg border-t-4 border-green-500 relative">
        <h2 className="text-xl font-black flex items-center gap-2 mb-4 text-green-900 border-b pb-3"><Lightbulb className="text-green-600" size={24}/> AI FAE 极速选型与销售建议</h2>
        <p className="text-gray-800 leading-loose font-medium text-base text-justify bg-green-50 p-4 rounded-xl border border-green-100">{data.strategy}</p>
      </div>

      {/* 5. 【新增】：晶振 BOM 汇总总表与导出功能 */}
      {flatBomList.length > 0 && (
        <div className="bg-white p-6 rounded-2xl shadow-lg border-t-4 border-cyan-500 relative overflow-hidden">
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-6 border-b border-gray-100 pb-4 gap-4">
            <h2 className="text-2xl font-black flex items-center gap-2 text-cyan-900">
              <Table2 className="text-cyan-600" size={28}/> 晶振BOM全景汇总表
            </h2>
            <button 
              onClick={exportToExcel}
              className="flex items-center gap-2 bg-gradient-to-r from-cyan-600 to-blue-600 text-white px-5 py-2.5 rounded-lg shadow-md hover:shadow-lg hover:-translate-y-0.5 transition-all font-bold text-sm"
            >
              <Download size={18} /> 导出为 Excel 表格
            </button>
          </div>
          
          <div className="overflow-x-auto rounded-xl border border-gray-200">
            <table className="w-full text-left text-sm whitespace-nowrap">
              <thead className="bg-gray-50 text-gray-700">
                <tr>
                  <th className="p-3 font-bold border-b">终端设备名称</th>
                  <th className="p-3 font-bold border-b">主控芯片/架构</th>
                  <th className="p-3 font-bold border-b text-orange-600">晶振频率</th>
                  <th className="p-3 font-bold border-b">封装/参数</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {flatBomList.map((item, idx) => (
                  <tr key={idx} className="hover:bg-cyan-50/30 transition-colors">
                    <td className="p-3 font-bold text-gray-800">{item.productName}</td>
                    <td className="p-3 text-gray-600 truncate max-w-[200px]" title={item.chipPlatform}>{item.chipPlatform}</td>
                    <td className="p-3 font-black text-orange-600">{item.freq}</td>
                    <td className="p-3 text-gray-600">{item.package} <span className="text-gray-400 text-xs ml-1">({item.params})</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

    </div>
  );
}
EOF

echo ">>> 3. 全面编译生效并重启服务..."
cd "$FRONTEND_DIR"
npm run build > /dev/null

echo "========================================================="
echo " ✅ BOM 总表与 Excel 导出功能已上线！"
echo "========================================================="
