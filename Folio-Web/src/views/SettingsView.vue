<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { createUser, deleteUser, getSettings, listLibraries, listUsers, updateSettings, updateUser } from '../api/client'
import type { AppSettings, AuthUser, MediaLibrary } from '../api/types'
import { changeAccount, currentUser, loadSession, signOut } from '../auth/session'
import FolioCheck from '../components/FolioCheck.vue'
import { confirmDialog } from '../lib/confirm'

const MASK = '********'
const DEFAULT_TMDB_IMAGE_BASE_URL = 'https://image.tmdb.org/t/p/original'

const router = useRouter()
const route = useRoute()
const fromLibrary = computed(() => route.query.from === 'library')

const loading = ref(true)
const saving = ref(false)
const error = ref<string | null>(null)
const toast = ref<string | null>(null)
let toastTimer: number | null = null

function showToast(message: string) {
  toast.value = message
  if (toastTimer != null) window.clearTimeout(toastTimer)
  toastTimer = window.setTimeout(() => {
    toast.value = null
    toastTimer = null
  }, 2800)
}
const snapshot = ref<AppSettings | null>(null)
const isAdmin = computed(() => currentUser.value?.role === 'ADMIN')
const section = ref<'account' | 'source' | 'playback' | 'match' | 'worker' | 'advanced'>(
  isAdmin.value ? 'source' : 'account',
)

const users = ref<AuthUser[]>([])
const usersLoading = ref(false)
const userTab = ref<'ADMIN' | 'USER'>('ADMIN')
const adminUsers = computed(() => users.value.filter((user) => user.role === 'ADMIN'))
const memberUsers = computed(() => users.value.filter((user) => user.role !== 'ADMIN'))
const visibleUsers = computed(() => {
  if (!isAdmin.value) return users.value
  return userTab.value === 'ADMIN' ? adminUsers.value : memberUsers.value
})
const allLibraries = ref<MediaLibrary[]>([])
const editorOpen = ref(false)
const editorMode = ref<'create' | 'edit' | 'libraries'>('edit')
const editorUser = ref<AuthUser | null>(null)
const editorUsername = ref('')
const editorPassword = ref('')
const editorCurrentPassword = ref('')
const editorRole = ref<'ADMIN' | 'USER'>('USER')
const editorError = ref<string | null>(null)
/** libraryId -> '' | 'READ' | 'WRITE' */
const editorLibraryAccess = ref<Record<number, '' | 'READ' | 'WRITE'>>({})

const tmdbApiKey = ref('')
const tmdbInput = ref<HTMLInputElement | null>(null)
const omdbApiKey = ref('')
const tvdbApiKey = ref('')
const tvdbPin = ref('')

const form = reactive({
  tmdbBaseUrl: '',
  tmdbImageBaseUrl: '',
  tmdbLanguage: '',
  tmdbSearchLanguage: '',
  tmdbRequestsPerSecond: 30,
  omdbBaseUrl: '',
  omdbRequestsPerSecond: 30,
  tvdbBaseUrl: '',
  tvdbRequestsPerSecond: 30,
  httpTimeoutSeconds: 10,
  matchAutoThreshold: 0.72,
  workerDelayMs: 2000,
  workerMaxAttempts: 3,
  workerConcurrency: 8,
  scanIntervalMinutes: 10,
  watchEnabled: true,
  playbackIgnoreBelowSeconds: 10,
  playbackCompleteRemainingSeconds: 30,
})

const allNav = [
  { id: 'account' as const, label: '账号' },
  { id: 'source' as const, label: '元数据源' },
  { id: 'playback' as const, label: '播放' },
  { id: 'match' as const, label: '匹配与扫描' },
  { id: 'worker' as const, label: '刮削任务' },
  { id: 'advanced' as const, label: '高级' },
]
const nav = computed(() => (isAdmin.value ? allNav : allNav.filter((item) => item.id === 'account')))
const activeAdminCount = computed(
  () => users.value.filter((user) => user.role === 'ADMIN' && !user.disabled).length,
)

const statusText = computed(() => {
  if (loading.value) return '正在加载设置'
  if (error.value) return error.value
  return '保存后立刻生效'
})

