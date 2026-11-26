<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, watch, type ComponentPublicInstance } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getPerson, refreshPerson } from '../api/client'
import type { PersonDetail, PersonWorkCredit } from '../api/types'
import PosterMedia from '../components/PosterMedia.vue'
import WorkDetailSkeleton from '../components/WorkDetailSkeleton.vue'
import { useArtworkTint } from '../lib/artworkColor'

const route = useRoute()
const router = useRouter()

const loading = ref(true)
const refreshing = ref(false)
const error = ref<string | null>(null)
const actionError = ref<string | null>(null)
const detail = ref<PersonDetail | null>(null)
const overviewOpen = ref(false)
const overviewClamped = ref(false)
const overviewVisible = ref('')
const overviewEl = ref<HTMLElement | null>(null)
let overviewObserver: ResizeObserver | null = null
let measuringOverview = false
let overviewNeedsRemeasure = false

const libraryQuery = computed(() => {
  const raw = route.query.library
  const value = Array.isArray(raw) ? raw[0] : raw
  const libraryId = Number(value)
  return Number.isInteger(libraryId) && libraryId > 0 ? { library: String(libraryId) } : {}
})

function creditTime(credit: PersonWorkCredit): number {
  if (credit.releaseDate) {
    const ms = Date.parse(credit.releaseDate)
    if (!Number.isNaN(ms)) return ms
  }
  if (credit.year != null) return Date.UTC(credit.year, 0, 1)
  return Number.NEGATIVE_INFINITY
}

function sortByTimeNearToFar(credits: PersonWorkCredit[]): PersonWorkCredit[] {
  return credits.slice().sort((a, b) => creditTime(b) - creditTime(a))
}

const localCredits = computed(() =>
  sortByTimeNearToFar((detail.value?.credits ?? []).filter((credit) => credit.hasLocalMedia)),
)

const remoteCredits = computed(() =>
  sortByTimeNearToFar((detail.value?.credits ?? []).filter((credit) => !credit.hasLocalMedia)),
)

const tintSource = computed(() => detail.value?.profileUrl ?? null)
const { pageStyle } = useArtworkTint(tintSource)

const canRefresh = computed(() => {
  const person = detail.value
  return !!person && person.provider.trim().toLowerCase() === 'tmdb' && !refreshing.value
})

const metaChips = computed(() => {
  const person = detail.value
  if (!person) return [] as string[]
  const chips: string[] = []
  if (person.knownForDepartment) chips.push(person.knownForDepartment)
  if (person.birthday) {
    chips.push(person.deathday ? `${person.birthday} – ${person.deathday}` : person.birthday)
  }
  if (person.placeOfBirth) chips.push(person.placeOfBirth)
  chips.push(`${person.credits.length} 部作品`)
  if (person.localCount > 0) chips.push(`${person.localCount} 部本地`)
  return chips
})

function creditYear(credit: PersonWorkCredit): string {
  return credit.year != null ? String(credit.year) : ''
}

function mediaTypeLabel(mediaType: string): string {
  switch (mediaType.trim().toLowerCase()) {
    case 'tv':
      return '剧集'
    case 'movie':
      return '电影'
    case 'stage':
    case 'theatre':
    case 'theater':
      return '话剧'
    default:
      return mediaType.trim() || '作品'
  }
}

function creditRole(credit: PersonWorkCredit): string {
  return credit.character || credit.job || credit.department || ''
}

function creditSubtitle(credit: PersonWorkCredit): string {
  return [creditYear(credit), creditRole(credit)].filter(Boolean).join(' · ')
}

