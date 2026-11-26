<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import type { ArtworkView } from '../api/types'
import PosterMedia from './PosterMedia.vue'

const containKinds = new Set(['backdrop', 'collection_backdrop', 'still', 'logo'])

function mediaFit(kind: string): 'cover' | 'contain' {
  return containKinds.has(kind) ? 'contain' : 'cover'
}

const props = withDefaults(
  defineProps<{
    title: string
    kind: string
    items: ArtworkView[]
    previewCount?: number
  }>(),
  { previewCount: 20 },
)

const open = ref(false)
const railEl = ref<HTMLElement | null>(null)
const canScrollLeft = ref(false)
const canScrollRight = ref(false)
let resizeObserver: ResizeObserver | null = null

const previewItems = computed(() => props.items.slice(0, props.previewCount))
const hasMore = computed(() => props.items.length > props.previewCount)
const showArrows = computed(() => canScrollLeft.value || canScrollRight.value)
const kindClass = computed(() => `kind-${props.kind}`)

function openModal() {
  open.value = true
}

function closeModal() {
  open.value = false
}

function measureOverflow(el: HTMLElement) {
  const byScroll = el.scrollWidth - el.clientWidth
  if (byScroll > 2) return byScroll
  const style = getComputedStyle(el)
  const gap = Number.parseFloat(style.columnGap || style.gap || '0') || 0
  let total = 0
  const children = Array.from(el.children) as HTMLElement[]
  children.forEach((child, index) => {
    total += child.getBoundingClientRect().width
    if (index > 0) total += gap
  })
  return total - el.clientWidth
}

function updateScrollState() {
  const el = railEl.value
  if (!el) {
    canScrollLeft.value = false
    canScrollRight.value = false
    return
  }
  const max = Math.max(0, measureOverflow(el))
  canScrollLeft.value = el.scrollLeft > 2
  canScrollRight.value = max > 2 && el.scrollLeft < max - 2
}

function bindImageLoads() {
  const el = railEl.value
  if (!el) return
  el.querySelectorAll('img').forEach((img) => {
    if (img.complete) return
    img.addEventListener('load', updateScrollState, { once: true })
    img.addEventListener('error', updateScrollState, { once: true })
  })
}

async function refreshScrollState() {
  await nextTick()
  bindImageLoads()
  updateScrollState()
  requestAnimationFrame(() => {
    updateScrollState()
    window.setTimeout(updateScrollState, 120)
    window.setTimeout(updateScrollState, 400)
  })
}

function scrollByDir(dir: -1 | 1) {
  const el = railEl.value
  if (!el) return
  const step = Math.max(el.clientWidth * 0.75, 280)
  const max = Math.max(0, el.scrollWidth - el.clientWidth)
  const next = Math.min(max, Math.max(0, el.scrollLeft + dir * step))
  el.scrollTo({ left: next, behavior: 'smooth' })
  window.setTimeout(updateScrollState, 80)
  window.setTimeout(updateScrollState, 320)
}

function onKey(e: KeyboardEvent) {
  if (e.key === 'Escape' && open.value) closeModal()
}

function caption(art: ArtworkView) {
  return art.locale || art.provider
}

watch(open, (value) => {
  document.body.style.overflow = value ? 'hidden' : ''
})

watch(
  () => [props.items.length, props.kind] as const,
  () => {
    void refreshScrollState()
  },
)

onMounted(async () => {
  window.addEventListener('keydown', onKey)
  window.addEventListener('resize', updateScrollState)
  await nextTick()
  if (railEl.value && typeof ResizeObserver !== 'undefined') {
    resizeObserver = new ResizeObserver(() => updateScrollState())
    resizeObserver.observe(railEl.value)
  }
  void refreshScrollState()
})

onUnmounted(() => {
  window.removeEventListener('keydown', onKey)
  window.removeEventListener('resize', updateScrollState)
  resizeObserver?.disconnect()
  resizeObserver = null
  document.body.style.overflow = ''
})
</script>

