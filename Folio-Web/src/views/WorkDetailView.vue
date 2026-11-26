<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { confirmManualMatch, getCollection, getSeason, getWork, getWorkByExternal, getWorkPlayback, getWorkWanted, getWorkWatch, putWorkWanted, putWorkWatch, refreshWork } from '../api/client'
import { subscribeScrapeEvents } from '../api/events'
import type { ArtworkView, CollectionPart, CreditView, MatchCandidate, PersonView, PlaybackProgress, RatingView, ReviewFileRow, ScrapeJobRow, WorkView } from '../api/types'
import ArtworkRail from '../components/ArtworkRail.vue'
import ManualMatchDialog from '../components/ManualMatchDialog.vue'
import PlaylistPickerDialog from '../components/PlaylistPickerDialog.vue'
import VideoInfoDialog from '../components/VideoInfoDialog.vue'
import PeopleRail from '../components/PeopleRail.vue'
import type { PersonItem } from '../components/PeopleRail.vue'
import PosterMedia from '../components/PosterMedia.vue'
import WorkDetailSkeleton from '../components/WorkDetailSkeleton.vue'
import { currentUser } from '../auth/session'
import { useArtworkTint } from '../lib/artworkColor'
import { noteWatch, noteWatchlist } from '../lib/watchMarks'

const route = useRoute()
const router = useRouter()
const isAdmin = computed(() => currentUser.value?.role === 'ADMIN')
const canRematch = computed(
  () =>
    isAdmin.value ||
    (currentUser.value?.libraries ?? []).some((item) => item.access === 'WRITE'),
)

const loading = ref(true)
const refreshing = ref(false)
const error = ref<string | null>(null)
const actionError = ref<string | null>(null)
const work = ref<WorkView | null>(null)
const collectionParts = ref<CollectionPart[]>([])
const rematchOpen = ref(false)
const playlistOpen = ref(false)
const videoInfoOpen = ref(false)
const moreOpen = ref(false)
const moreWrap = ref<HTMLElement | null>(null)
let unsubscribeEvents: (() => void) | null = null
let reloadTimer: number | null = null

const libraryFiles = computed(() => work.value?.libraryFiles ?? [])
const resumeFileId = ref<number | null>(null)
const seriesProgress = ref<PlaybackProgress | null>(null)
const openingPlay = ref(false)
const fileChoices = ref<ReviewFileRow[] | null>(null)
const moviePlayable = computed(() => work.value?.kind !== 'series' && libraryFiles.value.length > 0)
const seriesPlayable = computed(
  () => work.value?.kind === 'series' && work.value.seasons.some((season) => season.localEpisodeCount > 0),
)
const resumeTargetId = computed(() => {
  const id = resumeFileId.value
  if (id == null) return null
  return libraryFiles.value.some((file) => file.id === id) ? id : null
})
const seriesHint = computed(() => {
  const progress = seriesProgress.value
  if (!progress || work.value?.kind !== 'series') return ''
  const label =
    progress.seasonNumber != null && progress.episodeNumber != null
      ? `S${progress.seasonNumber}E${progress.episodeNumber}`
      : ''
  if (progress.resumePositionMs != null && progress.resumePositionMs > 0) {
    return [label, `已看至 ${formatClock(progress.resumePositionMs)}`].filter(Boolean).join(' · ')
  }
  if (label) return `${label} · 下一集`
  return '继续播放'
})

const hasTmdb = computed(() =>
  !!work.value?.externalIds.some((item) => item.provider.trim().toLowerCase() === 'tmdb'),
)

const canRefreshMetadata = computed(
  () => hasTmdb.value && libraryFiles.value.length === 0 && !refreshing.value,
)

const watchState = ref<string | null>(null)
const marking = ref(false)
const wanted = ref(false)
const wanting = ref(false)

const showMoreMenu = computed(() => {
  if (!work.value) return false
  if (!isExternalEntry.value) return true
  const rematch = canRematch.value && libraryFiles.value.length > 0
  const refreshMeta = hasTmdb.value && libraryFiles.value.length === 0
  const video = work.value.kind !== 'series' && libraryFiles.value.length > 0
  return rematch || refreshMeta || video
})

const markLabel = computed(() => {
  const series = work.value?.kind === 'series'
  if (watchState.value === 'watched') return series ? '整部标为未看' : '标为未看'
  return series ? '整部标为已看' : '标为已看'
})

const isExternalEntry = computed(() => route.name === 'work-external')

function pickLocalized(field: 'overview' | 'tagline' | 'title'): string {
  if (!work.value) return ''
  return work.value.translations.find((t) => t.locale === 'zh-CN' && t[field])?.[field] ?? ''
}

const title = computed(() => {
  if (!work.value) return ''
  return pickLocalized('title') || work.value.originalTitle
})

const overview = computed(() => pickLocalized('overview'))

const tagline = computed(() => pickLocalized('tagline'))

const posterUrl = computed(() => {
  const arts = work.value?.artworks ?? []
  return (
    arts.find((a) => a.kind === 'poster' && a.locale === 'zh-CN')?.remoteUrl ??
    arts.find((a) => a.kind === 'poster')?.remoteUrl ??
    null
  )
})

const backdropUrl = computed(
  () => work.value?.artworks.find((a) => a.kind === 'backdrop')?.remoteUrl ?? null,
)

const tintSource = computed(() => backdropUrl.value ?? posterUrl.value)
const { pageStyle } = useArtworkTint(tintSource)

const imdbUrl = computed(() => {
  const id = work.value?.externalIds.find((item) => item.provider === 'imdb')?.externalId
  return id ? `https://www.imdb.com/title/${id}` : null
})

const heroRatings = computed(() => {
  const rows = work.value?.ratings ?? []
  const rank = (provider: string) => {
    if (provider === 'imdb') return 0
    if (provider === 'rottentomatoes') return 1
    if (provider === 'rt_audience') return 2
    if (provider === 'metacritic') return 3
    if (provider === 'tmdb') return 4
    return 5
  }
  return [...rows].sort((a, b) => rank(a.provider) - rank(b.provider) || a.provider.localeCompare(b.provider))
})

const facts = computed(() => {
  const w = work.value
  if (!w) return []
  const rows: { label: string; value: string; href?: string }[] = []
  const push = (label: string, value: string | null | undefined, href?: string) => {
    if (value == null || value === '') return
    rows.push(href ? { label, value, href } : { label, value })
  }

  push('ID', String(w.id))
  push('类型', w.kind === 'series' ? '剧集' : '电影')
  push('来源', w.sourceProvider ? w.sourceProvider.toUpperCase() : null)
  push('原始片名', w.originalTitle)
  push('原始语言', w.originalLanguage)
  push('年份', w.year != null ? String(w.year) : null)
  push('首映/首播', w.premiereDate)
  push('最后播出', w.lastAirDate)
  push('片长', w.runtimeMinutes != null ? `${w.runtimeMinutes} 分钟` : null)
  push('状态', w.status)
  push('节目形态', w.showType)
  push('制作中', formatBool(w.inProduction))
  push('成人内容', formatBool(w.adult))
  push('季数', w.numberOfSeasons != null ? String(w.numberOfSeasons) : null)
  push('集数', w.numberOfEpisodes != null ? String(w.numberOfEpisodes) : null)
  push('热度', w.popularity != null ? Number(w.popularity).toFixed(3) : null)
  push('预算', formatMoney(w.budget))
  push('票房', formatMoney(w.revenue))
  push('系列', w.collectionName)
  push('系列 ID', w.collectionExternalId)
  push('奖项', w.awards)
  push('官网', w.homepage, w.homepage ?? undefined)
  return rows
})

