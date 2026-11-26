<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getEpisode, getFilePlayback } from '../api/client'
import type {
  ArtworkView,
  CreditView,
  EpisodeDetailView as EpisodeDetail,
  ReviewFileRow,
} from '../api/types'
import ArtworkRail from '../components/ArtworkRail.vue'
import PeopleRail, { type PersonItem } from '../components/PeopleRail.vue'
import PosterMedia from '../components/PosterMedia.vue'
import WorkDetailSkeleton from '../components/WorkDetailSkeleton.vue'
import VideoInfoDialog from '../components/VideoInfoDialog.vue'
import PlaylistPickerDialog from '../components/PlaylistPickerDialog.vue'
import { useArtworkTint } from '../lib/artworkColor'

const route = useRoute()
const router = useRouter()

const loading = ref(true)
const error = ref<string | null>(null)
const detail = ref<EpisodeDetail | null>(null)
const videoFiles = ref<ReviewFileRow[] | null>(null)
const resumeFileId = ref<number | null>(null)
const moreOpen = ref(false)
const playlistOpen = ref(false)
const moreWrap = ref<HTMLElement | null>(null)

const episode = computed(() => detail.value?.episode ?? null)

const stillUrl = computed(() => {
  const arts = episode.value?.artworks ?? []
  return (
    arts.find((a) => a.kind === 'still')?.remoteUrl ??
    arts.find((a) => a.kind === 'poster')?.remoteUrl ??
    arts[0]?.remoteUrl ??
    null
  )
})

const { pageStyle } = useArtworkTint(stillUrl)

const episodeTitle = computed(() => {
  if (!episode.value) return ''
  const name = episode.value.title?.trim()
  if (!name) return `第 ${episode.value.episodeNumber} 集`
  return `${episode.value.episodeNumber}. ${name}`
})

const seasonLabel = computed(() => {
  if (!detail.value) return ''
  const base = `第 ${detail.value.seasonNumber} 季`
  const name = detail.value.seasonName?.trim()
  if (!name || name === base || /^season\s*\d+$/i.test(name)) return base
  return `${base} ${name}`
})

const libraryQuery = computed(() => {
  const raw = route.query.library
  const value = Array.isArray(raw) ? raw[0] : raw
  const libraryId = Number(value)
  return Number.isInteger(libraryId) && libraryId > 0 ? { library: String(libraryId) } : {}
})

const facts = computed(() => {
  const ep = episode.value
  const current = detail.value
  if (!ep || !current) return [] as { label: string; value: string }[]
  const rows: { label: string; value: string }[] = [
    { label: '剧集', value: current.workTitle },
    { label: '季', value: seasonLabel.value },
  ]
  if (ep.airDate) rows.push({ label: '播出', value: ep.airDate })
  if (ep.runtimeMinutes != null) rows.push({ label: '片长', value: `${ep.runtimeMinutes} 分钟` })
  if (ep.voteAverage != null) {
    const score = Number(ep.voteAverage).toFixed(1)
    rows.push({
      label: '评分',
      value: ep.voteCount != null ? `${score}（${ep.voteCount}）` : score,
    })
  }
  if (ep.absoluteNumber != null) rows.push({ label: '绝对集', value: String(ep.absoluteNumber) })
  if (current.productionCode) rows.push({ label: '制作编号', value: current.productionCode })
  return rows
})

function isCast(credit: CreditView) {
  return (
    Boolean(credit.character) ||
    credit.department === 'Acting' ||
    credit.department === 'cast' ||
    credit.job === 'Actor' ||
    credit.job === 'actor' ||
    credit.job === 'guest_star'
  )
}

const castItems = computed<PersonItem[]>(() =>
  (detail.value?.credits ?? [])
    .filter((c) => isCast(c))
    .slice()
    .sort((a, b) => a.order - b.order)
    .map((c) => ({
      key: `cast-${c.externalId}-${c.order}-${c.character}`,
      name: c.name,
      subtitle: c.character || (c.job === 'guest_star' ? '嘉宾' : '—'),
      imageUrl: c.profileUrl,
      provider: c.provider,
      externalId: c.externalId,
    })),
)

const crewItems = computed<PersonItem[]>(() =>
  (detail.value?.credits ?? [])
    .filter((c) => !isCast(c))
    .slice()
    .sort((a, b) => a.order - b.order || a.name.localeCompare(b.name))
    .map((c) => ({
      key: `crew-${c.externalId}-${c.order}-${c.job}`,
      name: c.name,
      subtitle: c.job || c.department || '—',
      imageUrl: c.profileUrl,
      provider: c.provider,
      externalId: c.externalId,
    })),
)

const artworksByKind = computed(() => {
  const map = new Map<string, ArtworkView[]>()
  for (const art of episode.value?.artworks ?? []) {
    const list = map.get(art.kind) ?? []
    list.push(art)
    map.set(art.kind, list)
  }
  return [...map.entries()].map(([kind, items]) => ({ kind, items }))
})