<template>
  <section v-if="items.length" class="block">
    <div class="head">
      <h3>{{ title }}（{{ items.length }}）</h3>
      <div v-if="showArrows" class="arrows">
        <button
          type="button"
          class="arrow"
          aria-label="向左滑动"
          :disabled="!canScrollLeft"
          @click="scrollByDir(-1)"
        >
          ‹
        </button>
        <button
          type="button"
          class="arrow"
          aria-label="向右滑动"
          :disabled="!canScrollRight"
          @click="scrollByDir(1)"
        >
          ›
        </button>
      </div>
    </div>

    <div class="rail-shell">
      <div
        ref="railEl"
        class="rail"
        :class="kindClass"
        role="list"
        @scroll.passive="updateScrollState"
      >
        <a
          v-for="(art, idx) in previewItems"
          :key="`${art.remoteUrl}-${idx}`"
          class="art-card"
          role="listitem"
          :href="art.remoteUrl"
          target="_blank"
          rel="noreferrer"
          :title="`${art.provider} ${art.locale || ''}`"
        >
          <div class="art-frame">
            <PosterMedia
              class="art-media"
              :src="art.remoteUrl"
              :alt="`${title} ${idx + 1}`"
              :fit="mediaFit(kind)"
            />
          </div>
          <span>{{ caption(art) }}</span>
        </a>

        <button v-if="hasMore" class="view-all" type="button" @click="openModal">
          <div class="art-frame view-all-frame">
            <span>···</span>
          </div>
          <span>
            <strong>查看全部</strong>
            <small>共 {{ items.length }} 张</small>
          </span>
        </button>
      </div>
    </div>

    <Teleport to="body">
      <div v-if="open" class="modal-root" role="dialog" aria-modal="true" :aria-label="title">
        <div class="modal-backdrop" @click="closeModal" />
        <div class="modal-panel">
          <header class="modal-head">
            <div>
              <h3>{{ title }}</h3>
              <p>共 {{ items.length }} 张</p>
            </div>
            <button class="close" type="button" aria-label="关闭" @click="closeModal">×</button>
          </header>
          <div class="modal-body">
            <div class="modal-grid" :class="kindClass">
              <a
                v-for="(art, idx) in items"
                :key="`all-${art.remoteUrl}-${idx}`"
                class="art-card"
                :href="art.remoteUrl"
                target="_blank"
                rel="noreferrer"
                :title="`${art.provider} ${art.locale || ''}`"
              >
                <div class="art-frame">
                  <PosterMedia
                    class="art-media"
                    :src="art.remoteUrl"
                    :alt="`${title} ${idx + 1}`"
                    :fit="mediaFit(kind)"
                  />
                </div>
                <span>{{ caption(art) }}</span>
              </a>
            </div>
          </div>
        </div>
      </div>
    </Teleport>
  </section>
</template>

<style scoped>
.block {
  min-width: 0;
  max-width: 100%;
  width: 100%;
  overflow: hidden;
}

.block + .block {
  margin-top: 1.25rem;
}

.head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  margin-bottom: 0.75rem;
}

.head h3 {
  margin: 0;
  font-size: 0.9rem;
  color: var(--ink-muted);
  font-weight: 600;
}

.arrows {
  display: inline-flex;
  gap: 0.35rem;
  flex-shrink: 0;
}

.arrow {
  width: 2rem;
  height: 2rem;
  border-radius: 999px;
  border: 1px solid var(--line-strong);
  background: rgba(255, 255, 255, 0.03);
  color: var(--ink);
  font-size: 1.25rem;
  line-height: 1;
  cursor: pointer;
  display: grid;
  place-items: center;
  transition:
    border-color 0.2s ease,
    background 0.2s ease,
    color 0.2s ease,
    opacity 0.2s ease;
}

.arrow:hover:not(:disabled) {
  border-color: rgba(212, 165, 116, 0.5);
  background: rgba(212, 165, 116, 0.12);
  color: var(--copper);
}

.arrow:disabled {
  opacity: 0.28;
  cursor: default;
}

.rail-shell {
  width: 100%;
  min-width: 0;
  max-width: 100%;
  overflow: hidden;
}

.rail {
  display: flex;
  gap: 0.75rem;
  width: 100%;
  min-width: 0;
  overflow-x: auto;
  overflow-y: hidden;
  overscroll-behavior-x: contain;
  -webkit-overflow-scrolling: touch;
  padding: 0.1rem 0;
  scroll-snap-type: x proximity;
  scrollbar-width: none;
  -ms-overflow-style: none;
}

.rail::-webkit-scrollbar {
  display: none;
  width: 0;
  height: 0;
}

.art-card,
.view-all {
  flex: 0 0 140px;
  width: 140px;
  scroll-snap-align: start;
  display: grid;
  gap: 0.35rem;
  text-decoration: none;
  color: inherit;
  text-align: left;
}

.rail.kind-backdrop .art-card,
.rail.kind-collection_backdrop .art-card,
.rail.kind-still .art-card,
.rail.kind-backdrop .view-all,
.rail.kind-collection_backdrop .view-all,
.rail.kind-still .view-all {
  flex-basis: 260px;
  width: 260px;
}

.rail.kind-logo .art-card,
.rail.kind-logo .view-all {
  flex-basis: 180px;
  width: 180px;
}

.art-frame {
  display: grid;
  place-items: stretch;
  overflow: hidden;
  border-radius: 10px;
  border: 1px solid var(--line);
  background: var(--bg-soft);
  aspect-ratio: 2 / 3;
  width: 100%;
  min-height: 0;
}

.art-frame :deep(.art-media),
.art-frame :deep(.poster-media) {
  width: 100%;
  height: 100%;
  min-height: 100%;
}

