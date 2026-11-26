<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import PosterMedia from './PosterMedia.vue'

export interface PersonItem {
  key: string
  name: string
  subtitle: string
  imageUrl: string | null
  provider?: string
  externalId?: string
}

const props = withDefaults(
  defineProps<{
    title: string
    items: PersonItem[]
    previewCount?: number
  }>(),
  { previewCount: 20 },
)

const route = useRoute()
const router = useRouter()

function libraryQuery() {
  const raw = route.query.library
  const value = Array.isArray(raw) ? raw[0] : raw
  const id = Number(value)
  return Number.isInteger(id) && id > 0 ? { library: String(id) } : {}
}

function canOpen(person: PersonItem) {
  return Boolean(person.provider?.trim() && person.externalId?.trim())
}

function openPerson(person: PersonItem) {
  if (!canOpen(person)) return
  closeModal()
  void router.push({
    name: 'person',
    params: {
      provider: person.provider!.trim(),
      externalId: person.externalId!.trim(),
    },
    query: libraryQuery(),
  })
}

const open = ref(false)
const railEl = ref<HTMLElement | null>(null)
const canScrollLeft = ref(false)
const canScrollRight = ref(false)
let resizeObserver: ResizeObserver | null = null

const previewItems = computed(() => props.items.slice(0, props.previewCount))
const hasMore = computed(() => props.items.length > props.previewCount)
const showArrows = computed(() => canScrollLeft.value || canScrollRight.value)

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
  const step = Math.max(el.clientWidth * 0.75, 240)
  const max = Math.max(0, el.scrollWidth - el.clientWidth)
  const next = Math.min(max, Math.max(0, el.scrollLeft + dir * step))
  el.scrollTo({ left: next, behavior: 'smooth' })
  window.setTimeout(updateScrollState, 80)
  window.setTimeout(updateScrollState, 320)
}

function onKey(e: KeyboardEvent) {
  if (e.key === 'Escape' && open.value) closeModal()
}

watch(open, (value) => {
  document.body.style.overflow = value ? 'hidden' : ''
})

watch(
  () => props.items.length,
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
      <h2>{{ title }}（{{ items.length }}）</h2>
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
        role="list"
        @scroll.passive="updateScrollState"
      >
        <button
          v-for="person in previewItems"
          :key="person.key"
          type="button"
          class="rail-person"
          role="listitem"
          :class="{ clickable: canOpen(person) }"
          :disabled="!canOpen(person)"
          @click="openPerson(person)"
        >
          <PosterMedia class="avatar" :src="person.imageUrl" :alt="person.name" />
          <div class="meta">
            <strong>{{ person.name }}</strong>
            <small>{{ person.subtitle }}</small>
          </div>
        </button>

        <button v-if="hasMore" class="view-all" type="button" @click="openModal">
          <span class="view-all-avatar" aria-hidden="true">···</span>
          <span class="meta">
            <strong>查看全部</strong>
            <small>共 {{ items.length }} 人</small>
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
              <p>共 {{ items.length }} 人</p>
            </div>
            <button class="close" type="button" aria-label="关闭" @click="closeModal">×</button>
          </header>
          <div class="modal-body">
            <div class="modal-grid">
              <button
                v-for="person in items"
                :key="`all-${person.key}`"
                type="button"
                class="grid-person"
                :class="{ clickable: canOpen(person) }"
                :disabled="!canOpen(person)"
                @click="openPerson(person)"
              >
                <PosterMedia class="avatar" :src="person.imageUrl" :alt="person.name" />
                <div class="meta">
                  <strong>{{ person.name }}</strong>
                  <small>{{ person.subtitle }}</small>
                </div>
              </button>
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

.head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  margin-bottom: 0.85rem;
}

.head h2 {
  margin: 0;
  font-family: var(--font-display);
  font-size: 0.95rem;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--copper);
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
  gap: 0.85rem;
  width: 100%;
  min-width: 0;
  overflow-x: auto;
  overflow-y: hidden;
  overscroll-behavior-x: contain;
  -webkit-overflow-scrolling: touch;
  padding: 0.15rem 0;
  scroll-snap-type: x proximity;
  scrollbar-width: none;
  -ms-overflow-style: none;
}

.rail::-webkit-scrollbar {
  display: none;
  width: 0;
  height: 0;
}

.rail-person,
.view-all {
  flex: 0 0 104px;
  width: 104px;
  scroll-snap-align: start;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.5rem;
  text-align: center;
  border: 0;
  padding: 0;
  background: transparent;
  color: inherit;
  font: inherit;
}

.rail-person:disabled {
  cursor: default;
}

.rail-person.clickable {
  cursor: pointer;
}

.rail-person.clickable:hover .avatar {
  border-color: rgba(212, 165, 116, 0.45);
  transform: translateY(-2px);
}

.rail-person .avatar {
  transition:
    border-color 0.2s ease,
    transform 0.2s ease;
}

.avatar,
.view-all-avatar {
  width: 72px;
  height: 72px;
  flex-shrink: 0;
  border-radius: 50%;
  overflow: hidden;
  border: 1px solid var(--line);
  background: var(--bg-soft);
}

.avatar :deep(.poster-media-img),
.avatar :deep(.poster-placeholder) {
  width: 100%;
  height: 100%;
}

.avatar :deep(.poster-mark) {
  width: 42%;
  min-width: 18px;
}

.view-all-avatar {
  display: grid;
  place-items: center;
  font-family: var(--font-display);
  font-weight: 700;
  color: var(--copper);
  letter-spacing: 0.08em;
}

.view-all {
  border: 0;
  background: transparent;
  color: var(--ink);
  cursor: pointer;
  padding: 0;
}

.view-all-avatar {
  transition:
    background 0.2s ease,
    border-color 0.2s ease,
    transform 0.2s ease;
}

.view-all:hover .view-all-avatar {
  background: rgba(212, 165, 116, 0.16);
  border-color: rgba(212, 165, 116, 0.45);
  transform: translateY(-2px);
}

.meta {
  min-width: 0;
  width: 100%;
}

.meta strong {
  display: block;
  font-size: 0.88rem;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.meta small {
  display: block;
  margin-top: 0.15rem;
  color: var(--ink-faint);
  font-size: 0.75rem;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
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
  grid-template-columns: repeat(auto-fill, minmax(112px, 1fr));
  gap: 1.1rem 0.75rem;
}

.grid-person {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.5rem;
  text-align: center;
  min-width: 0;
  border: 0;
  padding: 0;
  background: transparent;
  color: inherit;
  font: inherit;
}

.grid-person:disabled {
  cursor: default;
}

.grid-person.clickable {
  cursor: pointer;
}

.grid-person.clickable:hover .avatar {
  border-color: rgba(212, 165, 116, 0.45);
  transform: translateY(-2px);
}

.grid-person .avatar {
  transition:
    border-color 0.2s ease,
    transform 0.2s ease;
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

  .modal-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
}

@media (prefers-reduced-motion: reduce) {
  .modal-panel,
  .view-all-avatar,
  .arrow {
    animation: none;
    transition: none;
  }

  .rail {
    scroll-behavior: auto;
  }
}
</style>