const externalIds = computed(() => detail.value?.externalIds ?? [])
const videos = computed(() => detail.value?.videos ?? [])

function artworkKindLabel(kind: string) {
  const map: Record<string, string> = {
    poster: '海报',
    backdrop: '背景',
    still: '剧照',
    logo: 'Logo',
  }
  return map[kind] ?? kind
}

function videoUrl(site: string | null, key: string | null) {
  if (!key) return null
  const s = (site ?? '').toLowerCase()
  if (s.includes('youtube')) return `https://www.youtube.com/watch?v=${key}`
  if (s.includes('vimeo')) return `https://vimeo.com/${key}`
  return null
}

function providerTitle(provider: string) {
  const labels: Record<string, string> = {
    tmdb: 'TMDB',
    tvdb: 'TVDB',
    imdb: 'IMDb',
    wikidata: 'Wikidata',
    facebook: 'Facebook',
    instagram: 'Instagram',
    twitter: 'X',
    tvrage: 'TVRage',
    freebase: 'Freebase',
  }
  return labels[provider] ?? provider.toUpperCase()
}

function externalUrl(provider: string, id: string) {
  if (id.startsWith('http://') || id.startsWith('https://')) return id
  switch (provider) {
    case 'tmdb':
      return `https://www.themoviedb.org/tv/episode/${id}`
    case 'imdb':
      return `https://www.imdb.com/title/${id}`
    case 'tvdb':
      return `https://www.thetvdb.com/?tab=episode&id=${id}`
    case 'wikidata':
      return `https://www.wikidata.org/wiki/${id}`
    case 'facebook':
      return `https://www.facebook.com/${id}`
    case 'instagram':
      return `https://www.instagram.com/${id}`
    case 'twitter':
      return `https://twitter.com/${id}`
    default:
      return null
  }
}

async function load(workId: number, seasonNumber: number, episodeNumber: number) {
  if (!Number.isFinite(workId) || !Number.isFinite(seasonNumber) || !Number.isFinite(episodeNumber)) {
    error.value = '无效的集参数'
    loading.value = false
    return
  }
  loading.value = true
  error.value = null
  detail.value = null
  videoFiles.value = null
  resumeFileId.value = null
  moreOpen.value = false
  try {
    detail.value = await getEpisode(workId, seasonNumber, episodeNumber)
    void loadResume(detail.value)
  } catch (e) {
    error.value = e instanceof Error ? e.message : '集详情加载失败'
  } finally {
    loading.value = false
  }
}

function goBack() {
  if (window.history.state?.back) {
    router.back()
    return
  }
  if (detail.value) {
    void router.push({
      name: 'season',
      params: {
        id: String(detail.value.workId),
        seasonNumber: String(detail.value.seasonNumber),
      },
      query: libraryQuery.value,
    })
    return
  }
  void router.push({ name: 'wall', query: libraryQuery.value })
}

async function loadResume(current: EpisodeDetail) {
  const files = current.episode.files
  if (!files.length) return
  try {
    const results = await Promise.all(files.map((file) => getFilePlayback(file.id).catch(() => null)))
    if (detail.value?.episode.id !== current.episode.id) return
    const hit = results.find((item) => item?.resumePositionMs != null && item.resumePositionMs > 0)
    if (hit) resumeFileId.value = hit.libraryFileId
  } catch {
    // 没有进度时只显示播放
  }
}

function openPlay() {
  const files = episode.value?.files ?? []
  const preferred = resumeFileId.value
  const id = preferred != null && files.some((file) => file.id === preferred) ? preferred : files[0]?.id
  if (!id) return
  void router.push({
    name: 'play',
    params: { fileId: String(id) },
  })
}

function toggleMore() {
  moreOpen.value = !moreOpen.value
}

function openVideoInfo() {
  moreOpen.value = false
  if (!episode.value?.files?.length) return
  videoFiles.value = episode.value.files
}

function onVideoInfoUpdated(next: ReviewFileRow[]) {
  videoFiles.value = next
  const current = detail.value
  if (!current) return
  const byId = new Map(next.map((file) => [file.id, file]))
  detail.value = {
    ...current,
    episode: {
      ...current.episode,
      files: current.episode.files.map((file) => byId.get(file.id) ?? file),
    },
  }
}

function onDocPointerDown(event: PointerEvent) {
  const target = event.target
  if (target instanceof Element && moreWrap.value?.contains(target)) return
  moreOpen.value = false
}

watch(
  () => [route.params.id, route.params.seasonNumber, route.params.episodeNumber] as const,
  ([id, seasonNumber, episodeNumber]) => {
    void load(Number(id), Number(seasonNumber), Number(episodeNumber))
  },
  { immediate: true },
)

