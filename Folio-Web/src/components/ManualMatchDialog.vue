<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { searchMatchCandidates } from '../api/client'
import type { MatchCandidate, ReviewFileRow } from '../api/types'
import PosterMedia from './PosterMedia.vue'

const props = defineProps<{
  /** 单文件入口（任务页）；与 files 二选一或同时传，files 优先。 */
  file?: ReviewFileRow
  files?: ReviewFileRow[]
  workKind?: string
  title?: string
}>()

const emit = defineEmits<{
  close: []
  confirm: [
    candidate: MatchCandidate,
    options: { fileId: number; year?: number; season?: number; episode?: number; scope?: 'file' | 'work' },
  ]
}>()

interface MatchOptions {
  year?: number
  season?: number
  episode?: number
}

const fileList = computed(() => {
  if (props.files?.length) return props.files
  return props.file ? [props.file] : []
})

const selectedId = ref(0)
const kind = ref<'movie' | 'series'>('movie')
const query = ref('')
const year = ref('')
const season = ref('')
const episode = ref('')
const candidates = ref<MatchCandidate[]>([])
const searching = ref(false)
const searchError = ref<string | null>(null)

const activeFile = computed(
  () => fileList.value.find((item) => item.id === selectedId.value) ?? fileList.value[0] ?? null,
)
const canSwitchFile = computed(() => fileList.value.length > 1)
const wholeWork = ref(props.workKind === 'series' && (props.files?.length ?? 0) > 1)
const fixingOne = computed(() => !wholeWork.value || kind.value !== 'series')
const episodeFileCount = computed(
  () => fileList.value.filter((item) => item.parsedSeason != null && item.parsedEpisode != null).length,
)
const unnamedFileCount = computed(() => fileList.value.length - episodeFileCount.value)
const dialogTitle = computed(() => props.title ?? '人工匹配')

function initFromFile(file: ReviewFileRow) {
  selectedId.value = file.id
  kind.value = props.workKind === 'series' || file.parsedSeason != null ? 'series' : 'movie'
  query.value = file.parsedTitle ?? ''
  year.value = ''
  season.value = file.parsedSeason != null ? String(file.parsedSeason) : ''
  episode.value = file.parsedEpisode != null ? String(file.parsedEpisode) : ''
  candidates.value = []
  searchError.value = null
  void search()
}

function onSelectFile(event: Event) {
  const nextId = Number((event.target as HTMLSelectElement).value)
  const next = fileList.value.find((item) => item.id === nextId)
  if (!next || next.id === activeFile.value?.id) return
  initFromFile(next)
}

function readOptionalInt(raw: string): number | undefined {
  const text = raw.trim()
  if (!text) return undefined
  const value = Number(text)
  return Number.isInteger(value) && value > 0 ? value : undefined
}

function invalidNumber(raw: string) {
  const text = raw.trim()
  return text.length > 0 && readOptionalInt(text) == null
}

function matchOptions(): MatchOptions | null {
  const checkSeason = fixingOne.value && kind.value === 'series'
  if (invalidNumber(year.value) || (checkSeason && (invalidNumber(season.value) || invalidNumber(episode.value)))) {
    searchError.value = '年份、季、集请填写正整数，或留空使用默认值'
    return null
  }
  return {
    year: readOptionalInt(year.value),
    season: checkSeason ? readOptionalInt(season.value) : undefined,
    episode: checkSeason ? readOptionalInt(episode.value) : undefined,
  }
}

async function search() {
  const file = activeFile.value
  if (!file) {
    candidates.value = []
    return
  }
  const options = matchOptions()
  if (!options) {
    candidates.value = []
    return
  }
  searching.value = true
  searchError.value = null
  try {
    candidates.value = await searchMatchCandidates(file.id, {
      q: query.value.trim() || undefined,
      kind: kind.value,
      year: options.year,
    })
  } catch (e) {
    searchError.value = e instanceof Error ? e.message : '搜索失败'
    candidates.value = []
  } finally {
    searching.value = false
  }
}

function choose(candidate: MatchCandidate) {
  const file = activeFile.value
  if (!file) return
  const options = matchOptions()
  if (!options) return
  emit('confirm', candidate, {
    fileId: file.id,
    ...options,
    scope: wholeWork.value && kind.value === 'series' ? 'work' : 'file',
  })
  emit('close')
}

function onOverlayClick(e: MouseEvent) {
  if (e.target === e.currentTarget) emit('close')
}

const yearPlaceholder = computed(() => {
  if (kind.value === 'series') return '留空不限年份'
  const parsedYear = activeFile.value?.parsedYear
  return parsedYear != null ? `默认 ${parsedYear}` : '年份'
})

