import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export const useStore = create(
  persist(
    (set) => ({
      activeTab: 'search',
      setActiveTab: (tab) => set({ activeTab: tab }),

      settingsOpen: false,
      setSettingsOpen: (open) => set({ settingsOpen: open }),

      searchResult: null,
      setResult: (res) => set({ searchResult: res }),

      loading: false,
      setLoading: (state) => set({ loading: state }),

      error: null,
      setError: (err) => set({ error: err }),

      refreshTrigger: 0,
      triggerRefresh: () => set((state) => ({ refreshTrigger: state.refreshTrigger + 1 })),

      streamStatus: '',
      setStreamStatus: (status) => set({ streamStatus: status }),

      streamText: '',
      setStreamText: (text) => set({ streamText: text }),
      clearStream: () => set({ streamStatus: '', streamText: '' }),

      searchPhases: [
        { key: 'website', label: '官网抓取', status: 'pending' },
        { key: 'search', label: '网络搜索', status: 'pending' },
        { key: 'ai', label: 'AI分析', status: 'pending' },
        { key: 'done', label: '报告生成', status: 'pending' },
      ],
      setPhaseStatus: (key, status) => set((state) => ({
        searchPhases: state.searchPhases.map(p =>
          p.key === key ? { ...p, status } : p
        )
      })),
      resetPhases: () => set((state) => ({
        searchPhases: state.searchPhases.map(p => ({ ...p, status: 'pending' }))
      })),

      generatedEmail: '',
      setGeneratedEmail: (email) => set({ generatedEmail: email }),
    }),
    {
      name: 'crystal-ui-storage',
      // 只持久化 UI 状态，不持久化大数据（searchResult 每次查完都会重新设置）
      partialize: (state) => ({
        activeTab: state.activeTab
      })
    }
  )
);