function measureOverview() {
  const el = overviewEl.value
  const full = detail.value?.biography?.trim() ?? ''
  if (!el || !full) {
    overviewVisible.value = full
    overviewClamped.value = false
    return
  }
  if (measuringOverview) {
    overviewNeedsRemeasure = true
    return
  }
  measuringOverview = true
  overviewNeedsRemeasure = false

  const probe = document.createElement('p')
  try {
    el.style.maxHeight = ''
    void el.offsetHeight

    const styles = getComputedStyle(el)
    const fontSize = parseFloat(styles.fontSize) || 16
    const lineHeightRaw = parseFloat(styles.lineHeight)
    const lineHeight = Number.isFinite(lineHeightRaw) ? lineHeightRaw : fontSize * 1.55
    const block = el.parentElement
    const available = block?.clientHeight ?? 0
    const width = block?.clientWidth || el.clientWidth
    if (available <= 0 || lineHeight <= 0 || width <= 0) {
      overviewVisible.value = full
      overviewClamped.value = false
      overviewNeedsRemeasure = true
      return
    }

    const maxLines = Math.max(1, Math.floor(available / lineHeight))
    Object.assign(probe.style, {
      position: 'absolute',
      visibility: 'hidden',
      pointerEvents: 'none',
      width: `${width}px`,
      margin: '0',
      padding: '0',
      font: styles.font,
      letterSpacing: styles.letterSpacing,
      whiteSpace: 'pre-wrap',
      wordBreak: 'break-word',
      lineHeight: styles.lineHeight,
    })
    document.body.appendChild(probe)

    let low = 0
    let high = full.length
    let best = full
    while (low <= high) {
      const mid = Math.floor((low + high) / 2)
      const candidate = full.slice(0, mid)
      probe.textContent = candidate
      if (probe.getBoundingClientRect().height <= maxLines * lineHeight + 1) {
        best = candidate
        low = mid + 1
      } else {
        high = mid - 1
      }
    }

    const needsClamp = best.length < full.length
    if (needsClamp) {
      const more = '...更多'
      let clipped = best
      while (clipped.length > 0) {
        probe.textContent = clipped + more
        if (probe.getBoundingClientRect().height <= maxLines * lineHeight + 1) break
        clipped = clipped.slice(0, -1)
      }
      overviewVisible.value = clipped
      overviewClamped.value = true
    } else {
      overviewVisible.value = full
      overviewClamped.value = false
    }
  } finally {
    probe.remove()
    measuringOverview = false
    if (overviewNeedsRemeasure) {
      overviewNeedsRemeasure = false
      requestAnimationFrame(() => measureOverview())
    }
  }
}

function bindOverview(el: Element | ComponentPublicInstance | null) {
  overviewObserver?.disconnect()
  overviewObserver = null
  overviewEl.value = el instanceof HTMLElement ? el : null
  if (!overviewEl.value || typeof ResizeObserver === 'undefined') return
  overviewObserver = new ResizeObserver(() => measureOverview())
  overviewObserver.observe(overviewEl.value)
  const parent = overviewEl.value.parentElement
  if (parent) overviewObserver.observe(parent)
}

async function load(provider: string, externalId: string) {
  if (!provider || !externalId) {
    error.value = '无效的人物'
    loading.value = false
    detail.value = null
    return
  }
  loading.value = true
  error.value = null
  actionError.value = null
  detail.value = null
  overviewOpen.value = false
  try {
    detail.value = await getPerson(provider, externalId)
  } catch (e) {
    error.value = e instanceof Error ? e.message : '人物详情加载失败'
  } finally {
    loading.value = false
    await nextTick()
    measureOverview()
  }
}

async function refresh() {
  const person = detail.value
  if (!person || person.provider.trim().toLowerCase() !== 'tmdb' || refreshing.value) return
  refreshing.value = true
  actionError.value = null
  try {
    detail.value = await refreshPerson(person.provider, person.externalId)
    await nextTick()
    measureOverview()
  } catch (e) {
    actionError.value = e instanceof Error ? e.message : '刷新失败'
  } finally {
    refreshing.value = false
  }
}

onBeforeUnmount(() => {
  overviewObserver?.disconnect()
})

function goBack() {
  if (window.history.state?.back) {
    router.back()
    return
  }
  void router.push({ name: 'wall', query: libraryQuery.value })
}

