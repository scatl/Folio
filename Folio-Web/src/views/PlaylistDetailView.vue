<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { deletePlaylist, getPlaylist, removePlaylistItem, renamePlaylist, reorderPlaylistItems } from '../api/client'
import type { PlaylistDetail } from '../api/types'
import PosterMedia from '../components/PosterMedia.vue'
import { confirmDialog } from '../lib/confirm'
import { notePlaylist } from '../lib/watchMarks'

const route = useRoute()
const router = useRouter()

const loading = ref(true)
const saving = ref(false)
const error = ref<string | null>(null)
const detail = ref<PlaylistDetail | null>(null)
const renaming = ref(false)
const nameDraft = ref('')
const nameInput = ref<HTMLInputElement | null>(null)
const draggingId = ref<number | null>(null)
let dragDirty = false

const playlistId = computed(() => {
  const raw = route.params.id
  const value = Number(Array.isArray(raw) ? raw[0] : raw)
  return Number.isInteger(value) && value > 0 ? value : 0
})

watch(playlistId, () => {
  void load()
}, { immediate: true })

async function load() {
  if (!playlistId.value) {
    error.value = '播放列表不存在'
    loading.value = false
    return
  }
  loading.value = true
  error.value = null
  try {
    detail.value = await getPlaylist(playlistId.value)
    nameDraft.value = detail.value.name
  } catch (e) {
    detail.value = null
    error.value = e instanceof Error ? e.message : '播放列表加载失败'
  } finally {
    loading.value = false
  }
}

function play(item: PlaylistDetail['items'][number]) {
  if (!item.playFileId || !detail.value) return
  void router.push({
    name: 'play',
    params: { fileId: String(item.playFileId) },
    query: { playlist: String(detail.value.id) },
  })
}

async function remove(workId: number) {
  if (!detail.value || saving.value) return
  saving.value = true
  error.value = null
  try {
    detail.value = await removePlaylistItem(detail.value.id, workId)
    notePlaylist()
  } catch (e) {
    error.value = e instanceof Error ? e.message : '移除失败'
  } finally {
    saving.value = false
  }
}

async function startRename() {
  nameDraft.value = detail.value?.name ?? ''
  renaming.value = true
  await nextTick()
  nameInput.value?.focus()
  nameInput.value?.select()
}

function cancelRename() {
  renaming.value = false
  nameDraft.value = detail.value?.name ?? ''
}

async function saveName() {
  if (!detail.value || saving.value) return
  const name = nameDraft.value.trim()
  if (!name) {
    error.value = '请填写播放列表名称'
    return
  }
  saving.value = true
  error.value = null
  try {
    detail.value = await renamePlaylist(detail.value.id, name)
    nameDraft.value = detail.value.name
    renaming.value = false
    notePlaylist()
  } catch (e) {
    error.value = e instanceof Error ? e.message : '重命名失败'
  } finally {
    saving.value = false
  }
}

function onDragStart(workId: number, event: DragEvent) {
  draggingId.value = workId
  dragDirty = false
  event.dataTransfer?.setData('text/plain', String(workId))
  if (event.dataTransfer) event.dataTransfer.effectAllowed = 'move'
}

function onDragOver(workId: number, event: DragEvent) {
  event.preventDefault()
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'move'
  const fromId = draggingId.value
  const current = detail.value
  if (fromId == null || fromId === workId || !current) return
  const from = current.items.findIndex((item) => item.workId === fromId)
  if (from < 0) return
  const row = event.currentTarget
  if (!(row instanceof HTMLElement)) return
  const rect = row.getBoundingClientRect()
  const before = event.clientY < rect.top + rect.height / 2
  const rest = current.items.filter((item) => item.workId !== fromId)
  const overInRest = rest.findIndex((item) => item.workId === workId)
  if (overInRest < 0) return
  const insertAt = before ? overInRest : overInRest + 1
  if (insertAt === from) return
  const moved = current.items[from]
  if (!moved) return
  const items = rest.slice()
  items.splice(insertAt, 0, moved)
  if (items.length === current.items.length && items.every((item, index) => item.workId === current.items[index]?.workId)) {
    return
  }
  detail.value = { ...current, items }
  dragDirty = true
}

async function onDragEnd() {
  const dirty = dragDirty
  const current = detail.value
  draggingId.value = null
  dragDirty = false
  if (!dirty || !current) return
  saving.value = true
  error.value = null
  try {
    detail.value = await reorderPlaylistItems(
      current.id,
      current.items.map((item) => item.workId),
    )
  } catch (e) {
    error.value = e instanceof Error ? e.message : '排序失败'
    await load()
  } finally {
    saving.value = false
  }
}

