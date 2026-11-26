<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, watch, type ComponentPublicInstance } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getCollection } from '../api/client'
import type { CollectionDetail, CollectionPart } from '../api/types'
import PosterMedia from '../components/PosterMedia.vue'
import WorkDetailSkeleton from '../components/WorkDetailSkeleton.vue'
import { useArtworkTint } from '../lib/artworkColor'

const route = useRoute()
const router = useRouter()

const loading = ref(true)
const error = ref<string | null>(null)
const detail = ref<CollectionDetail | null>(null)
const overviewOpen = ref(false)
const overviewClamped = ref(false)
const overviewVisible = ref('')
const overviewEl = ref<HTMLElement | null>(null)
let overviewObserver: ResizeObserver | null = null
let measuringOverview = false
let overviewNeedsRemeasure = false
const MORE_LABEL = '...更多'

const libraryQuery = computed(() => {
  const raw = route.query.library
  const value = Array.isArray(raw) ? raw[0] : raw
  const libraryId = Number(value)
  return Number.isInteger(libraryId) && libraryId > 0 ? { library: String(libraryId) } : {}
})

function partTime(part: CollectionPart): number {
  if (part.releaseDate) {
    const ms = Date.parse(part.releaseDate)
    if (!Number.isNaN(ms)) return ms
  }
  if (part.year != null) return Date.UTC(part.year, 0, 1)
  return Number.NEGATIVE_INFINITY
}

function sortByTimeNearToFar(parts: CollectionPart[]): CollectionPart[] {
  return parts.slice().sort((a, b) => partTime(b) - partTime(a))
}

const localParts = computed(() =>
  sortByTimeNearToFar((detail.value?.parts ?? []).filter((part) => part.hasLocalMedia)),
)

const remoteParts = computed(() =>
  sortByTimeNearToFar((detail.value?.parts ?? []).filter((part) => !part.hasLocalMedia)),
)

const yearSpan = computed(() => {
  const years = (detail.value?.parts ?? [])
    .map((part) => part.year)
    .filter((year): year is number => year != null)
  if (!years.length) return null
  const min = Math.min(...years)
  const max = Math.max(...years)
  return min === max ? String(min) : `${min}–${max}`
})

const tintSource = computed(() => detail.value?.backdropUrl ?? detail.value?.posterUrl ?? null)
const { pageStyle } = useArtworkTint(tintSource)

function partYear(part: CollectionPart): string {
  return part.year != null ? String(part.year) : ''
}

function measureOverview() {
  const el = overviewEl.value
  const full = detail.value?.overview?.trim() ?? ''
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
    // 先清空限高，用截断后的正文本身控高，避免 overflow 把末尾「更多」裁掉。
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

    const lines = Math.max(1, Math.floor((available + 0.01) / lineHeight))
    const snapped = lines * lineHeight

    probe.className = 'overview'
    probe.style.cssText = [
      'position:absolute',
      'left:0',
      'top:0',
      'visibility:hidden',
      'pointer-events:none',
      `width:${width}px`,
      'height:auto',
      'max-height:none',
      'overflow:visible',
      `font-size:${styles.fontSize}`,
      `line-height:${styles.lineHeight}`,
      `font-family:${styles.fontFamily}`,
      `letter-spacing:${styles.letterSpacing}`,
      `overflow-wrap:${styles.overflowWrap}`,
      'white-space:normal',
    ].join(';')
    block?.append(probe)

    const fits = (text: string, withMore: boolean) => {
      probe.textContent = withMore ? `${text}${MORE_LABEL}` : text
      return probe.scrollHeight <= snapped + 1
    }

    if (fits(full, false)) {
      if (overviewVisible.value !== full || overviewClamped.value) {
        overviewVisible.value = full
        overviewClamped.value = false
      }
      return
    }

    // Inline「更多」占最后一行末尾，正文截到能与按钮一起放下为止。
    let lo = 0
    let hi = full.length
    while (lo < hi) {
      const mid = Math.ceil((lo + hi) / 2)
      if (fits(full.slice(0, mid), true)) lo = mid
      else hi = mid - 1
    }

    let cut = lo
    while (cut > 0 && /\s/.test(full[cut - 1]!)) cut -= 1
    // 至少留一点正文，避免整段被按钮占满。
    if (cut < 1) cut = Math.min(1, full.length)
    const next = full.slice(0, cut)
    if (overviewVisible.value !== next || !overviewClamped.value) {
      overviewVisible.value = next
      overviewClamped.value = true
    }
  } finally {
    probe.remove()
    measuringOverview = false
    if (overviewNeedsRemeasure) {
      overviewNeedsRemeasure = false
      void nextTick(measureOverview)
    }
  }
}