function apply(data: AppSettings) {
  snapshot.value = data
  form.tmdbBaseUrl = data.tmdbBaseUrl
  form.tmdbImageBaseUrl = data.tmdbImageBaseUrl
  form.tmdbLanguage = data.tmdbLanguage
  form.tmdbSearchLanguage = data.tmdbSearchLanguage
  form.tmdbRequestsPerSecond = data.tmdbRequestsPerSecond
  form.omdbBaseUrl = data.omdbBaseUrl
  form.omdbRequestsPerSecond = data.omdbRequestsPerSecond
  form.tvdbBaseUrl = data.tvdbBaseUrl
  form.tvdbRequestsPerSecond = data.tvdbRequestsPerSecond
  form.httpTimeoutSeconds = data.httpTimeoutSeconds
  form.matchAutoThreshold = data.matchAutoThreshold
  form.workerDelayMs = data.workerDelayMs
  form.workerMaxAttempts = data.workerMaxAttempts
  form.workerConcurrency = data.workerConcurrency
  form.scanIntervalMinutes = data.scanIntervalMinutes
  form.watchEnabled = data.watchEnabled
  form.playbackIgnoreBelowSeconds = data.playbackIgnoreBelowSeconds ?? 10
  form.playbackCompleteRemainingSeconds = data.playbackCompleteRemainingSeconds ?? 30
  tmdbApiKey.value = data.tmdbApiKeyConfigured ? MASK : ''
  omdbApiKey.value = data.omdbApiKeyConfigured ? MASK : ''
  tvdbApiKey.value = data.tvdbApiKeyConfigured ? MASK : ''
  tvdbPin.value = data.tvdbPinConfigured ? MASK : ''
}

function secretPayload(typed: string, configured: boolean): string | null {
  const value = typed.trim()
  if (value === MASK) return null
  if (!value) return configured ? '' : null
  return value
}

function selectMask(event: Event) {
  const input = event.target as HTMLInputElement
  if (input.value === MASK) input.select()
}

function resetTmdbImageBaseUrl() {
  form.tmdbImageBaseUrl = DEFAULT_TMDB_IMAGE_BASE_URL
}

async function load() {
  loading.value = true
  error.value = null
  try {
    apply(await getSettings())
    if (snapshot.value && !snapshot.value.tmdbApiKeyConfigured) {
      section.value = 'source'
      await nextTick()
      tmdbInput.value?.focus()
    }
  } catch (e) {
    error.value = e instanceof Error ? e.message : '加载失败'
  } finally {
    loading.value = false
  }
}

function isLastAdmin(user: AuthUser) {
  return user.role === 'ADMIN' && !user.disabled && activeAdminCount.value <= 1
}

function userInitial(username: string) {
  const trimmed = username.trim()
  return trimmed ? trimmed.slice(0, 1).toUpperCase() : '?'
}

function userMeta(user: AuthUser): { label: string; tone: string }[] {
  const flags: { label: string; tone: string }[] = []
  if (user.role !== 'ADMIN') {
    flags.push({
      label: user.libraries?.length ? `${user.libraries.length} 个库` : '无资料库',
      tone: 'soft',
    })
  }
  if (user.disabled) flags.push({ label: '已禁用', tone: 'danger' })
  if (user.id === currentUser.value?.id) flags.push({ label: '当前', tone: 'accent' })
  return flags
}

function canDisable(user: AuthUser) {
  return isAdmin.value && user.id !== currentUser.value?.id && !isLastAdmin(user)
}

function canDelete(user: AuthUser) {
  return isAdmin.value && user.id !== currentUser.value?.id && !isLastAdmin(user)
}

async function loadUsers() {
  usersLoading.value = true
  try {
    if (isAdmin.value) {
      users.value = await listUsers()
    } else if (currentUser.value) {
      users.value = [currentUser.value]
    }
  } catch (e) {
    error.value = e instanceof Error ? e.message : '用户加载失败'
  } finally {
    usersLoading.value = false
  }
}

function blankLibraryAccess(): Record<number, '' | 'READ' | 'WRITE'> {
  const next: Record<number, '' | 'READ' | 'WRITE'> = {}
  for (const library of allLibraries.value) next[library.id] = ''
  return next
}

function fillLibraryAccess(user: AuthUser | null) {
  const next = blankLibraryAccess()
  for (const item of user?.libraries ?? []) {
    if (item.access === 'READ' || item.access === 'WRITE') next[item.libraryId] = item.access
  }
  editorLibraryAccess.value = next
}

function selectedLibraries() {
  return Object.entries(editorLibraryAccess.value)
    .filter(([, access]) => access === 'READ' || access === 'WRITE')
    .map(([libraryId, access]) => ({ libraryId: Number(libraryId), access: access as 'READ' | 'WRITE' }))
}

async function ensureLibrariesLoaded() {
  if (allLibraries.value.length > 0 || !isAdmin.value) return
  try {
    allLibraries.value = await listLibraries()
  } catch {
    allLibraries.value = []
  }
}