function openCredit(credit: PersonWorkCredit) {
  if (credit.workId != null) {
    void router.push({
      name: 'work',
      params: { id: String(credit.workId) },
      query: libraryQuery.value,
    })
    return
  }
  const externalId = credit.tmdbId?.trim()
  if (!externalId) return
  const kind = credit.mediaType.trim().toLowerCase() === 'tv' ? 'tv' : 'movie'
  void router.push({
    name: 'work-external',
    query: {
      ...libraryQuery.value,
      provider: 'tmdb',
      externalId,
      kind,
    },
  })
}

watch(
  () => [route.params.provider, route.params.externalId] as const,
  ([provider, externalId]) => {
    void load(String(provider ?? ''), String(externalId ?? ''))
  },
  { immediate: true },
)
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

    <template v-else-if="detail">
      <div class="hero">
        <img v-if="detail.profileUrl" class="hero-bg" :src="detail.profileUrl" alt="" />
        <div class="hero-shade" />
        <div class="hero-inner">
          <div class="hero-toolbar">
            <button class="back" type="button" @click="goBack">← 返回</button>
            <button
              v-if="detail.provider.toLowerCase() === 'tmdb'"
              type="button"
              class="refresh"
              :disabled="!canRefresh"
              @click="refresh"
            >
              {{ refreshing ? '刷新中…' : '刷新' }}
            </button>
          </div>
          <p v-if="actionError" class="state error toolbar-error">{{ actionError }}</p>
          <div class="hero-body">
            <div class="hero-poster">
              <PosterMedia :src="detail.profileUrl" :alt="detail.name" loading="eager" />
            </div>
            <div class="hero-copy">
              <h1>{{ detail.name }}</h1>
              <div v-if="metaChips.length" class="chips">
                <span v-for="chip in metaChips" :key="chip">{{ chip }}</span>
              </div>
              <div v-if="detail.biography" class="overview-block">
                <p :ref="bindOverview" class="overview">
                  <span>{{ overviewVisible }}</span
                  ><button
                    v-if="overviewClamped"
                    type="button"
                    class="overview-more"
                    @click="overviewOpen = true"
                  >
                    ...更多
                  </button>
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="body">
        <section v-if="localCredits.length" class="block">
          <h2>本地（{{ localCredits.length }}）</h2>
          <div class="grid">
            <button
              v-for="(credit, index) in localCredits"
              :key="`local-${credit.mediaType}-${credit.tmdbId}-${index}`"
              type="button"
              class="part-card"
              :style="{ '--delay': `${Math.min(index, 24) * 35}ms` }"
              @click="openCredit(credit)"
            >
              <span class="part-poster">
                <PosterMedia :src="credit.posterUrl" :alt="credit.title" />
                <span class="poster-veil" />
                <span class="poster-kind">{{ mediaTypeLabel(credit.mediaType) }}</span>
              </span>
              <span class="part-meta">
                <strong>{{ credit.title }}</strong>
                <small v-if="creditSubtitle(credit)">{{ creditSubtitle(credit) }}</small>
              </span>
            </button>
          </div>
        </section>

        <section v-if="remoteCredits.length" class="block">
          <h2>未入库（{{ remoteCredits.length }}）</h2>
          <div class="grid">
            <button
              v-for="(credit, index) in remoteCredits"
              :key="`remote-${credit.mediaType}-${credit.tmdbId}-${index}`"
              type="button"
              class="part-card locked"
              :style="{ '--delay': `${Math.min(index, 24) * 35}ms` }"
              @click="openCredit(credit)"
            >
              <span class="part-poster">
                <PosterMedia :src="credit.posterUrl" :alt="credit.title" />
                <span class="poster-veil" />
                <span class="poster-kind">{{ mediaTypeLabel(credit.mediaType) }}</span>
              </span>
              <span class="part-meta">
                <strong>{{ credit.title }}</strong>
                <small v-if="creditSubtitle(credit)">{{ creditSubtitle(credit) }}</small>
              </span>
            </button>
          </div>
        </section>

        <p v-if="!localCredits.length && !remoteCredits.length" class="empty">暂无相关作品</p>
      </div>
    </template>

    <div v-if="overviewOpen && detail?.biography" class="preview-scrim" @click.self="overviewOpen = false">
      <div class="preview-card overview-dialog" role="dialog" aria-modal="true" aria-label="人物简介">
        <h3>{{ detail.name }}</h3>
        <p class="preview-overview">{{ detail.biography }}</p>
        <div class="preview-actions">
          <button type="button" class="preview-close" @click="overviewOpen = false">关闭</button>
        </div>
      </div>
    </div>
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
  overflow: hidden;
}