const castItems = computed<PersonItem[]>(() =>
  (work.value?.credits ?? [])
    .filter((c) => isCast(c))
    .slice()
    .sort((a, b) => a.order - b.order)
    .map((c) => ({
      key: `cast-${c.externalId}-${c.order}-${c.character}`,
      name: c.name,
      subtitle: c.character || '—',
      imageUrl: c.profileUrl,
      provider: c.provider,
      externalId: c.externalId,
    })),
)

const crewItems = computed<PersonItem[]>(() =>
  (work.value?.credits ?? [])
    .filter((c) => !isCast(c))
    .slice()
    .sort((a, b) => a.order - b.order || a.name.localeCompare(b.name))
    .map((c) => ({
      key: `crew-${c.externalId}-${c.order}-${c.job}`,
      name: c.name,
      subtitle: c.job || c.department || '—',
      imageUrl: c.profileUrl,
      provider: c.provider,
      externalId: c.externalId,
    })),
)

const peopleItems = computed<PersonItem[]>(() =>
  (work.value?.people ?? []).map((person) => ({
    key: `people-${person.provider}-${person.externalId}`,
    name: person.name,
    subtitle: `${person.provider.toUpperCase()} · ${person.externalId}`,
    imageUrl: personImage(person),
    provider: person.provider,
    externalId: person.externalId,
  })),
)

const artworksByKind = computed(() => {
  const map = new Map<string, ArtworkView[]>()
  for (const art of work.value?.artworks ?? []) {
    const list = map.get(art.kind) ?? []
    list.push(art)
    map.set(art.kind, list)
  }
  return [...map.entries()].map(([kind, items]) => ({ kind, items }))
})

const companyRoleLabel: Record<string, string> = {
  production: '制片',
  network: '播出网络',
  distributor: '发行',
}

function isCast(credit: CreditView) {
  return Boolean(credit.character) || credit.department === 'Acting' || credit.job === 'Actor'
}

function formatBool(value: boolean | null | undefined) {
  if (value == null) return null
  return value ? '是' : '否'
}

function formatMoney(value: number | null | undefined) {
  if (value == null) return null
  return new Intl.NumberFormat('zh-CN', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0,
  }).format(value)
}

function artworkKindLabel(kind: string) {
  const map: Record<string, string> = {
    poster: '海报',
    backdrop: '背景',
    still: '剧照',
    logo: 'Logo',
    collection_poster: '系列海报',
    collection_backdrop: '系列背景',
  }
  return map[kind] ?? kind
}

function videoUrl(site: string | null, key: string | null) {
  if (!key) return null
  const s = (site ?? '').toLowerCase()
  if (s.includes('youtube')) return `https://www.youtube.com/watch?v=${key}`
  if (s.includes('vimeo')) return `https://vimeo.com/${key}`
  return null
}

function ratingKind(provider: string) {
  if (provider === 'rottentomatoes') return '影评'
  if (provider === 'rt_audience') return '观众'
  return ''
}

function ratingHint(provider: string) {
  if (provider === 'rottentomatoes') return '烂番茄影评人评分'
  if (provider === 'rt_audience') return '烂番茄观众评分'
  return ''
}

function formatRating(row: RatingView) {
  if (row.provider === 'rottentomatoes' || row.provider === 'rt_audience') {
    return `${Math.round(Number(row.value))}%`
  }
  if (row.provider === 'metacritic' || Number(row.scale) === 100) {
    return String(Math.round(Number(row.value)))
  }
  return Number(row.value).toFixed(1)
}

function externalId(provider: string) {
  return work.value?.externalIds.find((item) => item.provider === provider)?.externalId ?? null
}

function ratingHref(provider: string) {
  const current = work.value
  if (!current) return null
  if (provider === 'imdb') return imdbUrl.value
  if (provider === 'tmdb') {
    const id = externalId('tmdb')
    if (!id) return null
    return current.kind === 'series'
      ? `https://www.themoviedb.org/tv/${id}`
      : `https://www.themoviedb.org/movie/${id}`
  }
  if (provider === 'tvdb') {
    const id = externalId('tvdb')
    return id ? `https://www.thetvdb.com/?tab=series&id=${id}` : null
  }
  if (provider === 'rottentomatoes' || provider === 'rt_audience') {
    const stored = externalId('rottentomatoes')
    if (stored?.startsWith('http://') || stored?.startsWith('https://')) return stored
    const query = current.originalTitle || title.value
    if (!query) return null
    return `https://www.rottentomatoes.com/search?search=${encodeURIComponent(query)}`
  }
  return null
}

function providerTitle(provider: string) {
  const labels: Record<string, string> = {
    tmdb: 'TMDB',
    tvdb: 'TVDB',
    imdb: 'IMDb',
    rottentomatoes: '烂番茄',
    rt_audience: '观众',
    metacritic: 'Metacritic',
    wikidata: 'Wikidata',
    facebook: 'Facebook',
    instagram: 'Instagram',
    twitter: 'X',
    tvrage: 'TVRage',
    freebase: 'Freebase',
  }
  return labels[provider] ?? provider.toUpperCase()
}

function externalUrl(provider: string, id: string) {
  if (id.startsWith('http://') || id.startsWith('https://')) return id
  switch (provider) {
    case 'tmdb':
      return work.value?.kind === 'series'
        ? `https://www.themoviedb.org/tv/${id}`
        : `https://www.themoviedb.org/movie/${id}`
    case 'imdb':
      return `https://www.imdb.com/title/${id}`
    case 'tvdb':
      return `https://www.thetvdb.com/?tab=series&id=${id}`
    case 'wikidata':
      return `https://www.wikidata.org/wiki/${id}`
    case 'facebook':
      return `https://www.facebook.com/${id}`
    case 'instagram':
      return `https://www.instagram.com/${id}`
    case 'twitter':
      return `https://twitter.com/${id}`
    default:
      return null
  }
}

function personImage(person: PersonView) {
  return (
    person.profileUrl ||
    person.images.find((i) => i.kind === 'poster' || i.kind === 'still')?.remoteUrl ||
    person.images[0]?.remoteUrl ||
    null
  )
}

