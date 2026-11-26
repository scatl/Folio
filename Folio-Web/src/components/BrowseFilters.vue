<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { listWorkFacets } from '../api/client'
import type { WorkFacets } from '../api/types'
import FolioCheck from './FolioCheck.vue'
import FolioSelect from './FolioSelect.vue'
import { browseCount, emptyBrowseFilter, type WorkBrowseFilter } from '../lib/browse'

const props = defineProps<{
  modelValue: WorkBrowseFilter
  libraryId?: number | null
}>()

const emit = defineEmits<{
  'update:modelValue': [value: WorkBrowseFilter]
}>()

const open = ref(false)
const narrow = ref(window.matchMedia('(max-width: 720px)').matches)
const facets = ref<WorkFacets | null>(null)
const facetError = ref('')
const personQuery = ref('')
let personTimer: ReturnType<typeof setTimeout> | null = null

const count = computed(() => browseCount(props.modelValue))
const ratingScale = computed(() => {
  const provider = props.modelValue.ratingProvider
  if (provider === 'rottentomatoes' || provider === 'metacritic') return '0–100'
  return '0–10'
})

const watches = [
  { id: '', label: '全部' },
  { id: 'unwatched', label: '未看' },
  { id: 'watching', label: '在看' },
  { id: 'watched', label: '已看' },
]

const sorts = [
  { id: 'popularity', label: '热度' },
  { id: 'year', label: '年份' },
  { id: 'rating', label: '评分' },
  { id: 'added', label: '入库时间' },
]

const runtimes = [
  { id: '', label: '不限' },
  { id: 'lt90', label: '90 分钟内' },
  { id: 'm90', label: '90–120 分钟' },
  { id: 'm120', label: '120–150 分钟' },
  { id: 'm150', label: '150 分钟以上' },
]

const statuses = [
  { id: '', label: '不限' },
  { id: 'airing', label: '连载中' },
  { id: 'ended', label: '已完结' },
  { id: 'canceled', label: '已取消' },
]

const resolutions = [
  { id: '', label: '不限' },
  { id: '2160', label: '4K' },
  { id: '1080', label: '1080p' },
  { id: '720', label: '720p' },
  { id: 'sd', label: '标清' },
]

const subtitles = [
  { id: '', label: '不限' },
  { id: 'embedded', label: '有内嵌字幕' },
  { id: 'none', label: '无内嵌字幕' },
]

const providers = [
  { id: '', label: '不限' },
  { id: 'tmdb', label: 'TMDB' },
  { id: 'imdb', label: 'IMDb' },
  { id: 'rottentomatoes', label: '烂番茄' },
  { id: 'metacritic', label: 'Metacritic' },
]

function patch(partial: Partial<WorkBrowseFilter>) {
  emit('update:modelValue', { ...props.modelValue, ...partial })
}

function clearAll() {
  personQuery.value = ''
  emit('update:modelValue', emptyBrowseFilter())
}

async function loadFacets(personQ?: string) {
  try {
    const data = await listWorkFacets({
      libraryId: props.libraryId ?? undefined,
      personQ: personQ || undefined,
    })
    if (personQ) {
      facets.value = { ...(facets.value ?? data), people: data.people }
    } else {
      facets.value = data
    }
    facetError.value = ''
  } catch (e) {
    facetError.value = e instanceof Error ? e.message : '筛选项加载失败'
  }
}

function openPanel() {
  open.value = true
  if (!facets.value) void loadFacets()
}

function closePanel() {
  open.value = false
}

function onKey(event: KeyboardEvent) {
  if (!open.value || event.key !== 'Escape') return
  event.preventDefault()
  closePanel()
}

function syncNarrow() {
  narrow.value = window.matchMedia('(max-width: 720px)').matches
}

watch(
  () => props.libraryId,
  () => {
    facets.value = null
    if (open.value) void loadFacets()
  },
)

watch(open, (value) => {
  document.body.style.overflow = value ? 'hidden' : ''
})

onMounted(() => {
  syncNarrow()
  window.addEventListener('resize', syncNarrow)
  window.addEventListener('keydown', onKey)
})

onUnmounted(() => {
  window.removeEventListener('resize', syncNarrow)
  window.removeEventListener('keydown', onKey)
  if (open.value) document.body.style.overflow = ''
})

function onPersonInput() {
  if (personTimer) clearTimeout(personTimer)
  const q = personQuery.value.trim()
  if (!q) {
    if (facets.value) facets.value = { ...facets.value, people: [] }
    return
  }
  personTimer = setTimeout(() => {
    void loadFacets(q)
  }, 280)
}

function asList(value: string | string[]) {
  return Array.isArray(value) ? value.filter((item) => item !== '') : value ? [value] : []
}

