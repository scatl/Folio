<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { getServerLog, listServerLogs } from '../api/client'
import type { ServerLogContent, ServerLogFile } from '../api/types'
import EmptyState from '../components/EmptyState.vue'
import LoadingState from '../components/LoadingState.vue'
import { filterRecords, levelName, logLevels, type LogEntry, type LogLevel } from '../logs/filter'

const router = useRouter()

const level = ref<LogLevel>('all')
const available = ref(true)
const listMessage = ref<string | null>(null)
const files = ref<ServerLogFile[]>([])
const selected = ref<string | null>(null)
const content = ref<ServerLogContent | null>(null)
const listLoading = ref(true)
const contentLoading = ref(false)
const listError = ref<string | null>(null)
const contentError = ref<string | null>(null)
const viewer = ref<HTMLElement | null>(null)
const detail = ref<LogEntry | null>(null)

const records = computed(() => filterRecords(content.value?.text ?? '', level.value))
const rows = computed(() => {
  const items: { key: string; day?: string; entry?: LogEntry }[] = []
  let day: string | null = null
  records.value.forEach((entry, index) => {
    if (entry.date && entry.date !== day) {
      day = entry.date
      items.push({ key: `day-${day}-${index}`, day })
    }
    items.push({ key: `entry-${index}`, entry })
  })
  return items
})