function seasonPoster(artworks: { kind: string; remoteUrl: string }[]) {
  return (
    artworks.find((a) => a.kind === 'poster')?.remoteUrl ??
    artworks.find((a) => a.kind === 'still')?.remoteUrl ??
    artworks[0]?.remoteUrl ??
    null
  )
}

function seasonHeading(season: { seasonNumber: number; name: string | null }) {
  const base = `第 ${season.seasonNumber} 季`
  const name = season.name?.trim()
  if (!name || name === base || /^season\s*\d+$/i.test(name)) return base
  return `${base} ${name}`
}

function libraryQuery() {
  const raw = route.query.library
  const value = Array.isArray(raw) ? raw[0] : raw
  const id = Number(value)
  return Number.isInteger(id) && id > 0 ? { library: String(id) } : {}
}

function partTime(part: CollectionPart): number {
  if (part.releaseDate) {
    const ms = Date.parse(part.releaseDate)
    if (!Number.isNaN(ms)) return ms
  }
  if (part.year != null) return Date.UTC(part.year, 0, 1)
  return Number.POSITIVE_INFINITY
}

function sortParts(parts: CollectionPart[]): CollectionPart[] {
  return parts.slice().sort((a, b) => {
    const local = Number(b.hasLocalMedia) - Number(a.hasLocalMedia)
    if (local !== 0) return local
    return partTime(a) - partTime(b) || a.title.localeCompare(b.title)
  })
}

async function loadCollection(collectionId: string | null | undefined) {
  const id = collectionId?.trim()
  if (!id) {
    collectionParts.value = []
    return
  }
  try {
    const detail = await getCollection(id)
    collectionParts.value = sortParts(detail.parts)
  } catch {
    collectionParts.value = []
  }
}

function isCurrentPart(part: CollectionPart) {
  return part.workId != null && part.workId === work.value?.id
}

function openPart(part: CollectionPart) {
  if (isCurrentPart(part)) return
  if (part.workId != null) {
    void router.push({
      name: 'work',
      params: { id: String(part.workId) },
      query: libraryQuery(),
    })
    return
  }
  const externalId = part.tmdbId.trim()
  if (!externalId) return
  void router.push({
    name: 'work-external',
    query: {
      ...libraryQuery(),
      provider: 'tmdb',
      externalId,
      kind: 'movie',
    },
  })
}

function goToCollection() {
  const id = work.value?.collectionExternalId?.trim()
  if (!id) return
  void router.push({
    name: 'collection',
    params: { id },
    query: libraryQuery(),
  })
}

function goToSeason(seasonNumber: number) {
  if (!work.value) return
  void router.push({
    name: 'season',
    params: { id: String(work.value.id), seasonNumber: String(seasonNumber) },
    query: libraryQuery(),
  })
}

function queryParam(name: string): string {
  const raw = route.query[name]
  const value = Array.isArray(raw) ? raw[0] : raw
  return typeof value === 'string' ? value.trim() : ''
}

async function load(id: number) {
  if (!Number.isFinite(id)) {
    error.value = '无效的作品 ID'
    loading.value = false
    return
  }
  loading.value = true
  error.value = null
  actionError.value = null
  work.value = null
  collectionParts.value = []
  resumeFileId.value = null
  seriesProgress.value = null
  fileChoices.value = null
  watchState.value = null
  wanted.value = false
  try {
    work.value = await getWork(id)
    void loadWatch(id)
    void loadPlayback(work.value)
    await loadCollection(work.value.collectionExternalId)
  } catch (e) {
    error.value = e instanceof Error ? e.message : '详情加载失败'
  } finally {
    loading.value = false
  }
}

async function loadByExternal() {
  const provider = queryParam('provider') || 'tmdb'
  const externalId = queryParam('externalId')
  const kind = queryParam('kind')
  if (!externalId || !kind) {
    error.value = '无效的作品参数'
    loading.value = false
    return
  }
  loading.value = true
  error.value = null
  actionError.value = null
  work.value = null
  collectionParts.value = []
  resumeFileId.value = null
  seriesProgress.value = null
  fileChoices.value = null
  try {
    const detail = await getWorkByExternal({ provider, externalId, kind })
    work.value = detail
    void loadPlayback(detail)
    await loadCollection(detail.collectionExternalId)
    void router.replace({
      name: 'work',
      params: { id: String(detail.id) },
      query: libraryQuery(),
    })
  } catch (e) {
    error.value = e instanceof Error ? e.message : '详情加载失败'
  } finally {
    loading.value = false
  }
}

async function loadWatch(id: number) {
  try {
    const row = await getWorkWatch(id)
    if (work.value?.id === id) watchState.value = row.watchState
  } catch {
    if (work.value?.id === id) watchState.value = null
  }
  try {
    const row = await getWorkWanted(id)
    if (work.value?.id === id) wanted.value = row.wanted
  } catch {
    if (work.value?.id === id) wanted.value = false
  }
}

async function markWatched() {
  const current = work.value
  if (!current || marking.value) return
  marking.value = true
  actionError.value = null
  try {
    const row = await putWorkWatch(current.id, watchState.value !== 'watched')
    watchState.value = row.watchState
    noteWatch(current.id, row.watchState)
    void loadPlayback(current)
  } catch (e) {
    actionError.value = e instanceof Error ? e.message : '标记失败'
  } finally {
    marking.value = false
  }
}

async function toggleWanted() {
  const current = work.value
  if (!current || wanting.value) return
  wanting.value = true
  actionError.value = null
  try {
    const row = await putWorkWanted(current.id, !wanted.value)
    if (work.value?.id === current.id) wanted.value = row.wanted
    noteWatchlist()
  } catch (e) {
    actionError.value = e instanceof Error ? e.message : '想看保存失败'
  } finally {
    wanting.value = false
  }
}

