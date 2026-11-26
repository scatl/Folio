<script setup lang="ts">
import { computed, nextTick, onActivated, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router'
import { deleteLibrary, getHome, getScrapeJobStats, getSettings, getWatchlist, getWorkCard, listLibraries, listLibraryCollections, listPlaylists, listReviewFiles, listWorks, putWorkWatch, reorderLibraries, scanLibrary } from '../api/client'
import { subscribeScrapeEvents } from '../api/events'
import type { CollectionCard, ContinueWatchItem, MediaLibrary, PlaylistSummary, ScrapeJobRow, WatchlistItem, WorkCard } from '../api/types'
import { currentUser, signOut } from '../auth/session'
import BrowseFilters from '../components/BrowseFilters.vue'
import CreateLibraryDialog from '../components/CreateLibraryDialog.vue'
import EmptyState from '../components/EmptyState.vue'
import LoadingState from '../components/LoadingState.vue'
import PosterCard from '../components/PosterCard.vue'
import PosterMedia from '../components/PosterMedia.vue'
import PosterWallSkeleton from '../components/PosterWallSkeleton.vue'
import { browseActive, browseParams, emptyBrowseFilter } from '../lib/browse'
import { confirmDialog } from '../lib/confirm'
import { noteWatch, playlistTick, watchlistTick, watchMarks } from '../lib/watchMarks'

defineOptions({ name: 'PosterWallView' })

const SIDEBAR_KEY = 'folio.sidebar.collapsed'

const router = useRouter()
const route = useRoute()
const isAdmin = computed(() => currentUser.value?.role === 'ADMIN')

function canWriteLibrary(libraryId: number) {
  if (isAdmin.value) return true
  return libraries.value.find((item) => item.id === libraryId)?.access === 'WRITE'
}

function showLibraryMenu(libraryId: number) {
  return isAdmin.value || canWriteLibrary(libraryId)
}

const libraries = ref<MediaLibrary[]>([])
const draggingLibraryId = ref<number | null>(null)
let libraryDragDirty = false
const panel = ref<'home' | 'library'>(libraryIdFromRoute() != null ? 'library' : 'home')
const activeLibraryId = ref<number | null>(libraryIdFromRoute())
const sidebarCollapsed = ref(localStorage.getItem(SIDEBAR_KEY) === '1')
const navOpen = ref(false)

const items = ref<WorkCard[]>([])
const recentWorks = ref<WorkCard[]>([])
const recentTotal = ref(0)
const continueWatching = ref<ContinueWatchItem[]>([])
const homeContinueOk = ref(false)
const watchlist = ref<WatchlistItem[]>([])
const homeWatchlistOk = ref(false)
const playlists = ref<PlaylistSummary[]>([])
const homePlaylistsOk = ref(false)
const page = ref(0)
const total = ref(0)
const totalPages = ref(0)
const loading = ref(true)
const loadingMore = ref(false)
const librariesLoading = ref(true)
const homeLibrariesOk = ref(false)
const homeRecentOk = ref(false)
const error = ref<string | null>(null)
const taskBadge = ref(0)
const showCreateLibrary = ref(false)
const deletingLibraryId = ref<number | null>(null)
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
const scanningLibraryId = ref<number | null>(null)
const libraryMenuId = ref<number | null>(null)
const movieTab = ref<'all' | 'collections'>('all')
const collections = ref<CollectionCard[]>([])
const collectionsLoading = ref(false)

const query = ref('')
const filters = ref(emptyBrowseFilter())
const filtering = computed(() => browseActive(filters.value))
const searchInput = ref('')
const homeQuery = ref('')
const homeSearchInput = ref('')
const homeResults = ref<WorkCard[]>([])
const homePage = ref(0)
const homeTotal = ref(0)
const homeTotalPages = ref(0)
const homeLoading = ref(false)

const activeLibrary = computed(
  () => libraries.value.find((lib) => lib.id === activeLibraryId.value) ?? null,
)
const hasMore = computed(() => page.value + 1 < totalPages.value)
const homeHasMore = computed(() => homePage.value + 1 < homeTotalPages.value)
const empty = computed(() => !loading.value && !error.value && items.value.length === 0)
const tmdbConfigured = ref<boolean | null>(null)
const isHome = computed(() => panel.value === 'home')
const noLibraries = computed(() =>
  isHome.value ? homeLibrariesOk.value && libraries.value.length === 0 : !librariesLoading.value && libraries.value.length === 0,
)
const homeSearching = ref(libraryIdFromRoute() == null && Object.hasOwn(route.query, 'q'))
const isMovieLibrary = computed(() => !isHome.value && activeLibrary.value?.kind === 'movie')
const visibleCollections = computed(() => {
  const q = searchInput.value.trim().toLowerCase()
  if (!q) return collections.value
  return collections.value.filter((item) => item.name.toLowerCase().includes(q))
})
const homeBooting = computed(
  () =>
    isHome.value &&
    (loading.value || librariesLoading.value) &&
    libraries.value.length === 0 &&
    recentWorks.value.length === 0 &&
    !error.value,
)

const statusText = computed(() => {
  if (homeBooting.value) return ''
  if (librariesLoading.value || loading.value) return isHome.value ? '' : '正在整理海报墙'
  if (error.value) return error.value
  if (isHome.value) {
    if (noLibraries.value) return '还没有资料库'
    if (homeSearching.value) {
      if (!homeQuery.value) return '搜索全部作品'
      return homeLoading.value ? '正在搜索' : `「${homeQuery.value}」 · 共 ${homeTotal.value} 部`
    }
    if (homeLibrariesOk.value && homeRecentOk.value) {
      return `${libraries.value.length} 个资料库 · ${recentTotal.value} 部作品`
    }
    if (homeLibrariesOk.value) return `${libraries.value.length} 个资料库`
    if (homeRecentOk.value) return `${recentTotal.value} 部作品`
    return ''
  }
  if (!activeLibrary.value) return '选择一个资料库'
  if (isMovieLibrary.value && movieTab.value === 'collections') {
    return `${activeLibrary.value.name} · ${collections.value.length} 个系列`
  }
  return `${activeLibrary.value.name} · 共 ${total.value} 部作品`
})

const showHomeStatus = computed(() => !homeBooting.value && (!!statusText.value || !!error.value))

let searchTimer: ReturnType<typeof setTimeout> | null = null
let wallScrollY = 0
const posterMotion = ref(true)

function rememberScroll() {
  wallScrollY = window.scrollY
}

function restoreScroll() {
  const y = wallScrollY
  nextTick(() => {
    requestAnimationFrame(() => {
      window.scrollTo(0, y)
    })
  })
}

function toggleSidebar() {
  libraryMenuId.value = null
  sidebarCollapsed.value = !sidebarCollapsed.value
  localStorage.setItem(SIDEBAR_KEY, sidebarCollapsed.value ? '1' : '0')
}

function openNav() {
  navOpen.value = true
}

function closeNav() {
  navOpen.value = false
}

async function loadTmdbStatus() {
  if (!isAdmin.value) {
    tmdbConfigured.value = null
    return
  }
  try {
    const settings = await getSettings()
    tmdbConfigured.value = settings.tmdbApiKeyConfigured
  } catch {
    tmdbConfigured.value = null
  }
}

function openContinue(item: ContinueWatchItem) {
  closeNav()
  void router.push({ name: 'play', params: { fileId: String(item.libraryFileId) } })
}

const continueRailEl = ref<HTMLElement | null>(null)
const continueCanLeft = ref(false)
const continueCanRight = ref(false)
const continueShowArrows = computed(() => continueCanLeft.value || continueCanRight.value)
let continueResizeObserver: ResizeObserver | null = null

function measureContinueOverflow(el: HTMLElement) {
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

function updateContinueScroll() {
  const el = continueRailEl.value
  if (!el) {
    continueCanLeft.value = false
    continueCanRight.value = false
    return
  }
  const max = Math.max(0, measureContinueOverflow(el))
  continueCanLeft.value = el.scrollLeft > 2
  continueCanRight.value = max > 2 && el.scrollLeft < max - 2
}

function bindContinueImages() {
  const el = continueRailEl.value
  if (!el) return
  el.querySelectorAll('img').forEach((img) => {
    if (img.complete) return
    img.addEventListener('load', updateContinueScroll, { once: true })
    img.addEventListener('error', updateContinueScroll, { once: true })
  })
}

async function refreshContinueScroll() {
  await nextTick()
  bindContinueImages()
  updateContinueScroll()
  requestAnimationFrame(() => {
    updateContinueScroll()
    window.setTimeout(updateContinueScroll, 120)
    window.setTimeout(updateContinueScroll, 400)
  })
}

function scrollContinue(dir: -1 | 1) {
  const el = continueRailEl.value
  if (!el) return
  const step = Math.max(el.clientWidth * 0.75, 240)
  const max = Math.max(0, el.scrollWidth - el.clientWidth)
  const next = Math.min(max, Math.max(0, el.scrollLeft + dir * step))
  el.scrollTo({ left: next, behavior: 'smooth' })
  window.setTimeout(updateContinueScroll, 80)
  window.setTimeout(updateContinueScroll, 320)
}

const watchRailEl = ref<HTMLElement | null>(null)
const watchCanLeft = ref(false)
const watchCanRight = ref(false)
const watchShowArrows = computed(() => watchCanLeft.value || watchCanRight.value)
let watchResizeObserver: ResizeObserver | null = null
let wallSeen = false

function updateWatchScroll() {
  const el = watchRailEl.value
  if (!el) {
    watchCanLeft.value = false
    watchCanRight.value = false
    return
  }
  const max = Math.max(0, measureContinueOverflow(el))
  watchCanLeft.value = el.scrollLeft > 2
  watchCanRight.value = max > 2 && el.scrollLeft < max - 2
}

function bindWatchImages() {
  const el = watchRailEl.value
  if (!el) return
  el.querySelectorAll('img').forEach((img) => {
    if (img.complete) return
    img.addEventListener('load', updateWatchScroll, { once: true })
    img.addEventListener('error', updateWatchScroll, { once: true })
  })
}

async function refreshWatchScroll() {
  await nextTick()
  bindWatchImages()
  updateWatchScroll()
  requestAnimationFrame(() => {
    updateWatchScroll()
    window.setTimeout(updateWatchScroll, 120)
    window.setTimeout(updateWatchScroll, 400)
  })
}

function scrollWatch(dir: -1 | 1) {
  const el = watchRailEl.value
  if (!el) return
  const step = Math.max(el.clientWidth * 0.75, 240)
  const max = Math.max(0, el.scrollWidth - el.clientWidth)
  const next = Math.min(max, Math.max(0, el.scrollLeft + dir * step))
  el.scrollTo({ left: next, behavior: 'smooth' })
  window.setTimeout(updateWatchScroll, 80)
  window.setTimeout(updateWatchScroll, 320)
}

async function refreshWatchlist() {
  try {
    const items = await getWatchlist()
    homeWatchlistOk.value = true
    watchlist.value = items
  } catch {
    // 保留上次成功的清单
  }
  void refreshWatchScroll()
}

const listRailEl = ref<HTMLElement | null>(null)
const listCanLeft = ref(false)
const listCanRight = ref(false)
const listShowArrows = computed(() => listCanLeft.value || listCanRight.value)
let listResizeObserver: ResizeObserver | null = null

function updateListScroll() {
  const el = listRailEl.value
  if (!el) {
    listCanLeft.value = false
    listCanRight.value = false
    return
  }
  const max = Math.max(0, measureContinueOverflow(el))
  listCanLeft.value = el.scrollLeft > 2
  listCanRight.value = max > 2 && el.scrollLeft < max - 2
}

function bindListImages() {
  const el = listRailEl.value
  if (!el) return
  el.querySelectorAll('img').forEach((img) => {
    if (img.complete) return
    img.addEventListener('load', updateListScroll, { once: true })
    img.addEventListener('error', updateListScroll, { once: true })
  })
}

async function refreshListScroll() {
  await nextTick()
  bindListImages()
  updateListScroll()
  requestAnimationFrame(() => {
    updateListScroll()
    window.setTimeout(updateListScroll, 120)
    window.setTimeout(updateListScroll, 400)
  })
}

function scrollList(dir: -1 | 1) {
  const el = listRailEl.value
  if (!el) return
  const step = Math.max(el.clientWidth * 0.75, 240)
  const max = Math.max(0, el.scrollWidth - el.clientWidth)
  const next = Math.min(max, Math.max(0, el.scrollLeft + dir * step))
  el.scrollTo({ left: next, behavior: 'smooth' })
  window.setTimeout(updateListScroll, 80)
  window.setTimeout(updateListScroll, 320)
}

async function refreshPlaylists() {
  try {
    const items = await listPlaylists()
    homePlaylistsOk.value = true
    playlists.value = items
  } catch {
    // 保留上次成功的清单
  }
  void refreshListScroll()
}

function openPlaylist(id: number) {
  void router.push({ name: 'playlist', params: { id: String(id) } })
}

function openSettings() {
  closeNav()
  void router.push({ name: 'settings' })
}

function openLogs() {
  closeNav()
  void router.push({ name: 'logs' })
}

async function logout() {
  closeNav()
  await signOut()
  await router.replace({ name: 'login' })
}

async function loadLibraries() {
  librariesLoading.value = true
  try {
    const listed = await listLibraries()
    libraries.value = listed
    homeLibrariesOk.value = true
    if (
      activeLibraryId.value != null &&
      !libraries.value.some((lib) => lib.id === activeLibraryId.value)
    ) {
      activeLibraryId.value = null
      panel.value = 'home'
    }
  } catch (e) {
    error.value = e instanceof Error ? e.message : '资料库加载失败'
    libraries.value = []
    homeLibrariesOk.value = false
    activeLibraryId.value = null
    panel.value = 'home'
  } finally {
    librariesLoading.value = false
  }
}

function onLibraryDragStart(id: number, event: DragEvent) {
  draggingLibraryId.value = id
  libraryDragDirty = false
  event.dataTransfer?.setData('text/plain', String(id))
  if (event.dataTransfer) event.dataTransfer.effectAllowed = 'move'
}

function onLibraryDragOver(id: number, event: DragEvent) {
  event.preventDefault()
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'move'
  const fromId = draggingLibraryId.value
  if (fromId == null || fromId === id) return
  const current = libraries.value
  const from = current.findIndex((item) => item.id === fromId)
  const over = current.findIndex((item) => item.id === id)
  if (from < 0 || over < 0) return
  const row = event.currentTarget
  if (!(row instanceof HTMLElement)) return
  const rect = row.getBoundingClientRect()
  const before = event.clientY < rect.top + rect.height / 2
  // 先按「悬停项前/后」算插入点，再去掉正在拖的项。
  const rest = current.filter((item) => item.id !== fromId)
  const overInRest = rest.findIndex((item) => item.id === id)
  if (overInRest < 0) return
  const insertAt = before ? overInRest : overInRest + 1
  if (insertAt === from) return
  const moved = current[from]
  if (!moved) return
  const items = rest.slice()
  items.splice(insertAt, 0, moved)
  if (items.length === current.length && items.every((item, index) => item.id === current[index]?.id)) return
  libraries.value = items
  libraryDragDirty = true
}

async function onLibraryDragEnd() {
  const dirty = libraryDragDirty
  const ids = libraries.value.map((item) => item.id)
  draggingLibraryId.value = null
  libraryDragDirty = false
  if (!dirty) return
  try {
    await reorderLibraries(ids)
  } catch (e) {
    error.value = e instanceof Error ? e.message : '资料库排序失败'
    await loadLibraries()
  }
}

async function loadHome() {
  const cold = libraries.value.length === 0 && recentWorks.value.length === 0
  if (cold) {
    loading.value = true
    librariesLoading.value = true
  }
  error.value = null
  try {
    const home = await getHome()
    const listed = home.libraries
    homeLibrariesOk.value = listed != null
    libraries.value = listed ?? []
    if (
      listed != null &&
      activeLibraryId.value != null &&
      !listed.some((lib) => lib.id === activeLibraryId.value)
    ) {
      activeLibraryId.value = null
      panel.value = 'home'
    }
    homeRecentOk.value = home.recent != null
    recentWorks.value = home.recent?.items ?? []
    recentTotal.value = home.recent?.total ?? 0
    homeContinueOk.value = home.continueWatching != null
    continueWatching.value = home.continueWatching ?? []
    homeWatchlistOk.value = home.watchlist != null
    watchlist.value = home.watchlist ?? []
    homePlaylistsOk.value = home.playlists != null
    playlists.value = home.playlists ?? []
    if (home.setup) tmdbConfigured.value = home.setup.tmdbConfigured
  } catch (e) {
    error.value = e instanceof Error ? e.message : '首页加载失败'
    libraries.value = []
    recentWorks.value = []
    recentTotal.value = 0
    continueWatching.value = []
    homeLibrariesOk.value = false
    homeRecentOk.value = false
    homeContinueOk.value = false
    watchlist.value = []
    homeWatchlistOk.value = false
    playlists.value = []
    homePlaylistsOk.value = false
  } finally {
    loading.value = false
    librariesLoading.value = false
  }
}

async function fetchPage(nextPage: number, append: boolean) {
  const homeBrowse = panel.value === 'home' && filtering.value
  if (!homeBrowse && (panel.value !== 'library' || activeLibraryId.value == null)) {
    items.value = []
    total.value = 0
    totalPages.value = 0
    loading.value = false
    loadingMore.value = false
    return
  }
  if (append) {
    if (!hasMore.value || loadingMore.value || loading.value) return
    loadingMore.value = true
  } else {
    wallGeneration += 1
    loading.value = true
    loadingMore.value = false
    error.value = null
  }
  const generation = wallGeneration
  let ok = false
  try {
    const data = await listWorks({
      libraryId: homeBrowse ? undefined : activeLibraryId.value ?? undefined,
      q: homeBrowse ? undefined : query.value || undefined,
      ...browseParams(filters.value),
      page: nextPage,
      size: 48,
    })
    if (generation !== wallGeneration) return
    items.value = append ? [...items.value, ...data.items] : data.items
    page.value = data.page
    total.value = data.total
    totalPages.value = data.totalPages
    ok = true
  } catch (e) {
    if (generation !== wallGeneration) return
    error.value = e instanceof Error ? e.message : '加载失败'
    if (!append) items.value = []
  } finally {
    if (generation === wallGeneration) {
      if (append) loadingMore.value = false
      else loading.value = false
    }
  }
  if (ok) await fillIfShort()
}

function reload() {
  if (panel.value === 'home') {
    if (filtering.value) void fetchPage(0, false)
    else void loadHome()
    return
  }
  void fetchPage(0, false)
}

function rank(work: WorkCard): number {
  return work.popularity ?? -1
}

function comesAfter(card: WorkCard, other: WorkCard): boolean {
  const left = rank(card)
  const right = rank(other)
  if (left !== right) return left < right
  return card.id < other.id
}

function placeCard(list: WorkCard[], card: WorkCard, windowFull: boolean): WorkCard[] {
  const exists = list.some((work) => work.id === card.id)
  const rest = list.filter((work) => work.id !== card.id)
  const last = rest[rest.length - 1]
  if (!exists && windowFull && last && comesAfter(card, last)) return list
  const next = [...rest, card].sort((a, b) => (comesAfter(a, b) ? 1 : comesAfter(b, a) ? -1 : 0))
  return next
}

/** 首页近期作品：按最近刮削置顶，最多 50 条。 */
function placeRecentCard(list: WorkCard[], card: WorkCard): WorkCard[] {
  return [card, ...list.filter((work) => work.id !== card.id)].slice(0, 50)
}

function matchesQuery(card: WorkCard): boolean {
  const q = query.value.trim().toLowerCase()
  if (!q) return true
  return card.title.toLowerCase().includes(q) || card.originalTitle.toLowerCase().includes(q)
}

async function upsertFromJob(job: ScrapeJobRow) {
  if (job.workId == null || loading.value) return
  if (panel.value === 'library' && job.mediaLibraryId !== activeLibraryId.value) return
  let card: WorkCard
  try {
    card = await getWorkCard(job.workId)
  } catch {
    return
  }
  if (!matchesQuery(card)) return
  if (panel.value === 'home') {
    const existed = recentWorks.value.some((work) => work.id === card.id)
    recentWorks.value = placeRecentCard(recentWorks.value, card)
    if (!existed) recentTotal.value += 1
    homeRecentOk.value = true
    return
  }
  const existed = items.value.some((work) => work.id === card.id)
  items.value = placeCard(items.value, card, hasMore.value)
  if (!existed) total.value += 1
  totalPages.value = total.value === 0 ? 0 : Math.ceil(total.value / 48)
}

function loadMore() {
  if (loadingMore.value) return
  if (panel.value === 'home' && homeQuery.value) {
    if (homeLoading.value || !homeHasMore.value) return
    void searchHome(homePage.value + 1, true)
    return
  }
  if (panel.value === 'home' && filtering.value) {
    if (!hasMore.value || loading.value || loadingMore.value) return
    void fetchPage(page.value + 1, true)
    return
  }
  if (!hasMore.value || loading.value || panel.value !== 'library') return
  void fetchPage(page.value + 1, true)
}

async function fillIfShort() {
  await nextTick()
  const el = bottomSentinel.value
  if (!el || loadingMore.value) return
  if (panel.value === 'home' && homeQuery.value) {
    if (homeLoading.value || !homeHasMore.value) return
    if (el.getBoundingClientRect().top <= window.innerHeight + 480) loadMore()
    return
  }
  if (panel.value === 'home' && filtering.value) {
    if (!hasMore.value || loading.value) return
    if (el.getBoundingClientRect().top <= window.innerHeight + 480) loadMore()
    return
  }
  if (panel.value !== 'library' || !hasMore.value || loading.value) return
  if (el.getBoundingClientRect().top <= window.innerHeight + 480) loadMore()
}

function onBottomVisible(entries: IntersectionObserverEntry[]) {
  if (entries.some((entry) => entry.isIntersecting)) loadMore()
}

function removeWork(workId: number) {
  continueWatching.value = continueWatching.value.filter((item) => item.workId !== workId)
  const recentBefore = recentWorks.value.length
  recentWorks.value = recentWorks.value.filter((work) => work.id !== workId)
  if (recentWorks.value.length < recentBefore) {
    recentTotal.value = Math.max(0, recentTotal.value - 1)
  }
  const before = items.value.length
  items.value = items.value.filter((work) => work.id !== workId)
  if (items.value.length < before) {
    total.value = Math.max(0, total.value - 1)
    totalPages.value = total.value === 0 ? 0 : Math.ceil(total.value / 48)
  }
}

const libraryMenuStyle = ref({ top: '0px', left: '0px' })

function toggleLibraryMenu(id: number, event: MouseEvent) {
  if (libraryMenuId.value === id) {
    libraryMenuId.value = null
    return
  }
  const rect = (event.currentTarget as HTMLElement).getBoundingClientRect()
  libraryMenuStyle.value = {
    top: `${rect.bottom + 6}px`,
    left: `${rect.right}px`,
  }
  libraryMenuId.value = id
}

async function removeLibrary(id: number) {
  libraryMenuId.value = null
  if (deletingLibraryId.value != null) return
  const library = libraries.value.find((item) => item.id === id)
  const name = library?.name || '这个资料库'
  const ok = await confirmDialog({
    title: '删除资料库',
    message: `删除资料库「${name}」？\n磁盘上的视频会保留，已刮削的作品资料也会保留。`,
    confirmLabel: '删除',
    danger: true,
  })
  if (!ok) return
  deletingLibraryId.value = id
  error.value = null
  try {
    await deleteLibrary(id)
    if (libraryIdFromRoute() === id) {
      await router.push({ name: 'wall' })
    }
    await loadLibraries()
    showToast(`已删除「${name}」`)
  } catch (e) {
    error.value = e instanceof Error ? e.message : '删除资料库失败'
  } finally {
    deletingLibraryId.value = null
  }
}

async function scanOne(id: number) {
  libraryMenuId.value = null
  if (scanningLibraryId.value != null) return
  const library = libraries.value.find((item) => item.id === id)
  scanningLibraryId.value = id
  error.value = null
  try {
    await scanLibrary(id)
    showToast(`已开始扫描「${library?.name || '资料库'}」`)
  } catch (e) {
    error.value = e instanceof Error ? e.message : '扫描失败'
  } finally {
    scanningLibraryId.value = null
  }
}

function libraryIdFromRoute(): number | null {
  const raw = route.query.library
  const value = Array.isArray(raw) ? raw[0] : raw
  const id = Number(value)
  return Number.isInteger(id) && id > 0 ? id : null
}

async function loadCollections() {
  const libraryId = activeLibraryId.value
  if (libraryId == null) return
  collectionsLoading.value = true
  error.value = null
  try {
    collections.value = await listLibraryCollections(libraryId)
  } catch (e) {
    error.value = e instanceof Error ? e.message : '系列加载失败'
    collections.value = []
  } finally {
    collectionsLoading.value = false
  }
}

function openCollection(card: CollectionCard) {
  const libraryId = activeLibraryId.value
  void router.push({
    name: 'collection',
    params: { id: card.id },
    query: libraryId != null ? { library: String(libraryId) } : {},
  })
}

function setMovieTab(tab: 'all' | 'collections') {
  movieTab.value = tab
  if (tab === 'collections') void loadCollections()
}

function routeShowsCurrent(): boolean {
  const id = libraryIdFromRoute()
  if (id == null) return panel.value === 'home'
  return panel.value === 'library' && activeLibraryId.value === id
}

async function applyRoute() {
  const id = libraryIdFromRoute()
  if (id != null && !libraries.value.some((lib) => lib.id === id)) {
    await router.replace({ name: 'wall' })
    return
  }
  if (routeShowsCurrent()) {
    if (id == null && (recentWorks.value.length > 0 || !loading.value)) return
    if (id != null && (items.value.length > 0 || !loading.value)) return
  }
  movieTab.value = 'all'
  collections.value = []
  searchInput.value = ''
  query.value = ''
  if (id == null) {
    panel.value = 'home'
    activeLibraryId.value = null
    await loadHome()
    return
  }
  panel.value = 'library'
  if (activeLibraryId.value !== id) {
    activeLibraryId.value = id
    return
  }
  void fetchPage(0, false)
}

function goHome() {
  closeNav()
  searchInput.value = ''
  query.value = ''
  if (libraryIdFromRoute() == null) {
    panel.value = 'home'
    activeLibraryId.value = null
    if (!Object.hasOwn(route.query, 'q')) void loadHome()
    return
  }
  void router.push({ name: 'wall' })
}

function leaveSearch() {
  if (typeof router.options.history.state.back === 'string') {
    void router.back()
    return
  }
  void router.replace({ name: 'wall' })
}

function selectLibrary(id: number) {
  libraryMenuId.value = null
  closeNav()
  if (libraryIdFromRoute() === id) {
    panel.value = 'library'
    reload()
    return
  }
  void router.push({ name: 'wall', query: { library: String(id) } })
}

function onSearchInput() {
  if (panel.value !== 'library') return
  if (isMovieLibrary.value && movieTab.value === 'collections') return
  if (searchTimer) clearTimeout(searchTimer)
  searchTimer = setTimeout(() => {
    query.value = searchInput.value.trim()
    reload()
  }, 320)
}

async function searchHome(nextPage: number, append: boolean) {
  const q = homeQuery.value
  if (!q) {
    homeResults.value = []
    homePage.value = 0
    homeTotal.value = 0
    homeTotalPages.value = 0
    homeLoading.value = false
    return
  }
  if (append) {
    if (!homeHasMore.value || loadingMore.value || homeLoading.value) return
    loadingMore.value = true
  } else {
    wallGeneration += 1
    homeLoading.value = true
    loadingMore.value = false
    error.value = null
  }
  const generation = wallGeneration
  try {
    const data = await listWorks({ q, ...browseParams(filters.value), page: nextPage, size: 48 })
    if (generation !== wallGeneration || homeQuery.value !== q) return
    homeResults.value = append ? [...homeResults.value, ...data.items] : data.items
    homePage.value = data.page
    homeTotal.value = data.total
    homeTotalPages.value = data.totalPages
  } catch (e) {
    if (generation !== wallGeneration) return
    error.value = e instanceof Error ? e.message : '搜索失败'
    if (!append) homeResults.value = []
  } finally {
    if (generation === wallGeneration) {
      if (append) loadingMore.value = false
      else homeLoading.value = false
    }
  }
}

function paintWatch(list: WorkCard[]) {
  const watch = filters.value.watch
  return list.flatMap((work) => {
    const state = watchMarks[work.id] ?? work.watchState
    const next = state === work.watchState ? work : { ...work, watchState: state }
    if (watch && state && state !== watch) return []
    return [next]
  })
}

async function markWork(work: WorkCard, watched: boolean) {
  try {
    const result = await putWorkWatch(work.id, watched)
    noteWatch(work.id, result.watchState)
    items.value = paintWatch(items.value)
    recentWorks.value = paintWatch(recentWorks.value)
    homeResults.value = paintWatch(homeResults.value)
    if (result.watchState === 'watched') {
      continueWatching.value = continueWatching.value.filter((item) => item.workId !== work.id)
    }
  } catch (e) {
    error.value = e instanceof Error ? e.message : '标记失败'
  }
}

let filterTimer: ReturnType<typeof setTimeout> | null = null
watch(filters, () => {
  if (filterTimer) clearTimeout(filterTimer)
  filterTimer = setTimeout(() => {
    if (panel.value === 'home' && homeSearching.value) {
      void searchHome(0, false)
      return
    }
    reload()
  }, 250)
}, { deep: true })

watch(watchMarks, () => {
  items.value = paintWatch(items.value)
  recentWorks.value = paintWatch(recentWorks.value)
  homeResults.value = paintWatch(homeResults.value)
})

function routeQueryText() {
  const raw = route.query.q
  const value = Array.isArray(raw) ? raw[0] : raw
  return typeof value === 'string' ? value.trim() : ''
}

function clearHomeResults() {
  homeResults.value = []
  homePage.value = 0
  homeTotal.value = 0
  homeTotalPages.value = 0
  homeLoading.value = false
}

function onHomeSearchInput() {
  if (searchTimer) clearTimeout(searchTimer)
  searchTimer = setTimeout(() => {
    const q = homeSearchInput.value.trim()
    const searching = Object.hasOwn(route.query, 'q')
    if (searching && q === routeQueryText()) return
    const location = { name: 'wall' as const, query: { q } }
    if (searching) void router.replace(location)
    else void router.push(location)
  }, 320)
}

function viewTransition(update: () => void) {
  const start = document.startViewTransition?.bind(document)
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  if (!start || reduced) {
    update()
    return
  }
  start(async () => {
    update()
    await nextTick()
  })
}

watch(
  () => route.query.q,
  () => {
    if (libraryIdFromRoute() != null) {
      homeSearching.value = false
      return
    }
    const searching = Object.hasOwn(route.query, 'q')
    const modeChanged = homeSearching.value !== searching
    const apply = () => {
      homeSearching.value = searching
      const q = routeQueryText()
      if (!searching) {
        homeSearchInput.value = ''
        homeQuery.value = ''
        clearHomeResults()
        return
      }
      if (homeSearchInput.value.trim() !== q) homeSearchInput.value = q
      if (homeQuery.value === q) return
      homeQuery.value = q
      if (!q) {
        clearHomeResults()
        return
      }
      void searchHome(0, false)
    }
    if (modeChanged) viewTransition(apply)
    else apply()
  },
  { immediate: true },
)

function openWork(id: number) {
  rememberScroll()
  const libraryId = panel.value === 'library' ? activeLibraryId.value : null
  void router.push({
    name: 'work',
    params: { id: String(id) },
    query: libraryId != null ? { library: String(libraryId) } : {},
  })
}

function openTasks() {
  closeNav()
  void router.push({ name: 'tasks' })
}

function openCreateLibrary() {
  closeNav()
  if (tmdbConfigured.value === false) {
    void router.push({ name: 'settings', query: { from: 'library' } })
    return
  }
  showCreateLibrary.value = true
}

function onLibraryCreated(library: MediaLibrary) {
  showCreateLibrary.value = false
  showToast(`已创建「${library.name}」，正在后台扫描并入队刮削`)
  void loadLibraries().then(() => selectLibrary(library.id))
  void loadTaskBadge()
}

async function loadTaskBadge() {
  if (!isAdmin.value) {
    taskBadge.value = 0
    return
  }
  try {
    const [stats, review] = await Promise.all([
      getScrapeJobStats(),
      listReviewFiles({ page: 0, size: 1 }),
    ])
    taskBadge.value = Math.max(stats.active, review.total)
  } catch {
    taskBadge.value = 0
  }
}

watch(activeLibraryId, (id) => {
  if (panel.value === 'library' && id != null) {
    void fetchPage(0, false)
  }
})

watch(
  () => route.query.library,
  () => {
    if (librariesLoading.value) return
    void applyRoute()
  },
)

const bottomSentinel = ref<HTMLElement | null>(null)

let unsubscribeEvents: (() => void) | null = null
let bottomObserver: IntersectionObserver | null = null
let wallGeneration = 0
let reviewTotal = 0
let badgeTimer: number | null = null

function scheduleTaskBadge() {
  if (badgeTimer != null) return
  badgeTimer = window.setTimeout(() => {
    badgeTimer = null
    void loadTaskBadge()
  }, 800)
}

watch(bottomSentinel, (el, prev) => {
  if (!bottomObserver) return
  if (prev) bottomObserver.unobserve(prev)
  if (el) bottomObserver.observe(el)
})

onMounted(async () => {
  bottomObserver = new IntersectionObserver(onBottomVisible, {
    root: null,
    rootMargin: '480px 0px',
  })
  if (bottomSentinel.value) bottomObserver.observe(bottomSentinel.value)
  if (libraryIdFromRoute() == null) {
    await loadHome()
  } else {
    void loadTmdbStatus()
    await loadLibraries()
  }
  await applyRoute()
  if (isAdmin.value) {
    void loadTaskBadge()
    void listReviewFiles({ page: 0, size: 1 })
      .then((data) => {
        reviewTotal = data.total
      })
      .catch(() => {
        reviewTotal = 0
      })

    unsubscribeEvents = subscribeScrapeEvents({
      onStats: (stats) => {
        taskBadge.value = Math.max(stats.active, reviewTotal)
      },
      onDone: (job) => {
        if (job.matchStatus === 'matched') {
          void upsertFromJob(job)
        }
        if (job.matchStatus === 'needs_review') {
          reviewTotal += 1
          taskBadge.value = Math.max(taskBadge.value, reviewTotal)
        }
        scheduleTaskBadge()
      },
      onWorkRemoved: removeWork,
    })
  }
})

onBeforeRouteLeave(() => {
  rememberScroll()
  posterMotion.value = false
})

onActivated(() => {
  restoreScroll()
  void loadTmdbStatus()
  void refreshContinueScroll()
  if (wallSeen) {
    void refreshWatchlist()
    void refreshPlaylists()
  }
  wallSeen = true
})

watch(navOpen, (open) => {
  document.body.style.overflow = open ? 'hidden' : ''
})

watch(continueRailEl, (el, prev) => {
  if (prev) continueResizeObserver?.unobserve(prev)
  if (!el) {
    continueCanLeft.value = false
    continueCanRight.value = false
    return
  }
  if (!continueResizeObserver && typeof ResizeObserver !== 'undefined') {
    continueResizeObserver = new ResizeObserver(() => updateContinueScroll())
  }
  continueResizeObserver?.observe(el)
  void refreshContinueScroll()
})

watch(continueWatching, () => {
  void refreshContinueScroll()
})

watch(watchRailEl, (el, prev) => {
  if (prev) watchResizeObserver?.unobserve(prev)
  if (!el) {
    watchCanLeft.value = false
    watchCanRight.value = false
    return
  }
  if (!watchResizeObserver && typeof ResizeObserver !== 'undefined') {
    watchResizeObserver = new ResizeObserver(() => updateWatchScroll())
  }
  watchResizeObserver?.observe(el)
  void refreshWatchScroll()
})

watch(watchlist, () => {
  void refreshWatchScroll()
})

watch(watchlistTick, () => {
  void refreshWatchlist()
})

watch(listRailEl, (el, prev) => {
  if (prev) listResizeObserver?.unobserve(prev)
  if (!el) {
    listCanLeft.value = false
    listCanRight.value = false
    return
  }
  if (!listResizeObserver && typeof ResizeObserver !== 'undefined') {
    listResizeObserver = new ResizeObserver(() => updateListScroll())
  }
  listResizeObserver?.observe(el)
  void refreshListScroll()
})

watch(playlists, () => {
  void refreshListScroll()
})

watch(playlistTick, () => {
  void refreshPlaylists()
})

onBeforeUnmount(() => {
  document.body.style.overflow = ''
  bottomObserver?.disconnect()
  bottomObserver = null
  continueResizeObserver?.disconnect()
  continueResizeObserver = null
  watchResizeObserver?.disconnect()
  watchResizeObserver = null
  listResizeObserver?.disconnect()
  listResizeObserver = null
  if (searchTimer) clearTimeout(searchTimer)
  if (toastTimer != null) window.clearTimeout(toastTimer)
  if (badgeTimer != null) window.clearTimeout(badgeTimer)
  unsubscribeEvents?.()
  unsubscribeEvents = null
})
</script>

<template>
  <Teleport to="body">
    <template v-if="libraryMenuId != null">
      <button type="button" class="more-scrim" aria-label="关闭菜单" @click="libraryMenuId = null" />
      <div class="more-menu" :style="libraryMenuStyle" role="menu">
        <button
          v-if="libraryMenuId != null && canWriteLibrary(libraryMenuId)"
          type="button"
          role="menuitem"
          :disabled="scanningLibraryId != null"
          @click="libraryMenuId != null && scanOne(libraryMenuId)"
        >
          {{ scanningLibraryId === libraryMenuId ? '扫描中…' : '扫描' }}
        </button>
        <button
          v-if="isAdmin"
          type="button"
          role="menuitem"
          class="danger"
          :disabled="deletingLibraryId === libraryMenuId"
          @click="libraryMenuId != null && removeLibrary(libraryMenuId)"
        >
          {{ deletingLibraryId === libraryMenuId ? '删除中…' : '删除' }}
        </button>
      </div>
    </template>
  </Teleport>
  <div class="shell" :class="{ collapsed: sidebarCollapsed, 'nav-open': navOpen }">
    <button v-if="navOpen" type="button" class="nav-scrim" aria-label="关闭导航" @click="closeNav" />
    <aside class="sidebar" aria-label="资料库">
      <div class="sidebar-top">
        <button
          type="button"
          class="collapse-btn desk-collapse"
          :aria-label="sidebarCollapsed ? '展开侧边栏' : '收起侧边栏'"
          :title="sidebarCollapsed ? '展开' : '收起'"
          @click="toggleSidebar"
        >
          <span aria-hidden="true">{{ sidebarCollapsed ? '›' : '‹' }}</span>
        </button>
        <p class="sidebar-label">导航</p>
        <button type="button" class="drawer-close" @click="closeNav">关闭</button>
      </div>

      <nav class="library-nav">
        <button
          type="button"
          class="library-item"
          :class="{ active: isHome }"
          title="首页"
          @click="goHome"
        >
          <span class="library-icon home-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none">
              <path
                d="M4 10.5L12 4l8 6.5V20a1 1 0 0 1-1 1h-5.5v-6h-3v6H5a1 1 0 0 1-1-1v-9.5z"
                stroke="currentColor"
                stroke-width="1.8"
                stroke-linejoin="round"
              />
            </svg>
          </span>
          <span class="library-text">
            <strong>首页</strong>
          </span>
        </button>

        <TransitionGroup name="library-sort" tag="div" class="library-list">
        <div
          v-for="library in libraries"
          :key="library.id"
          class="library-row"
          :class="{ dragging: draggingLibraryId === library.id }"
          @dragover="onLibraryDragOver(library.id, $event)"
          @drop.prevent="onLibraryDragEnd"
        >
          <button
            v-if="isAdmin"
            type="button"
            class="drag-handle"
            draggable="true"
            title="拖动排序"
            aria-label="拖动排序"
            @dragstart="onLibraryDragStart(library.id, $event)"
            @dragend="onLibraryDragEnd"
            @click.stop
          >
            <span aria-hidden="true" />
          </button>
          <button
            type="button"
            class="library-item"
            :class="{ active: !isHome && library.id === activeLibraryId }"
            :title="library.name"
            @click="selectLibrary(library.id)"
          >
            <span class="library-icon" :data-kind="library.kind" aria-hidden="true">
              <svg v-if="library.kind === 'series'" viewBox="0 0 24 24" fill="none">
                <rect x="3" y="6" width="18" height="13" rx="2" stroke="currentColor" stroke-width="1.8" />
                <path d="M8 3l2.5 3M16 3l-2.5 3" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" />
                <path d="M8 12h8" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" />
              </svg>
              <svg v-else viewBox="0 0 24 24" fill="none">
                <rect x="3" y="5" width="18" height="14" rx="2" stroke="currentColor" stroke-width="1.8" />
                <path
                  d="M8 5v14M16 5v14M3 10h18M3 14h18"
                  stroke="currentColor"
                  stroke-width="1.8"
                  stroke-linecap="round"
                />
              </svg>
            </span>
            <span class="library-text">
              <strong>{{ library.name }}</strong>
              <small>{{ library.kind === 'series' ? '剧集' : '电影' }}</small>
            </span>
          </button>
          <div v-if="showLibraryMenu(library.id)" class="library-more">
            <button
              type="button"
              class="more-btn"
              :aria-expanded="libraryMenuId === library.id"
              :title="`${library.name} 的更多操作`"
              @click.stop="toggleLibraryMenu(library.id, $event)"
            >
              <span aria-hidden="true">···</span>
              <span class="sr-only">更多</span>
            </button>
          </div>
        </div>
        </TransitionGroup>
      </nav>

      <div class="sidebar-foot">
        <button
          v-if="isAdmin"
          type="button"
          class="library-item create"
          title="创建资料库"
          @click="openCreateLibrary"
        >
          <span class="library-icon create-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none">
              <path d="M12 5v14M5 12h14" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" />
            </svg>
          </span>
          <span class="library-text">
            <strong>创建资料库</strong>
          </span>
        </button>
        <button v-if="isAdmin" type="button" class="library-item" title="日志" @click="openLogs">
          <span class="library-icon settings-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none">
              <path d="M6 3h9l3 3v15H6V3z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" />
              <path d="M15 3v3h3" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" />
              <path d="M9 12h6M9 16h4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" />
            </svg>
          </span>
          <span class="library-text">
            <strong>日志</strong>
          </span>
        </button>
        <button type="button" class="library-item" title="设置" @click="openSettings">
          <span class="library-icon settings-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none">
              <circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="1.8" />
              <path
                d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H8a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V8c0 .7.4 1.3 1 1.5H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"
                stroke="currentColor"
                stroke-width="1.8"
                stroke-linejoin="round"
              />
            </svg>
          </span>
          <span class="library-text">
            <strong>设置</strong>
          </span>
        </button>
        <button type="button" class="library-item danger" title="退出登录" @click="logout">
          <span class="library-icon logout-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none">
              <path d="M10 7V5a2 2 0 0 1 2-2h7v18h-7a2 2 0 0 1-2-2v-2" stroke="currentColor" stroke-width="1.8" />
              <path d="M15 12H4m0 0l3-3m-3 3l3 3" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
            </svg>
          </span>
          <span class="library-text">
            <strong>退出登录</strong>
          </span>
        </button>
      </div>
    </aside>

    <div class="main">
      <section v-if="isAdmin && tmdbConfigured === false && !librariesLoading && libraries.length && !homeSearching" class="setup-banner">
        <div>
          <h2>先配置 TMDB API Key</h2>
          <p>没有 Key 时可以浏览已有海报，但新的刮削无法进行。</p>
        </div>
        <button type="button" class="review-link primary" @click="openSettings">去配置</button>
      </section>
      <template v-if="isHome">
        <header class="masthead home-masthead" :class="{ onboarding: noLibraries && !librariesLoading, searching: homeSearching }">
          <div v-if="!homeSearching" class="brand-block">
            <p class="brand-mark">Folio</p>
            <h1>Folio</h1>
            <p v-if="noLibraries && !librariesLoading && isAdmin && tmdbConfigured === false" class="lede">
              先配置 TMDB API Key，刮削才能搜索和建档。
            </p>
            <p v-else-if="noLibraries && !librariesLoading && isAdmin" class="lede">
              还没有资料库。先创建一个，选择本地影视目录，刮削后海报会汇集到这里。
            </p>
            <p v-else-if="noLibraries && !librariesLoading" class="lede">
              还没有资料库。请管理员创建。
            </p>
            <p v-else class="lede">最新刮削的作品会汇总在这里。</p>
          </div>
          <div v-else class="brand-block">
            <button type="button" class="review-link search-back" @click="leaveSearch">
              <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <path d="M15 6l-6 6 6 6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              返回
            </button>
            <h1>搜索</h1>
          </div>
          <div class="controls">
            <button type="button" class="menu-btn" aria-label="打开导航" @click="openNav">
              菜单
            </button>
            <button
              v-if="isAdmin && noLibraries && !librariesLoading && tmdbConfigured === false"
              type="button"
              class="review-link primary"
              @click="openSettings"
            >
              去配置
            </button>
            <button
              v-else-if="isAdmin && noLibraries && !librariesLoading && tmdbConfigured === true"
              type="button"
              class="review-link primary"
              @click="openCreateLibrary"
            >
              创建资料库
            </button>
            <button v-else-if="isAdmin && !librariesLoading && !noLibraries && !homeSearching" type="button" class="review-link" @click="openTasks">
              刮削任务
              <span v-if="taskBadge > 0" class="badge">{{ taskBadge }}</span>
            </button>
            <div v-if="!noLibraries" class="search-line">
              <label class="search">
                <span class="sr-only">搜索全部作品</span>
                <input
                  v-model="homeSearchInput"
                  type="search"
                  placeholder="搜索片名、类型、演职员…"
                  autocomplete="off"
                  @input="onHomeSearchInput"
                />
              </label>
              <BrowseFilters v-if="!homeBooting" class="search-filter" v-model="filters" />
            </div>
          </div>
        </header>

        <div v-if="showHomeStatus && (!noLibraries || error || homeSearching)" class="toolbar">
          <p :class="{ err: !!error && !loading && !homeLoading, loading: homeLoading }">
            <span v-if="homeLoading" class="status-dot" aria-hidden="true" />
            {{ statusText }}
          </p>
        </div>

        <section v-if="homeBooting" class="home-booting" aria-busy="true" aria-label="正在加载">
          <LoadingState />
        </section>

        <template v-else-if="homeSearching">
          <section class="home-section" aria-label="搜索结果">
            <PosterWallSkeleton v-if="homeLoading && !homeResults.length" />
            <div v-else-if="homeResults.length" class="grid">
              <PosterCard
                v-for="(work, index) in homeResults"
                :key="work.id"
                :work="work"
                :index="index"
                :motion="posterMotion"
                @select="openWork"
                @mark-watched="markWork(work, $event)"
              />
            </div>
            <EmptyState
              v-else-if="!homeQuery"
              title="搜索全部作品"
              body="输入片名、类型、年份、演职员或文件名。"
            />
            <EmptyState
              v-else
              title="没有找到相关作品"
              body="换个片名、类型、年份、演职员或文件名试试。"
            />
            <div v-if="homeHasMore" ref="bottomSentinel" class="sentinel" aria-hidden="true" />
          </section>
        </template>

        <template v-else-if="filtering">
          <section v-if="loading" aria-busy="true" aria-label="正在筛选">
            <LoadingState />
          </section>
          <EmptyState
            v-else-if="!items.length"
            title="没有符合筛选的作品"
            body="换一组条件，或清除筛选。"
          />
          <section v-else class="grid" aria-label="筛选结果">
            <PosterCard
              v-for="(work, index) in items"
              :key="work.id"
              :work="work"
              :index="index"
              :motion="posterMotion"
              @select="openWork"
              @mark-watched="markWork(work, $event)"
            />
          </section>
          <div v-if="hasMore" ref="bottomSentinel" class="sentinel" aria-hidden="true" />
        </template>

        <template v-else>
          <section
            v-if="homeContinueOk && continueWatching.length"
            class="home-section"
            aria-label="继续观看"
          >
            <div class="section-head continue-head">
              <h2>继续观看</h2>
              <div v-if="continueShowArrows" class="continue-arrows">
                <button
                  type="button"
                  class="continue-arrow"
                  aria-label="向左滑动"
                  :disabled="!continueCanLeft"
                  @click="scrollContinue(-1)"
                >
                  ‹
                </button>
                <button
                  type="button"
                  class="continue-arrow"
                  aria-label="向右滑动"
                  :disabled="!continueCanRight"
                  @click="scrollContinue(1)"
                >
                  ›
                </button>
              </div>
            </div>
            <div class="continue-shell">
            <div
              ref="continueRailEl"
              class="continue-row"
              @scroll.passive="updateContinueScroll"
            >
              <div
                v-for="item in continueWatching"
                :key="`${item.workId}-${item.libraryFileId}`"
                class="continue-card"
              >
                <button type="button" class="continue-main" @click="openContinue(item)">
                  <span class="continue-poster">
                    <PosterMedia :src="item.posterUrl" :alt="item.workTitle" />
                  </span>
                  <span class="continue-copy">
                    <strong>{{ item.workTitle }}</strong>
                    <small>{{ item.subtitle }}</small>
                  </span>
                </button>
                <button type="button" class="continue-detail" @click="openWork(item.workId)">详情</button>
                <span v-if="item.progressRatio > 0" class="continue-track">
                  <span class="continue-fill" :style="{ width: `${Math.min(100, Math.round(item.progressRatio * 100))}%` }" />
                </span>
              </div>
            </div>
            </div>
          </section>

          <section
            v-if="homeWatchlistOk && watchlist.length"
            class="home-section"
            aria-label="想看"
          >
            <div class="section-head continue-head">
              <h2>想看</h2>
              <div v-if="watchShowArrows" class="continue-arrows">
                <button
                  type="button"
                  class="continue-arrow"
                  aria-label="向左滑动"
                  :disabled="!watchCanLeft"
                  @click="scrollWatch(-1)"
                >
                  ‹
                </button>
                <button
                  type="button"
                  class="continue-arrow"
                  aria-label="向右滑动"
                  :disabled="!watchCanRight"
                  @click="scrollWatch(1)"
                >
                  ›
                </button>
              </div>
            </div>
            <div class="continue-shell">
              <div ref="watchRailEl" class="continue-row" @scroll.passive="updateWatchScroll">
                <button
                  v-for="item in watchlist"
                  :key="item.workId"
                  type="button"
                  class="continue-card watch-card"
                  @click="openWork(item.workId)"
                >
                  <span class="continue-main">
                    <span class="continue-poster">
                      <PosterMedia :src="item.posterUrl" :alt="item.workTitle" />
                    </span>
                    <span class="continue-copy">
                      <strong>{{ item.workTitle }}</strong>
                      <small>{{ item.subtitle }}</small>
                    </span>
                  </span>
                </button>
              </div>
            </div>
          </section>

          <section
            v-if="homePlaylistsOk && playlists.length"
            class="home-section"
            aria-label="播放列表"
          >
            <div class="section-head continue-head">
              <h2>播放列表</h2>
              <div v-if="listShowArrows" class="continue-arrows">
                <button
                  type="button"
                  class="continue-arrow"
                  aria-label="向左滑动"
                  :disabled="!listCanLeft"
                  @click="scrollList(-1)"
                >
                  ‹
                </button>
                <button
                  type="button"
                  class="continue-arrow"
                  aria-label="向右滑动"
                  :disabled="!listCanRight"
                  @click="scrollList(1)"
                >
                  ›
                </button>
              </div>
            </div>
            <div class="continue-shell">
              <div ref="listRailEl" class="continue-row" @scroll.passive="updateListScroll">
                <button
                  v-for="item in playlists"
                  :key="item.id"
                  type="button"
                  class="continue-card watch-card"
                  @click="openPlaylist(item.id)"
                >
                  <span class="continue-main">
                    <span class="continue-poster">
                      <PosterMedia :src="item.posterUrl" :alt="item.name" />
                    </span>
                    <span class="continue-copy">
                      <strong>{{ item.name }}</strong>
                      <small>{{ item.itemCount }} 项</small>
                    </span>
                  </span>
                </button>
              </div>
            </div>
          </section>

          <section v-if="homeRecentOk && recentWorks.length" class="home-section" aria-label="近期作品">
            <div class="section-head">
              <h2>近期作品</h2>
              <p>跨资料库的最新刮削结果</p>
            </div>
            <div class="grid">
              <PosterCard
                v-for="(work, index) in recentWorks"
                :key="work.id"
                :work="work"
                :index="index"
                :motion="posterMotion"
                @select="openWork"
                @mark-watched="markWork(work, $event)"
              />
            </div>
          </section>

          <EmptyState
            v-else-if="homeRecentOk && homeLibrariesOk && libraries.length && !continueWatching.length && !watchlist.length && !playlists.length"
            title="还没有作品海报"
            body="资料库刮削并匹配成功后，会汇总展示在这里。"
          />
        </template>
      </template>

      <template v-else>
        <header class="masthead">
          <div class="brand-block">
            <p class="brand-mark">Folio</p>
            <h1>{{ activeLibrary?.name || '海报墙' }}</h1>
          </div>

          <div class="controls">
            <button type="button" class="menu-btn" aria-label="打开导航" @click="openNav">
              菜单
            </button>
            <label class="search">
              <span class="sr-only">搜索</span>
              <input
                v-model="searchInput"
                type="search"
                placeholder="搜索片名、类型、演职员…"
                autocomplete="off"
                @input="onSearchInput"
              />
            </label>
          </div>
        </header>

        <div class="toolbar">
          <p :class="{ err: !!error && !loading, loading: loading || librariesLoading || collectionsLoading }">
            <span v-if="loading || librariesLoading || collectionsLoading" class="status-dot" aria-hidden="true" />
            {{ statusText }}
          </p>
        </div>

        <BrowseFilters
          v-if="!isMovieLibrary"
          class="library-filters"
          v-model="filters"
          :library-id="activeLibraryId"
        />

        <div v-if="isMovieLibrary" class="library-tabs" role="tablist" aria-label="电影浏览">
          <button type="button" :class="{ active: movieTab === 'all' }" @click="setMovieTab('all')">全部</button>
          <button type="button" :class="{ active: movieTab === 'collections' }" @click="setMovieTab('collections')">
            系列
          </button>
          <BrowseFilters
            v-if="movieTab === 'all'"
            class="tabs-filter"
            v-model="filters"
            :library-id="activeLibraryId"
          />
        </div>

        <template v-if="!isMovieLibrary || movieTab === 'all'">
          <section v-if="loading" aria-busy="true" aria-label="正在加载海报墙">
            <LoadingState />
          </section>

          <EmptyState
            v-else-if="empty"
            :title="filtering ? '没有符合筛选的作品' : '这个资料库还没有作品'"
            :body="filtering ? '换一组条件，或清除筛选。' : '刮削完成后，匹配成功的海报会出现在这里.'"
          />

          <section v-else class="grid" aria-label="海报墙">
            <PosterCard
              v-for="(work, index) in items"
              :key="work.id"
              :work="work"
              :index="index"
              :motion="posterMotion"
              @select="openWork"
              @mark-watched="markWork(work, $event)"
            />
          </section>

          <div v-if="hasMore" ref="bottomSentinel" class="sentinel" aria-hidden="true" />
          <div v-if="loadingMore" class="more-status" role="status" aria-label="正在加载更多">
            <span class="more-spinner" aria-hidden="true" />
          </div>
        </template>

        <template v-else>
          <section v-if="collectionsLoading" aria-busy="true" aria-label="正在加载系列">
            <LoadingState />
          </section>

          <EmptyState
            v-else-if="!visibleCollections.length"
            title="还没有可合并的系列"
            body="同一系列里至少有两部本地电影时，会出现在这里。"
          />

          <section v-else class="grid" aria-label="系列">
            <button
              v-for="item in visibleCollections"
              :key="item.id"
              type="button"
              class="collection-card"
              @click="openCollection(item)"
            >
              <span class="collection-poster">
                <PosterMedia :src="item.posterUrl" :alt="item.name" />
              </span>
              <span class="collection-meta">
                <strong>{{ item.name }}</strong>
                <small>{{ item.count }} 部</small>
              </span>
            </button>
          </section>
        </template>
      </template>
    </div>

    <p v-if="toast" class="toast" role="status">{{ toast }}</p>

    <CreateLibraryDialog
      v-if="showCreateLibrary"
      @close="showCreateLibrary = false"
      @created="onLibraryCreated"
    />
  </div>
</template>

<style scoped>
.shell {
  --rail: 2.35rem;
  --pad-x: 0.7rem;
  --sidebar-expanded: 15rem;
  --sidebar-collapsed: calc(var(--pad-x) * 2 + var(--rail) + 2px);
  --sidebar-ms: 0.32s;
  --sidebar-ease: cubic-bezier(0.4, 0, 0.2, 1);
  display: flex;
  align-items: stretch;
  min-height: 100vh;
}

.sidebar {
  flex: 0 0 var(--sidebar-expanded);
  width: var(--sidebar-expanded);
  min-width: 0;
  position: sticky;
  top: 0;
  height: 100vh;
  display: flex;
  flex-direction: column;
  gap: 0.55rem;
  padding: 1rem var(--pad-x) 1.15rem;
  border-right: 1px solid var(--line);
  background: rgba(10, 12, 16, 0.72);
  backdrop-filter: blur(10px);
  z-index: 3;
  overflow: hidden;
  transition:
    flex-basis var(--sidebar-ms) var(--sidebar-ease),
    width var(--sidebar-ms) var(--sidebar-ease);
}

.shell.collapsed .sidebar {
  flex-basis: var(--sidebar-collapsed);
  width: var(--sidebar-collapsed);
}

.collapse-btn {
  width: var(--rail);
  height: var(--rail);
  flex-shrink: 0;
  border-radius: 10px;
  border: 1px solid var(--line-strong);
  background: rgba(255, 255, 255, 0.03);
  color: var(--ink-muted);
  cursor: pointer;
  display: grid;
  place-items: center;
  font-size: 1.2rem;
  line-height: 1;
}

.collapse-btn:hover {
  border-color: rgba(212, 165, 116, 0.45);
  color: var(--copper);
}

.nav-scrim,
.drawer-close,
.menu-btn {
  display: none;
}

.sidebar-top {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  height: var(--rail);
  width: 100%;
  min-width: 0;
  transition: gap var(--sidebar-ms) var(--sidebar-ease);
}

.sidebar-label {
  margin: 0;
  font-size: 0.78rem;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--ink-faint);
  font-weight: 650;
  overflow: hidden;
  white-space: nowrap;
  min-width: 0;
  flex: 1 1 auto;
  opacity: 1;
  transition: opacity 0.16s ease;
}

.library-list {
  display: grid;
  gap: 0.65rem;
  min-width: 0;
}

.library-sort-move {
  transition: transform 0.22s ease;
  /* 上移穿过指针时不再二次 dragover，避免从上往下拖时把顺序弹回去。 */
  pointer-events: none;
}

.library-row {
  position: relative;
  min-width: 0;
}

.library-row .library-item {
  width: 100%;
}

.library-more {
  position: absolute;
  top: 0;
  right: 0;
  height: var(--rail);
  display: flex;
  align-items: center;
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.18s var(--sidebar-ease);
}

.drag-handle {
  display: grid;
  position: absolute;
  z-index: 1;
  right: 1.7rem;
  top: 0;
  width: 0.9rem;
  height: var(--rail);
  place-items: center;
  border: 0;
  padding: 0;
  background: transparent;
  color: var(--ink-faint);
  cursor: grab;
  opacity: 0;
  transform: translateX(6px) scale(0.92);
  pointer-events: none;
  transition:
    opacity 0.18s var(--sidebar-ease),
    transform 0.18s var(--sidebar-ease);
}

.drag-handle span {
  width: 0.45rem;
  height: 0.7rem;
  background:
    radial-gradient(circle, currentColor 1px, transparent 1.2px) 0 0 / 0.22rem 0.22rem;
}

.drag-handle:active {
  cursor: grabbing;
}

/* 与更多按钮一致：展开到位后再淡入，收起立刻隐去 */
.shell:not(.collapsed) .drag-handle,
.shell:not(.collapsed) .library-more {
  opacity: 1;
  pointer-events: auto;
  transition-delay: var(--sidebar-ms);
}

.shell:not(.collapsed) .drag-handle {
  transform: translateX(0) scale(1);
}

.library-row.dragging {
  z-index: 1;
  opacity: 0.45;
  transition: none;
}

.more-btn {
  width: 1.7rem;
  height: var(--rail);
  border: 0;
  border-radius: 8px;
  background: transparent;
  color: var(--ink-muted);
  cursor: pointer;
  padding: 0;
  font-size: 1.05rem;
  letter-spacing: 0.04em;
  line-height: 1;
}

.more-btn:hover,
.more-btn[aria-expanded='true'] {
  color: var(--copper);
  background: rgba(255, 255, 255, 0.04);
}

.more-scrim {
  position: fixed;
  inset: 0;
  z-index: 40;
  border: 0;
  padding: 0;
  background: transparent;
}

.more-menu {
  position: fixed;
  z-index: 41;
  transform: translateX(-100%);
  min-width: 8rem;
  padding: 0.35rem;
  border-radius: 12px;
  border: 1px solid var(--line-strong);
  background: #161a22;
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.35);
  display: grid;
  gap: 0.15rem;
}

