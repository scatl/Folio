<script setup lang="ts">
import { ref } from 'vue'
import type { WorkCard } from '../api/types'
import { watchLabel } from '../lib/browse'
import PosterMedia from './PosterMedia.vue'

const props = defineProps<{
  work: WorkCard
  index: number
  motion?: boolean
  /** 覆盖左下角类型标签，例如系列条里的「当前」。 */
  kindOverride?: string | null
  current?: boolean
}>()

const emit = defineEmits<{
  select: [id: number]
  'mark-watched': [watched: boolean]
}>()

const menuOpen = ref(false)

function toggleMenu(event: Event) {
  event.stopPropagation()
  menuOpen.value = !menuOpen.value
}

function mark(watched: boolean) {
  menuOpen.value = false
  emit('mark-watched', watched)
}

function kindLabel(kind: string) {
  if (props.kindOverride?.trim()) return props.kindOverride.trim()
  return kind === 'series' ? '剧集' : '电影'
}

function formatRating(value: number | null) {
  if (value == null) return null
  return Number(value).toFixed(1)
}
</script>

<template>
  <article
    class="poster-card"
    :class="{ static: motion === false, current }"
    :style="{ '--delay': `${Math.min(index, 24) * 35}ms` }"
    role="button"
    tabindex="0"
    @click="emit('select', work.id)"
    @keydown.enter.prevent="emit('select', work.id)"
    @keydown.space.prevent="emit('select', work.id)"
  >
    <div class="poster-frame">
      <PosterMedia class="poster-img" :src="work.posterUrl" :alt="work.title" />
      <div class="poster-veil" />
      <button type="button" class="mark" aria-label="观看状态" :aria-expanded="menuOpen" @click="toggleMenu">
        {{ watchLabel(work.watchState) || '标记' }}
      </button>
      <div v-if="menuOpen" class="mark-menu" @click.stop>
        <button v-if="work.watchState !== 'watched'" type="button" @click="mark(true)">标为已看</button>
        <button v-if="work.watchState && work.watchState !== 'unwatched'" type="button" @click="mark(false)">标为未看</button>
        <button v-if="!work.watchState" type="button" @click="mark(false)">标为未看</button>
      </div>
      <div class="poster-meta">
        <span class="kind">{{ kindLabel(work.kind) }}</span>
        <span v-if="formatRating(work.rating)" class="rating">{{ formatRating(work.rating) }}</span>
      </div>
    </div>
    <div class="caption">
      <h3>{{ work.title }}</h3>
      <p>
        <span v-if="work.year">{{ work.year }}</span>
        <span v-if="work.year && work.genres.length"> · </span>
        <span v-if="work.genres.length">{{ work.genres.slice(0, 2).join(' / ') }}</span>
      </p>
    </div>
  </article>
</template>

<style scoped>
.poster-card {
  --delay: 0ms;
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  cursor: pointer;
  animation: rise 0.55s cubic-bezier(0.22, 1, 0.36, 1) both;
  animation-delay: var(--delay);
  outline: none;
}

.poster-card.static {
  animation: none;
}

.poster-card.current {
  cursor: default;
}

.poster-card.current .poster-frame {
  border-color: rgba(212, 165, 116, 0.45);
}

.poster-card.current .kind {
  color: var(--copper);
}

.poster-card.current:hover .poster-frame,
.poster-card.current:focus-visible .poster-frame {
  transform: none;
}

.poster-card:focus-visible .poster-frame {
  box-shadow: 0 0 0 2px var(--copper), var(--shadow);
}

.mark {
  position: absolute;
  top: 0.45rem;
  right: 0.45rem;
  z-index: 2;
  margin: 0;
  padding: 0.18rem 0.45rem;
  border: 0;
  border-radius: 999px;
  background: rgba(0, 0, 0, 0.62);
  color: #fff;
  font: inherit;
  font-size: 0.72rem;
  cursor: pointer;
}

.mark-menu {
  position: absolute;
  top: 2rem;
  right: 0.45rem;
  z-index: 3;
  display: grid;
  min-width: 7rem;
  padding: 0.25rem;
  border-radius: 10px;
  background: #1c1c1c;
}

.mark-menu button {
  margin: 0;
  padding: 0.45rem 0.6rem;
  border: 0;
  border-radius: 8px;
  background: transparent;
  color: #fff;
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.mark-menu button:hover {
  background: rgba(255, 255, 255, 0.08);
}

.poster-frame {
  position: relative;
  aspect-ratio: 2 / 3;
  overflow: hidden;
  border-radius: calc(var(--radius) - 2px);
  background: var(--bg-soft);
  border: 1px solid var(--line);
  transition:
    transform 0.35s cubic-bezier(0.22, 1, 0.36, 1),
    box-shadow 0.35s ease,
    border-color 0.35s ease;
}

.poster-img {
  position: relative;
  z-index: 0;
  width: 100%;
  height: 100%;
  transition: transform 0.45s cubic-bezier(0.22, 1, 0.36, 1);
}

.poster-veil {
  position: absolute;
  inset: 0;
  z-index: 1;
  background: linear-gradient(180deg, transparent 45%, rgba(8, 10, 14, 0.85) 100%);
  pointer-events: none;
}

.poster-meta {
  position: absolute;
  left: 0.7rem;
  right: 0.7rem;
  bottom: 0.7rem;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 0.5rem;
  z-index: 2;
}

.kind,
.rating {
  font-size: 0.72rem;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.kind {
  color: var(--ink-muted);
}

.rating {
  padding: 0.2rem 0.45rem;
  border-radius: 999px;
  background: var(--copper-soft);
  color: var(--copper);
  border: 1px solid rgba(212, 165, 116, 0.35);
}

.caption h3 {
  margin: 0;
  font-family: var(--font-display);
  font-size: 0.98rem;
  font-weight: 700;
  line-height: 1.3;
  letter-spacing: -0.01em;
}

.caption p {
  margin: 0.28rem 0 0;
  font-size: 0.82rem;
  color: var(--ink-muted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.poster-card:hover .poster-frame,
.poster-card:focus-visible .poster-frame {
  transform: translateY(-6px);
  border-color: var(--line-strong);
  box-shadow: var(--shadow);
}

.poster-card:hover .poster-img,
.poster-card:focus-visible .poster-img {
  transform: scale(1.04);
}

@keyframes rise {
  from {
    opacity: 0;
    transform: translateY(18px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@media (max-width: 720px) {
  .poster-meta {
    left: 0.45rem;
    right: 0.45rem;
    bottom: 0.45rem;
  }

  .caption h3 {
    font-size: 0.86rem;
    display: -webkit-box;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 2;
    overflow: hidden;
  }

  .caption p {
    font-size: 0.75rem;
  }
}

@media (prefers-reduced-motion: reduce) {
  .poster-card,
  .poster-frame,
  .poster-img {
    animation: none;
    transition: none;
  }
}
</style>
