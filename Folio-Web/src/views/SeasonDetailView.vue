<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getSeason, getWorkPlayback } from '../api/client'
import type { PlaybackProgress, ReviewFileRow } from '../api/types'
import type { SeasonDetailView as SeasonDetail } from '../api/types'
import PosterMedia from '../components/PosterMedia.vue'
import WorkDetailSkeleton from '../components/WorkDetailSkeleton.vue'
import { useArtworkTint } from '../lib/artworkColor'

const route = useRoute()
const router = useRouter()

const loading = ref(true)
const error = ref<string | null>(null)
const detail = ref<SeasonDetail | null>(null)
const seasonProgress = ref<PlaybackProgress | null>(null)
const fileChoices = ref<ReviewFileRow[] | null>(null)

const season = computed(() => detail.value?.season ?? null)

const posterUrl = computed(() => {
  const arts = season.value?.artworks ?? []
  return (
    arts.find((a) => a.kind === 'poster')?.remoteUrl ??
    arts.find((a) => a.kind === 'still')?.remoteUrl ??
    arts[0]?.remoteUrl ??
    null
  )
})

const { pageStyle } = useArtworkTint(posterUrl)

const seasonTitle = computed(() => {
  if (!season.value) return ''
  const base = `第 ${season.value.seasonNumber} 季`
  const name = season.value.name?.trim()
  if (!name || name === base || /^season\s*\d+$/i.test(name)) return base
  return `${base} ${name}`
})

function stillOfEpisode(artworks: { kind: string; remoteUrl: string }[]) {
  return artworks.find((a) => a.kind === 'still')?.remoteUrl ?? artworks[0]?.remoteUrl ?? null
}

const seasonPlayable = computed(() => (season.value?.localEpisodeCount ?? 0) > 0)
const continuingSeason = computed(() => {
  const progress = seasonProgress.value
  const number = season.value?.seasonNumber
  return progress != null && number != null && progress.seasonNumber === number && progress.libraryFileId > 0
})
const playHint = computed(() => {
  const progress = seasonProgress.value
  if (!continuingSeason.value || !progress) return ''
  const label =
    progress.seasonNumber != null && progress.episodeNumber != null
      ? `S${progress.seasonNumber}E${progress.episodeNumber}`
      : ''
  if (progress.resumePositionMs != null && progress.resumePositionMs > 0) {
    return [label, `已看至 ${formatClock(progress.resumePositionMs)}`].filter(Boolean).join(' · ')
  }
  return [label, '下一集'].filter(Boolean).join(' · ')
})