function formatBytes(bytes: number) {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

async function scrollEnd() {
  await nextTick()
  const el = viewer.value
  if (el) el.scrollTop = el.scrollHeight
}

async function loadContent(name: string, keep: boolean) {
  selected.value = name
  contentLoading.value = true
  contentError.value = null
  if (!keep) content.value = null
  try {
    content.value = await getServerLog(name)
    await scrollEnd()
  } catch (e) {
    content.value = keep ? content.value : null
    contentError.value = e instanceof Error ? e.message : '读取失败'
  } finally {
    contentLoading.value = false
  }
}

async function loadList(keepSelection: boolean) {
  listLoading.value = true
  listError.value = null
  try {
    const listed = await listServerLogs()
    available.value = listed.available
    listMessage.value = listed.message
    files.value = listed.files
    if (!listed.available || listed.files.length === 0) {
      selected.value = null
      content.value = null
      return
    }
    const current = keepSelection ? selected.value : null
    const next = listed.files.find((file) => file.name === current)?.name ?? listed.files[0].name
    await loadContent(next, keepSelection && next === current)
  } catch (e) {
    listError.value = e instanceof Error ? e.message : '加载失败'
  } finally {
    listLoading.value = false
  }
}

function refresh() {
  if (listLoading.value) return
  void loadList(true)
}

function back() {
  void router.push({ name: 'wall' })
}

function openDetail(entry: LogEntry) {
  detail.value = entry
}

function closeDetail() {
  detail.value = null
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') closeDetail()
}

watch(level, () => {
  closeDetail()
  void scrollEnd()
})

onMounted(() => {
  window.addEventListener('keydown', onKeydown)
  void loadList(false)
})

onUnmounted(() => {
  window.removeEventListener('keydown', onKeydown)
})
</script>

<template>
  <div class="logs">
    <header class="masthead">
      <div class="brand-block">
        <button type="button" class="back" @click="back">
          <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <path d="M15 6l-6 6 6 6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
          </svg>
          返回
        </button>
        <h1>日志</h1>
      </div>
      <div class="mast-actions">
        <button type="button" class="ghost" :disabled="listLoading" @click="refresh">
          刷新
        </button>
      </div>
    </header>

    <div class="tabs" role="tablist" aria-label="日志级别">
      <button
        v-for="item in logLevels"
        :key="item.id"
        type="button"
        role="tab"
        :aria-selected="level === item.id"
        :class="{ active: level === item.id }"
        @click="level = item.id"
      >
        {{ item.label }}
      </button>
    </div>

    <div v-if="files.length" class="files" role="tablist" aria-label="日志文件">
        <button
          v-for="file in files"
          :key="file.name"
          type="button"
          :class="{ active: file.name === selected }"
          :title="file.name"
          @click="loadContent(file.name, false)"
        >
          <strong>{{ file.label }}</strong>
          <small>{{ formatBytes(file.size) }}<template v-if="file.compressed"> · gz</template></small>
        </button>
      </div>
      <div ref="viewer" class="viewer">
        <LoadingState v-if="listLoading || (contentLoading && !content)" label="正在读取日志" />
        <EmptyState
          v-else-if="listError || contentError"
          error
          title="日志读取失败"
          :body="listError || contentError || ''"
        />
        <EmptyState
          v-else-if="!available"
          title="没有服务器日志"
          :body="listMessage || '日志目录不可用'"
        />
        <EmptyState v-else-if="!files.length" title="还没有日志文件" body="服务端开始写文件后，当天和最近几天的日志会出现在这里。" />
        <p v-else-if="content && !content.text" class="empty-file">这个文件是空的</p>
        <div v-else-if="rows.length" class="records">
          <template v-for="row in rows" :key="row.key">
            <p v-if="row.day" class="day">{{ row.day }}</p>
            <button v-else-if="row.entry" type="button" class="record" @click="openDetail(row.entry)">
              <span class="record-head">
                <time v-if="row.entry.time">{{ row.entry.time }}</time>
                <span class="pill" :data-level="row.entry.level">{{ levelName(row.entry.level) }}</span>
                <span v-if="row.entry.source" class="tag">{{ row.entry.source }}</span>
              </span>
              <span v-if="row.entry.message" class="record-body">{{ row.entry.message }}</span>
            </button>
          </template>
        </div>
        <EmptyState v-else title="没有这个级别的日志" body="换一个级别，或查看全部。" />
      </div>

    <div v-if="detail" class="overlay" @click.self="closeDetail">
      <section class="dialog" role="dialog" aria-modal="true" aria-label="日志详情">
        <header class="dialog-head">
          <span class="pill" :data-level="detail.level">{{ levelName(detail.level) }}</span>
          <span v-if="detail.source" class="tag">{{ detail.source }}</span>
          <time>{{ [detail.date, detail.time].filter(Boolean).join(' ') }}</time>
          <button type="button" class="dialog-close" @click="closeDetail">关闭</button>
        </header>
        <p v-if="detail.detail" class="dialog-meta">{{ detail.detail }}</p>
        <p v-if="detail.message" class="dialog-message">{{ detail.message }}</p>
        <pre v-if="detail.extra.length">{{ detail.extra.join('\n') }}</pre>
      </section>
    </div>
  </div>
</template>

<style scoped>
.logs {
  width: min(1100px, calc(100% - 2.5rem));
  height: 100dvh;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  padding: calc(1.25rem + var(--safe-top)) 0 calc(1rem + var(--safe-bottom));
  min-height: 0;
}

.masthead {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  gap: 0.75rem 1rem;
  padding-bottom: 0.9rem;
  border-bottom: 1px solid var(--line);
}

.back {
  display: inline-flex;
  align-items: center;
  gap: 0.15rem;
  margin-bottom: 0.7rem;
  border: 1px solid var(--line-strong);
  background: rgba(18, 21, 28, 0.72);
  color: var(--ink);
  border-radius: 999px;
  padding: 0.45rem 0.85rem 0.45rem 0.55rem;
  cursor: pointer;
  font-weight: 650;
  font-size: 0.88rem;
}

.back svg {
  width: 1.05rem;
  height: 1.05rem;
}

.back:hover {
  color: var(--copper);
  border-color: rgba(212, 165, 116, 0.5);
}

.brand-block h1 {
  margin: 0;
  font-family: var(--font-display);
  font-size: clamp(1.8rem, 3vw, 2.4rem);
  letter-spacing: -0.03em;
}

.mast-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.75rem;
}

.ghost {
  border: 1px solid var(--line-strong);
  background: transparent;
  color: var(--ink-muted);
  border-radius: 999px;
  padding: 0.4rem 0.95rem;
  cursor: pointer;
  font-weight: 650;
}

.ghost:hover:not(:disabled) {
  color: var(--copper);
  border-color: rgba(212, 165, 116, 0.45);
}

.ghost:disabled {
  opacity: 0.45;
  cursor: default;
}

.tabs {
  display: flex;
  gap: 0.35rem;
  margin-top: 0.85rem;
  overflow-x: auto;
  scrollbar-width: none;
}

.tabs::-webkit-scrollbar {
  display: none;
}

.tabs button {
  flex: 0 0 auto;
  border: 0;
  background: transparent;
  color: var(--ink-muted);
  padding: 0.45rem 0.95rem;
  border-radius: 999px;
  cursor: pointer;
  font-weight: 600;
  font-size: 0.88rem;
}

.tabs button.active {
  color: var(--ink);
  background: linear-gradient(135deg, rgba(212, 165, 116, 0.22), rgba(95, 179, 168, 0.18));
}

.files {
  display: flex;
  gap: 0.45rem;
  overflow-x: auto;
  margin-top: 0.75rem;
  padding-bottom: 0.15rem;
}

