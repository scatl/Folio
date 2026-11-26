<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import { browseDirectories, createLibrary } from '../api/client'
import type { BrowseResult, MediaLibrary, WorkKind } from '../api/types'

const emit = defineEmits<{
  close: []
  created: [library: MediaLibrary]
}>()

const name = ref('')
const kind = ref<WorkKind>('movie')
const rootPath = ref('')
const submitting = ref(false)
const formError = ref<string | null>(null)

const browse = ref<BrowseResult | null>(null)
const browseLoading = ref(false)
const browseError = ref<string | null>(null)
const stageShell = ref<HTMLElement | null>(null)
const stageInner = ref<HTMLElement | null>(null)
const stageHeight = ref<number | null>(null)
const stageStyle = computed(() => (stageHeight.value == null ? undefined : { height: `${stageHeight.value}px` }))

const canSubmit = computed(() => !!rootPath.value.trim() && !submitting.value)

async function animateStage(apply: () => void) {
  const shell = stageShell.value
  const inner = stageInner.value
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  if (!shell || !inner || reduce || stageHeight.value == null) {
    apply()
    await nextTick()
    if (stageInner.value) stageHeight.value = stageInner.value.offsetHeight
    return
  }
  stageHeight.value = shell.getBoundingClientRect().height
  apply()
  await nextTick()
  void shell.offsetHeight
  stageHeight.value = stageInner.value?.offsetHeight ?? stageHeight.value
}

async function loadBrowse(path?: string) {
  browseLoading.value = true
  try {
    const next = await browseDirectories(path)
    await animateStage(() => {
      browse.value = next
      browseError.value = null
    })
  } catch (e) {
    const message = e instanceof Error ? e.message : '浏览目录失败'
    await animateStage(() => {
      browseError.value = message
    })
  } finally {
    browseLoading.value = false
  }
}

function selectDir(path: string) {
  rootPath.value = path
  void loadBrowse(path)
}

function goParent() {
  if (!browse.value) return
  const parent = browse.value.parent
  void loadBrowse(parent === null ? undefined : parent || undefined)
}

async function submit() {
  if (!canSubmit.value) return
  submitting.value = true
  formError.value = null
  try {
    const library = await createLibrary({
      name: name.value.trim() || undefined,
      kind: kind.value,
      rootPath: rootPath.value.trim(),
    })
    emit('created', library)
  } catch (e) {
    formError.value = e instanceof Error ? e.message : '创建失败'
  } finally {
    submitting.value = false
  }
}

function onOverlayClick(e: MouseEvent) {
  if (e.target === e.currentTarget && !submitting.value) emit('close')
}

function onKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape' && !submitting.value) emit('close')
}

onMounted(() => {
  void loadBrowse()
  window.addEventListener('keydown', onKeydown)
})

onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKeydown)
})
</script>

<template>
  <div class="overlay" @click="onOverlayClick">
    <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="create-library-title">
      <header class="dialog-head">
        <div>
          <h2 id="create-library-title">创建资料库</h2>
          <p class="hint">选择类型与服务器目录。创建后会在后台扫描视频并入队刮削。</p>
        </div>
        <button type="button" class="close" :disabled="submitting" @click="emit('close')">关闭</button>
      </header>

      <label class="field">
        <span>名称（可选）</span>
        <input v-model="name" type="text" placeholder="例如：家庭电影" maxlength="128" />
      </label>

      <div class="field">
        <span>类型</span>
        <div class="kind-toggle" role="group" aria-label="资料库类型">
          <button type="button" :class="{ active: kind === 'movie' }" @click="kind = 'movie'">电影</button>
          <button type="button" :class="{ active: kind === 'series' }" @click="kind = 'series'">剧集</button>
        </div>
      </div>

      <label class="field">
        <span>服务器目录</span>
        <input
          v-model="rootPath"
          type="text"
          placeholder="从下方选择，或直接输入路径"
          maxlength="1024"
        />
      </label>

      <div class="browser-head">
        <span>目录浏览</span>
        <button
          type="button"
          class="ghost"
          :disabled="browseLoading || browse?.parent === null || submitting"
          @click="goParent"
        >
          上级
        </button>
      </div>
      <div class="browser" aria-label="选择服务器目录">
        <div ref="stageShell" class="browser-stage" :style="stageStyle">
          <div ref="stageInner">
            <p class="path-line">{{ browse?.path || '（根目录）' }}</p>
            <p v-if="browseError" class="err">{{ browseError }}</p>
            <p v-else-if="browseLoading && !browse" class="muted">加载中…</p>
            <ul v-else-if="browse?.directories.length" class="dir-list">
              <li v-for="entry in browse.directories" :key="entry.path">
                <button type="button" :disabled="submitting || browseLoading" @click="selectDir(entry.path)">
                  <span class="dir-name">{{ entry.name }}</span>
                  <span class="dir-path">{{ entry.path }}</span>
                </button>
              </li>
            </ul>
            <p v-else-if="browse" class="muted">此目录下没有子目录，可直接用作资料库路径。</p>
          </div>
        </div>
      </div>

      <p v-if="formError" class="err">{{ formError }}</p>

      <button type="button" class="submit" :disabled="!canSubmit" @click="submit">
        {{ submitting ? '创建中…' : '创建并开始刮削' }}
      </button>
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
  width: min(560px, 100%);
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
  justify-content: space-between;
  gap: 1rem;
  align-items: start;
  margin-bottom: 1.1rem;
}

