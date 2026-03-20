import { create } from 'zustand';

export const useStore = create((set) => ({
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

  // 新增流式状态
  streamStatus: '',
  setStreamStatus: (status) => set({ streamStatus: status }),
  
  streamText: '',
  setStreamText: (text) => set({ streamText: text }),
  clearStream: () => set({ streamStatus: '', streamText: '' })
}));
