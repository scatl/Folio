<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { refreshFileMedia } from '../api/client'
import type { ReviewFileRow } from '../api/types'
import { currentUser } from '../auth/session'

const props = defineProps<{
  files: ReviewFileRow[]
}>()

const emit = defineEmits<{
  close: []
  updated: [files: ReviewFileRow[]]
}>()

const items = ref<ReviewFileRow[]>([...props.files])
const refreshing = ref(false)
const refreshError = ref<string | null>(null)
const canRefresh = computed(() => currentUser.value?.role === 'ADMIN')

watch(
  () => props.files,
  (next) => {
    items.value = [...next]
  },
)

async function refresh() {
  if (refreshing.value || !items.value.length) return
  refreshing.value = true
  refreshError.value = null
  try {
    const next: ReviewFileRow[] = []
    for (const file of items.value) {
      next.push(await refreshFileMedia(file.id))
    }
    items.value = next
    emit('updated', next)
  } catch (e) {
    refreshError.value = e instanceof Error ? e.message : '刷新失败'
  } finally {
    refreshing.value = false
  }
}

function onOverlayClick(event: MouseEvent) {
  if (event.target === event.currentTarget) emit('close')
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') emit('close')
}

function formatSize(bytes: number | null | undefined) {
  if (bytes == null || bytes < 0) return null
  if (bytes >= 1_000_000_000) return `${(bytes / 1_000_000_000).toFixed(2)} GB`
  if (bytes >= 1_000_000) return `${(bytes / 1_000_000).toFixed(1)} MB`
  if (bytes >= 1_000) return `${(bytes / 1_000).toFixed(0)} KB`
  return `${bytes} B`
}

