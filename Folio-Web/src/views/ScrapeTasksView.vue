<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { confirmManualMatch, deleteScrapeJob, listScrapeJobs, retryScrapeJob } from '../api/client'
import { subscribeScrapeEvents } from '../api/events'
import type { MatchCandidate, ReviewFileRow, ScrapeJobRow } from '../api/types'
import EmptyState from '../components/EmptyState.vue'
import LoadingState from '../components/LoadingState.vue'
import ManualMatchDialog from '../components/ManualMatchDialog.vue'
import { confirmDialog } from '../lib/confirm'

const router = useRouter()

const items = ref<ScrapeJobRow[]>([])
const page = ref(0)
const total = ref(0)
const totalPages = ref(0)
const loading = ref(true)
const loadingMore = ref(false)
const error = ref<string | null>(null)
const statusFilter = ref('')
const deletingId = ref<number | null>(null)
const retryingId = ref<number | null>(null)
const matchJob = ref<ScrapeJobRow | null>(null)
const actionError = ref<string | null>(null)

const bottomSentinel = ref<HTMLElement | null>(null)

let unsubscribeEvents: (() => void) | null = null
let bottomObserver: IntersectionObserver | null = null

const empty = computed(() => !loading.value && !error.value && items.value.length === 0)
const hasMore = computed(() => page.value + 1 < totalPages.value)
const statusText = computed(() => {
  if (loading.value) return '正在加载刮削任务'
  if (error.value) return error.value
  return `共 ${total.value} 个任务`
})

const matchFile = computed<ReviewFileRow | null>(() => {
  const job = matchJob.value
  if (!job) return null
  return {
    id: job.fileId,
    fileName: job.fileName,
    locator: job.locator,
    status: job.matchStatus,
    parsedTitle: job.parsedTitle,
    parsedYear: job.parsedYear,
    parsedSeason: job.parsedSeason,
    parsedEpisode: job.parsedEpisode,
    confidence: job.confidence,
    message: job.message,
  }
})

function jobStatusLabel(status: string) {
  switch (status) {
    case 'queued':
      return '排队中'
    case 'running':
      return '执行中'
    case 'succeeded':
      return '已完成'
    case 'failed':
      return '失败'
    default:
      return status
  }
}

function matchStatusLabel(status: string) {
  switch (status) {
    case 'pending':
      return '待匹配'
    case 'matched':
      return '已匹配'
    case 'needs_review':
      return '待人工确认'
    case 'failed':
      return '匹配失败'
    default:
      return status
  }
}

function canManualMatch(job: ScrapeJobRow) {
  return (
    job.matchStatus === 'needs_review' ||
    job.matchStatus === 'failed' ||
    job.matchStatus === 'matched'
  )
}

function canDelete(job: ScrapeJobRow) {
  return job.status !== 'running'
}

function canRetry(job: ScrapeJobRow) {
  return job.status === 'failed' || job.matchStatus === 'failed'
}

function shortMessage(message: string | null | undefined) {
  if (!message) return ''
  const compact = message.replace(/\s+/g, ' ').trim()
  if (!compact) return ''
  return compact.length > 72 ? `${compact.slice(0, 72)}…` : compact
}

function hidesCompleted(job: ScrapeJobRow) {
  return job.status === 'succeeded' && (job.matchStatus === 'needs_review' || job.matchStatus === 'failed')
}

function progressText(job: ScrapeJobRow) {
  if (job.progress === '待人工确认') return ''
  if (job.progress) return hidesCompleted(job) && job.progress === '已完成' ? '' : job.progress
  if (job.status === 'queued') return '等待执行'
  if (job.status === 'running') return '执行中…'
  if (job.status === 'succeeded') return hidesCompleted(job) ? '' : '已完成'
  if (job.status === 'failed') return '失败'
  return ''
}

function isLive(job: ScrapeJobRow) {
  return job.status === 'queued' || job.status === 'running'
}

async function fetchPage(nextPage: number, append: boolean, silent = false) {
  if (append) {
    if (!hasMore.value || loading.value || loadingMore.value) return
    loadingMore.value = true
  } else if (!silent) {
    loading.value = true
    loadingMore.value = false
    error.value = null
  }
  let ok = false
  try {
    const data = await listScrapeJobs({
      status: statusFilter.value || undefined,
      page: nextPage,
      size: 50,
    })
    items.value = append ? [...items.value, ...data.items] : data.items
    page.value = data.page
    total.value = data.total
    totalPages.value = data.totalPages
    ok = true
  } catch (e) {
    if (!silent) {
      error.value = e instanceof Error ? e.message : '加载失败'
      if (!append) items.value = []
    }
  } finally {
    if (append) loadingMore.value = false
    else if (!silent) loading.value = false
  }
  if (ok) await fillIfShort()
}

