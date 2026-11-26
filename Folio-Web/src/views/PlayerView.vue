<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'
import {
  fetchEmbeddedSubtitle,
  fetchSubtitleBytes,
  getEpisode,
  getFile,
  getFilePlayback,
  getMediaSegments,
  getPlaylistQueue,
  getSeason,
  getWork,
  listCollectionSiblings,
  listEmbeddedSubtitles,
  listSubtitles,
  putPlaybackProgress,
} from '../api/client'
import type { EmbeddedSubtitle, EpisodeView, FileView, MediaSegment, PlaylistQueueEntry, RatingView, ReviewFileRow, WorkCard } from '../api/types'
import { readSkipMode, skipAction, skipModeLabel, writeSkipMode, type SkipMode } from '../lib/skipSegments'
import {
  codecLabel,
  containerLabel,
  decodeSubtitle,
  fileQualityLabel,
  formatClock,
  isAssSubtitle,
  localizedTitle,
  playbackFailureDetail,
  rankSubtitles,
  toWebVtt,
  type SubtitleCandidate,
} from '../lib/playback'
import { dropAssSubtitle, showAssSubtitle } from '../lib/assSubtitle'

const route = useRoute()
const router = useRouter()

const rootRef = ref<HTMLElement | null>(null)
const videoRef = ref<HTMLVideoElement | null>(null)
const narrow = ref(window.matchMedia('(max-width: 720px)').matches)
let narrowQuery: MediaQueryList | null = null

const pageError = ref<string | null>(null)
const mediaFailed = ref(false)
const mediaDetail = ref('')
const opening = ref(true)
const title = ref('')
const chromeTitle = ref('')
const subtitle = ref('')
const metaLine = ref('')
const genresLine = ref('')
const ratings = ref<RatingView[]>([])
const displayFileName = ref('')
const posterUrl = ref<string | null>(null)
const headerTitle = computed(() => chromeTitle.value || title.value || displayFileName.value || '播放')
const files = ref<ReviewFileRow[]>([])
const subtitles = ref<SubtitleCandidate[]>([])
const embeddedSubtitles = ref<EmbeddedSubtitle[]>([])
const activeSubtitle = ref<string | null>(null)
const activeEmbedded = ref<number | null>(null)
const contentUrl = ref('')
const activeFileId = ref(0)

const paused = ref(true)
const ended = ref(false)
const buffering = ref(true)
const controlsVisible = ref(true)
const fullscreen = ref(false)
const menuOpen = ref(false)
const sheet = ref<'subtitle' | 'rate' | 'version' | 'info' | 'catalog' | 'skip' | null>(null)
const skipMode = ref<SkipMode>(readSkipMode())
const segments = ref<MediaSegment[]>([])
const skipEpoch = ref(0)
const dismissedSkips = new Set<string>()
const userHeldSkips = new Set<string>()
let segmentToken = 0
let lastAutoPos = -1
let manualSeekGrace = 0
let skipGeneration = 0
const playbackRate = ref(1)
const toastText = ref<string | null>(null)
const scrubbing = ref(false)
const scrubMs = ref(0)
const positionMs = ref(0)
const mediaDurationMs = ref(0)
const bufferedMs = ref(0)
const showRemaining = ref(false)
const volume = ref(readVolume())

type CatalogContext = {
  workId: number
  kind: string
  seasonNumber: number | null
  episodeNumber: number | null
  showCatalog: boolean
}

type CatalogSeason = {
  seasonNumber: number
  heading: string
  workTitle: string
  episodes: EpisodeView[]
}

const catalog = ref<CatalogContext | null>(null)
const catalogLoaded = ref(false)
const catalogLoading = ref(false)
const catalogError = ref<string | null>(null)
const catalogMates = ref<WorkCard[]>([])
const catalogSeasons = ref<CatalogSeason[]>([])
const catalogGridMode = ref(true)
let catalogLoadPromise: Promise<boolean> | null = null

const currentFile = computed(() => files.value.find((file) => file.id === activeFileId.value) ?? null)
const durationMs = computed(() => mediaDurationMs.value || currentFile.value?.durationMs || 0)
const shownPosition = computed(() => (scrubbing.value ? scrubMs.value : positionMs.value))
const multipleFiles = computed(() => files.value.length > 1)
const showCatalog = computed(() => catalog.value?.showCatalog === true)
const playlistId = computed(() => {
  const raw = route.query.playlist
  const value = Number(Array.isArray(raw) ? raw[0] : raw)
  return Number.isInteger(value) && value > 0 ? value : null
})
const showPlaylist = computed(() => playlistId.value != null)
const playlistQueue = ref<PlaylistQueueEntry[]>([])
const playlistLoading = ref(false)
const playlistError = ref<string | null>(null)
let loadedPlaylistId: number | null = null
const isSeriesCatalog = computed(() => catalog.value?.kind === 'series')
const playedRatio = computed(() => (durationMs.value > 0 ? Math.min(1, shownPosition.value / durationMs.value) : 0))
const bufferedRatio = computed(() => {
  if (durationMs.value <= 0) return 0
  return Math.min(1, Math.max(playedRatio.value, bufferedMs.value / durationMs.value))
})
const endTimeLabel = computed(() => {
  if (!showRemaining.value || durationMs.value <= 0) return formatClock(durationMs.value)
  return `-${formatClock(Math.max(0, durationMs.value - shownPosition.value))}`
})
const infoRows = computed(() => mediaInfoRows(currentFile.value))
const rates = [0.5, 0.75, 1, 1.5, 2, 3, 4]
const chromeOn = computed(() => controlsVisible.value || pageError.value || mediaFailed.value)
const sheetTitle = computed(() => {
  if (sheet.value === 'subtitle') return '字幕'
  if (sheet.value === 'rate') return '倍速'
  if (sheet.value === 'version') return '版本'
  if (sheet.value === 'skip') return '跳过片头片尾'
  if (sheet.value === 'catalog') return showPlaylist.value ? '播放列表' : '选集'
  return 'INFO'
})
const playingSeries = computed(() => {
  if (showPlaylist.value) {
    const index = playlistCursor()
    const entry = index >= 0 ? playlistQueue.value[index] : undefined
    if (entry) return entry.kind === 'series'
  }
  return catalog.value?.kind === 'series'
})
const skipOffer = computed(() => {
  skipEpoch.value
  if (skipMode.value !== 'button' || opening.value || scrubbing.value || pageError.value || mediaFailed.value) return null
  return skipAction(shownPosition.value, durationMs.value, segments.value, playingSeries.value, dismissedSkips)
})
const skipModes: { id: SkipMode; label: string; hint: string }[] = [
  { id: 'off', label: '关闭', hint: '不显示，也不自动跳' },
  { id: 'button', label: '显示按钮', hint: '播到片头或片尾时出现按钮' },
  { id: 'auto', label: '自动跳过', hint: '播到片头或片尾时直接跳过' },
]

let loadGeneration = 0
let subtitleToken = 0
let subtitleUrl: string | null = null
let hideTimer: number | null = null
let ticker: number | null = null
let toastTimer: number | null = null
let clickTimer: number | null = null
let skipHoldTimer: number | null = null
let skipRepeatTimer: number | null = null
let skipHeld = false
let hasPlayed = false
let resumeApplied = false
let pendingResumeMs: number | null = null
let startAtZero = false
let pendingAutoplay = true
let lastReported = -1

function readVolume() {
  const raw = Number(localStorage.getItem('folio.player.volume'))
  if (Number.isFinite(raw) && raw >= 0 && raw <= 1) return raw
  return 1
}

function stubFile(file: FileView): ReviewFileRow {
  return {
    id: file.id,
    fileName: file.fileName,
    locator: file.locator,
    status: file.status,
    parsedTitle: file.parsedTitle,
    parsedYear: file.parsedYear,
    parsedSeason: file.parsedSeason,
    parsedEpisode: file.parsedEpisode,
    confidence: file.confidence,
    message: file.message,
  }
}

function resetPlaybackState() {
  stopTicker()
  clearSubtitle()
  pageError.value = null
  mediaFailed.value = false
  mediaDetail.value = ''
  opening.value = true
  ended.value = false
  paused.value = true
  buffering.value = true
  controlsVisible.value = true
  contentUrl.value = ''
  title.value = ''
  chromeTitle.value = ''
  subtitle.value = ''
  metaLine.value = ''
  genresLine.value = ''
  ratings.value = []
  displayFileName.value = ''
  posterUrl.value = null
  catalog.value = null
  catalogLoaded.value = false
  catalogLoading.value = false
  catalogError.value = null
  catalogMates.value = []
  catalogSeasons.value = []
  catalogLoadPromise = null
  menuOpen.value = false
  sheet.value = null
  toastText.value = null
  if (toastTimer != null) {
    window.clearTimeout(toastTimer)
    toastTimer = null
  }
  segments.value = []
  dismissedSkips.clear()
  userHeldSkips.clear()
  lastAutoPos = -1
  manualSeekGrace = 0
  skipGeneration = 0
  skipEpoch.value += 1
  scrubbing.value = false
  positionMs.value = 0
  mediaDurationMs.value = 0
  bufferedMs.value = 0
  subtitles.value = []
  embeddedSubtitles.value = []
  activeSubtitle.value = null
  activeEmbedded.value = null
  hasPlayed = false
  resumeApplied = false
  pendingResumeMs = null
  lastReported = -1
  pendingAutoplay = true
}