function openCreate() {
  void ensureLibrariesLoaded().then(() => {
    editorMode.value = 'create'
    editorUser.value = null
    editorUsername.value = ''
    editorPassword.value = ''
    editorCurrentPassword.value = ''
    editorRole.value = 'USER'
    fillLibraryAccess(null)
    editorError.value = null
    editorOpen.value = true
  })
}

function openEdit(user: AuthUser) {
  editorMode.value = 'edit'
  editorUser.value = user
  editorUsername.value = user.username
  editorPassword.value = ''
  editorCurrentPassword.value = ''
  editorError.value = null
  editorOpen.value = true
}

function openLibraries(user: AuthUser) {
  void ensureLibrariesLoaded().then(() => {
    editorMode.value = 'libraries'
    editorUser.value = user
    fillLibraryAccess(user)
    editorError.value = null
    editorOpen.value = true
  })
}

async function submitEditor() {
  if (editorMode.value === 'libraries') {
    const editing = editorUser.value
    if (!editing) return
    saving.value = true
    editorError.value = null
    try {
      await updateUser(editing.id, { libraries: selectedLibraries() })
      editorOpen.value = false
      showToast('已保存资料库权限')
      await loadUsers()
    } catch (e) {
      editorError.value = e instanceof Error ? e.message : '保存失败'
    } finally {
      saving.value = false
    }
    return
  }
  const username = editorUsername.value.trim()
  const password = editorPassword.value
  if (username.length < 2) {
    editorError.value = '用户名至少 2 个字符'
    return
  }
  if (editorMode.value === 'create' && password.length < 4) {
    editorError.value = '密码至少 4 个字符'
    return
  }
  if (password && password.length < 4) {
    editorError.value = '密码至少 4 个字符'
    return
  }
  const editing = editorUser.value
  const self = editing != null && editing.id === currentUser.value?.id
  if (editorMode.value === 'edit' && !isAdmin.value && !editorCurrentPassword.value) {
    editorError.value = '请输入当前密码'
    return
  }
  if (editorMode.value === 'edit' && editing && username === editing.username && !password) {
    editorError.value = '没有要修改的内容'
    return
  }
  saving.value = true
  editorError.value = null
  error.value = null
  try {
    if (editorMode.value === 'create') {
      await createUser({
        username,
        password,
        role: editorRole.value,
        libraries: editorRole.value === 'USER' ? selectedLibraries() : [],
      })
      editorOpen.value = false
      showToast('已创建用户')
      await loadUsers()
      return
    }
    if (!editing) return
    if (!isAdmin.value) {
      await changeAccount({
        currentPassword: editorCurrentPassword.value,
        username: username === editing.username ? undefined : username,
        newPassword: password || undefined,
      })
      editorOpen.value = false
      await signOut()
      await router.replace({ name: 'login' })
      return
    }
    const next = await updateUser(editing.id, {
      username: username === editing.username ? undefined : username,
      newPassword: password || undefined,
    })
    editorOpen.value = false
    if (self && (username !== editing.username || password)) {
      await signOut()
      await router.replace({ name: 'login' })
      return
    }
    if (self) currentUser.value = next
    showToast('已保存')
    await loadUsers()
  } catch (e) {
    editorError.value = e instanceof Error ? e.message : '保存失败'
  } finally {
    saving.value = false
  }
}

async function toggleDisabled(user: AuthUser) {
  const next = !user.disabled
  const ok = await confirmDialog({
    title: next ? '禁用用户' : '启用用户',
    message: `${next ? '禁用' : '启用'}「${user.username}」？`,
    confirmLabel: next ? '禁用' : '启用',
    danger: next,
  })
  if (!ok) return
  error.value = null
  try {
    await updateUser(user.id, { disabled: next })
    showToast(next ? '已禁用' : '已启用')
    await loadUsers()
  } catch (e) {
    showToast(e instanceof Error ? e.message : '操作失败')
  }
}

async function removeUser(user: AuthUser) {
  const ok = await confirmDialog({
    title: '删除用户',
    message: `删除用户「${user.username}」？该用户的播放进度会一起删除。`,
    confirmLabel: '删除',
    danger: true,
  })
  if (!ok) return
  error.value = null
  try {
    await deleteUser(user.id)
    showToast('已删除')
    await loadUsers()
  } catch (e) {
    showToast(e instanceof Error ? e.message : '删除失败')
  }
}