function bindOverview(el: Element | ComponentPublicInstance | null) {
  overviewObserver?.disconnect()
  overviewObserver = null
  overviewEl.value = el instanceof HTMLElement ? el : null
  if (!overviewEl.value) {
    overviewVisible.value = ''
    overviewClamped.value = false
    return
  }
  overviewObserver = new ResizeObserver(() => {
    measureOverview()
  })
  overviewObserver.observe(overviewEl.value)
  const block = overviewEl.value.parentElement
  if (block) overviewObserver.observe(block)
  void nextTick(measureOverview)
}

async function load(id: string) {
  if (!id) {
    error.value = '无效的系列参数'
    loading.value = false
    return
  }
  loading.value = true
  error.value = null
  detail.value = null
  overviewOpen.value = false
  overviewClamped.value = false
  overviewVisible.value = ''
  try {
    detail.value = await getCollection(id)
  } catch (e) {
    error.value = e instanceof Error ? e.message : '系列详情加载失败'
  } finally {
    loading.value = false
    await nextTick()
    measureOverview()
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

function openPart(part: CollectionPart) {
  if (part.workId != null) {
    void router.push({
      name: 'work',
      params: { id: String(part.workId) },
      query: libraryQuery.value,
    })
    return
  }
  const externalId = part.tmdbId?.trim()
  if (!externalId) return
  void router.push({
    name: 'work-external',
    query: {
      ...libraryQuery.value,
      provider: 'tmdb',
      externalId,
      kind: 'movie',
    },
  })
}

watch(
  () => route.params.id,
  (id) => {
    void load(String(id ?? ''))
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
        <img v-if="detail.backdropUrl" class="hero-bg" :src="detail.backdropUrl" alt="" />
        <div class="hero-shade" />
        <div class="hero-inner">
          <button class="back" type="button" @click="goBack">← 返回</button>
          <div class="hero-body">
            <div class="hero-poster">
              <PosterMedia :src="detail.posterUrl" :alt="detail.name" loading="eager" />
            </div>
            <div class="hero-copy">
              <h1>{{ detail.name }}</h1>
              <div class="chips">
                <span>{{ detail.parts.length }} 部</span>
                <span>{{ detail.localCount }} 部本地</span>
                <span v-if="yearSpan">{{ yearSpan }}</span>
              </div>
              <div v-if="detail.overview" class="overview-block">
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
        <section v-if="localParts.length" class="block">
          <h2>本地（{{ localParts.length }}）</h2>
          <div class="grid">
            <button
              v-for="(part, index) in localParts"
              :key="part.tmdbId || `local-${part.title}-${index}`"
              type="button"
              class="part-card"
              :style="{ '--delay': `${Math.min(index, 24) * 35}ms` }"
              @click="openPart(part)"
            >
              <span class="part-poster">
                <PosterMedia :src="part.posterUrl" :alt="part.title" />
              </span>
              <span class="part-meta">
                <strong>{{ part.title }}</strong>
                <small v-if="partYear(part)">{{ partYear(part) }}</small>
              </span>
            </button>
          </div>
        </section>

        <section v-if="remoteParts.length" class="block">
          <h2>未入库（{{ remoteParts.length }}）</h2>
          <div class="grid">
            <button
              v-for="(part, index) in remoteParts"
              :key="part.tmdbId || `remote-${part.title}-${index}`"
              type="button"
              class="part-card locked"
              :style="{ '--delay': `${Math.min(index, 24) * 35}ms` }"
              @click="openPart(part)"
            >
              <span class="part-poster">
                <PosterMedia :src="part.posterUrl" :alt="part.title" />
              </span>
              <span class="part-meta">
                <strong>{{ part.title }}</strong>
                <small v-if="partYear(part)">{{ partYear(part) }}</small>
              </span>
            </button>
          </div>
        </section>

        <p v-if="!localParts.length && !remoteParts.length" class="empty">这个系列暂时没有作品</p>
      </div>
    </template>

    <div v-if="overviewOpen && detail?.overview" class="preview-scrim" @click.self="overviewOpen = false">
      <div class="preview-card overview-dialog" role="dialog" aria-modal="true" aria-label="系列简介">
        <h3>{{ detail.name }}</h3>
        <p class="preview-overview">{{ detail.overview }}</p>
        <button type="button" class="preview-close" @click="overviewOpen = false">关闭</button>
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
  opacity: 0.45;
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

.preview-overview.muted {
  color: var(--ink-faint);
}

.preview-close {
  margin-top: 1rem;
  border: 1px solid var(--line-strong);
  background: transparent;
  color: var(--ink);
  border-radius: 999px;
  padding: 0.5rem 1rem;
  cursor: pointer;
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
}
</style>