.more-menu button {
  border: 0;
  background: transparent;
  color: var(--ink);
  text-align: left;
  padding: 0.5rem 0.7rem;
  border-radius: 8px;
  cursor: pointer;
  font: inherit;
}

.more-menu button:hover:not(:disabled) {
  background: rgba(255, 255, 255, 0.05);
}

.more-menu button.danger {
  color: #e07a6b;
}

.more-menu button:disabled {
  opacity: 0.55;
  cursor: wait;
}

.library-nav {
  display: grid;
  gap: 0.65rem;
  flex: 1 1 auto;
  align-content: start;
  overflow-x: hidden;
  overflow-y: auto;
  min-height: 0;
  scrollbar-width: none;
}

.library-nav::-webkit-scrollbar {
  width: 0;
  height: 0;
}

.library-item {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  width: 100%;
  height: var(--rail);
  min-height: var(--rail);
  padding: 0;
  border: 0;
  border-radius: 12px;
  background: transparent;
  color: inherit;
  cursor: pointer;
  text-align: left;
  overflow: hidden;
  gap: 0;
}

.library-item:hover {
  background: rgba(255, 255, 255, 0.04);
}

.library-item.active {
  border-color: transparent;
  background: transparent;
}

.sidebar-foot {
  margin-top: auto;
  display: grid;
  gap: 0.65rem;
}