function setKind(next: 'movie' | 'series') {
  if (kind.value === next) return
  kind.value = next
  void search()
}

function onKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape') emit('close')
}

onMounted(() => {
  const first = fileList.value[0]
  if (first) initFromFile(first)
  window.addEventListener('keydown', onKeydown)
})

watch(
  () => fileList.value.map((item) => item.id).join(','),
  () => {
    const first = fileList.value[0]
    if (first) initFromFile(first)
  },
)

onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKeydown)
})
</script>

<template>
  <div class="overlay" @click="onOverlayClick">
    <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="match-dialog-title">
      <header class="dialog-head">
        <div>
          <h2 id="match-dialog-title">{{ dialogTitle }}</h2>
          <template v-if="canSwitchFile && fixingOne">
            <label class="file-pick">
              <span>选择视频</span>
              <select :value="selectedId" @change="onSelectFile">
                <option v-for="item in fileList" :key="item.id" :value="item.id">
                  {{ item.fileName || item.locator }}
                </option>
              </select>
            </label>
            <p v-if="activeFile?.locator" class="file-path">{{ activeFile.locator }}</p>
          </template>
          <p v-else-if="wholeWork && kind === 'series'" class="file-path">
            按各自文件名里的季、集，把 {{ episodeFileCount }} 个视频改挂到所选剧。
            <template v-if="unnamedFileCount">有 {{ unnamedFileCount }} 个文件名里没有季或集，会留在待处理。</template>
          </p>
          <p v-else-if="activeFile" class="file-path">{{ activeFile.fileName }}</p>
          <button
            v-if="canSwitchFile && workKind === 'series'"
            type="button"
            class="scope-switch"
            @click="wholeWork = !wholeWork"
          >
            {{ wholeWork && kind === 'series' ? '只改一集' : '整部改挂' }}
          </button>
        </div>
        <button type="button" class="close" @click="emit('close')">关闭</button>
      </header>

      <div class="search-bar">
        <input
          v-model="query"
          type="search"
          placeholder="搜索片名…"
          autofocus
          @keydown.enter.prevent="search"
        />
        <div class="kind-toggle" role="group" aria-label="类型">
          <button type="button" :class="{ active: kind === 'movie' }" @click="setKind('movie')">电影</button>
          <button type="button" :class="{ active: kind === 'series' }" @click="setKind('series')">剧集</button>
        </div>
        <button type="button" class="search-btn" :disabled="searching" @click="search">
          {{ searching ? '搜索中…' : '搜索' }}
        </button>
      </div>

      <div class="params">
        <label>
          <span>年份</span>
          <input
            v-model="year"
            inputmode="numeric"
            :placeholder="yearPlaceholder"
            @keydown.enter.prevent="search"
          />
        </label>
        <label v-if="kind === 'series' && fixingOne">
          <span>季</span>
          <input
            v-model="season"
            inputmode="numeric"
            :placeholder="activeFile?.parsedSeason != null ? `默认 ${activeFile.parsedSeason}` : '季'"
            @keydown.enter.prevent="search"
          />
        </label>
        <label v-if="kind === 'series' && fixingOne">
          <span>集</span>
          <input
            v-model="episode"
            inputmode="numeric"
            :placeholder="activeFile?.parsedEpisode != null ? `默认 ${activeFile.parsedEpisode}` : '集'"
            @keydown.enter.prevent="search"
          />
        </label>
      </div>

      <p v-if="searchError" class="err">{{ searchError }}</p>

      <div v-if="searching" class="muted">正在搜索候选…</div>
      <div v-else-if="!candidates.length" class="muted">暂无结果，可改关键词后重试。</div>

      <ul v-else class="candidates">
        <li v-for="item in candidates" :key="`${item.kind}-${item.externalId}`">
          <button
            type="button"
            class="candidate"
            @click="choose(item)"
          >
            <div class="poster">
              <PosterMedia :src="item.posterUrl" :alt="item.title || ''" />
            </div>
            <div class="info">
              <strong>{{ item.title || item.originalTitle || '未命名' }}</strong>
              <span class="sub">
                <template v-if="item.originalTitle && item.originalTitle !== item.title">
                  {{ item.originalTitle }} ·
                </template>
                {{ item.year || '年份未知' }} · {{ item.kind }} · 相似度
                {{ item.score.toFixed(2) }}
              </span>
              <p v-if="item.overview" class="overview">{{ item.overview }}</p>
              <span class="cta">
                {{ wholeWork && kind === 'series' ? '整部改挂到这部剧' : '使用此项刮削' }}
              </span>
            </div>
          </button>
        </li>
      </ul>
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
  max-height: min(86vh, 860px);
  overflow: auto;
  border-radius: 18px;
  border: 1px solid var(--line-strong);
  background: linear-gradient(180deg, #141822 0%, var(--bg-deep) 100%);
  box-shadow: var(--shadow);
  padding: 1.25rem 1.25rem 1.5rem;
}