function formatClock(ms: number) {
  const total = Math.max(0, Math.floor(ms / 1000))
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const seconds = total % 60
  if (hours > 0) return `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
  return `${minutes}:${String(seconds).padStart(2, '0')}`
}

function openFile(fileId: number) {
  fileChoices.value = null
  void router.push({ name: 'play', params: { fileId: String(fileId) } })
}

function openSeasonPlay() {
  const current = detail.value
  if (!current) return
  const progress = seasonProgress.value
  if (
    progress &&
    progress.seasonNumber === current.season.seasonNumber &&
    progress.libraryFileId > 0
  ) {
    openFile(progress.libraryFileId)
    return
  }
  const episode = current.season.episodes.find((item) => item.files.length > 0)
  const files = episode?.files ?? []
  if (files.length === 1) openFile(files[0].id)
  else if (files.length > 1) fileChoices.value = files
}

function openEpisode(episodeNumber: number) {
  if (!detail.value) return
  const raw = route.query.library
  const value = Array.isArray(raw) ? raw[0] : raw
  const libraryId = Number(value)
  const libraryQuery = Number.isInteger(libraryId) && libraryId > 0 ? { library: String(libraryId) } : {}
  void router.push({
    name: 'episode',
    params: {
      id: String(detail.value.workId),
      seasonNumber: String(detail.value.season.seasonNumber),
      episodeNumber: String(episodeNumber),
    },
    query: libraryQuery,
  })
}

async function load(workId: number, seasonNumber: number) {
  if (!Number.isFinite(workId) || !Number.isFinite(seasonNumber)) {
    error.value = '无效的季参数'
    loading.value = false
    return
  }
  loading.value = true
  error.value = null
  detail.value = null
  seasonProgress.value = null
  fileChoices.value = null
  try {
    detail.value = await getSeason(workId, seasonNumber)
    const progress = await getWorkPlayback(workId).catch(() => null)
    if (detail.value?.workId === workId && detail.value.season.seasonNumber === seasonNumber) {
      seasonProgress.value = progress
    }
  } catch (e) {
    error.value = e instanceof Error ? e.message : '季详情加载失败'
  } finally {
    loading.value = false
  }
}

function goBack() {
  // 优先 history.back，避免 push 回作品页后多叠一层导致作品页再 back 又进季详情
  if (window.history.state?.back) {
    router.back()
    return
  }
  const raw = route.query.library
  const value = Array.isArray(raw) ? raw[0] : raw
  const libraryId = Number(value)
  const libraryQuery = Number.isInteger(libraryId) && libraryId > 0 ? { library: String(libraryId) } : {}
  if (detail.value) {
    void router.push({
      name: 'work',
      params: { id: String(detail.value.workId) },
      query: libraryQuery,
    })
    return
  }
  void router.push({ name: 'wall', query: libraryQuery })
}

watch(
  () => [route.params.id, route.params.seasonNumber] as const,
  ([id, seasonNumber]) => {
    void load(Number(id), Number(seasonNumber))
  },
)

onMounted(() => {
  void load(Number(route.params.id), Number(route.params.seasonNumber))
})
</script>

<template>
  <div class="detail" :style="pageStyle">
    <WorkDetailSkeleton v-if="loading" />

    <div v-else-if="error" class="hero">
      <div class="hero-shade" />
      <div class="hero-inner">
        <button class="back" type="button" @click="goBack">← 返回</button>
        <p class="state error">{{ error }}</p>
      </div>
    </div>

    <template v-else-if="detail && season">
      <div class="hero">
        <div class="hero-shade" />
        <div class="hero-inner">
          <button class="back" type="button" @click="goBack">← 返回 {{ detail.workTitle }}</button>

          <div class="hero-body">
            <div class="hero-poster">
              <PosterMedia :src="posterUrl" :alt="seasonTitle" loading="eager" />
            </div>
            <div class="hero-copy">
              <p class="eyebrow">{{ detail.workTitle }}</p>
              <h1>{{ seasonTitle }}</h1>
              <div class="chips">
                <span>{{ season.localEpisodeCount }} 集本地</span>
                <span v-if="season.airDate">{{ season.airDate }}</span>
                <span v-if="season.episodeCount != null">共 {{ season.episodeCount }} 集</span>
              </div>
              <div v-if="seasonPlayable" class="play-actions">
                <button type="button" class="play-primary" @click="openSeasonPlay">
                  {{ continuingSeason ? '继续观看' : '播放本季' }}
                </button>
              </div>
              <p v-if="playHint" class="play-hint">{{ playHint }}</p>
            </div>
          </div>
          <p v-if="season.overview" class="overview">{{ season.overview }}</p>
        </div>
      </div>

      <div class="body">
        <section class="block">
          <h2>剧集（{{ season.episodes.length }}）</h2>
          <ul v-if="season.episodes.length" class="episode-list">
            <li
              v-for="ep in season.episodes"
              :key="ep.id"
              class="episode-item"
              role="link"
              tabindex="0"
              @click="openEpisode(ep.episodeNumber)"
              @keydown.enter.prevent="openEpisode(ep.episodeNumber)"
            >
              <div class="ep-still">
                <PosterMedia
                  :src="stillOfEpisode(ep.artworks)"
                  :alt="ep.title || `E${ep.episodeNumber}`"
                />
              </div>
              <div>
                <strong>
                  E{{ ep.episodeNumber }}
                  <template v-if="ep.absoluteNumber != null">（绝对集 {{ ep.absoluteNumber }}）</template>
                  · {{ ep.title || '未命名' }}
                </strong>
                <small class="dim">
                  <template v-if="ep.files.length">本地</template>
                  <template v-if="ep.files.length && ep.airDate"> · </template>
                  <template v-if="ep.airDate">{{ ep.airDate }}</template>
                  <template v-if="ep.runtimeMinutes"> · {{ ep.runtimeMinutes }} 分钟</template>
                  <template v-if="ep.voteAverage != null">
                    · 评分 {{ Number(ep.voteAverage).toFixed(1) }}
                    <template v-if="ep.voteCount != null">({{ ep.voteCount }})</template>
                  </template>
                </small>
                <p v-if="ep.overview">{{ ep.overview }}</p>
              </div>
            </li>
          </ul>
          <p v-else class="empty">暂无分集资料</p>
        </section>
      </div>
    </template>

    <Teleport to="body">
      <div
        v-if="fileChoices"
        class="file-pick"
        role="dialog"
        aria-modal="true"
        aria-label="选择要播放的文件"
        @click.self="fileChoices = null"
      >
        <div class="file-pick-card">
          <h2>选择要播放的文件</h2>
          <button v-for="file in fileChoices" :key="file.id" type="button" @click="openFile(file.id)">
            {{ file.fileName }}
          </button>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.detail {
  --detail-bg: var(--bg-deep);
  min-height: 100vh;
  overflow-x: clip;
  background-color: var(--detail-bg);
  animation: fade-in 0.45s cubic-bezier(0.22, 1, 0.36, 1) both;
}

.hero {
  position: relative;
  min-height: min(48vh, 420px);
  background-color: var(--detail-bg);
}

.hero-shade {
  position: absolute;
  inset: 0;
  background:
    linear-gradient(180deg, rgba(8, 10, 14, 0.6) 0%, rgba(8, 10, 14, 0.4) 42%, rgba(8, 10, 14, 0.7) 75%, var(--detail-bg) 100%),
    radial-gradient(ellipse at 20% 10%, rgba(212, 165, 116, 0.12), transparent 55%);
}

.hero-inner {
  position: relative;
  z-index: 1;
  width: min(1100px, calc(100% - 2.5rem));
  margin: 0 auto;
  padding: 1.5rem 0 2rem;
  min-height: inherit;
  display: flex;
  flex-direction: column;
}

.back {
  align-self: flex-start;
  margin-bottom: 1.5rem;
  border: 1px solid var(--line-strong);
  background: rgba(10, 12, 16, 0.45);
  color: var(--ink);
  border-radius: 999px;
  padding: 0.55rem 1rem;
  cursor: pointer;
  font-weight: 600;
  font-size: 0.9rem;
  backdrop-filter: blur(8px);
  transition:
    border-color 0.2s ease,
    transform 0.2s ease;
}

.back:hover {
  border-color: rgba(212, 165, 116, 0.5);
  transform: translateX(-2px);
}

.state {
  margin: auto 0;
  padding: 3rem 0;
  color: var(--ink-muted);
}

.state.error {
  color: var(--danger);
}

.hero-body {
  --poster-width: 160px;
  --poster-height: calc(var(--poster-width) * 3 / 2);
  margin-top: auto;
  display: grid;
  grid-template-columns: var(--poster-width) minmax(0, 1fr);
  gap: 1.5rem;
  align-items: stretch;
}

.hero-poster {
  width: var(--poster-width);
  height: var(--poster-height);
  border-radius: 12px;
  border: 1px solid var(--line-strong);
  box-shadow: var(--shadow);
  background: var(--bg-soft);
  overflow: hidden;
}

.hero-copy {
  height: var(--poster-height);
  max-height: var(--poster-height);
  min-height: 0;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  overflow: hidden;
}

.eyebrow {
  margin: 0;
  color: var(--ink-faint);
  font-size: 0.9rem;
}

.hero-copy h1 {
  margin: 0.35rem 0 0;
  font-family: var(--font-display);
  font-size: clamp(1.8rem, 4vw, 2.8rem);
  line-height: 1.1;
  letter-spacing: -0.03em;
}

.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 0.45rem;
  margin-top: 0.9rem;
}

.chips span {
  display: inline-flex;
  align-items: center;
  padding: 0.2rem 0.7rem;
  min-height: 1.7rem;
  border-radius: 999px;
  border: 1px solid var(--line);
  background: rgba(10, 12, 16, 0.35);
  color: var(--ink-muted);
  font-size: 0.82rem;
}

.overview {
  margin: 0.85rem 0 0;
  color: var(--ink-muted);
  line-height: 1.6;
  font-size: 0.95rem;
}

.body {
  width: min(1100px, calc(100% - 2.5rem));
  margin: 0 auto;
  padding: 0.5rem 0 3.5rem;
}

.block h2 {
  margin: 0 0 1rem;
  font-family: var(--font-display);
  font-size: 1.35rem;
}

.episode-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  gap: 1rem;
}

.episode-list li {
  display: grid;
  grid-template-columns: 168px minmax(0, 1fr);
  gap: 1rem;
  padding: 0.85rem 0;
  border-top: 1px solid var(--line);
  cursor: pointer;
}

.episode-list li:first-child {
  border-top: 0;
  padding-top: 0;
}

.episode-list li > div:not(.ep-still) {
  display: grid;
  gap: 0.35rem;
  min-width: 0;
  align-content: start;
}

.episode-list strong {
  display: block;
  line-height: 1.35;
}

.episode-list small,
.dim {
  display: block;
  line-height: 1.4;
  color: var(--ink-faint);
  font-size: 0.82rem;
}

.play-hint {
  margin: 0.55rem 0 0;
  color: var(--ink-muted);
  font-size: 0.82rem;
}

.ep-still {
  width: 100%;
  aspect-ratio: 16 / 9;
  border-radius: 10px;
  border: 1px solid var(--line);
  background: var(--bg-soft);
  overflow: hidden;
}

.episode-list p {
  margin: 0;
  color: var(--ink-muted);
  line-height: 1.55;
  font-size: 0.9rem;
}

.file-pick {
  position: fixed;
  inset: 0;
  z-index: 80;
  display: grid;
  place-items: end center;
  padding: 1.25rem;
  background: rgba(4, 6, 10, 0.45);
  backdrop-filter: blur(18px);
}

.file-pick-card {
  width: min(480px, 100%);
  margin-bottom: 1.5rem;
  padding: 1rem 0.4rem 0.6rem;
  border: 1px solid var(--line-strong);
  border-radius: 16px;
  background: rgba(16, 19, 26, 0.96);
}

.file-pick-card h2 {
  margin: 0 0.8rem 0.6rem;
  font-size: 1rem;
}

.file-pick-card button {
  display: block;
  width: 100%;
  padding: 0.75rem 0.8rem;
  border: 0;
  background: transparent;
  color: var(--ink);
  text-align: left;
  cursor: pointer;
}

.empty {
  margin: 0;
  color: var(--ink-muted);
}

@keyframes fade-in {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}

@media (max-width: 720px) {
  .hero {
    min-height: 0;
  }

  .hero-inner,
  .body {
    width: min(100% - 1.1rem, 1100px);
  }

  .hero-inner {
    padding: calc(0.9rem + var(--safe-top)) 0 1.35rem;
  }

  .body {
    padding-bottom: calc(2.5rem + var(--safe-bottom));
  }

  .back {
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .hero-body {
    --poster-width: 120px;
    grid-template-columns: var(--poster-width) minmax(0, 1fr);
    gap: 0.85rem;
  }

  .hero-copy {
    height: var(--poster-height);
    max-height: var(--poster-height);
  }

  .hero-copy h1 {
    overflow-wrap: anywhere;
  }

  .episode-list li {
    grid-template-columns: minmax(0, 1fr);
    gap: 0.65rem;
  }

  .ep-still {
    max-width: 100%;
  }
}

@media (prefers-reduced-motion: reduce) {
  .detail {
    animation: none;
  }
}
</style>
