import { onMounted, watch } from 'vue'

import { useClockStore } from '@/stores/clock'

// Runs `loader` when the view mounts and again every time simulated time changes.
export function useClockRefresh(loader: () => unknown) {
  const clock = useClockStore()

  onMounted(loader)
  watch(() => clock.revision, loader)
}