onMounted(() => document.addEventListener('pointerdown', onDocPointerDown))
onUnmounted(() => document.removeEventListener('pointerdown', onDocPointerDown))
</script>

<template>
  <WorkDetailSkeleton v-if="loading" />

  <div v-else-if="error" class="detail" :style="pageStyle">
    <div class="hero">
      <div class="hero-shade" />
      <div class="hero-inner">
        <button class="back" type="button" @click="goBack">← 返回</button>
        <div class="state error">{{ error }}</div>
      </div>
    </div>
  </div>

  <div v-else-if="detail && episode" class="detail" :style="pageStyle">
    <div class="hero" :style="stillUrl ? { backgroundImage: `url(${stillUrl})` } : undefined">
      <div class="hero-shade" />
      <div class="hero-inner">
        <button class="back" type="button" @click="goBack">← 返回 {{ detail.workTitle }} {{ seasonLabel }}</button>

        <div class="hero-body">
          <div class="hero-still">
            <PosterMedia :src="stillUrl" :alt="episodeTitle" loading="eager" />
          </div>
          <div class="hero-copy">
            <h1>{{ episodeTitle }}</h1>
            <div class="chips">
              <span>{{ seasonLabel }}</span>
              <span v-if="episode.airDate">{{ episode.airDate }}</span>
              <span v-if="episode.runtimeMinutes">{{ episode.runtimeMinutes }} 分钟</span>
              <span v-if="episode.voteAverage != null">
                ★ {{ Number(episode.voteAverage).toFixed(1) }}
                <template v-if="episode.voteCount != null">({{ episode.voteCount }})</template>
              </span>
              <div ref="moreWrap" class="chip-more">
                <button
                  type="button"
                  class="chip-more-btn"
                  :aria-expanded="moreOpen"
                  aria-haspopup="menu"
                  @click="toggleMore"
                >
                  更多
                </button>
                <div v-if="moreOpen" class="chip-menu" role="menu">
                  <button type="button" role="menuitem" @click="playlistOpen = true; moreOpen = false">
                    添加到播放列表
                  </button>
                  <button v-if="episode.files.length" type="button" role="menuitem" @click="openVideoInfo">视频信息</button>
                </div>
              </div>
            </div>
            <div v-if="episode.files.length" class="play-actions">
              <button type="button" class="play-primary" @click="openPlay">
                {{ resumeFileId ? '继续观看' : '播放' }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="body">
      <section class="block">
        <h2>简介</h2>
        <p v-if="episode.overview" class="overview">{{ episode.overview }}</p>
        <p v-else class="empty">暂无简介</p>
      </section>

      <section v-if="facts.length" class="block">
        <h2>基本信息</h2>
        <dl class="facts">
          <div v-for="row in facts" :key="row.label" class="fact">
            <dt>{{ row.label }}</dt>
            <dd>{{ row.value }}</dd>
          </div>
        </dl>
      </section>

      <section v-if="externalIds.length" class="block">
        <h2>外部 ID</h2>
        <dl class="facts">
          <div v-for="ext in externalIds" :key="`${ext.provider}-${ext.externalId}`" class="fact">
            <dt>{{ providerTitle(ext.provider) }}</dt>
            <dd>
              <a
                v-if="externalUrl(ext.provider, ext.externalId)"
                :href="externalUrl(ext.provider, ext.externalId)!"
                target="_blank"
                rel="noreferrer"
              >{{ ext.externalId }}</a>
              <template v-else>{{ ext.externalId }}</template>
            </dd>
          </div>
        </dl>
      </section>

      <section v-if="videos.length" class="block">
        <h2>相关视频</h2>
        <ul class="plain-list">
          <li v-for="video in videos" :key="video.externalId">
            <strong>{{ video.name || video.type || '视频' }}</strong>
            <span class="dim">
              {{ video.site || '—' }}
              <template v-if="video.type"> · {{ video.type }}</template>
              <template v-if="video.language"> · {{ video.language }}</template>
              <template v-if="video.official != null"> · {{ video.official ? '官方' : '非官方' }}</template>
            </span>
            <a
              v-if="videoUrl(video.site, video.key)"
              :href="videoUrl(video.site, video.key)!"
              target="_blank"
              rel="noreferrer"
            >打开</a>
            <span v-else-if="video.key" class="dim">{{ video.key }}</span>
          </li>
        </ul>
      </section>

      <section v-if="artworksByKind.length" class="block">
        <h2>图片素材（{{ episode.artworks.length }}）</h2>
        <ArtworkRail
          v-for="group in artworksByKind"
          :key="group.kind"
          :title="artworkKindLabel(group.kind)"
          :kind="group.kind"
          :items="group.items"
        />
      </section>

      <PeopleRail title="演员 / 嘉宾" :items="castItems" />
      <PeopleRail title="制作人员" :items="crewItems" />
    </div>
  </div>

  <VideoInfoDialog
    v-if="videoFiles"
    :files="videoFiles"
    @close="videoFiles = null"
    @updated="onVideoInfoUpdated"
  />
  <PlaylistPickerDialog
    v-if="playlistOpen && detail"
    :work-id="detail.workId"
    @close="playlistOpen = false"
  />
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
  min-height: min(52vh, 460px);
  background-color: var(--detail-bg);
  background-size: cover;
  background-position: center top;
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
  margin-bottom: 2rem;
  border: 1px solid var(--line-strong);
  background: rgba(10, 12, 16, 0.45);
  color: var(--ink);
  border-radius: 999px;
  padding: 0.55rem 1rem;
  cursor: pointer;
  font-weight: 600;
  font-size: 0.9rem;
  backdrop-filter: blur(8px);
}