function reload(silent = false) {
  void fetchPage(0, false, silent)
}

function loadMore() {
  if (!hasMore.value || loading.value || loadingMore.value) return
  void fetchPage(page.value + 1, true)
}

async function fillIfShort() {
  await nextTick()
  const el = bottomSentinel.value
  if (!el || !hasMore.value || loading.value || loadingMore.value) return
  const rect = el.getBoundingClientRect()
  if (rect.top <= window.innerHeight + 320) loadMore()
}

function onBottomVisible(entries: IntersectionObserverEntry[]) {
  if (entries.some((entry) => entry.isIntersecting)) loadMore()
}

function setStatus(value: string) {
  if (statusFilter.value === value) return
  statusFilter.value = value
  reload()
}

function openMatch(job: ScrapeJobRow) {
  actionError.value = null
  matchJob.value = job
}

function onConfirmMatch(
  candidate: MatchCandidate,
  options: { fileId: number; year?: number; season?: number; episode?: number; scope?: 'file' | 'work' },
) {
  const job = matchJob.value
  matchJob.value = null
  if (!job) return
  actionError.value = null
  void confirmManualMatch(options.fileId, {
    kind: candidate.kind,
    tmdbId: Number(candidate.externalId),
    year: options.year,
    season: options.season,
    episode: options.episode,
    scope: options.scope,
  })
    .then(() => {
      const current = items.value.find((item) => item.id === job.id)
      if (!current || current.matchStatus !== 'needs_review') return
      onJobEvent({
        ...current,
        status: 'running',
        matchStatus: 'pending',
        progress: '人工匹配中',
        message: '人工匹配中',
        lastError: null,
      })
    })
    .catch((e) => {
      actionError.value = e instanceof Error ? e.message : '匹配失败'
    })
}

async function removeJob(job: ScrapeJobRow) {
  if (!canDelete(job) || deletingId.value || retryingId.value) return
  const ok = await confirmDialog({
    title: '删除任务',
    message: `确定删除任务「${job.fileName}」？\n将同时删除对应文件记录。`,
    confirmLabel: '删除',
    danger: true,
  })
  if (!ok) return
  deletingId.value = job.id
  actionError.value = null
  try {
    await deleteScrapeJob(job.id)
    items.value = items.value.filter((item) => item.id !== job.id)
    total.value = Math.max(0, total.value - 1)
  } catch (e) {
    actionError.value = e instanceof Error ? e.message : '删除失败'
  } finally {
    deletingId.value = null
  }
}

async function retryJob(job: ScrapeJobRow) {
  if (!canRetry(job) || retryingId.value || deletingId.value) return
  retryingId.value = job.id
  actionError.value = null
  try {
    const updated = await retryScrapeJob(job.id)
    const index = items.value.findIndex((item) => item.id === job.id)
    if (index >= 0) {
      if (!matchesFilter(updated)) {
        items.value = items.value.filter((item) => item.id !== job.id)
        total.value = Math.max(0, total.value - 1)
      } else {
        items.value[index] = updated
      }
    }
  } catch (e) {
    actionError.value = e instanceof Error ? e.message : '重试失败'
  } finally {
    retryingId.value = null
  }
}

function openWork(workId: number) {
  void router.push({ name: 'work', params: { id: String(workId) } })
}

function back() {
  void router.push({ name: 'wall' })
}

function matchesFilter(job: ScrapeJobRow) {
  if (job.matchStatus === 'matched') return false
  switch (statusFilter.value) {
    case '':
      return true
    case 'queued':
      return job.status === 'queued'
    case 'running':
      return job.status === 'running' && job.matchStatus !== 'matched'
    case 'needs_review':
      return job.matchStatus === 'needs_review'
    case 'failed':
      return job.matchStatus !== 'needs_review' &&
        job.matchStatus !== 'matched' &&
        (job.status === 'failed' || job.matchStatus === 'failed')
    default:
      return true
  }
}