async function removeList() {
  if (!detail.value || saving.value) return
  const ok = await confirmDialog({
    title: '删除播放列表',
    message: `删除「${detail.value.name}」？里面的作品不会从资料库移除。`,
    confirmLabel: '删除',
    danger: true,
  })
  if (!ok) return
  saving.value = true
  error.value = null
  try {
    await deletePlaylist(detail.value.id)
    notePlaylist()
    router.push({ name: 'wall' })
  } catch (e) {
    error.value = e instanceof Error ? e.message : '删除失败'
    saving.value = false
  }
}
</script>

<template>
  <main class="playlist-page">
    <div class="column">
      <button type="button" class="back" @click="router.back()">← 返回</button>

      <header class="head">
        <div class="title-block">
          <h1 v-if="!renaming">{{ detail?.name || '播放列表' }}</h1>
          <form v-else class="rename" @submit.prevent="saveName">
            <input ref="nameInput" v-model="nameDraft" type="text" maxlength="40" aria-label="播放列表名称" />
            <button type="submit" class="save" :disabled="saving">保存</button>
            <button type="button" class="cancel" :disabled="saving" @click="cancelRename">取消</button>
          </form>
          <p v-if="detail && !renaming" class="count">{{ detail.items.length }} 项</p>
        </div>
        <div v-if="detail && !renaming" class="actions">
          <button type="button" class="icon" title="重命名" aria-label="重命名" @click="startRename">
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path
                fill="none"
                stroke="currentColor"
                stroke-width="1.8"
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M4 20h4l10.2-10.2a1.6 1.6 0 0 0 0-2.3L16.5 5.8a1.6 1.6 0 0 0-2.3 0L4 16v4z"
              />
            </svg>
          </button>
          <button type="button" class="icon danger" title="删除" aria-label="删除" :disabled="saving" @click="removeList">
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path
                fill="none"
                stroke="currentColor"
                stroke-width="1.8"
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M5 7h14M10 7V5h4v2M8 7l.8 12h6.4L16 7"
              />
            </svg>
          </button>
        </div>
      </header>

      <p v-if="error" class="error">{{ error }}</p>
      <p v-if="loading" class="status">加载中…</p>
      <p v-else-if="detail && !detail.items.length" class="empty">这个播放列表还是空的。在作品页的更多里可以加进来。</p>
      <TransitionGroup v-else-if="detail" name="playlist-sort" tag="ul">
        <li
          v-for="item in detail.items"
          :key="item.workId"
          :class="{ dragging: draggingId === item.workId }"
          @dragover="onDragOver(item.workId, $event)"
          @drop.prevent="onDragEnd"
        >
          <button
            type="button"
            class="drag-handle"
            draggable="true"
            title="拖动排序"
            aria-label="拖动排序"
            @dragstart="onDragStart(item.workId, $event)"
            @dragend="onDragEnd"
            @click.stop
          >
            <span aria-hidden="true" />
          </button>
          <button type="button" class="row" :disabled="!item.playFileId" @click="play(item)">
            <span class="poster">
              <PosterMedia :src="item.posterUrl" :alt="item.workTitle" />
            </span>
            <span class="copy">
              <strong>{{ item.workTitle }}</strong>
              <small>{{ item.playFileId ? item.subtitle : `${item.subtitle} · 没有可播放的文件` }}</small>
            </span>
          </button>
          <button type="button" class="icon remove" title="移除" aria-label="移除" :disabled="saving" @click="remove(item.workId)">
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" d="M7 7l10 10M17 7 7 17" />
            </svg>
          </button>
        </li>
      </TransitionGroup>
    </div>
  </main>
</template>

<style scoped>
.playlist-page {
  min-height: 100vh;
  color: var(--ink);
}

.column {
  width: min(720px, calc(100% - 2.5rem));
  margin: 0 auto;
  padding: calc(1.5rem + var(--safe-top)) 0 calc(3rem + var(--safe-bottom));
}

.back {
  margin-bottom: 1.75rem;
  border: 1px solid var(--line-strong);
  background: rgba(10, 12, 16, 0.45);
  color: var(--ink);
  border-radius: 999px;
  padding: 0.55rem 1rem;
  cursor: pointer;
  font-weight: 600;
  font-size: 0.9rem;
}