function asOne(value: string | string[]) {
  return Array.isArray(value) ? value[0] ?? '' : value
}

function namedOptions(items?: { id: string; label: string }[]) {
  return [{ id: '', label: '不限' }, ...(items ?? [])]
}

function tokenOptions(items?: string[]) {
  const seen = new Set<string>()
  const options = [{ id: '', label: '不限' }]
  for (const item of items ?? []) {
    if (!item || seen.has(item)) continue
    seen.add(item)
    options.push({ id: item, label: item === 'sdr' ? 'SDR' : item })
  }
  return options
}

function choosePerson(id: string, label: string) {
  patch({ personId: id, personLabel: label })
  personQuery.value = ''
  if (facets.value) facets.value = { ...facets.value, people: [] }
}
</script>

<template>
  <div class="browse">
    <div class="bar">
      <button type="button" class="filter-btn" @click="openPanel">
        筛选
        <span v-if="count" class="count">{{ count }}</span>
      </button>
      <button v-if="count" type="button" class="text" @click="clearAll">清除</button>
    </div>

    <Teleport to="body">
    <div v-if="open" class="overlay" :class="{ sheet: narrow }" @click.self="closePanel">
    <div class="panel" role="dialog" aria-modal="true" aria-label="筛选">
      <div v-if="narrow" class="grabber" aria-hidden="true" />
      <div class="panel-head">
        <h2>筛选</h2>
        <div class="head-actions">
          <button v-if="count" type="button" class="text" @click="clearAll">清除</button>
          <button type="button" class="text" @click="closePanel">关闭</button>
        </div>
      </div>
      <p v-if="facetError" class="err">{{ facetError }}</p>
      <div class="fields">
        <label>
          观看状态
          <FolioSelect :model-value="modelValue.watch" :options="watches" @update:model-value="patch({ watch: asOne($event) })" />
        </label>
        <label>
          排序
          <FolioSelect :model-value="modelValue.sort" :options="sorts" @update:model-value="patch({ sort: asOne($event) })" />
        </label>
        <label>
          类型
          <FolioSelect multiple :model-value="modelValue.genreIds" :options="namedOptions(facets?.genres)" @update:model-value="patch({ genreIds: asList($event) })" />
        </label>
        <label>
          年份从
          <input :value="modelValue.yearFrom" inputmode="numeric" placeholder="不限" @input="patch({ yearFrom: ($event.target as HTMLInputElement).value.trim() })" />
        </label>
        <label>
          年份到
          <input :value="modelValue.yearTo" inputmode="numeric" placeholder="不限" @input="patch({ yearTo: ($event.target as HTMLInputElement).value.trim() })" />
        </label>
        <label>
          评分来源
          <FolioSelect :model-value="modelValue.ratingProvider" :options="providers" @update:model-value="patch({ ratingProvider: asOne($event) })" />
        </label>
        <label>
          最低评分
          <input :value="modelValue.ratingMin" inputmode="decimal" :placeholder="ratingScale" @input="patch({ ratingMin: ($event.target as HTMLInputElement).value.trim() })" />
        </label>
        <label>
          地区
          <FolioSelect multiple :model-value="modelValue.countries" :options="namedOptions(facets?.countries)" @update:model-value="patch({ countries: asList($event) })" />
        </label>
        <label>
          语言
          <FolioSelect multiple :model-value="modelValue.languages" :options="namedOptions(facets?.languages)" @update:model-value="patch({ languages: asList($event) })" />
        </label>
        <label>
          片长
          <FolioSelect multiple :model-value="modelValue.runtimes" :options="runtimes" @update:model-value="patch({ runtimes: asList($event) })" />
        </label>
        <label>
          关键词
          <FolioSelect multiple :model-value="modelValue.keywordIds" :options="namedOptions(facets?.keywords)" @update:model-value="patch({ keywordIds: asList($event) })" />
        </label>
        <label class="wide">
          演职员
          <input v-model="personQuery" type="search" placeholder="输入姓名" @input="onPersonInput" />
          <span v-if="modelValue.personLabel" class="picked">
            {{ modelValue.personLabel }}
            <button type="button" @click="patch({ personId: '', personLabel: '' })">移除</button>
          </span>
          <span v-if="facets?.people?.length" class="picks">
            <button v-for="item in facets.people" :key="item.id" type="button" @click="choosePerson(item.id, item.label)">
              {{ item.label }}
            </button>
          </span>
        </label>
        <label>
          出品公司
          <FolioSelect multiple :model-value="modelValue.companyIds" :options="namedOptions(facets?.companies)" @update:model-value="patch({ companyIds: asList($event) })" />
        </label>
        <label>
          系列
          <FolioSelect multiple :model-value="modelValue.collectionIds" :options="namedOptions(facets?.collections)" @update:model-value="patch({ collectionIds: asList($event) })" />
        </label>
        <label class="check">
          <FolioCheck :model-value="modelValue.inCollection" @update:model-value="patch({ inCollection: $event })" />
          <span>只看系列作品</span>
        </label>
        <label>
          连载状态
          <FolioSelect multiple :model-value="modelValue.showStatuses" :options="statuses" @update:model-value="patch({ showStatuses: asList($event) })" />
        </label>
        <label>
          分辨率
          <FolioSelect multiple :model-value="modelValue.resolutions" :options="resolutions" @update:model-value="patch({ resolutions: asList($event) })" />
        </label>
        <label>
          动态范围
          <FolioSelect multiple :model-value="modelValue.dynamicRanges" :options="tokenOptions(['sdr', ...(facets?.dynamicRanges ?? [])])" @update:model-value="patch({ dynamicRanges: asList($event) })" />
        </label>
        <label>
          视频编码
          <FolioSelect multiple :model-value="modelValue.videoCodecs" :options="tokenOptions(facets?.videoCodecs)" @update:model-value="patch({ videoCodecs: asList($event) })" />
        </label>
        <label>
          音轨编码
          <FolioSelect multiple :model-value="modelValue.audioCodecs" :options="tokenOptions(facets?.audioCodecs)" @update:model-value="patch({ audioCodecs: asList($event) })" />
        </label>
        <label>
          字幕
          <FolioSelect :model-value="modelValue.subtitle" :options="subtitles" @update:model-value="patch({ subtitle: asOne($event) })" />
        </label>
      </div>
    </div>
    </div>
    </Teleport>
  </div>
