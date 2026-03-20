import React, { useState, useCallback } from 'react';
import { UploadCloud, FileText, Loader2, CheckCircle2, AlertCircle, Cpu, Zap, Lightbulb, Activity } from 'lucide-react';
import { useDropzone } from 'react-dropzone';
import axios from 'axios';

export default function PdfTranslator() {
  const [file, setFile] = useState(null);
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);

  const onDrop = useCallback(acceptedFiles => {
    if (acceptedFiles.length > 0) {
      setFile(acceptedFiles[0]);
      setError(null);
      setResult(null);
    }
  }, []);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: { 'application/pdf': ['.pdf'] },
    maxFiles: 1
  });

  const handleTranslate = async () => {
    if (!file) return;
    setLoading(true);
    setError(null);
    const formData = new FormData();
    formData.append('file', file);

    try {
      const res = await axios.post('/api/translate-pdf', formData, {
        headers: { 'Content-Type': 'multipart/form-data' }
      });
      // 现在的 res.data.data 是一个完美的 JSON 字典！
      setResult(res.data.data);
    } catch (err) {
      setError(err.response?.data?.message || '解析引擎对接失败，请检查网络或API配置');
    } finally {
      setLoading(false);
    }
  };

  // 动态渲染结构化数据或纯文本兜底
  const renderResult = () => {
    if (!result) return null;
    
    if (typeof result === 'string') {
      return <div className="whitespace-pre-wrap text-slate-800 leading-loose">{result}</div>;
    }

    return (
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 relative z-10">
        
        <div className="bg-gradient-to-br from-indigo-50 to-white p-6 rounded-2xl border border-indigo-100 shadow-[0_4px_20px_rgba(99,102,241,0.05)] md:col-span-2">
          <div className="flex items-center gap-2 mb-3"><Cpu className="text-indigo-500"/><h4 className="font-black text-indigo-900 text-lg">主控芯片核心型号</h4></div>
          <p className="text-indigo-700 font-black text-3xl tracking-tight">{result.chipName || '型号解析中...'}</p>
        </div>

        <div className={`p-6 rounded-2xl border shadow-[0_4px_20px_rgba(0,0,0,0.03)] ${result.hasCrystalRequirement === false ? 'bg-slate-50 border-slate-200' : 'bg-gradient-to-br from-rose-50 to-orange-50 border-rose-100'}`}>
          <div className="flex items-center gap-2 mb-3">
             <Activity className={result.hasCrystalRequirement === false ? 'text-slate-400' : 'text-rose-500'}/>
             <h4 className={`font-black text-lg ${result.hasCrystalRequirement === false ? 'text-slate-600' : 'text-rose-900'}`}>外接晶振需求</h4>
          </div>
          <div className="mt-2">
            {result.hasCrystalRequirement === false ? (
              <span className="inline-block bg-slate-200 text-slate-700 font-black px-4 py-2 rounded-lg text-lg">不需要 (内置)</span>
            ) : (
              <span className="inline-block bg-rose-500 text-white shadow-md font-black px-4 py-2 rounded-lg text-lg animate-pulse">必须外接 (YES)</span>
            )}
          </div>
        </div>

        <div className="bg-gradient-to-br from-teal-50 to-white p-6 rounded-2xl border border-teal-100 shadow-[0_4px_20px_rgba(20,184,166,0.05)]">
          <div className="flex items-center gap-2 mb-3"><Zap className="text-teal-500"/><h4 className="font-black text-teal-900 text-lg">晶振硬性参数指标</h4></div>
          <p className="text-teal-800 font-bold leading-relaxed whitespace-pre-wrap">{result.crystalParams || '规格书中未提及确切参数'}</p>
        </div>

        <div className="bg-gradient-to-br from-blue-50 to-white p-6 rounded-2xl border border-blue-100 shadow-[0_4px_20px_rgba(59,130,246,0.05)] md:col-span-2">
          <div className="flex items-center gap-2 mb-3"><FileText className="text-blue-500"/><h4 className="font-black text-blue-900 text-lg">芯片规格书摘要</h4></div>
          <p className="text-slate-700 leading-relaxed text-justify font-medium">{result.summary || '无'}</p>
        </div>

        <div className="bg-gradient-to-br from-amber-50 to-white p-6 rounded-2xl border border-amber-100 shadow-[0_4px_20px_rgba(245,158,11,0.05)] md:col-span-2">
          <div className="flex items-center gap-2 mb-3"><Lightbulb className="text-amber-500"/><h4 className="font-black text-amber-900 text-lg">FAE 实战销售建议</h4></div>
          <p className="text-amber-800 font-bold leading-relaxed whitespace-pre-wrap">{result.salesAdvice || '无'}</p>
        </div>

      </div>
    );
  };

  return (
    <div className="max-w-4xl mx-auto p-4 mt-8 animate-fade-in font-sans">
      
      <div className="premium-glass p-8 md:p-10 rounded-[2rem] shadow-[0_10px_40px_rgba(0,0,0,0.08)] border border-white/80 relative z-10 overflow-hidden">
        
        <div className="text-center mb-10 relative z-10">
          <div className="inline-flex items-center justify-center p-4 bg-white/60 backdrop-blur-md rounded-2xl shadow-[0_8px_30px_rgb(0,0,0,0.08)] mb-6 border border-white/80">
            <FileText className="text-teal-600 drop-shadow-md" size={40}/>
          </div>
          <h2 className="text-4xl md:text-5xl font-black tracking-tight mb-4 text-slate-800">
            英文规格书 <span className="text-transparent bg-clip-text bg-gradient-to-r from-teal-500 to-emerald-500">极速破译器</span>
          </h2>
        </div>

        <div {...getRootProps()} className={`border-2 border-dashed rounded-2xl p-12 text-center cursor-pointer transition-all duration-300 relative z-10 ${isDragActive ? 'border-teal-500 bg-teal-50/80 scale-[1.02] shadow-lg' : 'border-slate-300 bg-white/50 hover:bg-white/80 hover:border-teal-400 hover:shadow-md'}`}>
          <input {...getInputProps()} />
          <UploadCloud className={`mx-auto mb-4 transition-colors ${isDragActive ? 'text-teal-600' : 'text-slate-400'}`} size={56} />
          {file ? (
            <div className="flex flex-col items-center justify-center gap-2">
               <span className="text-teal-700 font-black text-xl">{file.name}</span>
               <span className="text-sm font-bold text-teal-600/70 bg-teal-100/50 px-3 py-1 rounded-full">已就绪，随时可解析</span>
            </div>
          ) : (
            <div className="text-slate-600 font-black text-lg">
               点击此处选择，或将 PDF 直接拖拽到雷达区
               <div className="text-sm text-slate-400 mt-2 font-bold">单次最高支持 200MB 的纯正原厂 Datasheet</div>
            </div>
          )}
        </div>
        
        <button onClick={handleTranslate} disabled={!file || loading} className="w-full mt-8 bg-gradient-to-r from-teal-500 via-emerald-500 to-green-500 hover:from-teal-400 hover:via-emerald-400 hover:to-green-400 text-white font-black text-lg p-5 rounded-[1.25rem] shadow-[0_10px_30px_rgba(20,184,166,0.3)] hover:shadow-[0_15px_40px_rgba(20,184,166,0.5)] hover:-translate-y-1 transition-all duration-300 flex items-center justify-center gap-3 disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none relative z-10">
          {loading ? <><Loader2 className="animate-spin" size={24} /> 正在解构 PDF 底层参数，请稍候...</> : <><Cpu size={24} /> 启动参数提纯与智能翻译</>}
        </button>

        {error && (
          <div className="mt-6 p-4 bg-red-50 text-red-600 border border-red-100 rounded-xl flex items-center gap-3 font-bold shadow-sm relative z-10">
            <AlertCircle size={22}/> {error}
          </div>
        )}
      </div>

      {result && (
        <div className="mt-8 premium-glass p-8 md:p-10 rounded-[2rem] shadow-[0_10px_40px_rgba(0,0,0,0.08)] border border-white/80 animate-fade-in relative z-10">
          <h3 className="text-2xl font-black text-slate-800 mb-8 flex items-center gap-3 border-b border-slate-200/60 pb-5">
            <div className="w-10 h-10 bg-green-100 rounded-full flex items-center justify-center"><CheckCircle2 className="text-green-600" size={24}/></div>
            规格书深度破译报告
          </h3>
          {renderResult()}
        </div>
      )}
    </div>
  );
}