.kind-backdrop .art-frame,
.kind-collection_backdrop .art-frame,
.kind-still .art-frame {
  aspect-ratio: 16 / 9;
}

.kind-logo .art-frame {
  aspect-ratio: auto;
  min-height: 96px;
  padding: 1rem 1.1rem;
  background: rgba(255, 255, 255, 0.1);
}

.kind-logo .art-frame :deep(.poster-media-img) {
  max-height: 72px;
  width: auto;
  margin: 0 auto;
}

.art-card > span,
.view-all > span {
  font-size: 0.75rem;
  color: var(--ink-faint);
}

.view-all {
  border: 0;
  background: transparent;
  cursor: pointer;
  padding: 0;
  font: inherit;
}

.view-all-frame {
  place-items: center;
  aspect-ratio: 2 / 3;
  width: 100%;
  color: var(--copper);
  font-family: var(--font-display);
  font-weight: 700;
  letter-spacing: 0.08em;
  font-size: 1.4rem;
  transition:
    background 0.2s ease,
    border-color 0.2s ease;
}

.kind-backdrop .view-all-frame,
.kind-collection_backdrop .view-all-frame,
.kind-still .view-all-frame {
  aspect-ratio: 16 / 9;
}

.kind-logo .view-all-frame {
  aspect-ratio: auto;
  min-height: 96px;
  background: rgba(255, 255, 255, 0.1);
  color: var(--copper);
}

.view-all:hover .view-all-frame {
  border-color: rgba(212, 165, 116, 0.45);
  background: rgba(212, 165, 116, 0.12);
}

.kind-logo .view-all:hover .view-all-frame {
  background: rgba(255, 255, 255, 0.16);
}

.view-all strong {
  display: block;
  color: var(--ink);
  font-size: 0.82rem;
}

.view-all small {
  display: block;
  margin-top: 0.12rem;
  color: var(--ink-faint);
}

.modal-root {
  position: fixed;
  inset: 0;
  z-index: 50;
  display: grid;
  place-items: center;
  padding: 1.25rem;
}

.modal-backdrop {
  position: absolute;
  inset: 0;
  background: rgba(4, 6, 10, 0.45);
  backdrop-filter: blur(18px);
  -webkit-backdrop-filter: blur(18px);
}

.modal-panel {
  position: relative;
  z-index: 1;
  display: flex;
  flex-direction: column;
  width: min(920px, 100%);
  max-height: min(82vh, 820px);
  overflow: hidden;
  border-radius: 18px;
  border: 1px solid var(--line-strong);
  background: linear-gradient(180deg, #141822 0%, var(--bg-deep) 100%);
  box-shadow: var(--shadow);
  animation: rise 0.28s cubic-bezier(0.22, 1, 0.36, 1) both;
}

.modal-head {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 1rem;
  flex-shrink: 0;
  padding: 1.25rem 1.25rem 0.85rem;
  border-bottom: 1px solid var(--line);
}

.modal-head h3 {
  margin: 0;
  font-family: var(--font-display);
  font-size: 1.2rem;
  color: var(--ink);
}

.modal-head p {
  margin: 0.3rem 0 0;
  color: var(--ink-faint);
  font-size: 0.85rem;
}

.close {
  width: 2.2rem;
  height: 2.2rem;
  border-radius: 999px;
  border: 1px solid var(--line-strong);
  background: rgba(10, 12, 16, 0.45);
  color: var(--ink);
  font-size: 1.35rem;
  line-height: 1;
  cursor: pointer;
}

.modal-body {
  flex: 1 1 auto;
  min-height: 0;
  overflow: auto;
  padding: 1.15rem 1.25rem 1.5rem;
}

.modal-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
  gap: 0.85rem;
}

.modal-grid.kind-backdrop,
.modal-grid.kind-collection_backdrop,
.modal-grid.kind-still {
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
}

.modal-grid.kind-logo {
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
}

.modal-grid .art-card {
  width: auto;
  flex: initial;
}

@keyframes rise {
  from {
    opacity: 0;
    transform: translateY(12px) scale(0.98);
  }
  to {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}

@media (max-width: 720px) {
  .modal-root {
    padding: 0;
    place-items: end stretch;
  }

  .modal-panel {
    width: 100%;
    max-height: min(94dvh, 100%);
    border-radius: 18px 18px 0 0;
  }

  .modal-body {
    padding-bottom: calc(1.25rem + var(--safe-bottom));
  }

  .modal-grid,
  .modal-grid.kind-backdrop,
  .modal-grid.kind-collection_backdrop,
  .modal-grid.kind-still,
  .modal-grid.kind-logo {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (prefers-reduced-motion: reduce) {
  .modal-panel,
  .view-all-frame,
  .arrow {
    animation: none;
    transition: none;
  }
}
</style>