.library-item.create:hover {
  background: rgba(255, 255, 255, 0.04);
}

.library-icon {
  width: var(--rail);
  height: var(--rail);
  border-radius: 10px;
  display: grid;
  place-items: center;
  background: rgba(212, 165, 116, 0.1);
  color: var(--copper);
  border: 1px solid transparent;
  flex-shrink: 0;
}

.library-icon svg {
  width: 1.2rem;
  height: 1.2rem;
  display: block;
}

.home-icon {
  background: rgba(212, 165, 116, 0.1);
  color: var(--copper);
}

.library-item.active .library-icon {
  background: rgba(212, 165, 116, 0.28);
  color: var(--copper);
}

.create-icon,
.settings-icon {
  background: rgba(255, 255, 255, 0.04);
  color: var(--ink-muted);
}

.library-item.danger .library-text strong {
  color: var(--danger);
}

.logout-icon {
  background: rgba(224, 122, 107, 0.12);
  color: var(--danger);
}

.library-text {
  min-width: 0;
  flex: 1 1 auto;
  display: grid;
  align-content: center;
  gap: 0.05rem;
  padding: 0 2.7rem 0 0.55rem;
  overflow: hidden;
  opacity: 1;
  transition: opacity 0.16s ease;
}

.shell.collapsed .sidebar-label,
.shell.collapsed .library-text,
.shell.collapsed .library-more,
.shell.collapsed .drag-handle {
  opacity: 0;
  pointer-events: none;
  transition-delay: 0s;
}

