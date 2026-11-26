import { reactive, ref } from 'vue'

export const watchMarks = reactive<Record<number, string>>({})

export function noteWatch(workId: number, watchState: string) {
  watchMarks[workId] = watchState
}

/** 想看有变动时递增，首页据此重拉清单。 */
export const watchlistTick = ref(0)

export function noteWatchlist() {
  watchlistTick.value += 1
}

/** 播放列表有变动时递增，首页据此重拉。 */
export const playlistTick = ref(0)

export function notePlaylist() {
  playlistTick.value += 1
}