async function openFile() {
  const generation = ++loadGeneration
  resetPlaybackState()
  const raw = route.params.fileId
  const fileId = Number(Array.isArray(raw) ? raw[0] : raw)
  if (!Number.isInteger(fileId) || fileId <= 0) {
    pageError.value = '无效的文件'
    buffering.value = false
    contentUrl.value = ''
    return
  }
  activeFileId.value = fileId
  void loadSegments(fileId)
  const from = route.query.from
  const fromValue = Array.isArray(from) ? from[0] : from
  startAtZero = fromValue === '0'
  contentUrl.value = ''
  try {
    const file = await getFile(fileId)
    if (generation !== loadGeneration) return
    const progress = await getFilePlayback(fileId).catch(() => null)
    if (generation !== loadGeneration) return
    const context = await loadContext(file, progress?.seasonNumber, progress?.episodeNumber)
    if (generation !== loadGeneration) return
    files.value = context.files
    title.value = context.title
    chromeTitle.value = context.chromeTitle
    subtitle.value = context.subtitle
    metaLine.value = context.metaLine
    genresLine.value = context.genresLine
    ratings.value = context.ratings
    displayFileName.value = file.fileName
    posterUrl.value = context.poster
    catalog.value = context.catalog
    if (!playlistId.value && context.catalog?.showCatalog) void ensureCatalogReady()
    void ensurePlaylistQueue()
    if (!startAtZero && progress?.resumePositionMs != null && progress.resumePositionMs > 0) {
      pendingResumeMs = progress.resumePositionMs
    }
    contentUrl.value = `/api/library/files/${fileId}/content`
    void loadSubtitleList(fileId, file.fileName, generation)
  } catch (error) {
    if (generation !== loadGeneration) return
    pageError.value = error instanceof Error ? error.message : '无法打开文件'
    opening.value = false
    buffering.value = false
  }
}

type PrepareContext = {
  files: ReviewFileRow[]
  title: string
  chromeTitle: string
  subtitle: string
  metaLine: string
  genresLine: string
  ratings: RatingView[]
  poster: string | null
  catalog: CatalogContext | null
}

function emptyPrepare(files: ReviewFileRow[], title: string, poster: string | null = null): PrepareContext {
  return {
    files,
    title,
    chromeTitle: title,
    subtitle: '',
    metaLine: '',
    genresLine: '',
    ratings: [],
    poster,
    catalog: null,
  }
}

function catalogOf(
  workId: number,
  kind: string,
  seasonNumber: number | null = null,
  episodeNumber: number | null = null,
  show = true,
): CatalogContext {
  return { workId, kind, seasonNumber, episodeNumber, showCatalog: show }
}

/** 剧集顶栏：`作品名 第1季第2集 集标题` */
function seriesChromeTitle(
  workTitle: string,
  seasonNumber: number,
  episodeNumber: number,
  episodeTitle: string | null | undefined,
) {
  const work = workTitle.trim()
  const base = work
    ? `${work} 第${seasonNumber}季第${episodeNumber}集`
    : `第${seasonNumber}季第${episodeNumber}集`
  const name = episodeTitle?.trim()
  return name ? `${base} ${name}` : base
}

async function loadContext(
  file: FileView,
  seasonNumber: number | null | undefined,
  episodeNumber: number | null | undefined,
): Promise<PrepareContext> {
  const fallbackTitle = file.work
    ? localizedTitle(file.work.originalTitle, file.work.translations)
    : file.fileName
  if (file.work?.kind === 'series' && file.workId) {
    const season = seasonNumber ?? file.parsedSeason
    const episode = episodeNumber ?? file.parsedEpisode
    if (season != null && episode != null) {
      try {
        const detail = await getEpisode(file.workId, season, episode)
        const score = detail.episode.voteAverage
        const year =
          detail.episode.airDate && detail.episode.airDate.length >= 4
            ? Number(detail.episode.airDate.slice(0, 4))
            : null
        return {
          files: withCurrent(file, detail.episode.files),
          title: episodeTitleHeading(detail.episode.episodeNumber, detail.episode.title),
          chromeTitle: seriesChromeTitle(
            detail.workTitle,
            detail.seasonNumber,
            detail.episode.episodeNumber,
            detail.episode.title,
          ),
          subtitle: `${detail.workTitle} · ${seasonHeading(detail.seasonNumber, detail.seasonName)}`,
          metaLine: joinMeta(['剧集', year && Number.isFinite(year) ? String(year) : '', runtimeLabel(detail.episode.runtimeMinutes)]),
          genresLine: '',
          ratings:
            score == null || score <= 0
              ? []
              : [{ provider: 'tmdb', value: score, votes: detail.episode.voteCount, scale: 10, logoUrl: null }],
          poster: artworkUrl(detail.episode.artworks),
          catalog: catalogOf(file.workId, 'series', detail.seasonNumber, detail.episode.episodeNumber),
        }
      } catch {
        // 集详情失败时仍播放这一个文件
      }
    }
    return {
      ...emptyPrepare([stubFile(file)], fallbackTitle),
      catalog: catalogOf(file.workId, 'series', season ?? null, episode ?? null),
    }
  }
  if (file.workId && file.work?.kind !== 'series') {
    try {
      const work = await getWork(file.workId)
      const workTitle =
        work.translations.find((item) => item.locale === 'zh-CN' && item.title)?.title || work.originalTitle
      return {
        files: withCurrent(file, work.libraryFiles),
        title: workTitle,
        chromeTitle: workTitle,
        subtitle: '',
        metaLine: joinMeta([
          work.kind === 'series' ? '剧集' : '电影',
          work.year != null ? String(work.year) : '',
          runtimeLabel(work.runtimeMinutes),
        ]),
        genresLine: work.genres
          .map((item) => item.name.trim())
          .filter(Boolean)
          .slice(0, 3)
          .join('  ·  '),
        ratings: sortedRatings(work.ratings),
        poster: artworkUrl(work.artworks),
        catalog: catalogOf(work.id, work.kind === 'series' ? 'series' : 'movie'),
      }
    } catch {
      // 作品详情失败时仍播放这一个文件
    }
    return {
      ...emptyPrepare([stubFile(file)], fallbackTitle),
      catalog: catalogOf(file.workId, 'movie'),
    }
  }
  return emptyPrepare([stubFile(file)], fallbackTitle)
}

function artworkUrl(artworks: { kind: string; remoteUrl: string; locale?: string | null }[]) {
  return (
    artworks.find((item) => item.kind === 'poster' && item.locale === 'zh-CN')?.remoteUrl ??
    artworks.find((item) => item.kind === 'poster')?.remoteUrl ??
    artworks.find((item) => item.kind === 'still')?.remoteUrl ??
    null
  )
}

function rateLabel(rate: number) {
  return Number.isInteger(rate) ? `${rate}×` : `${rate}×`
}

function formatBytes(size: number | null | undefined) {
  if (size == null || size <= 0) return ''
  if (size >= 1024 ** 3) return `${(size / 1024 ** 3).toFixed(2)} GB`
  if (size >= 1024 ** 2) return `${(size / 1024 ** 2).toFixed(1)} MB`
  return `${Math.round(size / 1024)} KB`
}

function mediaInfoRows(file: ReviewFileRow | null) {
  if (!file) return [] as { label: string; value: string }[]
  const rows: { label: string; value: string }[] = []
  const push = (label: string, value: string) => {
    const text = value.trim()
    if (text) rows.push({ label, value: text })
  }
  push('文件', file.fileName)
  push('容器', containerLabel(file))
  push('大小', formatBytes(file.fileSize))
  const picture = [
    codecLabel(file.videoCodec),
    file.videoWidth && file.videoHeight ? `${file.videoWidth}×${file.videoHeight}` : '',
    file.videoDynamicRange ?? '',
    file.videoFrameRate ? `${Number(file.videoFrameRate).toFixed(3).replace(/\.?0+$/, '')} fps` : '',
  ]
    .filter(Boolean)
    .join(' · ')
  push('视频', picture)
  const audio = (file.audioTracks ?? [])
    .map((track) => [codecLabel(track.codec), track.language, track.channelLayout || (track.channels ? `${track.channels}ch` : '')].filter(Boolean).join(' '))
    .filter(Boolean)
    .join(' / ')
  push('音频', audio)
  const subs = (file.subtitleTracks ?? [])
    .map((track) => [track.language, track.codec].filter(Boolean).join(' '))
    .filter(Boolean)
    .join(' / ')
  push('内嵌字幕', subs)
  if (activeSubtitle.value) push('外挂字幕', activeSubtitle.value)
  if (activeEmbedded.value != null) {
    const selected = embeddedSubtitles.value.find((track) => track.index === activeEmbedded.value)
    if (selected) push('当前字幕', embeddedLabel(selected))
  }
  push('倍速', playbackRate.value === 1 ? '' : rateLabel(playbackRate.value))
  return rows
}

function withCurrent(file: FileView, siblings: ReviewFileRow[]) {
  if (siblings.some((item) => item.id === file.id)) return siblings
  return [stubFile(file), ...siblings]
}

function episodeTitleHeading(episodeNumber: number, episodeTitle: string | null) {
  const name = episodeTitle?.trim()
  if (!name) return `第 ${episodeNumber} 集`
  return `${episodeNumber}. ${name}`
}

function seasonHeading(seasonNumber: number, seasonName: string | null) {
  const base = `第 ${seasonNumber} 季`
  const name = seasonName?.trim()
  if (!name || name === base || /^season\s*\d+$/i.test(name)) return base
  return `${base} ${name}`
}

function runtimeLabel(minutes: number | null | undefined) {
  return minutes == null || minutes <= 0 ? '' : `${minutes} 分钟`
}

function joinMeta(parts: Array<string | false | null | undefined>) {
  return parts.filter((part): part is string => typeof part === 'string' && part.length > 0).join('  ·  ')
}

function sortedRatings(rows: RatingView[]) {
  const rank = (provider: string) => {
    switch (provider) {
      case 'imdb':
        return 0
      case 'rottentomatoes':
        return 1
      case 'rt_audience':
        return 2
      case 'metacritic':
        return 3
      case 'tmdb':
        return 4
      default:
        return 5
    }
  }
  return [...rows].sort((a, b) => rank(a.provider) - rank(b.provider))
}

function ratingLabel(provider: string) {
  const labels: Record<string, string> = {
    tmdb: 'TMDB',
    tvdb: 'TVDB',
    imdb: 'IMDb',
    rottentomatoes: '烂番茄',
    rt_audience: '观众',
    metacritic: 'MC',
  }
  return labels[provider] ?? provider.toUpperCase()
}

function formatPrepareRating(row: RatingView) {
  if (row.provider === 'rottentomatoes' || row.provider === 'rt_audience') {
    return `${Math.round(Number(row.value))}%`
  }
  if (row.provider === 'metacritic' || Number(row.scale) === 100) {
    return String(Math.round(Number(row.value)))
  }
  return Number(row.value).toFixed(1)
}

function embeddedLabel(track: EmbeddedSubtitle) {
  const name = track.title?.trim() || track.language?.trim() || '字幕'
  const codec = track.codec?.trim()
  return codec ? `${name} · ${codec.toUpperCase()}` : name
}