async function save() {
  if (section.value === 'account') return
  saving.value = true
  error.value = null
  try {
    const updated = await updateSettings({
      tmdbApiKey: secretPayload(tmdbApiKey.value, !!snapshot.value?.tmdbApiKeyConfigured),
      tmdbBaseUrl: form.tmdbBaseUrl,
      tmdbImageBaseUrl: form.tmdbImageBaseUrl,
      tmdbLanguage: form.tmdbLanguage,
      tmdbSearchLanguage: form.tmdbSearchLanguage,
      tmdbRequestsPerSecond: Number(form.tmdbRequestsPerSecond),
      omdbApiKey: secretPayload(omdbApiKey.value, !!snapshot.value?.omdbApiKeyConfigured),
      omdbBaseUrl: form.omdbBaseUrl,
      omdbRequestsPerSecond: Number(form.omdbRequestsPerSecond),
      tvdbEnabled: tvdbApiKey.value.trim().length > 0,
      tvdbApiKey: secretPayload(tvdbApiKey.value, !!snapshot.value?.tvdbApiKeyConfigured),
      tvdbPin: secretPayload(tvdbPin.value, !!snapshot.value?.tvdbPinConfigured),
      tvdbBaseUrl: form.tvdbBaseUrl,
      tvdbRequestsPerSecond: Number(form.tvdbRequestsPerSecond),
      httpTimeoutSeconds: Number(form.httpTimeoutSeconds),
      matchAutoThreshold: Number(form.matchAutoThreshold),
      workerDelayMs: Number(form.workerDelayMs),
      workerMaxAttempts: Number(form.workerMaxAttempts),
      workerConcurrency: Number(form.workerConcurrency),
      scanIntervalMinutes: Number(form.scanIntervalMinutes),
      watchEnabled: form.watchEnabled,
      playbackIgnoreBelowSeconds: Number(form.playbackIgnoreBelowSeconds),
      playbackCompleteRemainingSeconds: Number(form.playbackCompleteRemainingSeconds),
    })
    apply(updated)
    showToast('已保存')
  } catch (e) {
    showToast(e instanceof Error ? e.message : '保存失败')
  } finally {
    saving.value = false
  }
}

function back() {
  void router.push({ name: 'wall' })
}

onUnmounted(() => {
  if (toastTimer != null) window.clearTimeout(toastTimer)
})

onMounted(async () => {
  await loadSession()
  if (!isAdmin.value) {
    section.value = 'account'
    loading.value = false
  } else if (fromLibrary.value) {
    section.value = 'source'
    void load()
  } else {
    void load()
  }
  void loadUsers()
})
</script>

