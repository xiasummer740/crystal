import React, { useState, useEffect } from 'react'
import axios from 'axios'
import { useStore } from '../store'
import {
  Building2,
  Cpu,
  Zap,
  Lightbulb,
  Link as LinkIcon,
  Info,
  Box,
  Copy,
  Check,
  MapPin,
  Table2,
  Activity,
} from 'lucide-react'

export default function ResultDisplay() {
  const { searchResult: data, error } = useStore()
  const [copiedId, setCopiedId] = useState(null)
  const [category, setCategory] = useState('未收藏')

  useEffect(() => {
    if (data?.company) {
      axios
        .get('/api/customers')
        .then((res) => {
          const existing = res.data.data.find((c) => c.company === data.company)
          setCategory(existing ? existing.category : '未收藏')
        })
        .catch(() => {})
    }
  }, [data])

  if (error)
    return (
      <div className="max-w-6xl mx-auto p-4 text-red-500 text-center font-bold glass-panel rounded-xl mt-4">
        {error}
      </div>
    )
  if (!data) return null

  const safeWebsite =
    data.website &&
    typeof data.website === 'string' &&
    data.website !== '未查明' &&
    data.website !== '无'
      ? data.website
      : ''
  const siteUrl = safeWebsite
    ? safeWebsite.startsWith('http')
      ? safeWebsite
      : `https://${safeWebsite}`
    : '#'

  const handleCopy = (text, id) => {
    if (!text) return
    navigator.clipboard.writeText(text)
    setCopiedId(id)
    setTimeout(() => setCopiedId(null), 2000)
  }

  const aggregatedBomList = []
  const bomMap = new Map()

  if (Array.isArray(data.products)) {
    data.products.forEach((p) => {
      if (Array.isArray(p.crystals)) {
        p.crystals.forEach((c) => {
          const key = `${c.freq || '未知'}|${c.package || '未知'}`
          if (!bomMap.has(key)) {
            bomMap.set(key, {
              freq: c.freq || '-',
              package: c.package || '-',
              params: `CL:${c.loadCap || '-'} | Tol:${c.tolerance || '-'}`,
              function: c.function || '',
              devices: new Set([p.name || '未知设备']),
              chips: new Set([p.chipPlatform || '未知架构']),
            })
          } else {
            bomMap.get(key).devices.add(p.name || '未知设备')
            bomMap.get(key).chips.add(p.chipPlatform || '未知架构')
          }
        })
      }
    })
  }

  bomMap.forEach((v) => {
    aggregatedBomList.push({
      freq: v.freq,
      package: v.package,
      params: v.params,
      function: v.function,
      devices: Array.from(v.devices).join(' \n '),
      chips: Array.from(v.chips).join(' \n '),
    })
  })

  return (
    <div className="max-w-6xl mx-auto p-4 space-y-8 animate-fade-in mt-4 font-sans text-gray-800">
      {/* 公司信息卡片 */}
      <div
        className="glass-panel p-6 rounded-2xl relative group overflow-hidden border-t-4 border-blue-500"
        onMouseDown={(e) => window.createRipple && window.createRipple(e, e.currentTarget)}
      >
        <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-4 border-b border-gray-100 pb-4 relative z-10">
          <div
            className="group/copy flex items-center gap-2 cursor-pointer hover:bg-blue-50/50 p-2 -ml-2 rounded-lg transition-colors"
            onClick={() => handleCopy(data.company, 'companyName')}
          >
            <Building2 className="text-blue-600" size={28} />
            <h2 className="text-2xl font-black text-blue-900">{data.company || '未知企业'}</h2>
            {copiedId === 'companyName' ? (
              <Check size={18} className="text-green-500 animate-pulse" />
            ) : (
              <Copy
                size={16}
                className="text-blue-300 opacity-0 group-hover/copy:opacity-100 transition-opacity"
              />
            )}
          </div>
          <div className="flex items-center gap-2 bg-white/60 px-4 py-2 rounded-xl shadow-sm border border-blue-100">
            <span className="text-sm font-bold text-blue-800">客户归档：</span>
            <span className="text-blue-900 text-sm font-bold">{category}</span>
          </div>
        </div>
        <div className="space-y-4 text-sm relative z-10 text-gray-700">
          <p className="flex items-center gap-3">
            <span className="font-semibold w-20 text-gray-500">注册地址:</span>{' '}
            <span className="font-bold flex items-center gap-1 text-gray-800">
              <MapPin size={18} className="text-red-500" />
              {data.address || '未查明'}
            </span>
          </p>
          <p className="flex items-center gap-3">
            <span className="font-semibold w-20 text-gray-500">官方网站:</span>
            {safeWebsite ? (
              <a
                href={siteUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-1 text-blue-600 hover:text-blue-800 hover:underline font-bold text-base"
              >
                <LinkIcon size={18} /> {safeWebsite}
              </a>
            ) : (
              <span className="text-gray-400 font-bold">未查明</span>
            )}
          </p>
          <p className="flex items-center gap-3">
            <span className="font-semibold w-20 text-gray-500">业务类型:</span>{' '}
            <span className="bg-blue-100/80 text-blue-800 px-3 py-1 rounded-md text-sm font-bold shadow-sm border border-blue-200/50">
              {data.type || '未定义'}
            </span>
          </p>
          <div className="mt-6 p-5 bg-blue-50/50 rounded-xl relative border border-blue-100">
            <div className="flex gap-3 items-start">
              <Info className="text-blue-500 flex-shrink-0 mt-1" size={22} />
              <p className="leading-loose text-base text-justify">
                {data.profile || '暂无企业简介'}
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* 【执行切除】：决策人模块已被彻底剔除 */}

      {/* Crystal需求分析 */}
      {data.crystalSummary && (
        <div className="glass-panel p-6 rounded-2xl relative overflow-hidden glass-hover-fx border-t-4 border-amber-500">
          <h2 className="text-2xl font-black flex items-center gap-2 mb-6 text-amber-900 border-b border-gray-100 pb-4">
            <Activity className="text-amber-600" size={28} /> Crystal需求分析
          </h2>

          {Array.isArray(data.crystalSummary.freqAggregation) &&
            data.crystalSummary.freqAggregation.length > 0 && (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-6">
                {data.crystalSummary.freqAggregation.map((item, idx) => (
                  <div
                    key={idx}
                    className="bg-amber-50/60 rounded-xl p-5 border border-amber-200 hover:shadow-md transition-shadow"
                  >
                    <div className="text-2xl font-black text-amber-700 mb-2">{item.freq}</div>
                    <div className="text-sm text-gray-500 mb-2">
                      需求数量: <span className="font-bold text-gray-800">{item.count ?? '-'}</span>
                    </div>
                    {Array.isArray(item.devices) && item.devices.length > 0 && (
                      <div className="text-xs text-gray-600">
                        <span className="font-bold">适用设备: </span>
                        {item.devices.join('、')}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}

          {data.crystalSummary.monthlyEstimate && (
            <div className="bg-blue-50/60 rounded-xl p-4 border border-blue-200 mb-4">
              <span className="font-bold text-blue-800">月用量预估: </span>
              <span className="text-blue-900 font-medium">
                {data.crystalSummary.monthlyEstimate}
              </span>
            </div>
          )}

          {data.crystalSummary.salesAngle && (
            <div className="bg-green-50/60 rounded-xl p-4 border border-green-200">
              <span className="font-bold text-green-800">销售切入点: </span>
              <span className="text-green-900 font-medium">{data.crystalSummary.salesAngle}</span>
            </div>
          )}
        </div>
      )}

      {/* 终端产品全景图鉴 */}
      {Array.isArray(data.products) && data.products.length > 0 && (
        <div className="space-y-6">
          <div className="flex items-center justify-between px-2">
            <h2 className="text-2xl font-black flex items-center gap-2 text-indigo-900">
              <Cpu className="text-indigo-600" size={28} /> 终端实物全景图鉴
            </h2>
            <span className="text-sm font-bold text-indigo-700 bg-indigo-100 px-3 py-1 rounded-full shadow-sm border border-indigo-200">
              挖掘出 {data.products.length} 款产品
            </span>
          </div>

          {data.products.map((product, idx) => (
            <div
              key={idx}
              className="glass-panel p-6 rounded-2xl overflow-hidden glass-hover-fx"
              onMouseDown={(e) => window.createRipple && window.createRipple(e, e.currentTarget)}
            >
              <div className="flex flex-col lg:flex-row gap-8 relative z-10">
                <div className="lg:w-1/3 flex flex-col items-center text-center space-y-4">
                  <div className="w-full h-64 rounded-xl bg-white/60 border border-gray-100 relative overflow-hidden flex flex-col items-center justify-center shadow-inner group">
                    {/* 直接使用官网原图 URL，经过 proxy 解决跨域 */}
                    {product.imageUrl ? (
                      <img
                        src={`/api/image-proxy?url=${encodeURIComponent(product.imageUrl)}`}
                        alt={product.name || '产品图片'}
                        className="w-full h-full object-contain p-2 group-hover:scale-110 transition-transform duration-700"
                        onError={(e) => {
                          e.target.style.display = 'none'
                          e.target.nextSibling.style.display = 'flex'
                        }}
                      />
                    ) : null}
                    <div
                      className="absolute inset-0 flex-col items-center justify-center text-gray-400"
                      style={{ display: product.imageUrl ? 'none' : 'flex' }}
                    >
                      <Box size={48} className="mb-2 opacity-30" />
                      <span className="text-sm font-bold px-4">
                        {product.name || '官网未能成功抓取到此型号的图片'}
                      </span>
                    </div>
                  </div>
                  <h3 className="text-xl font-black text-gray-900 leading-tight">
                    {product.name || '未知设备'}
                  </h3>
                  <div className="w-full bg-indigo-50/80 p-5 rounded-xl text-left border border-indigo-100 shadow-sm">
                    <p className="text-xs text-indigo-700 font-bold mb-2 uppercase border-b border-indigo-200 pb-2">
                      芯片架构拆解 (BOM推演)
                    </p>
                    <p className="text-sm font-extrabold text-indigo-900 leading-loose whitespace-pre-wrap">
                      {product.chipPlatform || '分析中...'}
                    </p>
                  </div>
                </div>
                <div className="lg:w-2/3 flex flex-col justify-center">
                  <div className="flex items-center gap-2 mb-5 border-b border-gray-100 pb-3">
                    <Zap className="text-orange-500" size={24} />
                    <h4 className="font-black text-gray-900 text-lg">晶振解析</h4>
                  </div>
                  <div className="overflow-hidden rounded-xl bg-white/60 border border-gray-200 shadow-sm">
                    <table className="w-full text-left text-sm">
                      <thead className="bg-gray-100 text-gray-700 border-b border-gray-200">
                        <tr>
                          <th className="p-4 font-bold uppercase w-1/4">频率</th>
                          <th className="p-4 font-bold uppercase w-1/4">参数</th>
                          <th className="p-4 font-bold uppercase w-1/2">核心作用解析</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-gray-100">
                        {Array.isArray(product.crystals) &&
                          product.crystals.map((c, cIdx) => (
                            <tr key={cIdx} className="hover:bg-orange-50/60 transition-colors">
                              <td className="p-4 font-black text-orange-600 text-lg whitespace-nowrap">
                                {c.freq || '-'}
                              </td>
                              <td className="p-4">
                                <div className="font-bold text-gray-800">{c.package || '-'}</div>
                                <div className="text-gray-500 text-xs mt-1">
                                  CL:{c.loadCap || '-'} | Tol:{c.tolerance || '-'}
                                </div>
                              </td>
                              <td
                                className="p-4 text-gray-700 leading-relaxed text-justify bg-orange-50/30"
                                style={{ whiteSpace: 'pre-wrap' }}
                              >
                                {c.function || '-'}
                              </td>
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
      )}

      {/* AI FAE 建议 */}
      {data.strategy && (
        <div className="glass-panel p-6 rounded-2xl relative overflow-hidden glass-hover-fx border-t-4 border-green-500">
          <h2 className="text-xl font-black flex items-center gap-2 mb-4 text-green-800 border-b border-gray-100 pb-3">
            <Lightbulb className="text-green-600" size={24} /> AI FAE 极速选型建议
          </h2>
          <p className="leading-loose font-medium text-base text-justify bg-green-50/80 p-4 rounded-xl relative z-10 text-gray-800 border border-green-100">
            {data.strategy}
          </p>
        </div>
      )}

      {/* BOM聚合分析表 */}
      {aggregatedBomList.length > 0 && (
        <div className="glass-panel p-6 rounded-2xl relative overflow-hidden glass-hover-fx border-t-4 border-cyan-500">
          <div className="flex items-center mb-6 border-b border-gray-100 pb-4 relative z-10">
            <h2 className="text-2xl font-black flex items-center gap-2 text-cyan-900">
              <Table2 className="text-cyan-600" size={28} /> 晶振BOM聚合分析表
            </h2>
          </div>
          <div className="overflow-x-auto rounded-xl bg-white/60 border border-gray-200 relative z-10 shadow-sm">
            <table className="w-full text-left text-sm">
              <thead className="bg-gray-100 text-gray-700">
                <tr>
                  <th className="p-3 font-bold border-b border-gray-200">汇总频率</th>
                  <th className="p-3 font-bold border-b border-gray-200">封装参数</th>
                  <th className="p-3 font-bold border-b border-gray-200">应用设备 (折叠合并)</th>
                  <th className="p-3 font-bold border-b border-gray-200">涉及主控 (推演)</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {aggregatedBomList.map((item, idx) => (
                  <tr key={idx} className="hover:bg-cyan-50/50 transition-colors text-gray-800">
                    <td className="p-3 font-black text-orange-600 text-lg align-top">
                      {item.freq}
                    </td>
                    <td className="p-3 align-top">
                      <div className="font-bold">{item.package}</div>
                      <div className="text-xs mt-1 text-gray-500">{item.params}</div>
                    </td>
                    <td className="p-3 font-bold align-top whitespace-pre-wrap leading-loose text-blue-900">
                      {item.devices}
                    </td>
                    <td className="p-3 text-gray-600 align-top whitespace-pre-wrap leading-relaxed max-w-[250px]">
                      {item.chips}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