.hero-bg {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
  object-position: center top;
  opacity: 0.35;
  filter: blur(18px);
  transform: scale(1.08);
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

.hero-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  margin-bottom: 1.5rem;
}

.back,
.refresh {
  border: 1px solid var(--line-strong);
  background: rgba(10, 12, 16, 0.45);
  color: var(--ink);
  border-radius: 999px;
  padding: 0.55rem 1rem;
  cursor: pointer;
}

.refresh {
  background: rgba(212, 165, 116, 0.16);
  border-color: rgba(212, 165, 116, 0.45);
  color: var(--copper);
}

.refresh:hover:not(:disabled) {
  background: rgba(212, 165, 116, 0.26);
}

.refresh:disabled {
  opacity: 0.55;
  cursor: default;
}

.toolbar-error {
  margin: -0.75rem 0 1rem;
}

.hero-body {
  --poster-width: 160px;
  --poster-height: calc(var(--poster-width) * 3 / 2);
  display: grid;
  grid-template-columns: var(--poster-width) minmax(0, 1fr);
  gap: 1.25rem;
  align-items: stretch;
  margin-top: auto;
}

.hero-poster {
  width: var(--poster-width);
  height: var(--poster-height);
  border-radius: calc(var(--radius) - 2px);
  border: 1px solid var(--line);
  background: var(--bg-soft);
  overflow: hidden;
}

.hero-poster :deep(.poster-media) {
  width: 100%;
  height: 100%;
}

.hero-copy {
  height: var(--poster-height);
  max-height: var(--poster-height);
  min-height: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.hero-copy h1 {
  margin: 0;
  flex: 0 0 auto;
  font-family: var(--font-display);
  font-size: clamp(1.8rem, 4vw, 2.6rem);
  line-height: 1.1;
}

.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 0.45rem;
  margin-top: 0.85rem;
  flex: 0 0 auto;
}

.chips span {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0.2rem 0.7rem;
  min-height: 1.7rem;
  box-sizing: border-box;
  border: 1px solid var(--line-strong);
  border-radius: 999px;
  color: var(--ink-muted);
  font-size: 0.85rem;
  line-height: 1;
  background: rgba(10, 12, 16, 0.35);
}

.overview-block {
  position: relative;
  margin-top: 1rem;
  min-height: 0;
  flex: 1 1 auto;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
}

.overview {
  margin: 0;
  color: var(--ink-muted);
  font-size: 0.95rem;
  line-height: 1.55;
  overflow: visible;
  overflow-wrap: anywhere;
}

.overview-more {
  display: inline;
  border: 0;
  margin: 0;
  padding: 0;
  background: transparent;
  color: var(--copper);
  font: inherit;
  font-size: inherit;
  line-height: inherit;
  cursor: pointer;
  vertical-align: baseline;
  white-space: nowrap;
}

.overview-more:hover {
  color: var(--ink);
}

.overview-dialog h3 {
  margin: 0 0 0.85rem;
  font-family: var(--font-display);
  font-size: 1.25rem;
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
  margin: 0 0 1rem;
  font-family: var(--font-display);
  font-size: 1.25rem;
  color: var(--copper);
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
  gap: 1rem 0.85rem;
}

.part-card {
  --delay: 0ms;
  min-width: 0;
  max-width: 100%;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  gap: 0.7rem;
  border: 0;
  padding: 0;
  background: transparent;
  color: inherit;
  text-align: left;
  cursor: pointer;
  animation: rise 0.55s cubic-bezier(0.22, 1, 0.36, 1) both;
  animation-delay: var(--delay);
}

