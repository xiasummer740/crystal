import React, { useEffect } from 'react';
import Header from './components/Header';
import SearchConsole from './components/SearchConsole';
import PdfTranslator from './components/PdfTranslator';
import CustomerMap from './components/CustomerMap';
import CustomerDatabase from './components/CustomerDatabase';
import SettingsModal from './components/SettingsModal';
import { useStore } from './store';

// 全局流体力学背景与波纹拖尾引擎（内存安全版）
function FluidBackground() {
  useEffect(() => {
    let rafId;
    let lastSpawnTime = 0;

    const MAX_WAVES = 8; // 最多同时存在 8 个粒子

    const handleMouseMove = (e) => {
      cancelAnimationFrame(rafId);
      rafId = requestAnimationFrame(() => {
        const x = (e.clientX / window.innerWidth) * 100;
        const y = (e.clientY / window.innerHeight) * 100;
        document.documentElement.style.setProperty('--fluid-x', `${x}%`);
        document.documentElement.style.setProperty('--fluid-y', `${y}%`);

        const now = Date.now();
        if (now - lastSpawnTime > 60) {
          // 控制 DOM 粒子总数，防止内存泄漏
          const existingWaves = document.querySelectorAll('.wave-trail');
          if (existingWaves.length >= MAX_WAVES) {
            existingWaves[0].remove();
          }

          const wave = document.createElement('div');
          wave.className = 'wave-trail';
          const size = Math.random() * 100 + 100;
          wave.style.width = `${size}px`;
          wave.style.height = `${size}px`;
          wave.style.left = `${e.clientX}px`;
          wave.style.top = `${e.clientY}px`;

          document.body.appendChild(wave);
          setTimeout(() => wave.remove(), 1200);
          lastSpawnTime = now;
        }
      });
    };

    window.addEventListener('mousemove', handleMouseMove);
    return () => {
      cancelAnimationFrame(rafId);
      window.removeEventListener('mousemove', handleMouseMove);
      document.querySelectorAll('.wave-trail').forEach(el => el.remove());
    };
  }, []);
  return null;
}

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
        {activeTab === 'search' && <SearchConsole />}
        {activeTab === 'pdf' && <div className="w-full absolute inset-0 overflow-y-auto pb-20"><PdfTranslator /></div>}
        {activeTab === 'map' && <div className="w-full absolute inset-0 overflow-hidden"><CustomerMap /></div>}
        {activeTab === 'database' && <div className="w-full absolute inset-0 overflow-y-auto pb-20"><CustomerDatabase /></div>}
      </main>
    </div>
  );
}