<template>
  <div class="settings">
    <header class="masthead">
      <div class="brand-block">
        <button type="button" class="back" @click="back">
          <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <path d="M15 6l-6 6 6 6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
          </svg>
          返回
        </button>
        <h1>设置</h1>
        <p v-if="fromLibrary && snapshot && !snapshot.tmdbApiKeyConfigured" class="lede">
          创建资料库前需要先配置 TMDB API Key。填好并保存后，再回到首页创建。
        </p>
        <p v-else-if="snapshot && !snapshot.tmdbApiKeyConfigured" class="lede">
          还没有 TMDB API Key。填好并保存后才能刮削。
        </p>
        <p v-else class="lede">左侧选择分类，右侧修改对应选项。已配置的密钥显示为星号。</p>
      </div>
      <div class="mast-actions">
        <p :class="['status', { err: !!error }]">{{ statusText }}</p>
      </div>
    </header>

    <form class="shell" @submit.prevent="save">
      <nav class="nav" aria-label="设置分类">
        <button
          v-for="item in nav"
          :key="item.id"
          type="button"
          :class="{ active: section === item.id }"
          @click="section = item.id"
        >
          {{ item.label }}
        </button>
      </nav>

      <div class="pane">
        <section v-show="section === 'account'">
          <div class="section-head">
            <h2>用户</h2>
            <button v-if="isAdmin" type="button" class="primary" @click="openCreate">新建用户</button>
          </div>
          <div v-if="isAdmin" class="tabs" role="tablist" aria-label="用户角色">
            <button
              type="button"
              role="tab"
              :aria-selected="userTab === 'ADMIN'"
              :class="{ active: userTab === 'ADMIN' }"
              @click="userTab = 'ADMIN'"
            >
              管理员
            </button>
            <button
              type="button"
              role="tab"
              :aria-selected="userTab === 'USER'"
              :class="{ active: userTab === 'USER' }"
              @click="userTab = 'USER'"
            >
              普通用户
            </button>
          </div>
          <p v-if="usersLoading" class="lede">正在加载用户…</p>
          <p v-else-if="!visibleUsers.length" class="lede">
            {{ userTab === 'ADMIN' ? '还没有管理员。' : '还没有普通用户。' }}
          </p>
          <ul v-else class="user-list">
            <li
              v-for="user in visibleUsers"
              :key="user.id"
              :class="{ muted: user.disabled, self: user.id === currentUser?.id }"
            >
              <div class="user-identity">
                <span class="user-avatar" aria-hidden="true">{{ userInitial(user.username) }}</span>
                <div class="user-copy">
                  <strong>{{ user.username }}</strong>
                  <div v-if="userMeta(user).length" class="user-meta">
                    <span
                      v-for="flag in userMeta(user)"
                      :key="flag.label"
                      :class="['user-flag', flag.tone]"
                    >
                      {{ flag.label }}
                    </span>
                  </div>
                </div>
              </div>
              <div class="user-actions">
                <button v-if="user.id === currentUser?.id" type="button" class="ghost" @click="openEdit(user)">修改密码</button>
                <button
                  v-if="isAdmin && user.role !== 'ADMIN'"
                  type="button"
                  class="ghost"
                  @click="openLibraries(user)"
                >
                  资料库权限
                </button>
                <button v-if="canDisable(user)" type="button" class="ghost" @click="toggleDisabled(user)">
                  {{ user.disabled ? '启用' : '禁用' }}
                </button>
                <button v-if="canDelete(user)" type="button" class="ghost danger" @click="removeUser(user)">删除</button>
              </div>
            </li>
          </ul>
        </section>

        <section v-show="section === 'source'">
          <h2>元数据源</h2>
          <p v-if="fromLibrary && snapshot && !snapshot.tmdbApiKeyConfigured" class="lede">
            请先填写下面的 TMDB API Key 并保存。没有它时无法创建资料库。
          </p>
          <p v-else class="lede">只有 TMDB 用来搜索和建档。OMDb、TVDB 只在匹配成功后补充数据，TMDB 没有结果时不会改用它们。</p>
          <label>
            <span>TMDB API Key</span>
            <input
              ref="tmdbInput"
              v-model="tmdbApiKey"
              type="text"
              autocomplete="off"
              spellcheck="false"
              :placeholder="snapshot?.tmdbApiKeyConfigured ? '' : '必填，唯一匹配来源'"
              @focus="selectMask"
            />
          </label>
          <label>
            <span>详情语言</span>
            <input v-model="form.tmdbLanguage" spellcheck="false" />
          </label>
          <label>
            <span>搜索语言</span>
            <input v-model="form.tmdbSearchLanguage" spellcheck="false" />
          </label>
          <label>
            <span>OMDb API Key</span>
            <input
              v-model="omdbApiKey"
              type="text"
              autocomplete="off"
              spellcheck="false"
              :placeholder="snapshot?.omdbApiKeyConfigured ? '' : '可选，只补充评分和奖项'"
              @focus="selectMask"
            />
          </label>
          <label>
            <span>TVDB API Key</span>
            <input
              v-model="tvdbApiKey"
              type="text"
              autocomplete="off"
              spellcheck="false"
              :placeholder="snapshot?.tvdbApiKeyConfigured ? '' : '可选，填写后补充资料，不参与匹配'"
              @focus="selectMask"
            />
          </label>
          <label>
            <span>TVDB PIN</span>
            <input
              v-model="tvdbPin"
              type="text"
              autocomplete="off"
              spellcheck="false"
              :placeholder="snapshot?.tvdbPinConfigured ? '' : '没有可留空'"
              @focus="selectMask"
            />
          </label>
        </section>

        <section v-show="section === 'playback'">
          <h2>播放</h2>
          <label>
            <span>片头不足多少秒不记进度</span>
            <input v-model.number="form.playbackIgnoreBelowSeconds" type="number" min="0" max="3600" step="1" />
            <small class="hint">短于这个时间就当没看，下次仍从头播。0 表示一播放就记。</small>
          </label>
          <label>
            <span>片尾剩余多少秒视为看完</span>
            <input v-model.number="form.playbackCompleteRemainingSeconds" type="number" min="0" max="3600" step="1" />
            <small class="hint">播到离结尾不超过这个时间，就记为看完。电影会离开继续观看；剧集有下一集会跳到下一集。</small>
          </label>
        </section>

        <section v-show="section === 'match'">
          <h2>匹配与扫描</h2>
          <label>
            <span>自动匹配阈值（0.1–1）</span>
            <input v-model.number="form.matchAutoThreshold" type="number" min="0.1" max="1" step="0.01" />
          </label>
          <label>
            <span>定时扫描间隔（分钟）</span>
            <input v-model.number="form.scanIntervalMinutes" type="number" min="1" max="1440" step="1" />
          </label>
          <label class="check">
            <FolioCheck v-model="form.watchEnabled" />
            监听资料库目录变化（关闭后仍按间隔扫描）
          </label>
        </section>

        <section v-show="section === 'worker'">
          <h2>刮削任务</h2>
          <label>
            <span>同时进行的任务数</span>
            <input v-model.number="form.workerConcurrency" type="number" min="1" max="64" step="1" />
          </label>
          <label>
            <span>领取任务间隔（毫秒）</span>
            <input v-model.number="form.workerDelayMs" type="number" min="200" max="60000" step="100" />
          </label>
          <label>
            <span>单个任务最多尝试次数</span>
            <input v-model.number="form.workerMaxAttempts" type="number" min="1" max="10" step="1" />
          </label>
        </section>

        <section v-show="section === 'advanced'">
          <h2>高级</h2>
          <label>
            <span>TMDB API 地址</span>
            <input v-model="form.tmdbBaseUrl" spellcheck="false" />
          </label>
          <label>
            <span>TMDB 图片地址</span>
            <div class="field-row">
              <input v-model="form.tmdbImageBaseUrl" spellcheck="false" />
              <button
                type="button"
                class="ghost"
                :disabled="form.tmdbImageBaseUrl === DEFAULT_TMDB_IMAGE_BASE_URL"
                @click="resetTmdbImageBaseUrl"
              >
                恢复默认
              </button>
            </div>
            <small class="hint">
              入库始终用官方地址；此处只影响访问时展示。改前缀后无需重刮。
              wsrv 示例：https://wsrv.nl/?url=https://image.tmdb.org/t/p/original
            </small>
          </label>
          <label>
            <span>TMDB 每秒请求上限</span>
            <input v-model.number="form.tmdbRequestsPerSecond" type="number" min="0.1" step="0.1" />
          </label>
          <label>
            <span>OMDb 地址</span>
            <input v-model="form.omdbBaseUrl" spellcheck="false" />
          </label>
          <label>
            <span>OMDb 每秒请求上限</span>
            <input v-model.number="form.omdbRequestsPerSecond" type="number" min="0.1" step="0.1" />
          </label>
          <label>
            <span>TVDB API 地址</span>
            <input v-model="form.tvdbBaseUrl" spellcheck="false" />
          </label>
          <label>
            <span>TVDB 每秒请求上限</span>
            <input v-model.number="form.tvdbRequestsPerSecond" type="number" min="0.1" step="0.1" />
          </label>
          <label>
            <span>外部 API 超时（秒）</span>
            <input v-model.number="form.httpTimeoutSeconds" type="number" min="1" max="120" step="1" />
          </label>
        </section>

        <div v-if="section !== 'account'" class="actions">
          <button type="submit" class="primary" :disabled="saving || loading">
            {{ saving ? '保存中…' : '保存' }}
          </button>
        </div>
      </div>
    </form>
    <div v-if="editorOpen" class="editor-overlay" @click.self="editorOpen = false">
      <form class="editor" @submit.prevent="submitEditor">
        <h2>
          {{
            editorMode === 'create'
              ? '新建用户'
              : editorMode === 'libraries'
                ? `资料库权限 · ${editorUser?.username ?? ''}`
                : '修改账号'
          }}
        </h2>
        <template v-if="editorMode !== 'libraries'">
          <label>
            <span>用户名</span>
            <input v-model="editorUsername" autocomplete="username" spellcheck="false" />
          </label>
          <label v-if="editorMode === 'edit' && !isAdmin">
            <span>当前密码</span>
            <input v-model="editorCurrentPassword" type="password" autocomplete="current-password" />
          </label>
          <label>
            <span>{{ editorMode === 'create' ? '密码' : '新密码（不改可留空）' }}</span>
            <input v-model="editorPassword" type="password" autocomplete="new-password" />
          </label>
          <label v-if="editorMode === 'create'">
            <span>角色</span>
            <select v-model="editorRole">
              <option value="USER">普通用户</option>
              <option value="ADMIN">管理员</option>
            </select>
          </label>
        </template>
        <div
          v-if="(editorMode === 'create' && editorRole === 'USER') || editorMode === 'libraries'"
          class="library-perms"
        >
          <p class="library-perms-title">资料库权限</p>
          <p v-if="allLibraries.length === 0" class="lede">还没有资料库可分配。</p>
          <ul v-else class="library-perm-list">
            <li v-for="library in allLibraries" :key="library.id">
              <span class="library-perm-name">{{ library.name }}</span>
              <select v-model="editorLibraryAccess[library.id]">
                <option value="">无</option>
                <option value="READ">只读</option>
                <option value="WRITE">读写</option>
              </select>
            </li>
          </ul>
        </div>
        <p v-if="editorError" class="editor-error">{{ editorError }}</p>
        <div class="editor-actions">
          <button type="button" class="ghost" @click="editorOpen = false">取消</button>
          <button type="submit" class="primary" :disabled="saving">{{ saving ? '保存中…' : '保存' }}</button>
        </div>
      </form>
    </div>
    <p v-if="toast" class="toast" role="status">{{ toast }}</p>
  </div>