function onJobEvent(job: ScrapeJobRow) {
  const index = items.value.findIndex((item) => item.id === job.id)
  if (!matchesFilter(job)) {
    if (index >= 0) {
      items.value = items.value.filter((item) => item.id !== job.id)
      total.value = Math.max(0, total.value - 1)
    }
    return
  }
  if (index >= 0) {
    items.value[index] = job
    return
  }
  // 新任务插入顶部（仅当前第一页场景）
  if (page.value === 0) {
    items.value = [job, ...items.value]
    total.value += 1
  }
}

function onDeletedEvent(id: number) {
  const before = items.value.length
  items.value = items.value.filter((item) => item.id !== id)
  if (items.value.length < before) {
    total.value = Math.max(0, total.value - 1)
  }
  if (matchJob.value?.id === id) matchJob.value = null
}

watch(bottomSentinel, (el, prev) => {
  if (!bottomObserver) return
  if (prev) bottomObserver.unobserve(prev)
  if (el) bottomObserver.observe(el)
})

onMounted(() => {
  bottomObserver = new IntersectionObserver(onBottomVisible, {
    root: null,
    rootMargin: '320px 0px',
  })
  if (bottomSentinel.value) bottomObserver.observe(bottomSentinel.value)
  reload()
  unsubscribeEvents = subscribeScrapeEvents({
    onJob: onJobEvent,
    onDeleted: onDeletedEvent,
  })
})

onBeforeUnmount(() => {
  bottomObserver?.disconnect()
  bottomObserver = null
  unsubscribeEvents?.()
  unsubscribeEvents = null
})
</script>

<template>
  <div class="tasks">
    <header class="masthead">
      <div class="brand-block">
        <button type="button" class="back" @click="back">← 海报墙</button>
        <h1>刮削任务</h1>
        <p class="lede">查看队列中的全部任务，可按状态筛选、人工匹配或删除。</p>
      </div>
      <div class="mast-actions">
        <p :class="['status', { err: !!error && !loading }]">{{ statusText }}</p>
        <button type="button" class="ghost" :disabled="loading" @click="reload()">刷新</button>
      </div>
    </header>

    <div class="filter-bar">
      <div class="filters" role="tablist" aria-label="任务状态筛选">
        <button type="button" :class="{ active: statusFilter === '' }" @click="setStatus('')">全部</button>
        <button type="button" :class="{ active: statusFilter === 'queued' }" @click="setStatus('queued')">
          排队中
        </button>
        <button type="button" :class="{ active: statusFilter === 'running' }" @click="setStatus('running')">
          执行中
        </button>
        <button type="button" :class="{ active: statusFilter === 'needs_review' }" @click="setStatus('needs_review')">
          待人工确认
        </button>
        <button type="button" :class="{ active: statusFilter === 'failed' }" @click="setStatus('failed')">
          失败
        </button>
      </div>
    </div>

    <p v-if="actionError" class="action-err">{{ actionError }}</p>

    <LoadingState v-if="loading" />

    <EmptyState
      v-else-if="empty"
      title="暂无刮削任务"
      body="创建资料库后，文件会进入这里排队刮削。"
    />

    <section v-else class="job-list" aria-label="刮削任务列表">
      <article v-for="job in items" :key="job.id" class="job">
        <div class="job-main">
          <div class="file-stack">
            <strong>{{ job.parsedTitle || job.fileName }}</strong>
            <span class="sub path" :title="job.locator || job.fileName">{{ job.locator || job.fileName }}</span>
            <span v-if="job.parsedYear || job.parsedSeason != null" class="sub">
              <template v-if="job.parsedYear">{{ job.parsedYear }}</template>
              <template v-if="job.parsedSeason != null">
                · S{{ String(job.parsedSeason).padStart(2, '0') }}
                <template v-if="job.parsedEpisode != null">
                  E{{ String(job.parsedEpisode).padStart(2, '0') }}
                </template>
              </template>
            </span>
          </div>
          <div class="job-meta">
            <span v-if="!hidesCompleted(job)" class="chip" :data-status="job.status">{{ jobStatusLabel(job.status) }}</span>
            <span class="chip match" :data-match="job.matchStatus">{{ matchStatusLabel(job.matchStatus) }}</span>
            <span v-if="progressText(job)" class="progress-cell" :class="{ live: isLive(job) }">
              <span v-if="isLive(job)" class="progress-dot" aria-hidden="true" />
              <span>{{ progressText(job) }}</span>
            </span>
            <span v-if="job.mediaLibraryName" class="muted-cell">{{ job.mediaLibraryName }}</span>
            <span class="muted-cell">尝试次数：{{ job.attempts }}/{{ job.maxAttempts }}</span>
            <span
              v-if="shortMessage(job.lastError || job.message)"
              class="msg-cell"
              :title="job.lastError || job.message || undefined"
            >
              {{ shortMessage(job.lastError || job.message) }}
            </span>
          </div>
        </div>
        <div class="actions">
          <button
            v-if="canRetry(job)"
            type="button"
            class="link-btn"
            :disabled="retryingId === job.id || deletingId === job.id"
            @click="retryJob(job)"
          >
            {{ retryingId === job.id ? '重试中…' : '重试' }}
          </button>
          <button v-if="canManualMatch(job)" type="button" class="link-btn" @click="openMatch(job)">
            人工匹配
          </button>
          <button v-if="job.workId" type="button" class="link-btn" @click="openWork(job.workId)">
            查看作品
          </button>
          <button
            type="button"
            class="link-btn danger"
            :disabled="!canDelete(job) || deletingId === job.id || retryingId === job.id"
            @click="removeJob(job)"
          >
            {{ deletingId === job.id ? '删除中…' : '删除' }}
          </button>
        </div>
      </article>
    </section>

    <div v-if="hasMore" ref="bottomSentinel" class="sentinel" aria-hidden="true" />
    <p v-if="loadingMore" class="more-status">加载中…</p>

    <ManualMatchDialog
      v-if="matchFile"
      :file="matchFile"
      @close="matchJob = null"
      @confirm="onConfirmMatch"
    />
  </div>