.shell.collapsed .drag-handle {
  transform: translateX(6px) scale(0.92);
}

.library-text strong {
  font-size: 0.9rem;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.library-text small {
  color: var(--ink-faint);
  font-size: 0.75rem;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.main {
  flex: 1 1 auto;
  min-width: 0;
  width: auto;
  max-width: none;
  margin: 0;
  padding: 2.25rem clamp(1rem, 2.2vw, 1.75rem) 4rem;
  transition: padding var(--sidebar-ms) var(--sidebar-ease);
}

.masthead {
  display: grid;
  gap: 1.75rem;
  padding-bottom: 1.5rem;
  border-bottom: 1px solid var(--line);
  animation: fade-down 0.6s cubic-bezier(0.22, 1, 0.36, 1) both;
}

.brand-mark {
  margin: 0 0 0.4rem;
  font-size: 0.75rem;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--teal);
  font-weight: 600;
}

.brand-block h1 {
  margin: 0;
  font-family: var(--font-display);
  font-size: clamp(2.4rem, 6vw, 4.2rem);
  line-height: 0.95;
  letter-spacing: -0.04em;
  background: linear-gradient(120deg, var(--ink) 20%, var(--copper) 85%);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

.lede {
  margin: 0.85rem 0 0;
  max-width: 34rem;
  color: var(--ink-muted);
  font-size: 1.02rem;
  line-height: 1.55;
}

.controls {
  display: flex;
  flex-wrap: wrap;
  gap: 0.85rem;
  align-items: center;
  justify-content: space-between;
}

.search {
  flex: 1 1 240px;
  max-width: 360px;
}

.search input {
  width: 100%;
  height: 2.7rem;
  padding: 0 1rem;
  border-radius: 999px;
  border: 1px solid var(--line-strong);
  background: rgba(18, 21, 28, 0.72);
  outline: none;
  transition:
    border-color 0.2s ease,
    box-shadow 0.2s ease;
}

.search input::placeholder {
  color: var(--ink-faint);
}

.search input:focus {
  border-color: rgba(212, 165, 116, 0.55);
  box-shadow: 0 0 0 3px var(--copper-soft);
}

.search input:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.search-back {
  margin-bottom: 0.85rem;
}

.search-back svg {
  width: 1rem;
  height: 1rem;
}

.search-line {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 0.55rem;
  flex: 1 1 280px;
  min-width: 0;
  max-width: 100%;
}

.search-line .search {
  flex: 1 1 240px;
  min-width: 0;
}

.home-masthead.searching .search-line {
  flex: 1 1 auto;
}

.home-masthead.searching .search-line .search {
  flex: 1 1 auto;
  max-width: none;
}

.search-filter {
  flex: none;
}

.home-masthead .search input {
  view-transition-name: folio-home-search;
}

:global(::view-transition-group(folio-home-search)) {
  animation-duration: 460ms;
  animation-timing-function: cubic-bezier(0.22, 1, 0.36, 1);
}

:global(::view-transition-old(folio-home-search)),
:global(::view-transition-new(folio-home-search)) {
  height: 100%;
  overflow: clip;
  border-radius: 999px;
}

:global(::view-transition-old(root)),
:global(::view-transition-new(root)) {
  animation-duration: 280ms;
  animation-timing-function: cubic-bezier(0.22, 1, 0.36, 1);
}

.setup-banner {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  margin-bottom: 1.25rem;
  padding: 1rem 1.1rem;
  border: 1px solid rgba(212, 165, 116, 0.45);
  border-radius: 14px;
  background: rgba(212, 165, 116, 0.08);
}

.setup-banner h2 {
  margin: 0;
  font-size: 1.05rem;
}

.setup-banner p {
  margin: 0.35rem 0 0;
  color: var(--ink-muted);
  font-size: 0.9rem;
  line-height: 1.45;
}

.home-masthead {
  align-items: end;
}

.review-link {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  border: 1px solid var(--line-strong);
  background: rgba(18, 21, 28, 0.72);
  color: var(--ink);
  padding: 0.55rem 0.95rem;
  border-radius: 999px;
  cursor: pointer;
  font-weight: 650;
  font-size: 0.88rem;
}

.review-link:hover:not(:disabled) {
  border-color: rgba(212, 165, 116, 0.5);
  color: var(--copper);
}

.review-link:disabled {
  opacity: 0.6;
  cursor: wait;
}

.review-link.primary {
  border-color: rgba(212, 165, 116, 0.45);
  background: linear-gradient(135deg, rgba(212, 165, 116, 0.2), rgba(95, 179, 168, 0.12));
}

.home-masthead.onboarding {
  min-height: min(52vh, 420px);
  align-content: center;
  border-bottom: 0;
  padding-bottom: 0.5rem;
}

.home-masthead.onboarding .brand-block h1 {
  font-size: clamp(3.2rem, 9vw, 5.2rem);
}

.home-masthead.onboarding .lede {
  max-width: 28rem;
}


.badge {
  min-width: 1.35rem;
  height: 1.35rem;
  padding: 0 0.35rem;
  border-radius: 999px;
  display: inline-grid;
  place-items: center;
  background: var(--copper);
  color: #1a120a;
  font-size: 0.75rem;
  font-weight: 750;
}

.home-booting {
  display: grid;
  place-items: center;
  min-height: min(52vh, 28rem);
}

.home-booting .status-dot {
  width: 0.7rem;
  height: 0.7rem;
}

.home-section {
  margin-bottom: 2.25rem;
}

.continue-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
}

.continue-arrows {
  display: inline-flex;
  gap: 0.35rem;
  flex-shrink: 0;
}

.continue-arrow {
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
}

.continue-arrow:hover:not(:disabled) {
  border-color: rgba(212, 165, 116, 0.5);
  background: rgba(212, 165, 116, 0.12);
  color: var(--copper);
}

.continue-arrow:disabled {
  opacity: 0.28;
  cursor: default;
}

.continue-shell {
  width: 100%;
  min-width: 0;
  overflow: hidden;
}

.continue-row {
  display: flex;
  gap: 0.85rem;
  width: 100%;
  min-width: 0;
  overflow-x: auto;
  overflow-y: hidden;
  overscroll-behavior-x: contain;
  scrollbar-width: none;
  -ms-overflow-style: none;
}

.continue-row::-webkit-scrollbar {
  display: none;
  width: 0;
  height: 0;
}

.continue-card {
  position: relative;
  flex: 0 0 17rem;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: rgba(18, 21, 28, 0.72);
  overflow: hidden;
}

.continue-main {
  display: grid;
  grid-template-columns: 4.6rem minmax(0, 1fr);
  gap: 0.75rem;
  align-items: center;
  width: 100%;
  margin: 0;
  padding: 0.7rem 3.4rem 0.7rem 0.7rem;
  border: 0;
  background: transparent;
  color: inherit;
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.continue-detail {
  position: absolute;
  top: 0.55rem;
  right: 0.5rem;
  z-index: 1;
  margin: 0;
  padding: 0.15rem 0.5rem;
  border: 1px solid var(--line-strong);
  border-radius: 999px;
  background: rgba(10, 12, 16, 0.78);
  color: var(--ink-muted);
  font: inherit;
  font-size: 0.75rem;
  line-height: 1.4;
  cursor: pointer;
}

.continue-detail:hover {
  color: var(--copper);
  border-color: rgba(212, 165, 116, 0.55);
}

.continue-card:hover {
  border-color: rgba(212, 165, 116, 0.45);
}

.watch-card {
  padding: 0;
  color: inherit;
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.watch-card .continue-main {
  padding-right: 0.7rem;
}

.continue-poster {
  width: 4.6rem;
  aspect-ratio: 2 / 3;
  border-radius: 8px;
  overflow: hidden;
  background: var(--bg-soft);
}

.continue-copy {
  display: grid;
  gap: 0.25rem;
  min-width: 0;
}

.continue-copy strong,
.continue-copy small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.continue-copy small {
  color: var(--ink-faint);
  font-size: 0.8rem;
}

.continue-track {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  height: 3px;
  background: rgba(242, 239, 232, 0.12);
}

.continue-fill {
  display: block;
  height: 100%;
  background: var(--copper);
}

.section-head {
  margin-bottom: 1rem;
}

.section-head h2 {
  margin: 0;
  font-family: var(--font-display);
  font-size: 1.15rem;
  letter-spacing: 0.04em;
  color: var(--copper);
  text-transform: uppercase;
}

.section-head p {
  margin: 0.35rem 0 0;
  color: var(--ink-faint);
  font-size: 0.9rem;
}

.empty.soft {
  border-style: solid;
  background: rgba(18, 21, 28, 0.28);
}

.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 1rem;
  flex-wrap: wrap;
  margin: 1.1rem 0 1.35rem;
  min-height: 1.4rem;
  color: var(--ink-faint);
  font-size: 0.88rem;
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

.toolbar p {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  margin: 0;
}

.toolbar .err {
  color: var(--danger);
}

.toolbar .loading {
  color: var(--ink-muted);
}

.status-dot {
  width: 0.45rem;
  height: 0.45rem;
  border-radius: 50%;
  background: var(--copper);
  box-shadow: 0 0 0 0 rgba(212, 165, 116, 0.45);
  animation: pulse-dot 1.4s ease-out infinite;
}

.library-filters {
  margin: 0 0 1.35rem;
}

.library-tabs {
  display: flex;
  align-items: center;
  gap: 0.45rem;
  margin: 1.25rem 0 1.35rem;
}

.tabs-filter {
  margin-left: auto;
}

.library-tabs button {
  border: 1px solid var(--line-strong);
  background: transparent;
  color: var(--ink-muted);
  border-radius: 999px;
  padding: 0.4rem 0.9rem;
  cursor: pointer;
  font-weight: 650;
}

.library-tabs button.active {
  color: var(--copper);
  border-color: rgba(212, 165, 116, 0.55);
  background: rgba(212, 165, 116, 0.12);
}

.back-collections {
  display: flex;
  width: fit-content;
  margin: 1.15rem 0 1.5rem;
  border: 0;
  background: transparent;
  color: var(--ink-muted);
  cursor: pointer;
  padding: 0.2rem 0;
  font-weight: 650;
}

.back-collections:hover {
  color: var(--copper);
}

.collection-card {
  display: grid;
  gap: 0.55rem;
  text-align: left;
  border: 0;
  background: transparent;
  color: inherit;
  cursor: pointer;
  padding: 0;
}

.collection-poster {
  display: block;
  aspect-ratio: 2 / 3;
  border-radius: 12px;
  overflow: hidden;
  background: var(--bg-soft);
}

.collection-poster img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.collection-fallback {
  display: grid;
  place-items: center;
  height: 100%;
  color: var(--ink-faint);
}

.collection-meta {
  display: grid;
  gap: 0.15rem;
}

.collection-meta strong {
  font-size: 0.92rem;
}

.collection-meta small {
  color: var(--ink-muted);
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(148px, 1fr));
  gap: 1.35rem 1rem;
}

.empty {
  padding: 4.5rem 1rem;
  text-align: center;
  border: 1px dashed var(--line-strong);
  border-radius: var(--radius);
  background: rgba(18, 21, 28, 0.4);
}

.empty h2 {
  margin: 0;
  font-family: var(--font-display);
}

.empty p {
  margin: 0.6rem 0 0;
  color: var(--ink-muted);
}

.empty-cta {
  margin-top: 1.25rem;
  height: 2.6rem;
  padding: 0 1.25rem;
  border-radius: 999px;
  border: 1px solid rgba(212, 165, 116, 0.4);
  background: linear-gradient(135deg, rgba(212, 165, 116, 0.18), rgba(95, 179, 168, 0.12));
  color: var(--ink);
  font-weight: 600;
  cursor: pointer;
}

.sentinel {
  height: 1px;
}

.more-status {
  display: flex;
  justify-content: center;
  margin: 1.5rem 0 0;
}

.more-spinner {
  width: 1.25rem;
  height: 1.25rem;
  border: 2px solid rgba(212, 165, 116, 0.28);
  border-top-color: #d4a574;
  border-radius: 50%;
  animation: more-spin 0.8s linear infinite;
}

@keyframes more-spin {
  to {
    transform: rotate(360deg);
  }
}

.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  border: 0;
}

@keyframes fade-down {
  from {
    opacity: 0;
    transform: translateY(-12px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
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

@media (max-width: 900px) {
  .shell .sidebar,
  .shell.collapsed .sidebar {
    flex-basis: var(--sidebar-collapsed);
    width: var(--sidebar-collapsed);
  }

  .sidebar-top,
  .library-item {
    gap: 0;
  }

  .sidebar-label,
  .library-text,
  .shell .library-more,
  .shell .drag-handle {
    opacity: 0;
    pointer-events: none;
    transition-delay: 0s;
  }

  .shell .drag-handle {
    transform: translateX(6px) scale(0.92);
  }

  .main {
    padding-top: 1.5rem;
  }

  .grid {
    grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
    gap: 1rem 0.75rem;
  }
}

@media (max-width: 720px) {
  .setup-banner {
    flex-direction: column;
    align-items: stretch;
  }

  .shell,
  .shell.collapsed {
    display: block;
  }

  .nav-scrim {
    display: block;
    position: fixed;
    inset: 0;
    z-index: 20;
    border: 0;
    background: rgba(4, 6, 10, 0.55);
    backdrop-filter: blur(4px);
  }

  .sidebar,
  .shell.collapsed .sidebar {
    position: fixed;
    left: 0;
    top: 0;
    width: min(19rem, calc(100vw - 2.75rem));
    height: 100dvh;
    transform: translateX(-105%);
    transition: transform 0.22s ease;
    padding-top: calc(0.85rem + var(--safe-top));
    padding-bottom: calc(1.1rem + var(--safe-bottom));
    padding-left: 0.85rem;
    padding-right: 0.85rem;
    align-items: stretch;
    gap: 0.75rem;
    z-index: 30;
  }

  .sidebar-top,
  .library-nav,
  .sidebar-foot,
  .shell.collapsed .sidebar-top,
  .shell.collapsed .library-nav,
  .shell.collapsed .sidebar-foot {
    width: 100%;
    min-width: 0;
    justify-content: flex-start;
    justify-items: stretch;
  }

  .sidebar-label,
  .library-text,
  .shell.collapsed .sidebar-label,
  .shell.collapsed .library-text {
    opacity: 1;
    pointer-events: auto;
  }

  .shell .library-more,
  .shell.collapsed .library-more {
    display: flex;
    opacity: 1;
    pointer-events: auto;
    transition-delay: 0s;
  }

  .shell .drag-handle,
  .shell.collapsed .drag-handle {
    display: grid;
    opacity: 1;
    transform: translateX(0) scale(1);
    pointer-events: auto;
    transition-delay: 0s;
  }

  .sidebar-foot {
    gap: 0.65rem;
  }

  .shell.nav-open .sidebar {
    transform: translateX(0);
  }

  .desk-collapse {
    display: none;
  }

  .drawer-close,
  .menu-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  .drawer-close {
    margin-left: auto;
    border: 1px solid var(--line-strong);
    background: transparent;
    color: var(--ink-muted);
    border-radius: 999px;
    padding: 0.35rem 0.75rem;
    cursor: pointer;
    font-weight: 650;
    font-size: 0.82rem;
  }

  .menu-btn {
    border: 1px solid var(--line-strong);
    background: rgba(18, 21, 28, 0.72);
    color: var(--ink);
    border-radius: 999px;
    padding: 0.55rem 0.95rem;
    cursor: pointer;
    font-weight: 650;
    font-size: 0.88rem;
  }

  .library-item,
  .shell.collapsed .library-item {
    width: 100%;
    height: var(--rail);
    min-height: var(--rail);
    padding: 0;
  }

  .main {
    width: 100%;
    padding: calc(1rem + var(--safe-top)) 0.9rem calc(2.5rem + var(--safe-bottom));
  }

  .masthead {
    gap: 1rem;
    padding-bottom: 1rem;
  }

  .brand-block h1 {
    font-size: clamp(2rem, 11vw, 2.8rem);
  }

  .lede {
    font-size: 0.95rem;
  }

  .home-masthead.onboarding {
    min-height: 0;
  }

  .controls {
    justify-content: flex-start;
    gap: 0.55rem;
  }

  .search-line {
    flex: 1 1 100%;
    max-width: none;
  }

  .search-line .search,
  .search {
    flex: 1 1 auto;
    max-width: none;
  }

  .search-filter {
    flex: none;
  }

  .grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 0.9rem 0.65rem;
  }
}

@media (prefers-reduced-motion: reduce) {
  .shell,
  .masthead,
  .sidebar-top,
  .sidebar-label,
  .library-item,
  .library-text,
  .library-sort-move {
    transition: none;
    animation: none;
  }
}
</style>