.back:hover {
  border-color: rgba(212, 165, 116, 0.5);
}

.head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 1rem;
}

.title-block {
  min-width: 0;
  flex: 1;
}

h1 {
  margin: 0;
  font-family: var(--font-display);
  font-size: clamp(1.8rem, 4vw, 2.6rem);
  font-weight: 500;
  letter-spacing: -0.03em;
  line-height: 1.1;
}

.count {
  margin: 0.45rem 0 0;
  color: var(--ink-muted);
  font-size: 0.92rem;
}

.actions {
  display: flex;
  gap: 0.45rem;
  padding-top: 0.35rem;
}

.icon {
  box-sizing: border-box;
  width: 2.45rem;
  height: 2.45rem;
  flex: 0 0 2.45rem;
  padding: 0;
  border-radius: 50%;
  border: 1px solid var(--line-strong);
  background: rgba(10, 12, 16, 0.45);
  color: var(--ink);
  display: inline-grid;
  place-items: center;
  cursor: pointer;
}

.icon svg {
  width: 1.15rem;
  height: 1.15rem;
  display: block;
}

.icon:hover:not(:disabled) {
  border-color: rgba(212, 165, 116, 0.8);
}

.icon.danger:hover:not(:disabled),
.icon.remove:hover:not(:disabled) {
  border-color: rgba(224, 122, 107, 0.8);
  color: #e7b2a4;
}

.icon:disabled {
  opacity: 0.55;
  cursor: default;
}

.rename {
  display: flex;
  align-items: center;
  gap: 0.45rem;
}

.rename input {
  flex: 1;
  min-width: 0;
  padding: 0.55rem 0.8rem;
  border: 1px solid var(--line-strong);
  border-radius: 12px;
  background: rgba(10, 12, 16, 0.45);
  color: var(--ink);
  font-family: var(--font-display);
  font-size: 1.35rem;
}

.save,
.cancel {
  border: 0;
  cursor: pointer;
  font-weight: 650;
}

.save {
  padding: 0.55rem 0.9rem;
  border-radius: 999px;
  background: var(--copper);
  color: #1a140e;
}

.cancel {
  padding: 0.55rem 0.4rem;
  background: transparent;
  color: var(--ink-muted);
}

.save:disabled,
.cancel:disabled {
  opacity: 0.55;
  cursor: default;
}

.error,
.status,
.empty {
  margin: 1.25rem 0 0;
  color: var(--ink-muted);
}

.error {
  color: #e7b2a4;
}

ul {
  list-style: none;
  margin: 1.5rem 0 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.65rem;
}

li {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.55rem;
  border: 1px solid var(--line);
  border-radius: 16px;
  background: rgba(18, 21, 28, 0.72);
}

li.dragging {
  opacity: 0.45;
}

.playlist-sort-move {
  transition: transform 0.22s ease;
  pointer-events: none;
}

.drag-handle {
  width: 1.6rem;
  height: 2.4rem;
  flex: none;
  display: grid;
  place-items: center;
  border: 0;
  padding: 0;
  background: transparent;
  color: var(--ink-faint);
  cursor: grab;
}

.drag-handle span {
  width: 0.55rem;
  height: 0.9rem;
  background: radial-gradient(circle, currentColor 1.1px, transparent 1.3px) 0 0 / 0.28rem 0.28rem;
}

.drag-handle:active {
  cursor: grabbing;
}

.row {
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 0.9rem;
  padding: 0.15rem 0.25rem;
  border: 0;
  border-radius: 12px;
  background: transparent;
  color: inherit;
  text-align: left;
  cursor: pointer;
}

.row:hover:not(:disabled) .copy strong {
  color: var(--copper);
}

.row:disabled {
  cursor: default;
  opacity: 0.6;
}

.poster {
  width: 3.6rem;
  aspect-ratio: 2 / 3;
  flex: none;
  overflow: hidden;
  border-radius: 8px;
  background: var(--bg-soft);
}

.poster :deep(.poster-media) {
  width: 100%;
  height: 100%;
}

.copy {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  min-width: 0;
}

.copy strong,
.copy small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.copy strong {
  font-size: 1.02rem;
  font-weight: 650;
}

.copy small {
  color: var(--ink-muted);
  font-size: 0.86rem;
}

@media (max-width: 720px) {
  .column {
    width: min(100% - 1.1rem, 720px);
  }

  .rename {
    flex-wrap: wrap;
  }

  .rename input {
    flex-basis: 100%;
  }
}
</style>