</template>

<style scoped>
.tasks {
  width: min(1280px, calc(100% - 2.5rem));
  max-width: 100%;
  margin: 0 auto;
  padding: 2rem 0 4rem;
  overflow-x: clip;
}

.masthead {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  gap: 1rem;
  padding-bottom: 1.25rem;
  border-bottom: 1px solid var(--line);
  margin-bottom: 1.25rem;
}

.back {
  display: inline-flex;
  align-items: center;
  margin-bottom: 0.75rem;
  border: 1px solid var(--line-strong);
  background: rgba(18, 21, 28, 0.72);
  color: var(--ink);
  border-radius: 999px;
  padding: 0.55rem 0.95rem;
  cursor: pointer;
  font-weight: 650;
  font-size: 0.88rem;
  transition:
    border-color 0.2s ease,
    color 0.2s ease;
}

.back:hover {
  border-color: rgba(212, 165, 116, 0.5);
  color: var(--copper);
}

.brand-block h1 {
  margin: 0;
  font-family: var(--font-display);
  font-size: clamp(2rem, 4vw, 2.75rem);
  letter-spacing: -0.03em;
}

.lede,
.status {
  margin: 0.5rem 0 0;
  color: var(--ink-muted);
}

.mast-actions {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 0.55rem;
}

.mast-actions .ghost {
  border: 1px solid var(--line);
  background: transparent;
  color: var(--ink-muted);
  border-radius: 999px;
  padding: 0.3rem 0.75rem;
  cursor: pointer;
  font-size: 0.82rem;
}

.mast-actions .ghost:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.status.err,
.action-err {
  color: var(--danger);
}

.action-err {
  margin: 0 0 0.85rem;
  font-size: 0.9rem;
}

.filter-bar {
  margin: 0 0 1.15rem;
  padding: 0;
}

.filters {
  display: flex;
  width: 100%;
  max-width: 100%;
  flex-wrap: wrap;
  gap: 0.35rem;
  padding: 0;
  border: 0;
  background: transparent;
}

.filters button {
  border: 0;
  background: transparent;
  color: var(--ink-muted);
  padding: 0.45rem 0.95rem;
  border-radius: 999px;
  cursor: pointer;
  font-weight: 600;
  font-size: 0.88rem;
}

.filters button.active {
  background: linear-gradient(135deg, rgba(212, 165, 116, 0.22), rgba(95, 179, 168, 0.18));
  color: var(--ink);
}

.panel {
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: rgba(18, 21, 28, 0.55);
  padding: 2rem 1.25rem;
}

.empty {
  text-align: center;
}

.empty h2 {
  margin: 0;
  font-family: var(--font-display);
}

.empty p,
.muted {
  margin: 0.55rem 0 0;
  color: var(--ink-muted);
}

.job-list {
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: rgba(18, 21, 28, 0.55);
}

.job {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 0.75rem 1rem;
  align-items: start;
  padding: 0.9rem 1rem;
  border-bottom: 1px solid var(--line);
}

.job:last-child {
  border-bottom: 0;
}

