import React, { useEffect } from 'react';
import Header from './components/Header';
import SearchLead from './components/SearchLead';
import ResultDisplay from './components/ResultDisplay';
import PdfTranslator from './components/PdfTranslator';
import CustomerMap from './components/CustomerMap';
import CustomerDatabase from './components/CustomerDatabase';
import SettingsModal from './components/SettingsModal';
import { useStore } from './store';

// 全局流体力学背景与波纹拖尾引擎
function FluidBackground() {
  useEffect(() => {
    let rafId;
    let lastSpawnTime = 0;
    
    const handleMouseMove = (e) => {
      cancelAnimationFrame(rafId);
      rafId = requestAnimationFrame(() => {
        // 1. 移动底部光晕巨幕
        const x = (e.clientX / window.innerWidth) * 100;
        const y = (e.clientY / window.innerHeight) * 100;
        document.documentElement.style.setProperty('--fluid-x', `${x}%`);
        document.documentElement.style.setProperty('--fluid-y', `${y}%`);

        // 2. 鼠标划动生成水波涟漪粒子 (每 60 毫秒生成一个)
        const now = Date.now();
        if (now - lastSpawnTime > 60) {
          const wave = document.createElement('div');
          wave.className = 'wave-trail';
          
          // 随机生成 100px 到 200px 左右的初始波纹大小
          const size = Math.random() * 100 + 100; 
          wave.style.width = `${size}px`;
          wave.style.height = `${size}px`;
          wave.style.left = `${e.clientX}px`;
          wave.style.top = `${e.clientY}px`;
          
          document.body.appendChild(wave);
          
          // 动画结束后清理 DOM 节点
          setTimeout(() => wave.remove(), 1200);
          lastSpawnTime = now;
        }
      });
    };
    
    window.addEventListener('mousemove', handleMouseMove);
    return () => window.removeEventListener('mousemove', handleMouseMove);
  }, []);
  return null;
}

// 点击水波纹挂载器
window.createRipple = function(event, element) {
  const circle = document.createElement("span");
  const diameter = Math.max(element.clientWidth, element.clientHeight);
  const radius = diameter / 2;
  circle.style.width = circle.style.height = `${diameter}px`;
  circle.style.left = `${event.clientX - element.getBoundingClientRect().left - radius}px`;
  circle.style.top = `${event.clientY - element.getBoundingClientRect().top - radius}px`;
  circle.classList.add("mouse-ripple");
  
  const existing = element.querySelector('.mouse-ripple');
  if (existing) existing.remove();
  
  element.appendChild(circle);
};

export default function App() {
  const { activeTab } = useStore();
  
  return (
    <div className="min-h-screen flex flex-col relative text-gray-800">
      <FluidBackground />
      <Header />
      <SettingsModal />
      
      <main className="flex-1 w-full relative z-10">
        {activeTab === 'search' && (
          <div className="w-full absolute inset-0 overflow-y-auto pb-20 scroll-smooth">
            <SearchLead />
            <ResultDisplay />
          </div>
        )}
        {activeTab === 'pdf' && <div className="w-full absolute inset-0 overflow-y-auto pb-20"><PdfTranslator /></div>}
        {activeTab === 'map' && <div className="w-full absolute inset-0 overflow-hidden"><CustomerMap /></div>}
        {activeTab === 'database' && <div className="w-full absolute inset-0 overflow-y-auto pb-20"><CustomerDatabase /></div>}
      </main>
    </div>
  );
}