</template>

<style scoped>
.settings {
  width: min(1080px, calc(100% - 2.5rem));
  max-width: 100%;
  margin: 0 auto;
  padding: calc(2rem + var(--safe-top)) 0 calc(4rem + var(--safe-bottom));
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
  font-size: clamp(2rem, 4vw, 2.75rem);
  letter-spacing: -0.03em;
}

.lede,
.status {
  margin: 0.5rem 0 0;
  color: var(--ink-muted);
}

.status.err {
  color: var(--danger);
}

.mast-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.75rem;
}

.shell {
  display: grid;
  grid-template-columns: 11.5rem minmax(0, 1fr);
  gap: 1.25rem;
  align-items: start;
}

.nav {
  display: grid;
  gap: 0.3rem;
  padding: 0.45rem;
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: rgba(18, 21, 28, 0.55);
  position: sticky;
  top: calc(0.75rem + var(--safe-top));
}

.nav button {
  text-align: left;
  border: 0;
  background: transparent;
  color: var(--ink-muted);
  padding: 0.7rem 0.85rem;
  border-radius: 10px;
  cursor: pointer;
  font-weight: 650;
}

.nav button:hover {
  color: var(--ink);
  background: rgba(242, 239, 232, 0.05);
}

.nav button.active {
  color: var(--ink);
  background: linear-gradient(135deg, rgba(212, 165, 116, 0.22), rgba(95, 179, 168, 0.16));
}