async function loadSubtitleList(fileId: number, fileName: string, generation: number) {
  const [externalResult, embeddedResult] = await Promise.allSettled([
    listSubtitles(fileId),
    listEmbeddedSubtitles(fileId),
  ])
  if (generation !== loadGeneration) return
  if (externalResult.status === 'fulfilled') {
    const ranked = rankSubtitles(fileName, externalResult.value)
    subtitles.value = ranked
    const pick = ranked.length === 1 || (ranked[0] && ranked[0].score > 0) ? ranked[0] : null
    activeSubtitle.value = pick?.name ?? null
  } else {
    subtitles.value = []
  }
  embeddedSubtitles.value = embeddedResult.status === 'fulfilled' ? embeddedResult.value : []
}

function clearTextTrack() {
  const video = videoRef.value
  video?.querySelectorAll('track').forEach((track) => track.remove())
  if (subtitleUrl) {
    URL.revokeObjectURL(subtitleUrl)
    subtitleUrl = null
  }
}

function clearSubtitle() {
  subtitleToken += 1
  clearTextTrack()
  dropAssSubtitle()
}

async function mountSubtitle(generation: number) {
  const token = ++subtitleToken
  clearTextTrack()
  const video = videoRef.value
  const embedded = activeEmbedded.value
  const name = activeSubtitle.value
  if (!video || !activeFileId.value || (embedded == null && !name)) {
    if (token === subtitleToken) clearToast(embeddedReading)
    dropAssSubtitle()
    return
  }
  try {
    if (embedded != null) {
      showToast(embeddedReading, 0)
      const text = await fetchEmbeddedSubtitle(activeFileId.value, embedded)
      if (token !== subtitleToken || generation !== loadGeneration || videoRef.value !== video) return
      await showAssSubtitle(video, text)
      if (token === subtitleToken) clearToast(embeddedReading)
      return
    }
    if (token === subtitleToken) clearToast(embeddedReading)
    if (!name) {
      dropAssSubtitle()
      return
    }
    const bytes = await fetchSubtitleBytes(activeFileId.value, name)
    if (token !== subtitleToken || generation !== loadGeneration || videoRef.value !== video) return
    const text = decodeSubtitle(bytes)
    if (name && isAssSubtitle(name)) {
      await showAssSubtitle(video, text)
      return
    }
    dropAssSubtitle()
    if (token !== subtitleToken || generation !== loadGeneration || videoRef.value !== video) return
    const vtt = toWebVtt(text)
    const url = URL.createObjectURL(new Blob([vtt], { type: 'text/vtt' }))
    subtitleUrl = url
    const track = document.createElement('track')
    track.kind = 'subtitles'
    track.label = name
    track.src = url
    track.default = true
    const show = () => {
      if (track.track) track.track.mode = 'showing'
    }
    track.addEventListener('load', show)
    video.appendChild(track)
    show()
  } catch (error) {
    if (token !== subtitleToken) return
    clearToast(embeddedReading)
    activeSubtitle.value = null
    activeEmbedded.value = null
    if (embedded != null) showToast(error instanceof Error ? error.message : '内嵌字幕读取失败')
  }
}

const embeddedReading = '正在读取内嵌字幕'
const imageSubtitleCodecs = new Set(['hdmv_pgs_subtitle', 'dvd_subtitle', 'dvb_subtitle', 'xsub'])

const emptySubtitleHint = computed(() => {
  const tracks = currentFile.value?.subtitleTracks ?? []
  const onlyImages = tracks.length > 0 && tracks.every((track) => imageSubtitleCodecs.has((track.codec ?? '').toLowerCase()))
  return onlyImages ? '只有图形字幕，网页端无法显示' : '没有可用字幕'
})

function chooseSubtitle(name: string | null) {
  sheet.value = null
  activeEmbedded.value = null
  activeSubtitle.value = name
}

function chooseEmbedded(index: number) {
  sheet.value = null
  activeSubtitle.value = null
  activeEmbedded.value = index
}

watch([videoRef, activeSubtitle, activeEmbedded], () => {
  void mountSubtitle(loadGeneration)
})

function applyResume() {
  const video = videoRef.value
  if (!video) return false
  video.volume = volume.value
  video.playbackRate = playbackRate.value
  if (resumeApplied || video.readyState < 1) return false
  const resume = pendingResumeMs
  if (startAtZero || resume == null || resume <= 0) {
    resumeApplied = true
    return false
  }
  const target = resume / 1000
  positionMs.value = resume
  resumeApplied = true
  if (Math.abs(video.currentTime - target) > 0.75) {
    video.currentTime = target
    return true
  }
  return false
}

function kickPlayback() {
  if (!pendingAutoplay) return
  const video = videoRef.value
  if (!video || mediaFailed.value || pageError.value || !resumeApplied) return
  pendingAutoplay = false
  void video.play().catch(() => {
    paused.value = true
  })
}

function onCanPlay() {
  opening.value = false
  if (!hasPlayed) buffering.value = false
  const waitingForSeek = applyResume()
  if (!waitingForSeek) kickPlayback()
}

function onSeeked() {
  onTime()
  kickPlayback()
}

function onWaiting() {
  if (hasPlayed && !ended.value && !mediaFailed.value) buffering.value = true
}

function onPlaying() {
  hasPlayed = true
  opening.value = false
  paused.value = false
  ended.value = false
  buffering.value = false
  applyResume()
  startTicker()
  showControls()
}

function onPause() {
  paused.value = true
  stopTicker()
  showControls()
  if (!videoRef.value?.ended) void reportProgress(true)
}

function onEnded() {
  ended.value = true
  paused.value = true
  buffering.value = false
  stopTicker()
  showControls()
  void reportProgress(true)
}

function onTime() {
  const video = videoRef.value
  if (!video || scrubbing.value || video.seeking) return
  positionMs.value = Math.round(video.currentTime * 1000)
  if (Number.isFinite(video.duration) && video.duration > 0) {
    mediaDurationMs.value = Math.round(video.duration * 1000)
  }
  if (video.buffered.length > 0) {
    bufferedMs.value = Math.round(video.buffered.end(video.buffered.length - 1) * 1000)
  }
}

function onMediaError(event: Event) {
  const video = event.target
  if (!(video instanceof HTMLVideoElement) || video !== videoRef.value || !contentUrl.value) return
  buffering.value = false
  opening.value = false
  stopTicker()
  mediaFailed.value = true
  mediaDetail.value = playbackFailureDetail(currentFile.value)
}

function togglePlay() {
  const video = videoRef.value
  if (!video || mediaFailed.value || pageError.value) return
  if (video.paused) void video.play().catch(() => undefined)
  else video.pause()
}

function onScrubPointerDown(event: PointerEvent) {
  const input = event.target as HTMLInputElement
  scrubbing.value = true
  scrubMs.value = Number(input.value)
  try {
    input.setPointerCapture(event.pointerId)
  } catch {
    // 部分环境不支持 capture，忽略即可
  }
  showControls()
}

function onScrubInput(event: Event) {
  scrubbing.value = true
  scrubMs.value = Number((event.target as HTMLInputElement).value)
  showControls()
}

function commitScrub(raw: number) {
  const max = durationMs.value || 0
  const next = Math.min(Math.max(0, Number.isFinite(raw) ? raw : 0), max)
  noteManualSeek(next)
  scrubMs.value = next
  positionMs.value = next
  const video = videoRef.value
  if (video && Number.isFinite(next)) video.currentTime = next / 1000
  scrubbing.value = false
  showControls()
}

function onScrubCommit(event: Event) {
  if (!scrubbing.value) return
  commitScrub(Number((event.target as HTMLInputElement).value))
}

function onScrubPointerUp(event: PointerEvent) {
  if (!scrubbing.value) return
  commitScrub(Number((event.target as HTMLInputElement).value))
}

function seekBy(seconds: number) {
  const video = videoRef.value
  if (!video || mediaFailed.value) return
  const duration = Number.isFinite(video.duration) && video.duration > 0 ? video.duration : durationMs.value / 1000
  const next = Math.min(Math.max(0, video.currentTime + seconds), duration || video.currentTime + seconds)
  const nextMs = Math.round(next * 1000)
  noteManualSeek(nextMs)
  video.currentTime = next
  positionMs.value = nextMs
}

function showToast(message: string, duration = 1600) {
  toastText.value = message
  if (toastTimer != null) window.clearTimeout(toastTimer)
  toastTimer = null
  if (duration <= 0) return
  toastTimer = window.setTimeout(() => {
    toastText.value = null
    toastTimer = null
  }, duration)
}

function clearToast(message?: string) {
  if (message && toastText.value !== message) return
  toastText.value = null
  if (toastTimer != null) window.clearTimeout(toastTimer)
  toastTimer = null
}

async function ensureCatalogReady() {
  if (catalogLoaded.value) return true
  if (!catalog.value?.showCatalog) return false
  if (catalogLoadPromise) return catalogLoadPromise
  catalogLoadPromise = loadCatalogData().finally(() => {
    catalogLoadPromise = null
  })
  return catalogLoadPromise
}

async function loadCatalogData() {
  const current = catalog.value
  if (!current) return false
  catalogLoading.value = true
  catalogError.value = null
  try {
    if (current.kind === 'movie') {
      catalogMates.value = await listCollectionSiblings(current.workId)
      catalogSeasons.value = []
    } else {
      const work = await getWork(current.workId)
      const details = await Promise.all(
        work.seasons.map((season) => getSeason(current.workId, season.seasonNumber)),
      )
      catalogSeasons.value = details.map((detail) => ({
        seasonNumber: detail.season.seasonNumber,
        heading: seasonHeading(detail.season.seasonNumber, detail.season.name),
        workTitle: detail.workTitle,
        episodes: detail.season.episodes,
      }))
      catalogMates.value = []
    }
    catalogLoaded.value = true
    catalogError.value = null
    return true
  } catch (error) {
    catalogError.value = error instanceof Error ? error.message : '选集加载失败'
    return false
  } finally {
    catalogLoading.value = false
  }
}

function isEpisodeSelected(seasonNumber: number, episodeNumber: number) {
  return catalog.value?.seasonNumber === seasonNumber && catalog.value?.episodeNumber === episodeNumber
}