function formatDuration(ms: number | null | undefined) {
  if (ms == null || ms <= 0) return null
  const total = Math.round(ms / 1000)
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const seconds = total % 60
  if (hours > 0) return `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
  return `${minutes}:${String(seconds).padStart(2, '0')}`
}

function formatBitrate(bps: number | null | undefined) {
  if (bps == null || bps <= 0) return null
  if (bps >= 1_000_000) return `${(bps / 1_000_000).toFixed(1)} Mbps`
  return `${Math.round(bps / 1_000)} kbps`
}

function formatCodec(codec: string | null | undefined) {
  if (!codec) return null
  const map: Record<string, string> = {
    hevc: 'HEVC',
    h264: 'H.264',
    av1: 'AV1',
    mpeg2video: 'MPEG-2',
    mpeg4: 'MPEG-4',
    vp9: 'VP9',
    aac: 'AAC',
    ac3: 'Dolby Digital',
    eac3: 'Dolby Digital Plus',
    truehd: 'TrueHD',
    dts: 'DTS',
    dca: 'DTS',
    flac: 'FLAC',
    mp3: 'MP3',
    opus: 'Opus',
    subrip: 'SRT',
    ass: 'ASS',
    hdmv_pgs_subtitle: 'PGS',
    dvd_subtitle: 'VOBSUB',
  }
  return map[codec.toLowerCase()] ?? codec.toUpperCase()
}

function formatTime(value: string | null | undefined) {
  if (!value) return null
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value
  return date.toLocaleString()
}

function formatSampleRate(hz: number | null | undefined) {
  if (hz == null || hz <= 0) return null
  if (hz % 1000 === 0) return `${hz / 1000} kHz`
  return `${hz} Hz`
}

function formatChannelLayout(raw: string | null | undefined, channels: number | null | undefined) {
  if (raw) {
    const map: Record<string, string> = {
      mono: '单声道',
      stereo: '立体声',
    }
    return map[raw.toLowerCase()] ?? raw
  }
  if (channels) return `${channels} 声道`
  return null
}

function videoLine(file: ReviewFileRow) {
  const parts: string[] = []
  const codec = formatCodec(file.videoCodec)
  if (codec) parts.push(codec)
  if (file.videoProfile) parts.push(file.videoProfile)
  if (file.videoWidth && file.videoHeight) parts.push(`${file.videoWidth}×${file.videoHeight}`)
  if (file.videoPixelFormat) parts.push(file.videoPixelFormat)
  if (file.videoFrameRate) parts.push(`${Number(file.videoFrameRate).toFixed(3).replace(/\.?0+$/, '')} fps`)
  const rate = formatBitrate(file.videoBitrate)
  if (rate) parts.push(rate)
  if (file.videoBitDepth) parts.push(`${file.videoBitDepth} bit`)
  if (file.videoDynamicRange) parts.push(file.videoDynamicRange)
  return parts.join(' · ') || null
}

function audioLine(track: NonNullable<ReviewFileRow['audioTracks']>[number], index: number) {
  const parts = [`音轨 ${index + 1}`]
  const codec = formatCodec(track.codec)
  if (codec) parts.push(codec)
  if (track.profile) parts.push(track.profile)
  const layout = formatChannelLayout(track.channelLayout, track.channels)
  if (layout) parts.push(layout)
  const sample = formatSampleRate(track.sampleRate)
  if (sample) parts.push(sample)
  if (track.language) parts.push(track.language)
  const rate = formatBitrate(track.bitrate)
  if (rate) parts.push(rate)
  return parts.join(' · ')
}

function subtitleLine(track: NonNullable<ReviewFileRow['subtitleTracks']>[number], index: number) {
  const parts = [`字幕 ${index + 1}`]
  const codec = formatCodec(track.codec)
  if (codec) parts.push(codec)
  if (track.language) parts.push(track.language)
  return parts.join(' · ')
}

onMounted(() => {
  window.addEventListener('keydown', onKeydown)
})

onUnmounted(() => {
  window.removeEventListener('keydown', onKeydown)
})
</script>

<template>
  <div class="overlay" @click="onOverlayClick">
    <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="video-info-title">
      <header class="dialog-head">
        <h2 id="video-info-title">视频信息</h2>
        <div class="head-actions">
          <button
            v-if="canRefresh"
            type="button"
            class="refresh"
            :disabled="refreshing || !items.length"
            @click="refresh"
          >
            {{ refreshing ? '刷新中…' : '刷新视频元数据' }}
          </button>
          <button type="button" class="close" @click="emit('close')">关闭</button>
        </div>
      </header>

      <p v-if="refreshError" class="err">{{ refreshError }}</p>
      <p v-if="!items.length" class="empty">没有关联的视频文件</p>
      <article v-for="file in items" :key="file.id" class="file">
        <dl>
          <div>
            <dt>路径</dt>
            <dd>{{ file.locator }}</dd>
          </div>
          <div v-if="formatSize(file.fileSize)">
            <dt>大小</dt>
            <dd>{{ formatSize(file.fileSize) }}</dd>
          </div>
          <div v-if="file.container">
            <dt>容器</dt>
            <dd>{{ file.container }}</dd>
          </div>
          <div v-if="formatDuration(file.durationMs)">
            <dt>时长</dt>
            <dd>{{ formatDuration(file.durationMs) }}</dd>
          </div>
          <div v-if="formatTime(file.sourceModifiedAt)">
            <dt>修改时间</dt>
            <dd>{{ formatTime(file.sourceModifiedAt) }}</dd>
          </div>
          <div v-if="videoLine(file)">
            <dt>视频</dt>
            <dd>{{ videoLine(file) }}</dd>
          </div>
          <div v-for="(track, index) in file.audioTracks" :key="`a-${index}`">
            <dt v-if="index === 0">音频</dt>
            <dt v-else></dt>
            <dd>{{ audioLine(track, index) }}</dd>
          </div>
          <div v-for="(track, index) in file.subtitleTracks" :key="`s-${index}`">
            <dt v-if="index === 0">字幕</dt>
            <dt v-else></dt>
            <dd>{{ subtitleLine(track, index) }}</dd>
          </div>
        </dl>
      </article>
    </div>
  </div>
</template>

<style scoped>
.overlay {
  position: fixed;
  inset: 0;
  z-index: 50;
  display: grid;
  place-items: center;
  padding: 1.25rem;
  background: rgba(4, 6, 10, 0.45);
  backdrop-filter: blur(18px);
  -webkit-backdrop-filter: blur(18px);
}

.dialog {
  width: min(720px, 100%);
  max-height: min(860px, calc(100vh - 2.5rem));
  overflow: auto;
  border: 1px solid var(--line-strong);
  border-radius: var(--radius);
  background: linear-gradient(180deg, rgba(26, 31, 42, 0.98), rgba(14, 17, 24, 0.98));
  box-shadow: var(--shadow);
  padding: 1.25rem 1.35rem 1.5rem;
}

.dialog-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 1rem;
  margin-bottom: 1rem;
}

.dialog-head h2 {
  margin: 0;
  min-width: 0;
  font-family: var(--font-display);
  font-size: 1.45rem;
}

.head-actions {
  display: flex;
  flex-shrink: 0;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: 0.5rem;
}

.refresh,
.close {
  flex-shrink: 0;
  white-space: nowrap;
  border: 1px solid var(--line-strong);
  background: transparent;
  border-radius: 999px;
  padding: 0.45rem 0.9rem;
  cursor: pointer;
  color: var(--ink-muted);
}

.refresh:hover:not(:disabled),
.close:hover {
  color: var(--ink);
  border-color: var(--copper);
}

.refresh:disabled {
  opacity: 0.6;
  cursor: default;
}

.err {
  margin: 0 0 0.85rem;
  color: #e8a0a0;
}

.empty {
  margin: 0;
  color: var(--ink-muted);
}

.file + .file {
  margin-top: 1.25rem;
  padding-top: 1.15rem;
  border-top: 1px solid var(--line);
}

dl {
  display: grid;
  gap: 0.55rem;
  margin: 0;
}

dl > div {
  display: grid;
  grid-template-columns: 5.5rem 1fr;
  gap: 0.75rem;
  align-items: start;
}

dt {
  color: var(--ink-faint);
  font-size: 0.82rem;
}

dd {
  margin: 0;
  color: var(--ink-muted);
  line-height: 1.5;
  overflow-wrap: anywhere;
}

@media (max-width: 720px) {
  .overlay {
    padding: 0;
    place-items: end stretch;
  }

  .dialog {
    width: 100%;
    max-height: min(94dvh, 100%);
    border-radius: 18px 18px 0 0;
    padding-bottom: calc(1.25rem + var(--safe-bottom));
  }

  .dialog-head {
    align-items: flex-start;
    flex-wrap: wrap;
  }

  dl > div {
    grid-template-columns: 4.5rem minmax(0, 1fr);
    gap: 0.45rem;
  }
}
</style>