.files button {
  flex: 0 0 auto;
  display: grid;
  justify-items: start;
  gap: 0.1rem;
  border: 1px solid var(--line);
  background: rgba(18, 21, 28, 0.55);
  color: var(--ink-muted);
  border-radius: 12px;
  padding: 0.45rem 0.75rem;
  cursor: pointer;
}

.files button strong {
  color: var(--ink);
  font-size: 0.92rem;
}

.files button small {
  color: var(--ink-faint);
  font-size: 0.75rem;
}

.files button.active {
  border-color: rgba(212, 165, 116, 0.45);
  background: linear-gradient(135deg, rgba(212, 165, 116, 0.18), rgba(95, 179, 168, 0.1));
}

.viewer {
  flex: 1;
  min-height: 0;
  margin-top: 0.85rem;
  overflow: auto;
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: rgba(8, 10, 14, 0.72);
}

.viewer:has(.empty-state),
.viewer:has(.loading-state) {
  display: flex;
  align-items: center;
  justify-content: center;
}

.empty-file {
  margin: 0;
  padding: 1.4rem 1rem;
  color: var(--ink-faint);
  text-align: center;
}

.records {
  padding: 0.85rem 1rem 1.3rem;
}

.day {
  margin: 0.85rem 0 0.4rem;
  color: var(--ink-faint);
  font-size: 0.75rem;
  font-weight: 650;
}

.day:first-child {
  margin-top: 0.15rem;
}

.record {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 0.25rem;
  width: 100%;
  margin: 0 0 0.9rem;
  padding: 0;
  border: 0;
  background: transparent;
  color: inherit;
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.record-head {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  max-width: 100%;
}

.record time,
.dialog-head time {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-variant-numeric: tabular-nums;
  font-size: 0.75rem;
  color: var(--ink-muted);
}

.pill {
  flex: 0 0 auto;
  border-radius: 999px;
  padding: 0.08rem 0.5rem;
  font-size: 0.72rem;
  font-weight: 700;
  line-height: 1.35;
}

.pill[data-level='debug'] {
  color: var(--ink-muted);
  background: rgba(154, 149, 140, 0.16);
}

.pill[data-level='info'] {
  color: var(--teal);
  background: rgba(95, 179, 168, 0.16);
}

.pill[data-level='warn'] {
  color: var(--copper);
  background: rgba(212, 165, 116, 0.16);
}

.pill[data-level='error'] {
  color: var(--danger);
  background: rgba(224, 122, 107, 0.16);
}

.tag {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--ink-muted);
  font-size: 0.82rem;
  font-weight: 650;
}

.record-body,
.dialog-message {
  white-space: pre-wrap;
  word-break: break-word;
  font-size: 0.84rem;
  line-height: 1.45;
  color: var(--ink);
}

.record:hover .record-body {
  color: #fff;
}

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
  max-height: min(860px, calc(100vh - 2.5rem));
  overflow: auto;
  border: 1px solid var(--line-strong);
  border-radius: var(--radius);
  background: linear-gradient(180deg, rgba(26, 31, 42, 0.98), rgba(14, 17, 24, 0.98));
  box-shadow: var(--shadow);
  padding: 1.25rem 1.35rem 1.5rem;
}

.dialog-head {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.dialog-head time {
  margin-left: auto;
}

.dialog-close {
  flex: 0 0 auto;
  border: 1px solid var(--line-strong);
  background: transparent;
  color: var(--ink-muted);
  border-radius: 999px;
  padding: 0.45rem 0.9rem;
  cursor: pointer;
  font-weight: 650;
}

.dialog-close:hover {
  color: var(--ink);
  border-color: var(--copper);
}

.dialog-meta {
  margin: 0.7rem 0 0;
  color: var(--ink-faint);
  font-size: 0.78rem;
  line-height: 1.4;
}

.dialog-message {
  margin: 0.8rem 0 0;
}

.dialog pre {
  margin: 0.8rem 0 0;
  white-space: pre-wrap;
  word-break: break-word;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.75rem;
  line-height: 1.45;
  color: var(--ink-muted);
}

@media (max-width: 720px) {
  .logs {
    width: 100%;
    padding-left: 1rem;
    padding-right: 1rem;
  }

  .overlay {
    padding: 0;
    place-items: end stretch;
  }

  .dialog {
    width: 100%;
    max-height: min(94dvh, 100%);
    border-radius: 18px 18px 0 0;
    padding-bottom: calc(1.25rem + var(--safe-bottom));
  }
}
</style>