.part-card.locked {
  opacity: 0.78;
}

.part-poster {
  display: block;
  position: relative;
  width: 100%;
  aspect-ratio: 2 / 3;
  border-radius: calc(var(--radius) - 2px);
  overflow: hidden;
  border: 1px solid var(--line);
  background: var(--bg-soft);
}

.part-poster :deep(.poster-media) {
  display: block;
  width: 100%;
  height: 100%;
}

.poster-veil {
  position: absolute;
  inset: 0;
  z-index: 1;
  background: linear-gradient(180deg, transparent 45%, rgba(8, 10, 14, 0.85) 100%);
  pointer-events: none;
}

.poster-kind {
  position: absolute;
  left: 0.7rem;
  bottom: 0.7rem;
  z-index: 2;
  font-size: 0.72rem;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--ink-muted);
}

.part-meta {
  display: block;
  min-width: 0;
  width: 100%;
  overflow: hidden;
}

.part-meta strong {
  display: block;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
  font-size: 0.95rem;
  line-height: 1.3;
}

.part-meta small {
  display: block;
  margin-top: 0.25rem;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
  color: var(--ink-faint);
  font-size: 0.8rem;
}

.empty,
.state {
  color: var(--ink-muted);
}

.state.error {
  color: var(--danger);
}

.preview-scrim {
  position: fixed;
  inset: 0;
  z-index: 40;
  display: grid;
  place-items: center;
  padding: 1.25rem;
  background: rgba(4, 6, 10, 0.45);
  backdrop-filter: blur(18px);
  -webkit-backdrop-filter: blur(18px);
}

.preview-card {
  width: min(440px, 100%);
  border: 1px solid var(--line-strong);
  border-radius: calc(var(--radius) + 2px);
  background: var(--bg-soft);
  padding: 1.1rem;
  box-shadow: var(--shadow);
}

.preview-head {
  display: grid;
  grid-template-columns: 72px 1fr;
  gap: 0.9rem;
  align-items: start;
}

.preview-poster {
  display: block;
  width: 72px;
  aspect-ratio: 2 / 3;
  border-radius: 8px;
  border: 1px solid var(--line);
  overflow: hidden;
  background: var(--bg-soft);
}

.preview-poster :deep(.poster-media) {
  display: block;
  width: 100%;
  height: 100%;
}

.preview-head h3 {
  margin: 0;
  font-family: var(--font-display);
  font-size: 1.2rem;
  line-height: 1.25;
}

.preview-original,
.preview-meta {
  margin: 0.35rem 0 0;
  color: var(--ink-faint);
  font-size: 0.85rem;
}

.preview-overview {
  margin: 1rem 0 0;
  color: var(--ink-muted);
  line-height: 1.55;
  font-size: 0.92rem;
}

.preview-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.6rem;
  margin-top: 1rem;
}

.preview-close,
.preview-tmdb {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.4rem;
  border-radius: 999px;
  padding: 0.5rem 1rem;
  cursor: pointer;
  text-decoration: none;
  font: inherit;
  line-height: 1;
}

.preview-close {
  border: 1px solid var(--line-strong);
  background: transparent;
  color: var(--ink);
}

.preview-close:hover {
  border-color: rgba(212, 165, 116, 0.45);
  background: rgba(212, 165, 116, 0.1);
}

.preview-tmdb {
  border: 1px solid rgba(0, 179, 229, 0.45);
  background: rgba(0, 179, 229, 0.16);
  color: #7ed7f0;
}

.preview-tmdb:hover {
  background: rgba(0, 179, 229, 0.26);
}

.preview-tmdb-icon {
  width: 1.35rem;
  height: 0.58rem;
  object-fit: contain;
  display: block;
}

@keyframes fade-in {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}

@keyframes rise {
  from {
    opacity: 0;
    transform: translateY(12px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@media (max-width: 720px) {
  .hero-body {
    --poster-width: 110px;
  }

  .poster-kind {
    left: 0.45rem;
    bottom: 0.45rem;
  }
}
</style>