function isMovieSelected(workId: number) {
  return catalog.value?.workId === workId
}

async function ensurePlaylistQueue() {
  const id = playlistId.value
  if (!id) {
    playlistQueue.value = []
    playlistError.value = null
    loadedPlaylistId = null
    return false
  }
  if (loadedPlaylistId === id && playlistQueue.value.length) return true
  playlistLoading.value = true
  playlistError.value = null
  try {
    const rows = await getPlaylistQueue(id)
    if (playlistId.value !== id) return false
    playlistQueue.value = rows
    loadedPlaylistId = id
    return rows.length > 0
  } catch (error) {
    if (playlistId.value !== id) return false
    playlistQueue.value = []
    loadedPlaylistId = null
    playlistError.value = error instanceof Error ? error.message : '播放列表加载失败'
    return false
  } finally {
    if (playlistId.value === id) playlistLoading.value = false
  }
}

function playlistCursor() {
  const queue = playlistQueue.value
  const byFile = queue.findIndex((entry) => entry.fileId === activeFileId.value)
  if (byFile >= 0) return byFile
  const current = catalog.value
  if (!current) return -1
  if (current.kind !== 'series') {
    return queue.findIndex((entry) => entry.kind !== 'series' && entry.workId === current.workId)
  }
  return queue.findIndex(
    (entry) =>
      entry.workId === current.workId &&
      entry.seasonNumber === current.seasonNumber &&
      entry.episodeNumber === current.episodeNumber,
  )
}

async function playPlaylistEntry(entry: PlaylistQueueEntry) {
  const id = playlistId.value
  if (!id || entry.fileId === activeFileId.value) return
  sheet.value = null
  await replacePlay(entry.fileId)
}

function replacePlay(fileId: number) {
  const playlist = playlistId.value
  return router.replace({
    name: 'play',
    params: { fileId: String(fileId) },
    query: playlist ? { playlist: String(playlist) } : {},
  })
}

async function playAdjacentPlaylist(delta: number) {
  const ok = await ensurePlaylistQueue()
  if (!ok) {
    showToast(playlistError.value || '这个播放列表没有可播放的视频')
    return
  }
  const index = playlistCursor()
  if (index < 0) {
    showToast('找不到当前视频在播放列表中的位置')
    return
  }
  const next = playlistQueue.value[index + delta]
  if (!next) {
    showToast(delta > 0 ? '已经是最后一个视频' : '已经是第一个视频')
    return
  }
  await playPlaylistEntry(next)
}

async function openCatalog() {
  menuOpen.value = false
  sheet.value = 'catalog'
  showControls()
  if (showPlaylist.value) {
    const ok = await ensurePlaylistQueue()
    if (!ok && playlistError.value) showToast(playlistError.value)
    return
  }
  const ok = await ensureCatalogReady()
  if (!ok && catalogError.value) showToast(catalogError.value)
}

async function retryCatalog() {
  catalogLoaded.value = false
  await loadCatalogData()
}

async function playCatalogMovie(mate: WorkCard) {
  if (isMovieSelected(mate.id)) return
  try {
    const work = await getWork(mate.id)
    const file = work.libraryFiles[0]
    if (!file) {
      showToast('没有可播放的文件')
      return
    }
    sheet.value = null
    await replacePlay(file.id)
  } catch (error) {
    showToast(error instanceof Error ? error.message : '打开失败')
  }
}

async function playCatalogEpisode(seasonNumber: number, episode: EpisodeView) {
  if (!episode.files.length) return
  if (isEpisodeSelected(seasonNumber, episode.episodeNumber)) return
  const file = episode.files[0]
  if (!file) return
  sheet.value = null
  await replacePlay(file.id)
}

async function playAdjacent(delta: number) {
  if (showPlaylist.value) {
    await playAdjacentPlaylist(delta)
    return
  }
  if (!showCatalog.value) {
    showToast(delta > 0 ? '已经是最后一个视频' : '已经是第一个视频')
    return
  }
  const ok = await ensureCatalogReady()
  if (!ok) {
    showToast(catalogError.value || '选集加载失败')
    return
  }
  const current = catalog.value
  if (!current) {
    showToast(delta > 0 ? '已经是最后一个视频' : '已经是第一个视频')
    return
  }
  if (current.kind === 'movie') {
    const mates = catalogMates.value
    const idx = mates.findIndex((mate) => mate.id === current.workId)
    if (idx < 0) {
      showToast('找不到当前影片在系列中的位置')
      return
    }
    let cursor = idx + delta
    while (cursor >= 0 && cursor < mates.length) {
      const mate = mates[cursor]
      try {
        const work = await getWork(mate.id)
        const file = work.libraryFiles[0]
        if (file) {
          await replacePlay(file.id)
          return
        }
      } catch {
        // 试下一邻近作品
      }
      cursor += delta
    }
    showToast(delta > 0 ? '已经是最后一个视频' : '已经是第一个视频')
    return
  }
  const queue: { seasonNumber: number; episode: EpisodeView }[] = []
  for (const season of catalogSeasons.value) {
    for (const episode of season.episodes) {
      if (episode.files.length) queue.push({ seasonNumber: season.seasonNumber, episode })
    }
  }
  if (!queue.length) {
    showToast('没有可播放的剧集')
    return
  }
  const idx = queue.findIndex(
    (item) => item.seasonNumber === current.seasonNumber && item.episode.episodeNumber === current.episodeNumber,
  )
  if (idx < 0) {
    showToast('找不到当前集在列表中的位置')
    return
  }
  const next = queue[idx + delta]
  if (!next) {
    showToast(delta > 0 ? '已经是最后一个视频' : '已经是第一个视频')
    return
  }
  await playCatalogEpisode(next.seasonNumber, next.episode)
}

function onSurfaceClick() {
  if (clickTimer != null) window.clearTimeout(clickTimer)
  clickTimer = window.setTimeout(() => {
    clickTimer = null
    if (menuOpen.value || sheet.value) {
      menuOpen.value = false
      sheet.value = null
      return
    }
    controlsVisible.value = !controlsVisible.value
    if (controlsVisible.value) showControls()
  }, 220)
}

function onSurfaceDblClick() {
  if (clickTimer != null) window.clearTimeout(clickTimer)
  clickTimer = null
  togglePlay()
}

function stopSkipRepeat() {
  if (skipHoldTimer != null) window.clearTimeout(skipHoldTimer)
  if (skipRepeatTimer != null) window.clearInterval(skipRepeatTimer)
  skipHoldTimer = null
  skipRepeatTimer = null
}

function onSkipDown(seconds: number) {
  skipHeld = false
  stopSkipRepeat()
  skipHoldTimer = window.setTimeout(() => {
    skipHeld = true
    seekBy(seconds)
    skipRepeatTimer = window.setInterval(() => seekBy(seconds), 250)
  }, 350)
}

function onSkipClick(seconds: number) {
  if (skipHeld) {
    skipHeld = false
    return
  }
  seekBy(seconds)
}

function openMenu() {
  sheet.value = null
  menuOpen.value = !menuOpen.value
  showControls()
}

function chooseSkipMode(mode: SkipMode) {
  skipMode.value = mode
  writeSkipMode(mode)
  sheet.value = null
  if (mode !== 'off') void loadSegments(activeFileId.value)
  else maybeAutoSkip()
}

async function loadSegments(fileId: number) {
  if (!fileId) return
  const token = ++segmentToken
  if (skipMode.value === 'off') {
    segments.value = []
    return
  }
  try {
    const data = await getMediaSegments(fileId)
    if (token !== segmentToken || activeFileId.value !== fileId) return
    segments.value = data.segments
    maybeAutoSkip()
  } catch {
    if (token !== segmentToken || activeFileId.value !== fileId) return
    segments.value = []
  }
}

watch([positionMs, durationMs, segments, skipMode], () => {
  maybeAutoSkip()
})

function segmentAt(position: number) {
  return skipAction(position, durationMs.value, segments.value, playingSeries.value, new Set())
}

function noteManualSeek(position: number) {
  skipGeneration += 1
  manualSeekGrace = performance.now() + 1500
  lastAutoPos = position
  const segment = segmentAt(position)
  if (segment) userHeldSkips.add(segment.key)
  else userHeldSkips.clear()
}

function maybeAutoSkip() {
  if (skipMode.value !== 'auto' || scrubbing.value || opening.value) return
  if (!resumeApplied && pendingResumeMs != null && pendingResumeMs > 0 && !startAtZero) return
  const position = positionMs.value
  const previous = lastAutoPos
  lastAutoPos = position
  const segment = segmentAt(position)
  const jumped = previous >= 0 && Math.abs(position - previous) > 2500
  if (jumped) {
    if (segment) userHeldSkips.add(segment.key)
    else if (performance.now() >= manualSeekGrace) userHeldSkips.clear()
    return
  }
  if (performance.now() < manualSeekGrace) return
  if (!segment) {
    userHeldSkips.clear()
    return
  }
  if (userHeldSkips.has(segment.key)) return
  const action = skipAction(position, durationMs.value, segments.value, playingSeries.value, dismissedSkips)
  if (!action) return
  dismissedSkips.add(action.key)
  skipEpoch.value += 1
  void performSkip(action)
}

async function performSkip(action: { targetMs: number; advance: boolean }) {
  const generation = skipGeneration
  if (action.advance) {
    const before = activeFileId.value
    await playAdjacent(1)
    if (generation !== skipGeneration || activeFileId.value !== before) return
  }
  if (generation !== skipGeneration) return
  const video = videoRef.value
  const max = durationMs.value || action.targetMs
  const next = Math.min(Math.max(0, action.targetMs), max)
  positionMs.value = next
  if (video && Number.isFinite(next)) video.currentTime = next / 1000
}

function onSkipOffer() {
  const action = skipOffer.value
  if (!action) return
  dismissedSkips.add(action.key)
  skipEpoch.value += 1
  void performSkip(action)
}

function openSheet(next: 'subtitle' | 'rate' | 'version' | 'info' | 'catalog' | 'skip') {
  menuOpen.value = false
  sheet.value = next
  showControls()
  if (next === 'catalog') void ensureCatalogReady()
}

function applyPlaybackRate(rate: number) {
  playbackRate.value = rate
  if (videoRef.value) videoRef.value.playbackRate = rate
  sheet.value = null
}