</template>

<style scoped>
.browse {
  display: grid;
}

.bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.4rem;
}

.filter-btn,
.text,
.fields input,
.picks button,
.picked button {
  font: inherit;
}

.filter-btn {
  margin: 0;
  padding: 0.35rem 0.75rem;
  border: 1px solid var(--line-strong);
  border-radius: 999px;
  background: transparent;
  color: var(--ink);
  cursor: pointer;
}

.count {
  margin-left: 0.3rem;
  color: var(--copper);
}

.text {
  margin: 0;
  padding: 0.35rem 0.2rem;
  border: 0;
  background: transparent;
  color: var(--ink-muted);
  cursor: pointer;
}

.overlay {
  position: fixed;
  inset: 0;
  z-index: 80;
  display: grid;
  place-items: center;
  padding: 1.25rem;
  background: rgba(4, 6, 10, 0.45);
  backdrop-filter: blur(18px);
  -webkit-backdrop-filter: blur(18px);
}

.overlay.sheet {
  place-items: end stretch;
  padding: 0;
}

.panel {
  display: grid;
  align-content: start;
  gap: 0.8rem;
  width: min(720px, 100%);
  max-height: min(80vh, 760px);
  overflow: auto;
  padding: 0.9rem 1rem 1rem;
  border: 1px solid var(--line-strong);
  border-radius: 16px;
  background: rgba(16, 19, 26, 0.98);
}

.overlay.sheet .panel {
  width: 100%;
  max-height: min(88vh, 100%);
  border-radius: 16px 16px 0 0;
  border-bottom: 0;
  padding-bottom: calc(1rem + env(safe-area-inset-bottom, 0px));
}

.grabber {
  width: 2.4rem;
  height: 0.25rem;
  margin: 0.15rem auto 0.2rem;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.28);
}

.panel-head,
.head-actions {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.6rem;
}

.panel-head h2 {
  margin: 0;
  font-size: 1rem;
}

.err {
  margin: 0;
  color: var(--danger);
}

.fields {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0.75rem 0.9rem;
}

.overlay.sheet .fields {
  grid-template-columns: 1fr;
}

.fields label {
  display: grid;
  gap: 0.3rem;
  color: var(--ink-muted);
  font-size: 0.78rem;
}

.fields input {
  width: 100%;
  height: 2.7rem;
  padding: 0 0.85rem;
  border: 1px solid var(--line-strong);
  border-radius: 12px;
  background: rgba(18, 21, 28, 0.86);
  color: var(--ink);
}

.fields input:focus {
  border-color: rgba(212, 165, 116, 0.55);
  box-shadow: 0 0 0 3px var(--copper-soft);
  outline: none;
}

.wide,
.fields label.check {
  grid-column: 1 / -1;
}

.fields label.check {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: flex-start;
  gap: 0.45rem;
  width: fit-content;
}

.picked,
.picks {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
}

.picks button,
.picked button {
  padding: 0.2rem 0.5rem;
  border: 1px solid var(--line);
  border-radius: 999px;
  background: transparent;
  color: var(--ink);
  cursor: pointer;
}
</style>