.pane {
  display: grid;
  gap: 1rem;
  min-width: 0;
}

section {
  display: grid;
  gap: 0.85rem;
  padding: 1.15rem 1.2rem;
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: rgba(18, 21, 28, 0.55);
}

h2 {
  margin: 0;
  font-size: 1.05rem;
}

label {
  display: grid;
  gap: 0.35rem;
}

label span {
  font-size: 0.82rem;
  color: var(--ink-muted);
}

label .hint {
  font-size: 0.78rem;
  color: var(--ink-faint);
  line-height: 1.4;
}

.field-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 0.55rem;
  align-items: center;
}

.field-row .ghost {
  height: 2.7rem;
  padding: 0 0.95rem;
  border: 1px solid var(--line-strong);
  background: transparent;
  color: var(--ink-muted);
  white-space: nowrap;
}

.field-row .ghost:hover:not(:disabled) {
  color: var(--copper);
  border-color: rgba(212, 165, 116, 0.45);
}

.field-row .ghost:disabled {
  opacity: 0.45;
  cursor: default;
}

.check {
  grid-template-columns: auto 1fr;
  align-items: center;
  gap: 0.55rem;
}

.check :deep(.folio-check) {
  font-size: 1rem;
  color: inherit;
}

input,
select {
  height: 2.7rem;
  padding: 0 0.85rem;
  border-radius: 12px;
  border: 1px solid var(--line-strong);
  background: rgba(18, 21, 28, 0.86);
  color: var(--ink);
  outline: none;
}

input:focus,
select:focus {
  border-color: rgba(212, 165, 116, 0.55);
  box-shadow: 0 0 0 3px var(--copper-soft);
}

.ghost,
.primary {
  border-radius: 999px;
  cursor: pointer;
  font-weight: 650;
}

.actions {
  display: flex;
  justify-content: flex-end;
}

.primary {
  border: 0;
  padding: 0.55rem 1.2rem;
  color: #1a140e;
  background: var(--copper);
}

.primary:disabled {
  opacity: 0.6;
  cursor: wait;
}

@media (max-width: 820px) {
  .settings {
    width: 100%;
    padding-left: 1rem;
    padding-right: 1rem;
  }

  .shell {
    grid-template-columns: 1fr;
  }

  .nav {
    position: static;
    grid-auto-flow: column;
    grid-auto-columns: max-content;
    overflow-x: auto;
    gap: 0.2rem;
  }

  .nav button {
    white-space: nowrap;
  }
}

.section-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  margin-bottom: 0.85rem;
}

