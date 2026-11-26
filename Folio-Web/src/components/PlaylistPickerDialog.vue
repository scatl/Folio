<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { addPlaylistItem, createPlaylist, listPlaylists, removePlaylistItem } from '../api/client'
import type { PlaylistSummary } from '../api/types'
import FolioCheck from './FolioCheck.vue'
import { notePlaylist } from '../lib/watchMarks'

const props = defineProps<{
  workId: number
}>()

const emit = defineEmits<{
  close: []
}>()

const loading = ref(true)
const saving = ref(false)
const error = ref<string | null>(null)
const name = ref('')
const lists = ref<PlaylistSummary[]>([])

onMounted(() => {
  void load()
})

async function load() {
  loading.value = true
  error.value = null
  try {
    lists.value = await listPlaylists(props.workId)
  } catch (e) {
    error.value = e instanceof Error ? e.message : '播放列表加载失败'
  } finally {
    loading.value = false
  }
}

async function toggle(item: PlaylistSummary) {
  if (saving.value) return
  saving.value = true
  error.value = null
  try {
    if (item.contains) {
      await removePlaylistItem(item.id, props.workId)
      item.contains = false
      item.itemCount = Math.max(0, item.itemCount - 1)
    } else {
      const updated = await addPlaylistItem(item.id, props.workId)
      item.contains = true
      item.itemCount = updated.itemCount
      item.posterUrl = updated.posterUrl
    }
    notePlaylist()
  } catch (e) {
    error.value = e instanceof Error ? e.message : '保存失败'
  } finally {
    saving.value = false
  }
}

async function create() {
  const title = name.value.trim()
  if (!title) {
    error.value = '请填写播放列表名称'
    return
  }
  if (saving.value) return
  saving.value = true
  error.value = null
  try {
    const created = await createPlaylist(title, props.workId)
    lists.value = [created, ...lists.value.filter((item) => item.id !== created.id)]
    name.value = ''
    notePlaylist()
  } catch (e) {
    error.value = e instanceof Error ? e.message : '创建失败'
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="picker-layer" @click.self="emit('close')">
    <div class="picker" role="dialog" aria-modal="true" aria-label="添加到播放列表">
      <header>
        <h2>添加到播放列表</h2>
        <button type="button" class="close" aria-label="关闭" @click="emit('close')">×</button>
      </header>
      <form class="create" @submit.prevent="create">
        <input v-model="name" type="text" maxlength="40" placeholder="新播放列表名称" />
        <button type="submit" :disabled="saving">创建</button>
      </form>
      <p v-if="error" class="error">{{ error }}</p>
      <p v-if="loading" class="status">加载中…</p>
      <p v-else-if="!lists.length" class="status">还没有播放列表</p>
      <ul v-else>
        <li v-for="item in lists" :key="item.id">
          <button type="button" :disabled="saving" @click="toggle(item)">
            <FolioCheck decorative :model-value="item.contains" />
            <span class="copy">
              <strong>{{ item.name }}</strong>
              <small>{{ item.itemCount }} 项</small>
            </span>
          </button>
        </li>
      </ul>
    </div>
  </div>
</template>

<style scoped>
.picker-layer {
  position: fixed;
  inset: 0;
  z-index: 40;
  display: grid;
  place-items: center;
  padding: 1.5rem;
  background: rgba(6, 8, 12, 0.55);
  backdrop-filter: blur(8px);
}

.picker {
  width: min(420px, 100%);
  max-height: min(70vh, 640px);
  display: flex;
  flex-direction: column;
  padding: 1rem 1rem 0.6rem;
  border-radius: 16px;
  background: var(--bg-panel);
  color: var(--ink);
  box-shadow: 0 18px 50px rgba(0, 0, 0, 0.35);
}

header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

h2 {
  flex: 1;
  margin: 0;
  font-size: 1.05rem;
  font-weight: 650;
}

.close {
  width: 2rem;
  height: 2rem;
  border: 0;
  border-radius: 999px;
  background: transparent;
  color: var(--ink);
  font-size: 1.4rem;
  line-height: 1;
  cursor: pointer;
}

.create {
  display: flex;
  gap: 0.5rem;
  margin: 0.9rem 0 0.4rem;
}

.create input {
  flex: 1;
  min-width: 0;
  padding: 0.55rem 0.75rem;
  border: 1px solid rgba(242, 239, 232, 0.14);
  border-radius: 10px;
  background: transparent;
  color: var(--ink);
}

.create button,
ul button {
  border: 0;
  cursor: pointer;
}

.create button {
  padding: 0 0.9rem;
  border-radius: 10px;
  background: var(--copper);
  color: #1a140e;
  font-weight: 650;
}

.create button:disabled,
ul button:disabled {
  opacity: 0.55;
  cursor: default;
}

.error,
.status {
  margin: 0.35rem 0;
  color: var(--ink-muted);
  font-size: 0.88rem;
}

.error {
  color: #e7b2a4;
}

ul {
  list-style: none;
  margin: 0.2rem -0.35rem 0.2rem;
  padding: 0;
  overflow: auto;
}

ul button {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.7rem 0.55rem;
  border-radius: 10px;
  background: transparent;
  color: inherit;
  text-align: left;
}

ul button:hover {
  background: rgba(242, 239, 232, 0.06);
}

.copy {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  min-width: 0;
}

.copy strong,
.copy small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.copy small {
  color: var(--ink-muted);
}
</style>