.job-main {
  min-width: 0;
}

.job-meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.4rem 0.75rem;
  margin-top: 0.45rem;
  min-width: 0;
}

.file-stack {
  display: grid;
  gap: 0.2rem;
  min-width: 0;
}

.file-stack strong,
.file-stack .sub {
  display: -webkit-box;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  overflow: hidden;
  overflow-wrap: anywhere;
  white-space: normal;
}

.file-stack .sub.path {
  display: block;
  -webkit-line-clamp: unset;
  overflow: visible;
}

.sub,
.muted-cell,
.msg-cell {
  color: var(--ink-faint);
  font-size: 0.82rem;
}

.msg-cell {
  line-height: 1.4;
  display: -webkit-box;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  overflow: hidden;
  overflow-wrap: anywhere;
}

.progress-cell {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  max-width: 100%;
  color: var(--ink-muted);
  font-size: 0.88rem;
  font-weight: 600;
}

.progress-cell.live {
  color: var(--copper);
}

.progress-dot {
  width: 0.45rem;
  height: 0.45rem;
  border-radius: 50%;
  background: var(--copper);
  box-shadow: 0 0 0 0 rgba(212, 165, 116, 0.45);
  animation: pulse-dot 1.4s ease-out infinite;
}

@keyframes pulse-dot {
  0% {
    box-shadow: 0 0 0 0 rgba(212, 165, 116, 0.45);
  }
  70% {
    box-shadow: 0 0 0 8px rgba(212, 165, 116, 0);
  }
  100% {
    box-shadow: 0 0 0 0 rgba(212, 165, 116, 0);
  }
}

@media (prefers-reduced-motion: reduce) {
  .progress-dot {
    animation: none;
  }
}

.chip {
  display: inline-flex;
  align-items: center;
  padding: 0.2rem 0.55rem;
  border-radius: 999px;
  font-size: 0.78rem;
  font-weight: 700;
  border: 1px solid var(--line-strong);
  color: var(--ink-muted);
  white-space: nowrap;
}

.chip[data-status='queued'] {
  color: var(--ink);
  border-color: rgba(95, 179, 168, 0.4);
}

.chip[data-status='running'] {
  color: var(--copper);
  border-color: rgba(212, 165, 116, 0.45);
}

.chip[data-status='failed'],
.chip[data-match='failed'] {
  color: var(--danger);
  border-color: rgba(224, 122, 107, 0.45);
}

.chip[data-status='succeeded'],
.chip[data-match='matched'] {
  color: var(--teal);
  border-color: rgba(95, 179, 168, 0.4);
}

.chip[data-match='needs_review'] {
  color: var(--copper);
  border-color: rgba(212, 165, 116, 0.45);
}

.actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  align-content: flex-start;
  gap: 0.4rem;
  width: 11.5rem;
  max-width: 100%;
}

.link-btn {
  border: 1px solid var(--line);
  background: transparent;
  color: var(--ink-muted);
  border-radius: 999px;
  padding: 0.28rem 0.45rem;
  cursor: pointer;
  font-size: 0.8rem;
  font-weight: 600;
  white-space: nowrap;
}

.link-btn:hover:not(:disabled) {
  color: var(--copper);
  border-color: rgba(212, 165, 116, 0.45);
}

.link-btn.danger:hover:not(:disabled) {
  color: var(--danger);
  border-color: rgba(224, 122, 107, 0.45);
}

.link-btn:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.sentinel {
  height: 1px;
}

.more-status {
  margin: 1rem 0 0;
  text-align: center;
  color: var(--ink-muted);
  font-size: 0.85rem;
}

@media (max-width: 720px) {
  .tasks {
    width: min(100% - 1.1rem, 1280px);
    padding: calc(1rem + var(--safe-top)) 0 calc(2.5rem + var(--safe-bottom));
  }

  .masthead {
    flex-direction: column;
    align-items: stretch;
  }

  .mast-actions {
    align-items: flex-start;
    flex-direction: row;
    flex-wrap: wrap;
  }

  .filters {
    border-radius: 16px;
    overflow-x: auto;
    flex-wrap: nowrap;
    scrollbar-width: none;
  }

  .filters::-webkit-scrollbar {
    display: none;
  }

  .filters button {
    flex: 0 0 auto;
  }

  .job {
    grid-template-columns: minmax(0, 1fr);
    padding: 0.85rem 0.8rem;
  }

  .actions {
    width: auto;
    justify-content: flex-start;
  }
}
</style>