.dialog-head {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  align-items: flex-start;
  margin-bottom: 1rem;
}

.dialog-head h2 {
  margin: 0;
  font-family: var(--font-display);
  font-size: 1.35rem;
}

.file-pick {
  display: grid;
  gap: 0.35rem;
  margin-top: 0.65rem;
}

.file-pick span {
  font-size: 0.78rem;
  color: var(--ink-faint);
}

.file-pick select {
  width: 100%;
  border-radius: 10px;
  border: 1px solid var(--line-strong);
  background: rgba(10, 12, 16, 0.45);
  color: var(--ink);
  padding: 0.55rem 0.7rem;
  font: inherit;
}

.file-path {
  margin: 0.35rem 0 0;
  color: var(--ink-faint);
  font-size: 0.82rem;
  line-height: 1.45;
  word-break: break-all;
}

.scope-switch {
  margin-top: 0.45rem;
  padding: 0;
  border: 0;
  background: transparent;
  color: var(--copper);
  font: inherit;
  font-size: 0.85rem;
  cursor: pointer;
}

.close {
  border: 1px solid var(--line-strong);
  background: transparent;
  color: var(--ink);
  border-radius: 999px;
  padding: 0.4rem 0.85rem;
  cursor: pointer;
}

.search-bar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.65rem;
  margin-bottom: 0.85rem;
}

.search-bar input[type='search'] {
  flex: 1 1 180px;
  min-width: 0;
  border-radius: 999px;
  border: 1px solid var(--line-strong);
  background: rgba(10, 12, 16, 0.45);
  color: var(--ink);
  padding: 0.65rem 1rem;
  font: inherit;
}

.kind-toggle {
  display: inline-flex;
  border-radius: 999px;
  border: 1px solid var(--line-strong);
  overflow: hidden;
}

.kind-toggle button {
  border: 0;
  background: transparent;
  color: var(--ink-muted);
  padding: 0.55rem 0.9rem;
  cursor: pointer;
  font: inherit;
}

.kind-toggle button.active {
  background: rgba(212, 165, 116, 0.18);
  color: var(--copper);
}

.search-btn {
  border: 0;
  border-radius: 999px;
  background: var(--teal, #5fb3a8);
  color: #061312;
  font-weight: 700;
  padding: 0.65rem 1.1rem;
  cursor: pointer;
}

.search-btn:disabled {
  opacity: 0.6;
  cursor: wait;
}

.params {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
  gap: 0.75rem;
  margin-bottom: 0.85rem;
}

.params label {
  display: grid;
  gap: 0.3rem;
  font-size: 0.8rem;
  color: var(--ink-faint);
}

.params input {
  border-radius: 10px;
  border: 1px solid var(--line-strong);
  background: rgba(10, 12, 16, 0.45);
  color: var(--ink);
  padding: 0.55rem 0.7rem;
  font: inherit;
}

.err {
  color: var(--danger);
  margin: 0 0 0.75rem;
}

.muted {
  color: var(--ink-faint);
  margin: 0.5rem 0 0;
}

.candidates {
  list-style: none;
  margin: 0.75rem 0 0;
  padding: 0;
  display: grid;
  gap: 0.75rem;
}

.candidate {
  width: 100%;
  display: grid;
  grid-template-columns: 72px minmax(0, 1fr);
  gap: 0.85rem;
  text-align: left;
  border-radius: 14px;
  border: 1px solid var(--line);
  background: rgba(255, 255, 255, 0.03);
  color: inherit;
  padding: 0.75rem;
  cursor: pointer;
  font: inherit;
}

.candidate:hover {
  border-color: var(--copper);
}

.poster {
  width: 72px;
  aspect-ratio: 2 / 3;
  border-radius: 8px;
  overflow: hidden;
  background: var(--bg-soft);
}

.poster :deep(.poster-media) {
  width: 100%;
  height: 100%;
}

.info {
  display: grid;
  gap: 0.3rem;
  align-content: start;
}

.info strong {
  font-size: 1.02rem;
}

.sub {
  color: var(--ink-faint);
  font-size: 0.82rem;
}

.overview {
  margin: 0;
  color: var(--ink-muted);
  font-size: 0.85rem;
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.cta {
  color: var(--copper);
  font-size: 0.85rem;
  font-weight: 600;
}
</style>