.section-head .primary {
  height: 2.4rem;
  border-radius: 999px;
}

.tabs {
  display: flex;
  gap: 0.35rem;
  margin: 0 0 0.85rem;
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

.user-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  gap: 0.55rem;
}

.user-list li {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 0.85rem 1rem;
  padding: 0.85rem 1rem;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: rgba(18, 21, 28, 0.42);
}

.user-list li.self {
  border-color: rgba(212, 165, 116, 0.28);
  background: linear-gradient(135deg, rgba(212, 165, 116, 0.1), rgba(18, 21, 28, 0.4));
}

.user-list li.muted {
  opacity: 0.72;
}

.user-identity {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  min-width: 0;
  flex: 1 1 12rem;
}

.user-avatar {
  flex: 0 0 auto;
  width: 2.4rem;
  height: 2.4rem;
  display: grid;
  place-items: center;
  border-radius: 999px;
  background: rgba(212, 165, 116, 0.16);
  color: var(--copper);
  font-weight: 700;
  font-size: 0.95rem;
  letter-spacing: 0.02em;
}

.user-list li.self .user-avatar {
  background: rgba(212, 165, 116, 0.28);
  color: #f2efe8;
}

.user-copy {
  min-width: 0;
  display: grid;
  gap: 0.35rem;
}

.user-copy strong {
  font-size: 1rem;
  font-weight: 650;
  letter-spacing: -0.01em;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.user-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
}

.user-flag {
  font-size: 0.72rem;
  line-height: 1.2;
  color: var(--ink-muted);
  border: 1px solid var(--line);
  border-radius: 999px;
  padding: 0.18rem 0.5rem;
}

.user-flag.accent {
  color: var(--copper);
  border-color: rgba(212, 165, 116, 0.4);
  background: rgba(212, 165, 116, 0.1);
}

.user-flag.danger {
  color: var(--danger, #e07a6a);
  border-color: rgba(224, 122, 106, 0.4);
  background: rgba(224, 122, 106, 0.1);
}

.user-actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: 0.4rem;
}

.user-actions .ghost {
  height: 2.15rem;
  padding: 0 0.8rem;
  border: 1px solid var(--line-strong);
  border-radius: 999px;
  background: transparent;
  color: var(--ink-muted);
  font-size: 0.85rem;
}

.user-actions .ghost:hover {
  color: var(--ink);
  border-color: rgba(212, 165, 116, 0.45);
}

.user-actions .ghost.danger {
  color: var(--danger, #e07a6a);
  border-color: rgba(224, 122, 106, 0.45);
}

.user-actions .ghost.danger:hover {
  background: rgba(224, 122, 106, 0.1);
}

.editor-overlay {
  position: fixed;
  inset: 0;
  z-index: 30;
  display: grid;
  place-items: center;
  padding: 1.25rem;
  background: rgba(4, 6, 10, 0.45);
  backdrop-filter: blur(18px);
  -webkit-backdrop-filter: blur(18px);
}

.editor {
  width: min(420px, 100%);
  display: grid;
  gap: 0.85rem;
  padding: 1.2rem;
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: var(--bg-panel, #161a22);
}

.editor-error {
  margin: 0;
  color: var(--danger, #e07a6a);
  font-size: 0.85rem;
}

.editor-actions {
  display: flex;
  justify-content: flex-end;
  align-items: center;
  gap: 0.65rem;
}

.editor-actions .ghost,
.editor-actions .primary {
  box-sizing: border-box;
  height: 2.5rem;
  min-width: 5.25rem;
  padding: 0 1.15rem;
  font-size: 0.95rem;
  line-height: 1;
}

.editor-actions .ghost {
  border: 1px solid var(--line-strong);
  background: transparent;
  color: var(--ink-muted);
}

.library-perms {
  display: grid;
  gap: 0.55rem;
}

.library-perms-title {
  margin: 0;
  color: var(--ink-muted);
  font-size: 0.88rem;
}

.library-perm-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  gap: 0.45rem;
  max-height: 14rem;
  overflow: auto;
}

.library-perm-list li {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
}

.library-perm-name {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.library-perm-list select {
  width: 6.5rem;
  flex: 0 0 auto;
}

.toast {
  position: fixed;
  left: 50%;
  bottom: calc(1.25rem + var(--safe-bottom));
  z-index: 40;
  transform: translateX(-50%);
  max-width: min(32rem, calc(100% - 2rem));
  margin: 0;
  padding: 0.75rem 1rem;
  border-radius: 12px;
  background: var(--bg-soft);
  color: var(--ink);
  box-shadow: var(--shadow);
}
</style>