async function toggleFullscreen() {
  menuOpen.value = false
  const root = rootRef.value
  if (!root) return
  if (document.fullscreenElement === root) {
    await document.exitFullscreen()
    return
  }
  await root.requestFullscreen()
}

function onFullscreenChange() {
  fullscreen.value = document.fullscreenElement === rootRef.value
}

let chromeHover = false

function onChromeEnter() {
  chromeHover = true
  if (hideTimer != null) {
    window.clearTimeout(hideTimer)
    hideTimer = null
  }
  controlsVisible.value = true
}

function onChromeLeave() {
  chromeHover = false
  if (menuOpen.value || sheet.value || scrubbing.value) return
  const video = videoRef.value
  if (!video || video.paused || ended.value) return
  if (hideTimer != null) window.clearTimeout(hideTimer)
  hideTimer = window.setTimeout(() => {
    hideTimer = null
    if (chromeHover || menuOpen.value || sheet.value || scrubbing.value) return
    if (!videoRef.value || videoRef.value.paused || ended.value) return
    controlsVisible.value = false
  }, 120)
}

function showControls() {
  controlsVisible.value = true
  if (hideTimer != null) window.clearTimeout(hideTimer)
  if (chromeHover) {
    hideTimer = null
    return
  }
  const hide = () => {
    const video = videoRef.value
    if (chromeHover || menuOpen.value || sheet.value || scrubbing.value) {
      hideTimer = window.setTimeout(hide, 2500)
      return
    }
    if (!video || video.paused || ended.value) return
    controlsVisible.value = false
  }
  hideTimer = window.setTimeout(hide, 2500)
}

async function chooseFile(fileId: number) {
  sheet.value = null
  if (fileId === activeFileId.value) return
  await replacePlay(fileId)
}

function leave() {
  if (window.history.state?.back) {
    router.back()
    return
  }
  void router.push({ name: 'wall' })
}

function onKey(event: KeyboardEvent) {
  const target = event.target
  const tag = target instanceof HTMLElement ? target.tagName : ''
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return
  if (event.key === ' ') {
    if (tag === 'BUTTON') return
    event.preventDefault()
    togglePlay()
    return
  }
  if (event.key === 'ArrowLeft') {
    event.preventDefault()
    seekBy(event.repeat ? -5 : -10)
    return
  }
  if (event.key === 'ArrowRight') {
    event.preventDefault()
    seekBy(event.repeat ? 5 : 10)
    return
  }
  if (event.key === 'f' || event.key === 'F') {
    event.preventDefault()
    void toggleFullscreen()
    return
  }
  if (event.key === 'Escape') {
    if (sheet.value || menuOpen.value) {
      sheet.value = null
      menuOpen.value = false
      return
    }
    if (document.fullscreenElement) {
      void document.exitFullscreen()
      return
    }
    leave()
  }
}

async function reportProgress(force: boolean, keepalive = false) {
  if (!hasPlayed || !activeFileId.value) return
  const video = videoRef.value
  if (!video) return
  let position = Math.round((Number.isFinite(video.currentTime) ? video.currentTime : 0) * 1000)
  const duration = Number.isFinite(video.duration) && video.duration > 0
    ? Math.round(video.duration * 1000)
    : currentFile.value?.durationMs || 0
  if ((video.ended || ended.value) && duration > 0) position = duration
  if (!force && Math.abs(position - lastReported) < 2000) return
  lastReported = position
  const body = {
    libraryFileId: activeFileId.value,
    positionMs: position,
    ...(duration > 0 ? { durationMs: duration } : {}),
  }
  if (keepalive) {
    void fetch('/api/playback/progress', {
      method: 'PUT',
      credentials: 'include',
      keepalive: true,
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    })
    return
  }
  try {
    await putPlaybackProgress(body)
  } catch {
    // 离开页面时进度写失败不打断播放
  }
}

function startTicker() {
  stopTicker()
  ticker = window.setInterval(() => {
    void reportProgress(false)
  }, 10_000)
}

function stopTicker() {
  if (ticker != null) {
    window.clearInterval(ticker)
    ticker = null
  }
}

function onPageHide() {
  void reportProgress(true, true)
}

function onVisibility() {
  if (document.visibilityState === 'hidden') void reportProgress(true, true)
}

watch(
  () => route.params.fileId,
  () => {
    void openFile()
  },
  { immediate: true },
)

onBeforeRouteUpdate(async (to, from) => {
  if (String(to.params.fileId) !== String(from.params.fileId)) {
    await reportProgress(true)
  }
})

onBeforeRouteLeave(async () => {
  await reportProgress(true)
})

function syncNarrow() {
  narrow.value = narrowQuery?.matches ?? window.matchMedia('(max-width: 720px)').matches
}

onMounted(() => {
  narrowQuery = window.matchMedia('(max-width: 720px)')
  narrow.value = narrowQuery.matches
  narrowQuery.addEventListener('change', syncNarrow)
  document.addEventListener('fullscreenchange', onFullscreenChange)
  document.addEventListener('keydown', onKey)
  window.addEventListener('pagehide', onPageHide)
  document.addEventListener('visibilitychange', onVisibility)
})

onBeforeUnmount(() => {
  narrowQuery?.removeEventListener('change', syncNarrow)
  stopTicker()
  stopSkipRepeat()
  if (hideTimer != null) window.clearTimeout(hideTimer)
  if (toastTimer != null) window.clearTimeout(toastTimer)
  if (clickTimer != null) window.clearTimeout(clickTimer)
  document.removeEventListener('fullscreenchange', onFullscreenChange)
  document.removeEventListener('keydown', onKey)
  window.removeEventListener('pagehide', onPageHide)
  document.removeEventListener('visibilitychange', onVisibility)
  void reportProgress(true, true)
  clearSubtitle()
})
</script>