.back:hover {
  border-color: rgba(212, 165, 116, 0.5);
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
  margin-top: auto;
  display: grid;
  grid-template-columns: minmax(200px, 280px) minmax(0, 1fr);
  gap: 1.75rem;
  align-items: stretch;
}

.hero-still {
  width: 100%;
  aspect-ratio: 16 / 9;
  border-radius: 12px;
  border: 1px solid var(--line-strong);
  box-shadow: var(--shadow);
  overflow: hidden;
  background: var(--bg-soft);
  align-self: start;
}

.hero-copy {
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  min-height: 0;
}

.hero-copy h1 {
  margin: 0;
  font-family: var(--font-display);
  font-size: clamp(1.8rem, 4.5vw, 3rem);
  line-height: 1.08;
  letter-spacing: -0.03em;
}

.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 0.45rem;
  margin-top: 1.1rem;
}

.chips span,
.chip-more-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0.2rem 0.7rem;
  min-height: 1.7rem;
  box-sizing: border-box;
  border-radius: 999px;
  border: 1px solid var(--line-strong);
  background: rgba(10, 12, 16, 0.35);
  color: var(--ink-muted);
  font-size: 0.85rem;
  line-height: 1;
}

.chip-more {
  position: relative;
  z-index: 5;
}

.chip-more-btn {
  cursor: pointer;
  font: inherit;
}

.chip-more-btn:hover,
.chip-more-btn[aria-expanded='true'] {
  border-color: rgba(212, 165, 116, 0.45);
  color: var(--ink);
  background: rgba(212, 165, 116, 0.12);
}

.chip-menu {
  position: absolute;
  top: calc(100% + 0.4rem);
  right: 0;
  z-index: 30;
  min-width: 8.5rem;
  padding: 0.3rem;
  border-radius: 10px;
  border: 1px solid var(--line-strong);
  background: rgba(18, 21, 28, 0.96);
  box-shadow: 0 14px 32px rgba(0, 0, 0, 0.35);
}

.chip-menu button {
  width: 100%;
  border: 0;
  background: transparent;
  color: var(--ink);
  text-align: left;
  padding: 0.55rem 0.7rem;
  border-radius: 8px;
  font-size: 0.88rem;
  cursor: pointer;
}

.chip-menu button:hover {
  background: rgba(212, 165, 116, 0.14);
  color: var(--copper);
}

.body {
  width: min(1100px, calc(100% - 2.5rem));
  margin: 0 auto;
  padding: 0.5rem 0 3rem;
}

.block + .block {
  margin-top: 2rem;
}

.block h2 {
  margin: 0 0 0.85rem;
  font-family: var(--font-display);
  font-size: 1.25rem;
  color: var(--copper);
}

.overview {
  margin: 0;
  color: var(--ink-muted);
  line-height: 1.6;
}

.facts {
  margin: 0;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 0.85rem 1rem;
}

.fact {
  padding-bottom: 0.7rem;
  border-bottom: 1px solid var(--line);
}

.fact dt {
  font-size: 0.75rem;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--ink-faint);
  margin-bottom: 0.25rem;
}

.fact dd {
  margin: 0;
  color: var(--ink);
  word-break: break-word;
}

.fact a {
  color: var(--teal);
  text-decoration: none;
}

.fact a:hover {
  text-decoration: underline;
}

.empty {
  color: var(--ink-muted);
}

.plain-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  gap: 0.65rem;
}

.plain-list li {
  display: flex;
  flex-wrap: wrap;
  gap: 0.45rem 0.75rem;
  align-items: baseline;
  color: var(--ink);
}

.plain-list a {
  color: var(--teal);
  text-decoration: none;
}

.plain-list a:hover {
  text-decoration: underline;
}

.dim {
  color: var(--ink-faint);
  font-size: 0.88rem;
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
  .hero-body {
    grid-template-columns: 1fr;
    align-items: start;
  }
}
</style>