function formatClock(ms: number) {
  const total = Math.max(0, Math.floor(ms / 1000))
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const seconds = total % 60
  if (hours > 0) return `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
  return `${minutes}:${String(seconds).padStart(2, '0')}`
}

async function loadPlayback(current: WorkView) {
  resumeFileId.value = null
  seriesProgress.value = null
  if (current.kind === 'series') {
    if (!current.seasons.some((season) => season.localEpisodeCount > 0)) return
    try {
      const progress = await getWorkPlayback(current.id)
      if (work.value?.id !== current.id) return
      seriesProgress.value = progress
    } catch {
      // 没有进度时从第一集播放
    }
    return
  }
  if (current.libraryFiles.length === 0) return
  try {
    const progress = await getWorkPlayback(current.id)
    if (work.value?.id !== current.id) return
    if (progress?.resumePositionMs != null && progress.resumePositionMs > 0) {
      resumeFileId.value = progress.libraryFileId
    }
  } catch {
    // 没有进度时只显示播放
  }
}

function openFile(fileId: number) {
  fileChoices.value = null
  void router.push({ name: 'play', params: { fileId: String(fileId) } })
}

async function openSeries() {
  const current = work.value
  if (!current || openingPlay.value) return
  const progress = seriesProgress.value
  if (progress?.libraryFileId) {
    openFile(progress.libraryFileId)
    return
  }
  const season = [...current.seasons]
    .filter((item) => item.localEpisodeCount > 0)
    .sort((a, b) => a.seasonNumber - b.seasonNumber)[0]
  if (!season) return
  openingPlay.value = true
  actionError.value = null
  try {
    const detail = await getSeason(current.id, season.seasonNumber)
    if (work.value?.id !== current.id) return
    const episode = detail.season.episodes.find((item) => item.files.length > 0)
    const files = episode?.files ?? []
    if (!files.length) {
      actionError.value = '没有可播放的剧集'
      return
    }
    if (files.length === 1) {
      openFile(files[0].id)
      return
    }
    fileChoices.value = files
  } catch (e) {
    actionError.value = e instanceof Error ? e.message : '播放失败'
  } finally {
    openingPlay.value = false
  }
}

function openMovie() {
  const id = resumeTargetId.value ?? libraryFiles.value[0]?.id
  if (!id) return
  void router.push({
    name: 'play',
    params: { fileId: String(id) },
  })
}

async function refreshMetadata() {
  const current = work.value
  if (!current || !canRefreshMetadata.value) return
  closeMore()
  refreshing.value = true
  actionError.value = null
  try {
    work.value = await refreshWork(current.id)
    await loadCollection(work.value.collectionExternalId)
  } catch (e) {
    actionError.value = e instanceof Error ? e.message : '刷新元数据失败'
  } finally {
    refreshing.value = false
  }
}

function resolveRouteLoad() {
  closeMore()
  if (isExternalEntry.value) {
    void loadByExternal()
    return
  }
  const id = route.params.id
  if (typeof id === 'string' && id) void load(Number(id))
}

function goBack() {
  // 按钮语义是回海报墙；勿用 history.back，否则从季详情返回后会再回到季详情
  void router.push({ name: 'wall', query: libraryQuery() })
}

function toggleMore() {
  moreOpen.value = !moreOpen.value
}

function closeMore() {
  moreOpen.value = false
}

function onDocPointerDown(event: PointerEvent) {
  const el = moreWrap.value
  if (!el || !moreOpen.value) return
  if (event.target instanceof Node && !el.contains(event.target)) {
    closeMore()
  }
}

function openRematch() {
  if (!libraryFiles.value.length) return
  closeMore()
  rematchOpen.value = true
}

function openVideoInfo() {
  closeMore()
  videoInfoOpen.value = true
}

function onVideoInfoUpdated(next: ReviewFileRow[]) {
  if (!work.value) return
  const byId = new Map(next.map((file) => [file.id, file]))
  work.value = {
    ...work.value,
    libraryFiles: work.value.libraryFiles.map((file) => byId.get(file.id) ?? file),
  }
}

function closeRematch() {
  rematchOpen.value = false
}

function onMatchFinished(job: ScrapeJobRow) {
  const current = work.value
  if (!current || job.matchStatus !== 'matched' || job.workId == null) return
  if (job.workId !== current.id) {
    if (!current.libraryFiles.some((file) => file.id === job.fileId)) return
    void router.replace({ name: 'work', params: { id: String(job.workId) } })
    return
  }
  if (reloadTimer != null) window.clearTimeout(reloadTimer)
  reloadTimer = window.setTimeout(() => {
    reloadTimer = null
    if (work.value?.id === current.id) void load(current.id)
  }, 400)
}

function onConfirmMatch(
  candidate: MatchCandidate,
  options: { fileId: number; year?: number; season?: number; episode?: number; scope?: 'file' | 'work' },
) {
  rematchOpen.value = false
  void confirmManualMatch(options.fileId, {
    kind: candidate.kind,
    tmdbId: Number(candidate.externalId),
    year: options.year,
    season: options.season,
    episode: options.episode,
    scope: options.scope,
  }).catch((e) => {
    error.value = e instanceof Error ? e.message : '匹配失败'
  })
}

watch(
  () => [route.name, route.params.id, route.query.provider, route.query.externalId, route.query.kind] as const,
  () => {
    // replace 到 /works/:id 时不要重复拉取
    if (route.name === 'work' && work.value != null && String(work.value.id) === String(route.params.id)) {
      return
    }
    resolveRouteLoad()
  },
)

onMounted(() => {
  document.addEventListener('pointerdown', onDocPointerDown)
  if (isAdmin.value) unsubscribeEvents = subscribeScrapeEvents({ onDone: onMatchFinished })
  resolveRouteLoad()
})

onUnmounted(() => {
  document.removeEventListener('pointerdown', onDocPointerDown)
  unsubscribeEvents?.()
  unsubscribeEvents = null
  if (reloadTimer != null) window.clearTimeout(reloadTimer)
})
</script>

<template>
  <WorkDetailSkeleton v-if="loading" />

  <div v-else-if="error" class="detail" :style="pageStyle">
    <div class="hero">
      <div class="hero-shade" />
      <div class="hero-inner">
        <button class="back" type="button" @click="goBack">← 返回海报墙</button>
        <div class="state error">{{ error }}</div>
      </div>
    </div>
  </div>

  <div v-else-if="work" class="detail" :style="pageStyle">
    <div
      class="hero"
      :style="backdropUrl ? { backgroundImage: `url(${backdropUrl})` } : undefined"
    >
      <div class="hero-shade" />
      <div class="hero-inner">
        <button class="back" type="button" @click="goBack">← 返回海报墙</button>
        <p v-if="actionError" class="state error toolbar-error">{{ actionError }}</p>

        <div class="hero-body">
          <PosterMedia class="hero-poster" :src="posterUrl" :alt="title" loading="eager" />
          <div class="hero-copy">
            <div class="title-row">
              <h1>{{ title }}</h1>
              <div v-if="work.genres.length" class="title-tags">
                <span v-for="g in work.genres" :key="g.externalId">{{ g.name }}</span>
              </div>
            </div>
            <p v-if="work.originalTitle !== title" class="original">{{ work.originalTitle }}</p>
            <p v-if="tagline" class="tagline">{{ tagline }}</p>
            <div class="chips">
              <span v-if="work.year">{{ work.year }}</span>
              <component
                :is="ratingHref(row.provider) ? 'a' : 'span'"
                v-for="row in heroRatings"
                :key="row.provider"
                class="chip-rating"
                :href="ratingHref(row.provider) ?? undefined"
                :target="ratingHref(row.provider) ? '_blank' : undefined"
                :rel="ratingHref(row.provider) ? 'noreferrer' : undefined"
                :title="ratingHint(row.provider) || undefined"
              >
                <img
                  v-if="row.logoUrl"
                  class="chip-logo"
                  :src="row.logoUrl"
                  :alt="ratingHint(row.provider) || providerTitle(row.provider)"
                />
                <template v-else>{{ providerTitle(row.provider) }}</template>
                {{ formatRating(row) }}
              </component>
              <span v-if="work.runtimeMinutes">{{ work.runtimeMinutes }} 分钟</span>
              <span v-if="work.status">{{ work.status }}</span>
              <span v-if="work.numberOfSeasons">{{ work.numberOfSeasons }} 季</span>
              <span v-if="work.numberOfEpisodes">{{ work.numberOfEpisodes }} 集</span>
              <button
                v-if="work.collectionExternalId && work.collectionName"
                type="button"
                class="chip-link"
                @click="goToCollection"
              >
                {{ work.collectionName }}
              </button>
              <span v-else-if="work.collectionName">{{ work.collectionName }}</span>
            </div>
            <div v-if="moviePlayable || seriesPlayable || libraryFiles.length || showMoreMenu" class="play-actions">
              <button v-if="moviePlayable" type="button" class="play-primary" @click="openMovie">
                {{ resumeTargetId ? '继续观看' : '播放' }}
              </button>
              <button v-if="seriesPlayable" type="button" class="play-primary" :disabled="openingPlay" @click="openSeries">
                {{ openingPlay ? '打开中…' : seriesProgress ? '继续观看' : '播放' }}
              </button>
              <template v-if="moviePlayable || seriesPlayable || libraryFiles.length">
                <button
                  type="button"
                  class="play-icon"
                  :class="{ 'is-on': watchState === 'watched' }"
                  :disabled="marking"
                  :title="markLabel"
                  :aria-label="markLabel"
                  @click="markWatched"
                >
                  <svg v-if="watchState === 'watched'" viewBox="0 0 24 24" aria-hidden="true">
                    <path
                      fill="currentColor"
                      d="M12 2a10 10 0 1 0 .01 20.01A10 10 0 0 0 12 2Zm-1.05 14.2-3.55-3.55 1.41-1.41 2.14 2.13 4.64-4.64 1.41 1.42-6.05 6.05Z"
                    />
                  </svg>
                  <svg v-else viewBox="0 0 24 24" fill="none" aria-hidden="true">
                    <circle cx="12" cy="12" r="8.25" stroke="currentColor" stroke-width="1.8" />
                    <path
                      d="M8.2 12.2 10.8 14.8 15.8 9.4"
                      stroke="currentColor"
                      stroke-width="1.8"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                  </svg>
                </button>
                <button
                  type="button"
                  class="play-icon"
                  :class="{ 'is-on': wanted }"
                  :disabled="wanting"
                  :title="wanted ? '已想看' : '想看'"
                  :aria-label="wanted ? '已想看' : '想看'"
                  @click="toggleWanted"
                >
                  <svg viewBox="0 0 24 24" aria-hidden="true">
                    <path
                      :fill="wanted ? 'currentColor' : 'none'"
                      :stroke="wanted ? 'none' : 'currentColor'"
                      stroke-width="1.8"
                      stroke-linejoin="round"
                      d="M7 3.75h10A1.25 1.25 0 0 1 18.25 5v15.1L12 16.4 5.75 20.1V5A1.25 1.25 0 0 1 7 3.75Z"
                    />
                  </svg>
                </button>
              </template>
              <div v-if="showMoreMenu" ref="moreWrap" class="chip-more">
                <button
                  type="button"
                  class="play-icon"
                  aria-label="更多"
                  title="更多"
                  :aria-expanded="moreOpen"
                  aria-haspopup="menu"
                  @click="toggleMore"
                >
                  <svg viewBox="0 0 24 24" aria-hidden="true">
                    <circle cx="12" cy="5.5" r="1.6" fill="currentColor" />
                    <circle cx="12" cy="12" r="1.6" fill="currentColor" />
                    <circle cx="12" cy="18.5" r="1.6" fill="currentColor" />
                  </svg>
                </button>
                <div v-if="moreOpen" class="chip-menu" role="menu">
                  <button
                    v-if="!isExternalEntry && work"
                    type="button"
                    role="menuitem"
                    @click="playlistOpen = true; moreOpen = false"
                  >
                    添加到播放列表
                  </button>
                  <button
                    v-if="canRematch && libraryFiles.length"
                    type="button"
                    role="menuitem"
                    @click="openRematch()"
                  >
                    重新匹配
                  </button>
                  <button
                    v-if="canRefreshMetadata"
                    type="button"
                    role="menuitem"
                    :disabled="refreshing"
                    @click="refreshMetadata()"
                  >
                    {{ refreshing ? '刷新中…' : '刷新元数据' }}
                  </button>
                  <button
                    v-if="work.kind !== 'series' && libraryFiles.length"
                    type="button"
                    role="menuitem"
                    @click="openVideoInfo()"
                  >
                    视频信息
                  </button>
                </div>
              </div>
            </div>
            <p v-if="seriesHint" class="play-hint">{{ seriesHint }}</p>
          </div>
        </div>
      </div>
    </div>

    <div class="body">
      <section v-if="collectionParts.length || work.collectionExternalId" class="block">
        <div class="block-head">
          <h2>{{ work.collectionName || '系列' }}</h2>
          <button
            v-if="work.collectionExternalId"
            type="button"
            class="block-link"
            @click="goToCollection"
          >
            查看系列
          </button>
        </div>
        <div v-if="collectionParts.length" class="mate-grid">
          <button
            v-for="(part, index) in collectionParts"
            :key="part.tmdbId || `${part.title}-${index}`"
            type="button"
            class="mate-card"
            :class="{ current: isCurrentPart(part) }"
            @click="openPart(part)"
          >
            <span class="mate-poster">
              <PosterMedia :src="part.posterUrl" :alt="part.title" />
              <span class="mate-badges">
                <span v-if="isCurrentPart(part)" class="mate-badge current">当前</span>
                <span v-if="part.hasLocalMedia" class="mate-badge">本地</span>
              </span>
            </span>
            <span class="mate-meta">
              <strong>{{ part.title }}</strong>
              <small v-if="part.year != null">{{ part.year }}</small>
            </span>
          </button>
        </div>
      </section>

      <section v-if="work.seasons.length" class="block">
        <h2>季（{{ work.seasons.length }}）</h2>
        <div class="season-grid">
          <button
            v-for="season in work.seasons"
            :key="season.id"
            type="button"
            class="season-card"
            @click="goToSeason(season.seasonNumber)"
          >
            <div class="season-card-poster">
              <PosterMedia
                :src="seasonPoster(season.artworks)"
                :alt="`${seasonHeading(season)} 海报`"
              />
            </div>
            <div class="season-card-meta">
              <strong>{{ seasonHeading(season) }}</strong>
              <span>{{ season.localEpisodeCount }} 集本地</span>
            </div>
          </button>
        </div>
      </section>

      <section v-if="overview" class="block">
        <h2>简介</h2>
        <p>{{ overview }}</p>
      </section>

      <section v-if="facts.length" class="block">
        <h2>基本信息</h2>
        <dl class="facts">
          <div v-for="row in facts" :key="row.label" class="fact">
            <dt>{{ row.label }}</dt>
            <dd>
              <a v-if="row.href" :href="row.href" target="_blank" rel="noreferrer">{{ row.value }}</a>
              <template v-else>{{ row.value }}</template>
            </dd>
          </div>
        </dl>
      </section>

      <section v-if="work.keywords.length" class="block">
        <h2>关键词</h2>
        <div class="tags muted">
          <span v-for="k in work.keywords" :key="k.externalId">{{ k.name }}</span>
        </div>
      </section>

      <section v-if="work.ratings.length" class="block">
        <h2>评分</h2>
        <dl class="facts">
          <div v-for="r in work.ratings" :key="r.provider" class="fact">
            <dt>
              {{ providerTitle(r.provider) }}
              <template v-if="ratingKind(r.provider) && ratingKind(r.provider) !== providerTitle(r.provider)">
                · {{ ratingKind(r.provider) }}
              </template>
            </dt>
            <dd>
              <a
                v-if="ratingHref(r.provider)"
                :href="ratingHref(r.provider)!"
                target="_blank"
                rel="noreferrer"
              >
                {{ formatRating(r) }}
                <template v-if="r.votes != null">（{{ r.votes.toLocaleString('zh-CN') }} 票）</template>
              </a>
              <template v-else>
                {{ formatRating(r) }}
                <template v-if="r.votes != null">（{{ r.votes.toLocaleString('zh-CN') }} 票）</template>
              </template>
            </dd>
          </div>
        </dl>
      </section>

      <section v-if="work.externalIds.length" class="block">
        <h2>外部 ID</h2>
        <dl class="facts">
          <div v-for="ext in work.externalIds" :key="`${ext.provider}-${ext.externalId}`" class="fact">
            <dt>{{ providerTitle(ext.provider) }}</dt>
            <dd>
              <a
                v-if="externalUrl(ext.provider, ext.externalId)"
                :href="externalUrl(ext.provider, ext.externalId)!"
                target="_blank"
                rel="noreferrer"
              >{{ ext.externalId }}</a>
              <template v-else>{{ ext.externalId }}</template>
            </dd>
          </div>
        </dl>
      </section>

      <section v-if="work.countries.length" class="block">
        <h2>国家 / 地区</h2>
        <ul class="plain-list">
          <li v-for="c in work.countries" :key="`${c.code}-${c.kind}`">
            <strong>{{ c.name || c.code }}</strong>
            <span class="dim">{{ c.code }} · {{ c.kind }}</span>
          </li>
        </ul>
      </section>

      <section v-if="work.spokenLanguages.length" class="block">
        <h2>对白语言</h2>
        <ul class="plain-list">
          <li v-for="lang in work.spokenLanguages" :key="lang.code">
            <strong>{{ lang.name || lang.code }}</strong>
            <span class="dim">{{ lang.code }}</span>
          </li>
        </ul>
      </section>

      <section v-if="work.companies.length" class="block">
        <h2>公司</h2>
        <ul class="company-list">
          <li v-for="company in work.companies" :key="`${company.externalId}-${company.role}`">
            <div class="company-logo">
              <PosterMedia :src="company.logoUrl" :alt="company.name" fit="contain" />
            </div>
            <div>
              <strong>{{ company.name }}</strong>
              <small>
                {{ companyRoleLabel[company.role] || company.role }}
                <template v-if="company.originCountry"> · {{ company.originCountry }}</template>
              </small>
            </div>
          </li>
        </ul>
      </section>

      <section v-if="work.videos.length" class="block">
        <h2>相关视频</h2>
        <ul class="plain-list">
          <li v-for="video in work.videos" :key="video.externalId">
            <strong>{{ video.name || video.type || '视频' }}</strong>
            <span class="dim">
              {{ video.site || '—' }}
              <template v-if="video.type"> · {{ video.type }}</template>
              <template v-if="video.language"> · {{ video.language }}</template>
              <template v-if="video.official != null"> · {{ video.official ? '官方' : '非官方' }}</template>
            </span>
            <a
              v-if="videoUrl(video.site, video.key)"
              :href="videoUrl(video.site, video.key)!"
              target="_blank"
              rel="noreferrer"
            >打开</a>
            <span v-else-if="video.key" class="dim">{{ video.key }}</span>
          </li>
        </ul>
      </section>

      <section v-if="artworksByKind.length" class="block">
        <h2>图片素材（{{ work.artworks.length }}）</h2>
        <ArtworkRail
          v-for="group in artworksByKind"
          :key="group.kind"
          :title="artworkKindLabel(group.kind)"
          :kind="group.kind"
          :items="group.items"
        />
      </section>

      <PeopleRail title="演员" :items="castItems" />
      <PeopleRail title="制作人员" :items="crewItems" />
      <PeopleRail title="关联人物" :items="peopleItems" />
    </div>

    <VideoInfoDialog
      v-if="videoInfoOpen"
      :files="libraryFiles"
      @close="videoInfoOpen = false"
      @updated="onVideoInfoUpdated"
    />

    <Teleport to="body">
      <div
        v-if="fileChoices"
        class="file-pick"
        role="dialog"
        aria-modal="true"
        aria-label="选择要播放的文件"
        @click.self="fileChoices = null"
        @keydown.esc="fileChoices = null"
      >
        <div class="file-pick-card">
          <h2>选择要播放的文件</h2>
          <button v-for="file in fileChoices" :key="file.id" type="button" @click="openFile(file.id)">
            {{ file.fileName }}
          </button>
        </div>
      </div>
    </Teleport>

    <PlaylistPickerDialog
      v-if="playlistOpen && work"
      :work-id="work.id"
      @close="playlistOpen = false"
    />

    <ManualMatchDialog
      v-if="rematchOpen"
      :files="libraryFiles"
      :work-kind="work.kind"
      title="重新匹配"
      @close="closeRematch"
      @confirm="onConfirmMatch"
    />
  </div>
</template>

<style scoped>
.play-actions {
  flex-direction: row;
  align-items: center;
  justify-content: flex-start;
  width: fit-content;
  max-width: 100%;
}

.play-actions > .play-primary {
  flex: 0 0 auto;
  width: auto;
}

.play-icon {
  box-sizing: border-box;
  width: 2.45rem;
  height: 2.45rem;
  flex: 0 0 2.45rem;
  aspect-ratio: 1;
  padding: 0;
  border-radius: 50%;
  border: 1px solid var(--line-strong);
  background: rgba(10, 12, 16, 0.45);
  color: var(--ink);
  display: inline-grid;
  place-items: center;
  cursor: pointer;
}

.play-icon svg {
  width: 1.25rem;
  height: 1.25rem;
  display: block;
}

.play-icon.is-on {
  border-color: rgba(212, 165, 116, 0.7);
  color: var(--copper);
}

.play-icon:hover:not(:disabled),
.play-icon[aria-expanded='true'] {
  border-color: rgba(212, 165, 116, 0.8);
}

.play-icon:disabled {
  opacity: 0.55;
  cursor: default;
}

.play-actions .chip-more {
  display: flex;
  align-items: center;
}
.detail {
  --detail-bg: var(--bg-deep);
  min-height: 100vh;
  overflow-x: clip;
  background-color: var(--detail-bg);
  animation: fade-in 0.45s cubic-bezier(0.22, 1, 0.36, 1) both;
}

.hero {
  position: relative;
  z-index: 2;
  min-height: min(72vh, 640px);
  background-color: var(--detail-bg);
  background-size: cover;
  background-position: center top;
}

.hero-shade {
  position: absolute;
  inset: 0;
  background:
    linear-gradient(180deg, rgba(8, 10, 14, 0.6) 0%, rgba(8, 10, 14, 0.4) 42%, rgba(8, 10, 14, 0.7) 75%, var(--detail-bg) 100%),
    linear-gradient(90deg, rgba(10, 12, 16, 0.72) 0%, rgba(10, 12, 16, 0.25) 55%, rgba(10, 12, 16, 0.55) 100%);
}

.hero-inner {
  position: relative;
  z-index: 1;
  width: min(1100px, calc(100% - 2.5rem));
  margin: 0 auto;
  padding: 1.5rem 0 2.5rem;
  min-height: inherit;
  display: flex;
  flex-direction: column;
}

.back {
  align-self: flex-start;
  margin-bottom: 2rem;
  border: 1px solid var(--line-strong);
  background: rgba(10, 12, 16, 0.45);
  color: var(--ink);
  border-radius: 999px;
  padding: 0.55rem 1rem;
  cursor: pointer;
  font-weight: 600;
  font-size: 0.9rem;
  backdrop-filter: blur(8px);
  transition:
    border-color 0.2s ease,
    transform 0.2s ease;
}

.back:hover {
  border-color: rgba(212, 165, 116, 0.5);
  transform: translateX(-2px);
}

.toolbar-error {
  margin: -1rem 0 1rem;
  padding: 0;
}

.state {
  margin: auto 0;
  padding: 3rem 0;
  color: var(--ink-muted);
}

.state.error {
  color: var(--danger);
}

.hero-body {
  --poster-width: 200px;
  --poster-height: calc(var(--poster-width) * 3 / 2);
  margin-top: auto;
  display: grid;
  grid-template-columns: var(--poster-width) minmax(0, 1fr);
  gap: 1.75rem;
  align-items: stretch;
}

.hero-poster {
  width: var(--poster-width);
  height: var(--poster-height);
  border-radius: 12px;
  border: 1px solid var(--line-strong);
  box-shadow: var(--shadow);
  overflow: hidden;
}

.hero-copy {
  min-height: var(--poster-height);
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
}

.title-row {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 0.55rem 0.85rem;
}

.hero-copy h1 {
  margin: 0;
  font-family: var(--font-display);
  font-size: clamp(2rem, 5vw, 3.4rem);
  line-height: 1.05;
  letter-spacing: -0.03em;
}

.title-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  max-width: 100%;
}

.title-tags span {
  padding: 0.22rem 0.65rem;
  border-radius: 999px;
  background: rgba(95, 179, 168, 0.14);
  border: 1px solid rgba(95, 179, 168, 0.32);
  color: var(--teal);
  font-size: 0.78rem;
  font-weight: 650;
  line-height: 1.3;
}

.original {
  margin: 0.45rem 0 0;
  color: var(--ink-faint);
  font-size: 0.95rem;
}

.tagline {
  margin: 0.75rem 0 0;
  color: var(--ink-muted);
  font-size: 1.05rem;
  max-width: 40rem;
  line-height: 1.5;
}

.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 0.45rem;
  margin-top: 1.1rem;
}

.chips a.chip-rating {
  color: inherit;
  text-decoration: none;
}

.chips a.chip-rating:hover {
  border-color: rgba(212, 165, 116, 0.5);
  color: var(--ink);
}

.chips span,
.chips a.chip-rating,
.chips button.chip-link {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0.2rem 0.7rem;
  min-height: 1.7rem;
  box-sizing: border-box;
  border-radius: 999px;
  border: 1px solid var(--line-strong);
  background: rgba(255, 255, 255, 0.04);
  font-size: 0.82rem;
  line-height: 1;
  color: var(--ink-muted);
}

.chips button.chip-link {
  cursor: pointer;
  color: var(--copper);
}

.chips button.chip-link:hover {
  border-color: rgba(212, 165, 116, 0.5);
  color: var(--ink);
}

.chip-rating {
  gap: 0.4rem;
}

.chip-logo {
  width: auto;
  height: 0.95rem;
  object-fit: contain;
  flex-shrink: 0;
}

.chip-more {
  position: relative;
}

.chip-menu {
  position: absolute;
  top: calc(100% + 0.4rem);
  left: 0;
  z-index: 20;
  min-width: 8.5rem;
  padding: 0.3rem;
  border-radius: 10px;
  border: 1px solid var(--line-strong);
  background: rgba(18, 21, 28, 0.96);
  box-shadow: 0 14px 32px rgba(0, 0, 0, 0.35);
  backdrop-filter: blur(10px);
}

.chip-menu button {
  width: 100%;
  border: 0;
  background: transparent;
  color: var(--ink);
  text-align: left;
  padding: 0.55rem 0.7rem;
  border-radius: 8px;
  font-size: 0.88rem;
  cursor: pointer;
}

.chip-menu button:hover {
  background: rgba(212, 165, 116, 0.14);
  color: var(--copper);
}

.body {
  width: min(1100px, calc(100% - 2.5rem));
  max-width: 100%;
  min-width: 0;
  margin: 0 auto;
  padding: 0.5rem 0 4rem;
  display: grid;
  gap: 2.25rem;
  overflow-x: clip;
}

/* Grid items default to min-width:auto and expand to rail content,
   which clips the row without enabling overflow scroll/arrows. */
.body > * {
  min-width: 0;
  max-width: 100%;
}

.block {
  min-width: 0;
  max-width: 100%;
}

.block-head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 0.75rem;
  margin-bottom: 0.85rem;
}

.block-head h2 {
  margin: 0;
}

.block-link {
  border: 0;
  background: transparent;
  color: var(--teal);
  cursor: pointer;
  font-size: 0.85rem;
  padding: 0;
}

.block-link:hover {
  color: var(--ink);
}

.block h2 {
  margin: 0 0 0.85rem;
  font-family: var(--font-display);
  font-size: 0.95rem;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--copper);
}

.block-head + .mate-grid {
  margin-top: 0;
}

.block h3 {
  margin: 0 0 0.7rem;
  font-size: 0.9rem;
  color: var(--ink-muted);
  font-weight: 600;
}

.block > p {
  margin: 0;
  line-height: 1.75;
  color: var(--ink-muted);
  font-size: 1.02rem;
}

.facts {
  margin: 0;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 0.85rem 1rem;
}

.fact {
  padding-bottom: 0.7rem;
  border-bottom: 1px solid var(--line);
}

.fact dt {
  font-size: 0.75rem;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--ink-faint);
  margin-bottom: 0.25rem;
}

.fact dd {
  margin: 0;
  color: var(--ink);
  word-break: break-word;
}

.fact a,
.plain-list a,
.art-item {
  color: var(--teal);
}

.tags {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.tags span {
  padding: 0.35rem 0.75rem;
  border-radius: 999px;
  background: rgba(95, 179, 168, 0.12);
  border: 1px solid rgba(95, 179, 168, 0.28);
  color: var(--teal);
  font-size: 0.85rem;
  font-weight: 600;
}

.tags.muted span {
  background: rgba(242, 239, 232, 0.04);
  border-color: var(--line-strong);
  color: var(--ink-muted);
  font-weight: 500;
}

.plain-list,
.company-list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.plain-list {
  display: grid;
  gap: 0.55rem;
}

.plain-list li {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem 0.75rem;
  align-items: baseline;
}

.dim {
  color: var(--ink-faint);
}

.company-list {
  display: grid;
  grid-template-columns: 1fr;
  gap: 1.1rem;
}

.company-list li {
  display: grid;
  grid-template-columns: 52px 1fr;
  gap: 0.75rem;
  align-items: center;
}

.company-logo {
  width: 52px;
  height: 36px;
  overflow: hidden;
}

.company-logo :deep(.poster-media) {
  width: 100%;
  height: 100%;
  background: transparent;
}

.company-logo :deep(.poster-media-img) {
  padding: 0.25rem;
  box-sizing: border-box;
}

.company-logo :deep(.poster-mark) {
  width: 48%;
  min-width: 14px;
}

.company-list strong {
  display: block;
  font-size: 0.9rem;
}

.company-list small {
  display: block;
  color: var(--ink-faint);
  font-size: 0.78rem;
}

.art-grid.tiny {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(96px, 1fr));
  gap: 0.75rem;
  margin: 0.75rem 0;
}

.mate-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(132px, 1fr));
  gap: 1rem 0.8rem;
}

.mate-card {
  display: grid;
  gap: 0.55rem;
  padding: 0;
  border: 0;
  background: transparent;
  color: inherit;
  cursor: pointer;
  text-align: left;
}

.mate-card.current {
  cursor: default;
}

.mate-poster {
  position: relative;
  display: block;
  width: 100%;
  aspect-ratio: 2 / 3;
  border-radius: 10px;
  border: 1px solid var(--line-strong);
  overflow: hidden;
  background: var(--bg-soft);
}

.mate-poster :deep(.poster-media) {
  width: 100%;
  height: 100%;
}

.mate-card.current .mate-poster {
  border-color: rgba(212, 165, 116, 0.7);
}

.mate-badges {
  position: absolute;
  left: 0.4rem;
  bottom: 0.4rem;
  z-index: 2;
  display: flex;
  gap: 0.3rem;
}

.mate-badge {
  padding: 0.12rem 0.4rem;
  border-radius: 999px;
  background: rgba(8, 10, 14, 0.72);
  border: 1px solid var(--line);
  color: var(--ink-muted);
  font-size: 0.68rem;
  font-weight: 600;
}

.mate-badge.current {
  color: var(--copper);
  border-color: rgba(212, 165, 116, 0.45);
}

.mate-meta {
  display: grid;
  gap: 0.15rem;
  min-width: 0;
}

.mate-meta strong,
.mate-meta small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mate-meta strong {
  font-size: 0.92rem;
}

.mate-meta small {
  color: var(--ink-faint);
  font-size: 0.78rem;
}

.season-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(132px, 1fr));
  gap: 1.1rem 0.9rem;
}

.season-card {
  display: grid;
  gap: 0.55rem;
  padding: 0;
  border: 0;
  background: transparent;
  color: inherit;
  cursor: pointer;
  text-align: left;
  transition: transform 0.2s ease;
}

.season-card:hover {
  transform: translateY(-3px);
}

.season-card-poster {
  width: 100%;
  aspect-ratio: 2 / 3;
  border-radius: 10px;
  border: 1px solid var(--line-strong);
  background: var(--bg-soft);
  box-shadow: 0 10px 24px rgba(0, 0, 0, 0.22);
  overflow: hidden;
}

.season-card-meta {
  display: grid;
  gap: 0.2rem;
  min-width: 0;
}

.season-card-meta strong {
  font-size: 0.95rem;
  line-height: 1.3;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.season-card-meta span {
  color: var(--ink-faint);
  font-size: 0.8rem;
}

.play-hint {
  margin: 0.55rem 0 0;
  color: var(--ink-muted);
  font-size: 0.82rem;
}

.file-pick {
  position: fixed;
  inset: 0;
  z-index: 80;
  display: grid;
  place-items: end center;
  padding: 1.25rem;
  background: rgba(4, 6, 10, 0.45);
  backdrop-filter: blur(18px);
}

.file-pick-card {
  width: min(480px, 100%);
  margin-bottom: 1.5rem;
  padding: 1rem 0.4rem 0.6rem;
  border: 1px solid var(--line-strong);
  border-radius: 16px;
  background: rgba(16, 19, 26, 0.96);
}

.file-pick-card h2 {
  margin: 0 0.8rem 0.6rem;
  font-size: 1rem;
  font-weight: 600;
}

.file-pick-card button {
  display: block;
  width: 100%;
  padding: 0.75rem 0.8rem;
  border: 0;
  background: transparent;
  color: var(--ink);
  text-align: left;
  cursor: pointer;
}

.file-pick-card button:hover {
  background: rgba(255, 255, 255, 0.05);
}

@keyframes fade-in {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}

@media (max-width: 720px) {
  .hero {
    min-height: 0;
  }

  .hero-inner,
  .body {
    width: min(100% - 1.1rem, 1100px);
  }

  .hero-inner {
    padding: calc(0.9rem + var(--safe-top)) 0 1.5rem;
  }

  .body {
    padding-bottom: calc(2.5rem + var(--safe-bottom));
    gap: 1.6rem;
  }

  .back {
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .hero-body {
    --poster-width: 108px;
    grid-template-columns: var(--poster-width) minmax(0, 1fr);
    gap: 0.9rem;
    align-items: stretch;
  }

  .hero-copy {
    min-height: var(--poster-height);
  }

  .hero-copy h1 {
    font-size: clamp(1.55rem, 8vw, 2.2rem);
    overflow-wrap: anywhere;
  }

  .title-row {
    flex-direction: column;
    align-items: flex-start;
    gap: 0.55rem;
  }

  .chip-menu {
    left: auto;
    right: 0;
  }

  .facts {
    grid-template-columns: 1fr;
  }

  .mate-grid,
  .season-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (prefers-reduced-motion: reduce) {
  .detail {
    animation: none;
  }
}
</style>