<template>
  <div ref="rootRef" class="folio-player">
    <video
      v-if="contentUrl && !pageError"
      :key="activeFileId"
      ref="videoRef"
      :src="contentUrl"
      playsinline
      preload="auto"
      @loadedmetadata="applyResume"
      @canplay="onCanPlay"
      @waiting="onWaiting"
      @playing="onPlaying"
      @pause="onPause"
      @ended="onEnded"
      @timeupdate="onTime"
      @progress="onTime"
      @seeked="onSeeked"
      @error="onMediaError"
    />

    <div
      v-if="contentUrl && !pageError && !opening && !mediaFailed"
      class="hit"
      @click="onSurfaceClick"
      @dblclick="onSurfaceDblClick"
    />

    <div v-if="opening && !pageError && !mediaFailed" class="prepare">
      <div v-if="posterUrl" class="prepare-blur" :style="{ backgroundImage: `url(${posterUrl})` }" />
      <div class="prepare-shade" />
      <button type="button" class="icon-btn prepare-back" aria-label="返回" @click="leave">
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z" /></svg>
      </button>
      <div class="prepare-body">
        <img v-if="posterUrl" class="prepare-poster" :src="posterUrl" alt="" />
        <div class="prepare-copy">
          <h1>{{ title || displayFileName || '播放' }}</h1>
          <p v-if="subtitle" class="prepare-subtitle">{{ subtitle }}</p>
          <p v-if="metaLine" class="prepare-meta">{{ metaLine }}</p>
          <p v-if="genresLine" class="prepare-genres">{{ genresLine }}</p>
          <div v-if="ratings.length" class="prepare-ratings">
            <span v-for="row in ratings" :key="row.provider" class="prepare-rating">
              <img v-if="row.logoUrl" class="prepare-rating-logo" :src="row.logoUrl" :alt="ratingLabel(row.provider)" />
              <span v-else class="prepare-rating-name">{{ ratingLabel(row.provider) }}</span>
              {{ formatPrepareRating(row) }}
            </span>
          </div>
          <p class="prepare-status"><span class="live-dot" />播放准备中</p>
        </div>
      </div>
    </div>

    <div v-if="pageError" class="stage-message">
      <p>{{ pageError }}</p>
    </div>
    <div v-else-if="mediaFailed" class="stage-message">
      <p v-if="mediaDetail" class="stage-title">{{ mediaDetail }}</p>
      <p>浏览器无法直接播放这个文件</p>
    </div>
    <div v-else-if="buffering && !opening" class="spinner" role="status" aria-label="正在缓冲" />

    <p v-if="toastText" class="toast">{{ toastText }}</p>

    <div
      v-if="!opening || pageError || mediaFailed"
      class="chrome-zone top-zone"
      @pointerenter="onChromeEnter"
      @pointerleave="onChromeLeave"
    >
      <header class="chrome top" :class="{ hidden: !chromeOn }">
        <button type="button" class="icon-btn" aria-label="返回" @click="leave">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z" /></svg>
        </button>
        <h1 class="file-name">{{ headerTitle }}</h1>
        <button
          v-if="(showPlaylist || showCatalog) && !pageError"
          type="button"
          class="word-btn"
          @click="openCatalog"
        >
          {{ showPlaylist ? '播放列表' : '选集' }}
        </button>
        <div v-if="!pageError" class="more-wrap">
          <button type="button" class="icon-btn" aria-label="更多" :aria-expanded="menuOpen" @click="openMenu">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 8a2 2 0 1 0 0-4 2 2 0 0 0 0 4zm0 2a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm0 6a2 2 0 1 0 0 4 2 2 0 0 0 0-4z" /></svg>
          </button>
          <div v-if="menuOpen" class="more-menu" role="menu">
            <button type="button" role="menuitem" @click="openSheet('subtitle')">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zM7 15H5v-2h2v2zm0-4H5V9h2v2zm4 4H9v-2h2v2zm0-4H9V9h2v2zm8 4h-6v-2h6v2zm0-4h-6V9h6v2z" /></svg>
              字幕
            </button>
            <button type="button" role="menuitem" @click="openSheet('rate')">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20.38 8.57l-1.23 1.85a8 8 0 0 1-.22 7.58H5.07A8 8 0 0 1 15.58 6.85l1.85-1.23A10 10 0 0 0 3.35 19a2 2 0 0 0 1.72 1h13.85a2 2 0 0 0 1.74-1 10 10 0 0 0-.27-10.44zM10.59 15.41a2 2 0 0 0 2.83 0l5.66-8.49-8.49 5.66a2 2 0 0 0 0 2.83z" /></svg>
              倍速 {{ rateLabel(playbackRate) }}
            </button>
            <button type="button" role="menuitem" @click="openSheet('skip')">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6v12l8.5-6L6 6zm10 0h2v12h-2z" /></svg>
              片头片尾 · {{ skipModeLabel(skipMode) }}
            </button>
            <button v-if="multipleFiles" type="button" role="menuitem" @click="openSheet('version')">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6h16v2H4zm0 5h16v2H4zm0 5h16v2H4z" /></svg>
              版本
            </button>
            <button type="button" role="menuitem" @click="toggleFullscreen">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z" /></svg>
              {{ fullscreen ? '退出全屏' : '全屏' }}
            </button>
            <button type="button" role="menuitem" @click="openSheet('info')">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M11 7h2v2h-2zm0 4h2v6h-2zm1-9C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z" /></svg>
              INFO
            </button>
          </div>
        </div>
      </header>
    </div>

    <button
      v-if="skipOffer"
      type="button"
      class="skip-segment"
      @click.stop="onSkipOffer"
    >
      {{ skipOffer.label }}
    </button>

    <div
      v-if="!pageError && !mediaFailed && !opening"
      class="chrome-zone bottom-zone"
      @pointerenter="onChromeEnter"
      @pointerleave="onChromeLeave"
    >
      <footer class="chrome bottom" :class="{ hidden: !chromeOn }">
        <div class="transport">
          <button
            type="button"
            class="transport-btn"
            aria-label="后退5秒"
            @pointerdown="onSkipDown(-5)"
            @pointerup="stopSkipRepeat"
            @pointerleave="stopSkipRepeat"
            @pointercancel="stopSkipRepeat"
            @click="onSkipClick(-5)"
          >
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12.5 8V4.5L8 9l4.5 4.5V9a5 5 0 1 1-5 5H6a6.5 6.5 0 1 0 6.5-6.5z" /><text x="12" y="15.5" text-anchor="middle" font-size="7" font-weight="700">5</text></svg>
          </button>
          <button type="button" class="transport-btn" aria-label="上一个" @click="playAdjacent(-1)">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6h2v12H6zm3.5 6 8.5 6V6z" /></svg>
          </button>
          <button type="button" class="transport-btn play" :aria-label="paused ? '播放' : '暂停'" @click="togglePlay">
            <svg v-if="paused" viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14l11-7z" /></svg>
            <svg v-else viewBox="0 0 24 24" aria-hidden="true"><path d="M6 5h4v14H6zm8 0h4v14h-4z" /></svg>
          </button>
          <button type="button" class="transport-btn" aria-label="下一个" @click="playAdjacent(1)">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 18l8.5-6L6 6v12zm10-12v12h2V6z" /></svg>
          </button>
          <button
            type="button"
            class="transport-btn"
            aria-label="前进5秒"
            @pointerdown="onSkipDown(5)"
            @pointerup="stopSkipRepeat"
            @pointerleave="stopSkipRepeat"
            @pointercancel="stopSkipRepeat"
            @click="onSkipClick(5)"
          >
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M11.5 8V4.5L16 9l-4.5 4.5V9a5 5 0 1 0 5 5H18a6.5 6.5 0 1 1-6.5-6.5z" /><text x="12" y="15.5" text-anchor="middle" font-size="7" font-weight="700">5</text></svg>
          </button>
        </div>
        <div class="seek-row">
          <span class="time">{{ formatClock(shownPosition) }}</span>
          <div class="seek-wrap">
            <div class="seek-rail" aria-hidden="true">
              <span class="seek-buffer" :style="{ width: `${bufferedRatio * 100}%` }" />
              <span class="seek-played" :style="{ width: `${playedRatio * 100}%` }" />
            </div>
            <input
              class="seek"
              type="range"
              min="0"
              :max="durationMs || 0"
              step="1000"
              :value="shownPosition"
              :disabled="!durationMs"
              aria-label="进度"
              @pointerdown="onScrubPointerDown"
              @pointerup="onScrubPointerUp"
              @pointercancel="onScrubPointerUp"
              @input="onScrubInput"
              @change="onScrubCommit"
            />
          </div>
          <button
            type="button"
            class="time time-end"
            :aria-label="showRemaining ? '剩余时间，点击切换为总时长' : '总时长，点击切换为剩余时间'"
            @click="showRemaining = !showRemaining"
          >
            {{ endTimeLabel }}
          </button>
        </div>
      </footer>
    </div>

    <div v-if="sheet" class="sheet-layer" :class="{ sheet: narrow }">
      <button type="button" class="sheet-scrim" aria-label="关闭" @click="sheet = null" />
      <div class="sheet" :class="{ catalog: sheet === 'catalog' }" role="dialog" aria-modal="true" :aria-label="sheetTitle">
      <div v-if="narrow" class="sheet-grabber" aria-hidden="true" />
      <div class="sheet-head">
        <h2>{{ sheetTitle }}</h2>
        <button
          v-if="sheet === 'catalog' && isSeriesCatalog && !showPlaylist"
          type="button"
          class="icon-btn"
          :aria-label="catalogGridMode ? '列表' : '宫格'"
          @click="catalogGridMode = !catalogGridMode"
        >
          <svg v-if="catalogGridMode" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6h16v2H4V6zm0 5h16v2H4v-2zm0 5h16v2H4v-2z" /></svg>
          <svg v-else viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h6v6H4V4zm10 0h6v6h-6V4zM4 14h6v6H4v-6zm10 0h6v6h-6v-6z" /></svg>
        </button>
        <button type="button" class="icon-btn" aria-label="关闭" @click="sheet = null">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z" /></svg>
        </button>
      </div>
      <div v-if="sheet === 'subtitle'" class="sheet-list" role="listbox">
        <button type="button" role="option" :aria-selected="activeSubtitle == null && activeEmbedded == null" @click="chooseSubtitle(null)">关闭</button>
        <p v-if="!subtitles.length && !embeddedSubtitles.length" class="sheet-empty">{{ emptySubtitleHint }}</p>
        <template v-if="subtitles.length">
          <p class="sheet-label">外挂</p>
          <button
            v-for="item in subtitles"
            :key="item.name"
            type="button"
            role="option"
            :aria-selected="activeSubtitle === item.name"
            @click="chooseSubtitle(item.name)"
          >
            {{ item.name }}
          </button>
        </template>
        <template v-if="embeddedSubtitles.length">
          <p class="sheet-label">内嵌</p>
          <button
            v-for="track in embeddedSubtitles"
            :key="track.index"
            type="button"
            role="option"
            :aria-selected="activeEmbedded === track.index"
            @click="chooseEmbedded(track.index)"
          >
            {{ embeddedLabel(track) }}
          </button>
        </template>
      </div>
      <div v-else-if="sheet === 'skip'" class="sheet-list" role="listbox">
        <button
          v-for="mode in skipModes"
          :key="mode.id"
          type="button"
          role="option"
          :aria-selected="mode.id === skipMode"
          @click="chooseSkipMode(mode.id)"
        >
          <strong>{{ mode.label }}</strong>
          <small>{{ mode.hint }}</small>
        </button>
      </div>
      <div v-else-if="sheet === 'rate'" class="sheet-list" role="listbox">
        <button
          v-for="rate in rates"
          :key="rate"
          type="button"
          role="option"
          :aria-selected="rate === playbackRate"
          @click="applyPlaybackRate(rate)"
        >
          {{ rateLabel(rate) }}
        </button>
      </div>
      <div v-else-if="sheet === 'version'" class="sheet-list" role="listbox">
        <button
          v-for="file in files"
          :key="file.id"
          type="button"
          role="option"
          :aria-selected="file.id === activeFileId"
          @click="chooseFile(file.id)"
        >
          <strong>{{ file.fileName }}</strong>
          <small v-if="fileQualityLabel(file)">{{ fileQualityLabel(file) }}</small>
        </button>
      </div>
      <div v-else-if="sheet === 'catalog' && showPlaylist" class="catalog-body playlist-sheet">
        <div v-if="playlistLoading && !playlistQueue.length" class="catalog-status">加载中…</div>
        <div v-else-if="playlistError && !playlistQueue.length" class="catalog-status">
          <p>{{ playlistError }}</p>
          <button type="button" class="catalog-retry" @click="ensurePlaylistQueue">重试</button>
        </div>
        <div v-else class="playlist-list" role="listbox">
          <p v-if="!playlistQueue.length" class="sheet-empty">这个播放列表没有可播放的视频</p>
          <template v-for="(entry, index) in playlistQueue" :key="`${entry.workId}-${entry.fileId}-${index}`">
            <p
              v-if="entry.kind === 'series' && (index === 0 || playlistQueue[index - 1]?.workId !== entry.workId)"
              class="playlist-group"
            >
              {{ entry.workTitle }}
            </p>
            <button
              type="button"
              class="playlist-row"
              role="option"
              :aria-selected="playlistCursor() === index"
              :disabled="playlistCursor() === index"
              @click="playPlaylistEntry(entry)"
            >
              <strong>{{ entry.kind === 'series' ? entry.label : entry.workTitle }}</strong>
              <small v-if="entry.kind !== 'series'">电影</small>
            </button>
          </template>
        </div>
      </div>
      <div v-else-if="sheet === 'catalog'" class="catalog-body">
        <div v-if="catalogLoading && !catalogLoaded" class="catalog-status">加载中…</div>
        <div v-else-if="catalogError && !catalogLoaded" class="catalog-status">
          <p>{{ catalogError }}</p>
          <button type="button" class="catalog-retry" @click="retryCatalog">重试</button>
        </div>
        <div v-else-if="!isSeriesCatalog" class="sheet-list catalog-movies" role="listbox">
          <p v-if="!catalogMates.length" class="sheet-empty">没有系列作品</p>
          <button
            v-for="mate in catalogMates"
            :key="mate.id"
            type="button"
            role="option"
            :aria-selected="isMovieSelected(mate.id)"
            :disabled="isMovieSelected(mate.id)"
            @click="playCatalogMovie(mate)"
          >
            <img v-if="mate.posterUrl" class="catalog-poster" :src="mate.posterUrl" alt="" />
            <span v-else class="catalog-poster placeholder" />
            <span class="catalog-movie-copy">
              <strong>{{ mate.title }}</strong>
              <small v-if="mate.year">{{ mate.year }}</small>
            </span>
          </button>
        </div>
        <div v-else-if="catalogGridMode" class="catalog-grid">
          <p v-if="!catalogSeasons.length" class="sheet-empty">没有剧集</p>
          <section v-for="season in catalogSeasons" :key="season.seasonNumber" class="catalog-season">
            <h3>{{ season.heading }}</h3>
            <div class="catalog-ep-grid">
              <button
                v-for="episode in season.episodes"
                :key="`${season.seasonNumber}-${episode.episodeNumber}`"
                type="button"
                class="catalog-ep-cell"
                :class="{
                  selected: isEpisodeSelected(season.seasonNumber, episode.episodeNumber),
                  disabled: !episode.files.length,
                }"
                :disabled="!episode.files.length"
                @click="playCatalogEpisode(season.seasonNumber, episode)"
              >
                {{ episode.episodeNumber }}
              </button>
            </div>
          </section>
        </div>
        <div v-else class="catalog-list">
          <p v-if="!catalogSeasons.length" class="sheet-empty">没有剧集</p>
          <section v-for="season in catalogSeasons" :key="season.seasonNumber" class="catalog-season">
            <h3>{{ season.heading }}</h3>
            <button
              v-for="episode in season.episodes"
              :key="`${season.seasonNumber}-${episode.episodeNumber}`"
              type="button"
              class="catalog-ep-row"
              :class="{
                selected: isEpisodeSelected(season.seasonNumber, episode.episodeNumber),
                disabled: !episode.files.length,
              }"
              :disabled="!episode.files.length"
              @click="playCatalogEpisode(season.seasonNumber, episode)"
            >
              <span class="ep-num">{{ episode.episodeNumber }}</span>
              <span class="ep-copy">
                <strong>{{ episode.title?.trim() || `第 ${episode.episodeNumber} 集` }}</strong>
                <small v-if="episode.runtimeMinutes">{{ episode.runtimeMinutes }} 分钟</small>
              </span>
            </button>
          </section>
        </div>
      </div>
      <dl v-else class="info-list">
        <div v-for="row in infoRows" :key="row.label">
          <dt>{{ row.label }}</dt>
          <dd>{{ row.value }}</dd>
        </div>
        <p v-if="!infoRows.length" class="sheet-empty">没有视频信息</p>
      </dl>
      </div>
    </div>
  </div>
