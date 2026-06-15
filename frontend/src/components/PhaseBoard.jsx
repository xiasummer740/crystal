import React from 'react';
import { useStore } from '../store';
import { Loader2, CheckCircle2, XCircle, Clock, Activity } from 'lucide-react';

const phaseIcons = {
  website: '🌐',
  search: '🔍',
  ai: '🧠',
  done: '📊',
};

const statusConfig = {
  pending: { icon: Clock, className: 'text-gray-400', label: '等待中' },
  running: { icon: Loader2, className: 'text-blue-500 animate-spin', label: '进行中' },
  success: { icon: CheckCircle2, className: 'text-green-500', label: '已完成' },
  error: { icon: XCircle, className: 'text-red-500', label: '失败' },
};

export default function PhaseBoard() {
  const { searchPhases, loading, streamStatus } = useStore();

  if (!loading) return null;

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2 mb-4">
        <Activity size={18} className="text-blue-600" />
        <h3 className="font-black text-sm text-blue-900 tracking-wide">执行进度</h3>
      </div>
      {searchPhases.map((phase) => {
        const icon = phaseIcons[phase.key] || '📋';
        const st = statusConfig[phase.status] || statusConfig.pending;
        const Icon = st.icon;
        const isRunning = phase.status === 'running';

        return (
          <div key={phase.key} className={`flex items-center gap-3 p-3 rounded-xl transition-all ${
            isRunning ? 'bg-blue-50 border border-blue-200 shadow-sm' : 'bg-white/50'
          }`}>
            <span className="text-lg">{icon}</span>
            <div className="flex-1 min-w-0">
              <div className="flex items-center justify-between">
                <span className={`text-sm font-bold ${isRunning ? 'text-blue-800' : 'text-gray-600'}`}>
                  {phase.label}
                </span>
                {phase.status === 'running' && streamStatus && (
                  <span className="text-[10px] text-blue-500 font-bold truncate max-w-[100px] ml-2">
                    {streamStatus}
                  </span>
                )}
              </div>
              <div className="flex items-center gap-1.5 mt-0.5">
                <Icon size={12} className={st.className} />
                <span className="text-[10px] font-bold">{st.label}</span>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