.dialog-head h2 {
  margin: 0;
  font-family: var(--font-display);
  font-size: 1.45rem;
}

.hint {
  margin: 0.4rem 0 0;
  color: var(--ink-muted);
  font-size: 0.9rem;
  line-height: 1.45;
}

.close {
  border: 1px solid var(--line);
  background: transparent;
  color: var(--ink-muted);
  border-radius: 999px;
  padding: 0.35rem 0.8rem;
  cursor: pointer;
  flex-shrink: 0;
}

.close:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.field {
  display: grid;
  gap: 0.45rem;
  margin-bottom: 0.95rem;
}

.field > span {
  color: var(--ink-muted);
  font-size: 0.86rem;
}

.field input {
  height: 2.65rem;
  padding: 0 0.95rem;
  border-radius: 10px;
  border: 1px solid var(--line-strong);
  background: rgba(10, 12, 16, 0.55);
  outline: none;
}

.field input:focus {
  border-color: rgba(212, 165, 116, 0.55);
  box-shadow: 0 0 0 3px var(--copper-soft);
}

.kind-toggle {
  display: inline-flex;
  gap: 0.3rem;
  padding: 0.25rem;
  border-radius: 999px;
  border: 1px solid var(--line);
  background: rgba(10, 12, 16, 0.4);
  width: fit-content;
}

.kind-toggle button {
  border: 0;
  background: transparent;
  color: var(--ink-muted);
  padding: 0.45rem 1rem;
  border-radius: 999px;
  cursor: pointer;
  font-weight: 600;
}

.kind-toggle button.active {
  background: linear-gradient(135deg, rgba(212, 165, 116, 0.22), rgba(95, 179, 168, 0.18));
  color: var(--ink);
}

.browser {
  margin: 0 0 1.1rem;
  padding: 0.95rem 1rem;
  border: 1px dashed var(--line-strong);
  border-radius: 12px;
  background: rgba(10, 12, 16, 0.35);
}

.browser-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 0.75rem;
  margin-bottom: 0.45rem;
}

.browser-head span {
  color: var(--ink-muted);
  font-size: 0.86rem;
}

.ghost {
  border: 1px solid var(--line);
  background: transparent;
  color: var(--ink-muted);
  border-radius: 999px;
  padding: 0.3rem 0.75rem;
  cursor: pointer;
  font-size: 0.82rem;
}

.ghost:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.browser-stage {
  overflow: hidden;
  transition: height 0.34s cubic-bezier(0.22, 1, 0.36, 1);
}

.path-line {
  margin: 0 0 0.75rem;
  color: var(--teal);
  font-size: 0.84rem;
  word-break: break-all;
}

.dir-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  gap: 0.45rem;
  max-height: 220px;
  overflow: auto;
}

.dir-list button {
  width: 100%;
  text-align: left;
  border: 1px solid var(--line);
  background: rgba(18, 21, 28, 0.7);
  border-radius: 10px;
  padding: 0.65rem 0.8rem;
  cursor: pointer;
  display: grid;
  gap: 0.15rem;
}

.dir-list button:hover:not(:disabled) {
  border-color: rgba(212, 165, 116, 0.45);
}

.dir-list button:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.dir-name {
  font-weight: 650;
}

.dir-path {
  color: var(--ink-faint);
  font-size: 0.78rem;
  word-break: break-all;
}

.submit {
  width: 100%;
  height: 2.8rem;
  border: 1px solid rgba(212, 165, 116, 0.4);
  border-radius: 999px;
  background: linear-gradient(135deg, rgba(212, 165, 116, 0.2), rgba(95, 179, 168, 0.14));
  color: var(--ink);
  font-weight: 650;
  cursor: pointer;
}

.submit:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.muted {
  color: var(--ink-faint);
  margin: 0;
}

.err {
  color: var(--danger);
  margin: 0 0 0.75rem;
  font-size: 0.9rem;
}

@media (prefers-reduced-motion: reduce) {
  .browser-stage {
    transition: none;
  }
}

@media (max-width: 720px) {
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