</template>

<style scoped>
.folio-player {
  position: relative;
  height: 100vh;
  height: 100dvh;
  background: #000;
  color: #fff;
  overflow: hidden;
  user-select: none;
}

.folio-player:fullscreen {
  width: 100%;
  height: 100%;
}

video {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: contain;
  background: #000;
}

.hit {
  position: absolute;
  inset: 0;
  z-index: 1;
  border: 0;
  background: transparent;
}

.prepare {
  position: absolute;
  inset: 0;
  z-index: 6;
  display: grid;
  place-items: center;
  background: #050505;
}

.prepare-blur {
  position: absolute;
  inset: -10%;
  background-position: center right;
  background-size: cover;
  filter: blur(32px);
  transform: scale(1.18);
  transform-origin: center right;
}

.prepare-shade {
  position: absolute;
  inset: 0;
  background: linear-gradient(
    90deg,
    rgba(0, 0, 0, 0.7) 0%,
    rgba(0, 0, 0, 0.6) 45%,
    rgba(0, 0, 0, 0.8) 100%
  );
}

.prepare-back {
  position: absolute;
  top: calc(0.35rem + var(--safe-top));
  left: calc(0.35rem + var(--safe-left));
  z-index: 1;
}

.prepare-body {
  position: relative;
  z-index: 1;
  display: flex;
  align-items: center;
  gap: 1.5rem;
  max-width: min(40rem, calc(100% - 4.5rem));
  padding: 1.5rem 2.25rem;
}

.prepare-poster {
  height: clamp(8.75rem, 42vh, 13.75rem);
  width: auto;
  aspect-ratio: 2 / 3;
  object-fit: cover;
  border-radius: 10px;
  box-shadow: 0 16px 40px rgba(0, 0, 0, 0.45);
  flex-shrink: 0;
}

.prepare-copy {
  min-width: 0;
  max-width: 26.25rem;
}

.prepare-copy h1 {
  margin: 0;
  font-family: var(--font-display);
  font-size: 1.375rem;
  font-weight: 700;
  line-height: 1.25;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.prepare-copy p {
  margin: 0.5rem 0 0;
  color: rgba(255, 255, 255, 0.78);
  font-size: 0.8125rem;
  line-height: 1.35;
}

.prepare-subtitle {
  margin-top: 0.5rem !important;
}

.prepare-meta {
  margin-top: 0.625rem !important;
  color: rgba(255, 255, 255, 0.82) !important;
}

.prepare-genres {
  margin-top: 0.375rem !important;
  color: rgba(255, 255, 255, 0.72) !important;
}

.prepare-ratings {
  display: flex;
  flex-wrap: wrap;
  gap: 0.375rem;
  margin-top: 0.75rem;
}

.prepare-rating {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  padding: 0.2rem 0.5rem;
  border-radius: 999px;
  border: 1px solid rgba(255, 255, 255, 0.16);
  background: rgba(255, 255, 255, 0.04);
  color: rgba(255, 255, 255, 0.92);
  font-size: 0.75rem;
  line-height: 1;
}

.prepare-rating-name {
  color: rgba(255, 255, 255, 0.62);
}

.prepare-rating-logo {
  height: 0.875rem;
  width: auto;
  object-fit: contain;
}

.prepare-status {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-top: 1rem !important;
  color: var(--copper) !important;
  font-size: 0.875rem !important;
  font-weight: 600;
}

.live-dot {
  width: 0.5rem;
  height: 0.5rem;
  border-radius: 50%;
  background: var(--copper);
  box-shadow: 0 0 0 0 rgba(212, 165, 116, 0.55);
  animation: live-pulse 1.4s ease-out infinite;
}

@keyframes live-pulse {
  70% {
    box-shadow: 0 0 0 7px rgba(212, 165, 116, 0);
  }
  100% {
    box-shadow: 0 0 0 0 rgba(212, 165, 116, 0);
  }
}

.stage-message {
  position: absolute;
  inset: 0;
  z-index: 2;
  display: grid;
  place-items: center;
  align-content: center;
  gap: 0.35rem;
  padding: 4.5rem 1.5rem 6rem;
  text-align: center;
}

.stage-message p {
  margin: 0;
  max-width: 28rem;
  line-height: 1.45;
}

.stage-title {
  color: rgba(255, 255, 255, 0.72);
  font-size: 0.92rem;
}

.spinner {
  position: absolute;
  top: 50%;
  left: 50%;
  z-index: 2;
  width: 2.25rem;
  height: 2.25rem;
  margin: -1.125rem 0 0 -1.125rem;
  border: 3px solid rgba(255, 255, 255, 0.22);
  border-top-color: #fff;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

.toast {
  position: absolute;
  top: 28%;
  left: 50%;
  z-index: 7;
  margin: 0;
  padding: 0.45rem 0.9rem;
  border-radius: 999px;
  background: rgba(0, 0, 0, 0.8);
  font-size: 0.88rem;
  transform: translateX(-50%);
  pointer-events: none;
}

.chrome-zone {
  position: absolute;
  left: 0;
  right: 0;
  z-index: 3;
  pointer-events: auto;
}

.top-zone {
  top: 0;
}

.bottom-zone {
  bottom: 0;
}

.chrome {
  transition: opacity 0.18s ease;
}

.chrome.hidden {
  opacity: 0;
  pointer-events: none;
}

.top {
  display: flex;
  align-items: center;
  gap: 0.15rem;
  padding: calc(0.25rem + var(--safe-top)) calc(0.35rem + var(--safe-right)) 2.4rem calc(0.35rem + var(--safe-left));
  background: linear-gradient(180deg, rgba(0, 0, 0, 0.8), transparent);
}

.file-name {
  flex: 1;
  min-width: 0;
  margin: 0;
  overflow: hidden;
  font-size: 1rem;
  font-weight: 500;
  line-height: 1.25;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.icon-btn,
.transport-btn {
  display: grid;
  place-items: center;
  margin: 0;
  padding: 0;
  border: 0;
  background: transparent;
  color: #fff;
  cursor: pointer;
}

.icon-btn {
  width: 2.5rem;
  height: 2.5rem;
  border-radius: 999px;
}

.word-btn {
  flex: none;
  margin: 0;
  padding: 0.35rem 0.45rem;
  border: 0;
  border-radius: 999px;
  background: transparent;
  color: #fff;
  font: inherit;
  font-size: 0.95rem;
  font-weight: 600;
  line-height: 1;
  cursor: pointer;
}

.word-btn:hover {
  background: rgba(255, 255, 255, 0.08);
}

.icon-btn svg,
.transport-btn svg,
.more-menu svg {
  width: 1.35rem;
  height: 1.35rem;
  fill: currentColor;
}

.icon-btn:hover,
.transport-btn:hover,
.more-menu button:hover,
.sheet-list button:hover {
  background: rgba(255, 255, 255, 0.08);
}

.more-wrap {
  position: relative;
}

.skip-segment {
  position: absolute;
  z-index: 4;
  top: 50%;
  right: calc(1.15rem + var(--safe-right));
  margin: 0;
  padding: 0.42rem 0.85rem;
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 999px;
  background: rgba(10, 12, 16, 0.36);
  color: rgba(242, 239, 232, 0.78);
  font: inherit;
  font-size: 0.82rem;
  font-weight: 500;
  letter-spacing: 0.02em;
  transform: translateY(-50%);
  cursor: pointer;
}

.more-menu {
  position: absolute;
  top: calc(100% - 0.15rem);
  right: 0.2rem;
  z-index: 4;
  display: grid;
  min-width: 15rem;
  padding: 0.35rem 0;
  border-radius: 8px;
  background: #2a2a2a;
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.45);
}

.more-menu button {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  width: 100%;
  margin: 0;
  padding: 0.62rem 0.9rem;
  border: 0;
  background: transparent;
  color: #fff;
  font: inherit;
  font-size: 0.95rem;
  text-align: left;
  cursor: pointer;
}

.more-menu svg {
  flex: none;
  color: rgba(255, 255, 255, 0.72);
}

.bottom {
  display: grid;
  gap: 0.15rem;
  padding: 4.4rem calc(0.75rem + var(--safe-right)) calc(0.55rem + var(--safe-bottom)) calc(0.75rem + var(--safe-left));
  background: linear-gradient(
    0deg,
    rgba(0, 0, 0, 0.86) 0%,
    rgba(0, 0, 0, 0.55) 48%,
    transparent 100%
  );
}

.transport {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.35rem;
}

.transport-btn {
  width: 2.75rem;
  height: 2.75rem;
}

.transport-btn svg {
  width: 1.85rem;
  height: 1.85rem;
}

.transport-btn.play {
  width: 3.4rem;
  height: 3.4rem;
}

.transport-btn.play svg {
  width: 2.6rem;
  height: 2.6rem;
}

.seek-row {
  display: flex;
  align-items: center;
  gap: 0.55rem;
}

.time {
  flex: none;
  min-width: 2.6rem;
  color: rgba(255, 255, 255, 0.92);
  font-size: 0.78rem;
  font-variant-numeric: tabular-nums;
}

button.time-end {
  margin: 0;
  padding: 0.2rem 0;
  border: 0;
  background: transparent;
  font: inherit;
  text-align: right;
  cursor: pointer;
  min-width: 3rem;
}

button.time-end:hover {
  color: #fff;
}

.seek-wrap {
  position: relative;
  flex: 1;
  height: 1.5rem;
}

.seek-rail {
  position: absolute;
  top: 50%;
  right: 0;
  left: 0;
  height: 3px;
  overflow: hidden;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.2);
  transform: translateY(-50%);
}

.seek-buffer,
.seek-played {
  position: absolute;
  top: 0;
  bottom: 0;
  left: 0;
}

.seek-buffer {
  background: rgba(255, 255, 255, 0.55);
}

.seek-played {
  background: var(--copper);
}

.seek {
  position: absolute;
  inset: 0;
  width: 100%;
  margin: 0;
  background: transparent;
  cursor: pointer;
  appearance: none;
}

.seek::-webkit-slider-runnable-track {
  height: 3px;
  background: transparent;
}

.seek::-webkit-slider-thumb {
  width: 10px;
  height: 10px;
  margin-top: -3.5px;
  border: 0;
  border-radius: 50%;
  background: #fff;
  appearance: none;
}

.seek::-moz-range-track {
  height: 3px;
  background: transparent;
  border: 0;
}

.seek::-moz-range-thumb {
  width: 10px;
  height: 10px;
  border: 0;
  border-radius: 50%;
  background: #fff;
}

.sheet-layer {
  position: absolute;
  inset: 0;
  z-index: 8;
  display: grid;
  place-items: center;
  padding: 1.25rem;
}

.sheet-layer.sheet {
  place-items: end stretch;
  padding: 0;
}

.sheet-scrim {
  position: absolute;
  inset: 0;
  border: 0;
  background: rgba(0, 0, 0, 0.45);
  cursor: pointer;
}

.sheet {
  position: relative;
  z-index: 1;
  display: flex;
  flex-direction: column;
  width: min(28rem, 100%);
  max-height: min(80dvh, 36rem);
  overflow: hidden;
  border-radius: 16px;
  background: #1c1c1c;
  box-shadow: 0 18px 50px rgba(0, 0, 0, 0.45);
}

.sheet.catalog {
  width: min(36rem, 100%);
}

.sheet.catalog:has(.catalog-movies) {
  width: max-content;
  max-width: min(40rem, 100%);
}

.sheet.catalog:has(.catalog-movies) .sheet-head {
  padding-left: 1.5rem;
  padding-right: 0.75rem;
}

.sheet-layer.sheet .sheet,
.sheet-layer.sheet .sheet.catalog,
.sheet-layer.sheet .sheet.catalog:has(.catalog-movies) {
  width: 100%;
  max-width: 100%;
  max-height: min(88dvh, 100%);
  border-radius: 16px 16px 0 0;
  padding-bottom: var(--safe-bottom);
}

.sheet-grabber {
  width: 2.4rem;
  height: 0.25rem;
  margin: 0.55rem auto 0;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.28);
}

.sheet-head {
  display: flex;
  flex: none;
  align-items: center;
  gap: 0.15rem;
  padding: 0.7rem 0.4rem 0.2rem 1rem;
}

.sheet-head h2 {
  flex: 1;
  margin: 0;
  font-size: 1rem;
  font-weight: 650;
}

.catalog-body {
  flex: 0 1 auto;
  min-height: 0;
  overflow: auto;
  padding: 0.15rem 0 0.45rem;
}

.catalog-status {
  display: grid;
  place-items: center;
  gap: 0.75rem;
  min-height: 8rem;
  padding: 1.5rem;
  color: rgba(255, 255, 255, 0.72);
  text-align: center;
}

.playlist-sheet {
  min-height: 12rem;
}

.playlist-list {
  min-width: 16rem;
}

.playlist-group {
  margin: 0.85rem 0 0.1rem;
  padding: 0 1rem;
  color: rgba(255, 255, 255, 0.62);
  font-size: 0.82rem;
}

.playlist-row {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 0.12rem;
  width: 100%;
  margin: 0;
  padding: 0.68rem 1rem;
  border: 0;
  background: transparent;
  color: #fff;
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.playlist-row strong {
  font-weight: 600;
}

.playlist-row small {
  color: rgba(255, 255, 255, 0.62);
  font-size: 0.78rem;
}

.playlist-row[aria-selected='true'],
.playlist-row[aria-selected='true'] small {
  color: var(--copper);
}

.playlist-row:disabled {
  cursor: default;
}

.catalog-retry {
  margin: 0;
  padding: 0.4rem 0.9rem;
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 999px;
  background: transparent;
  color: #fff;
  font: inherit;
  cursor: pointer;
}

.catalog-movies {
  display: flex;
  gap: 0.85rem;
  padding: 0.35rem 1rem 0.85rem;
}

.catalog-poster {
  width: 5.6rem;
  height: 8.4rem;
  object-fit: cover;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.08);
}

.catalog-poster.placeholder {
  display: block;
}

.catalog-movie-copy {
  min-width: 0;
  display: grid;
  gap: 0.1rem;
}

.catalog-movie-copy strong,
.catalog-movie-copy small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.catalog-season {
  padding: 0.4rem 0.85rem 0.75rem;
}

.catalog-season h3 {
  margin: 0 0 0.55rem;
  color: var(--copper);
  font-size: 0.82rem;
  font-weight: 650;
}

.catalog-ep-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.catalog-ep-cell {
  width: 2.5rem;
  height: 2.5rem;
  margin: 0;
  padding: 0;
  border: 0;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.08);
  color: #fff;
  font: inherit;
  font-size: 0.82rem;
  font-weight: 500;
  cursor: pointer;
}

.catalog-ep-cell.selected {
  background: rgba(212, 165, 116, 0.22);
  color: var(--copper);
  font-weight: 700;
}

.catalog-ep-cell.disabled,
.catalog-ep-row.disabled {
  opacity: 0.35;
  cursor: default;
}

.catalog-ep-row {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  width: 100%;
  margin: 0;
  padding: 0.65rem 0.15rem;
  border: 0;
  background: transparent;
  color: #fff;
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.catalog-ep-row.selected,
.catalog-ep-row.selected .ep-copy small {
  color: var(--copper);
}

.catalog-ep-row .ep-num {
  flex: none;
  width: 2rem;
  font-weight: 650;
}

.catalog-ep-row .ep-copy {
  min-width: 0;
  display: grid;
  gap: 0.15rem;
}

.catalog-ep-row .ep-copy strong {
  font-weight: 550;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.catalog-ep-row .ep-copy small {
  color: rgba(255, 255, 255, 0.62);
  font-size: 0.78rem;
}

.sheet-list {
  min-height: 0;
  flex: 1 1 auto;
  overflow: auto;
  padding: 0.2rem 0 0.6rem;
}

.sheet-list button {
  display: grid;
  width: 100%;
  margin: 0;
  padding: 0.72rem 1rem;
  border: 0;
  background: transparent;
  color: #fff;
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.sheet-list button[aria-selected='true'] {
  color: var(--copper);
}

.catalog-movies.sheet-list {
  padding: 0.5rem 1.5rem 1.25rem;
}

.catalog-movies.sheet-list button {
  display: grid;
  flex: none;
  width: 5.6rem;
  justify-items: start;
  gap: 0.35rem;
  padding: 0;
  text-align: left;
}

.sheet-list strong,
.sheet-list small {
  display: block;
}

.sheet-list strong {
  font-weight: 600;
}

.sheet-list small {
  margin-top: 0.15rem;
  color: rgba(255, 255, 255, 0.62);
  font-size: 0.78rem;
}

.sheet-list button[aria-selected='true'] small {
  color: var(--copper);
}

.sheet-empty {
  margin: 0;
  padding: 0.8rem 1rem 1rem;
  color: rgba(255, 255, 255, 0.62);
}

.sheet-label {
  margin: 0.2rem 0 0;
  padding: 0.55rem 1rem 0.1rem;
  color: rgba(255, 255, 255, 0.45);
  font-size: 0.75rem;
}

.info-list {
  min-height: 0;
  flex: 1 1 auto;
  overflow: auto;
  margin: 0;
  padding: 0.2rem 1rem 1rem;
}

.info-list div {
  display: grid;
  grid-template-columns: 6.5rem minmax(0, 1fr);
  gap: 0.75rem;
  padding: 0.45rem 0;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}

.info-list dt {
  margin: 0;
  color: rgba(255, 255, 255, 0.55);
}

.info-list dd {
  margin: 0;
  overflow-wrap: anywhere;
}

@media (max-width: 640px) {
  .prepare-body {
    flex-direction: column;
    align-items: center;
    text-align: center;
    padding: 1.25rem 1.5rem;
  }

  .prepare-copy {
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .prepare-ratings,
  .prepare-status {
    justify-content: center;
  }
}
</style>

<style>
.folio-player video::cue {
  color: #fff;
  background-color: rgba(0, 0, 0, 0.6);
}

.folio-player canvas.JASSUB {
  z-index: 1;
}
</style>
