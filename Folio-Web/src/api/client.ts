import type {
  AppSettings,
  AppSettingsUpdate,
  AuthUser,
  LibraryPermission,
  BrowseResult,
  CreateMediaLibraryBody,
  ManualMatchResult,
  MatchCandidate,
  MediaLibrary,
  PageResult,
  ReviewFileRow,
  ScrapeJobRow,
  ScrapeJobStats,
  EpisodeDetailView,
  EmbeddedSubtitle,
  FileView,
  PlaybackProgress,
  SeasonDetailView,
  ServerConnections,
  ServerIdentity,
  CollectionCard,
  CollectionDetail,
  PersonDetail,
  HomeView,
  WorkCard,
  WorkFacets,
  WorkWatch,
  WatchlistFlag,
  WatchlistItem,
  PlaylistDetail,
  MediaSegments,
  PlaylistQueueEntry,
  PlaylistSummary,
  WorkView,
  ServerLogContent,
  ServerLogList,
} from './types'

interface ApiResponse<T> {
  code: number
  data: T | null
  msg: string
}

let unauthorizedHandler: (() => void) | null = null

export function setUnauthorizedHandler(handler: (() => void) | null) {
  unauthorizedHandler = handler
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, {
    credentials: 'include',
    headers: { Accept: 'application/json', ...(init?.headers ?? {}) },
    ...init,
  })

  let body: ApiResponse<T> | null = null
  try {
    body = (await res.json()) as ApiResponse<T>
  } catch {
    // fall through
  }

  if (res.status === 401 && !path.startsWith('/api/auth/')) {
    unauthorizedHandler?.()
  }

  if (!res.ok) {
    throw new Error(body?.msg || `请求失败 (${res.status})`)
  }
  if (!body || typeof body.code !== 'number') {
    throw new Error('响应格式无效')
  }
  if (body.code !== 0) {
    throw new Error(body.msg || `请求失败 (${body.code})`)
  }
  if (body.data == null) {
    throw new Error(body.msg || '响应数据为空')
  }
  return body.data
}

async function requestNullable<T>(path: string, init?: RequestInit): Promise<T | null> {
  const res = await fetch(path, {
    credentials: 'include',
    headers: { Accept: 'application/json', ...(init?.headers ?? {}) },
    ...init,
  })

  let body: ApiResponse<T> | null = null
  try {
    body = (await res.json()) as ApiResponse<T>
  } catch {
    // fall through
  }

  if (res.status === 401 && !path.startsWith('/api/auth/')) {
    unauthorizedHandler?.()
  }

  if (!res.ok) {
    throw new Error(body?.msg || `请求失败 (${res.status})`)
  }
  if (!body || typeof body.code !== 'number') {
    throw new Error('响应格式无效')
  }
  if (body.code !== 0) {
    throw new Error(body.msg || `请求失败 (${body.code})`)
  }
  return body.data
}

export interface ListWorksParams {
  kind?: string
  libraryId?: number
  q?: string
  page?: number
  size?: number
  sort?: string
  watch?: string
  genreId?: string
  yearFrom?: number
  yearTo?: number
  ratingProvider?: string
  ratingMin?: number
  country?: string
  language?: string
  runtime?: string
  keywordId?: string
  personId?: number
  companyId?: string
  collectionId?: string
  inCollection?: boolean
  showStatus?: string
  resolution?: string
  dynamicRange?: string
  videoCodec?: string
  audioCodec?: string
  subtitle?: string
  personQ?: string
}

function worksQuery(params: ListWorksParams) {
  const query = new URLSearchParams()
  for (const [key, value] of Object.entries(params)) {
    if (value == null || value === '' || value === false) continue
    query.set(key, String(value))
  }
  return query
}

export function listWorks(params: ListWorksParams = {}) {
  const query = worksQuery({ page: 0, size: 48, ...params })
  return request<PageResult<WorkCard>>(`/api/works?${query}`)
}

export function listWorkFacets(params: { libraryId?: number; personQ?: string } = {}) {
  return request<WorkFacets>(`/api/works/facets?${worksQuery(params)}`)
}

export function getWork(id: number) {
  return request<WorkView>(`/api/works/${id}`)
}

export function getWorkByExternal(params: { provider: string; externalId: string; kind: string }) {
  const query = new URLSearchParams({
    provider: params.provider,
    externalId: params.externalId,
    kind: params.kind,
  })
  return request<WorkView>(`/api/works/detail?${query}`)
}

export function refreshWork(id: number) {
  return request<WorkView>(`/api/works/${id}/refresh`, { method: 'POST' })
}

export function getWorkCard(id: number) {
  return request<WorkCard>(`/api/works/${id}/card`)
}

export function listCollectionSiblings(workId: number) {
  return request<WorkCard[]>(`/api/works/${workId}/collection`)
}

export function listLibraryCollections(libraryId: number) {
  return request<CollectionCard[]>(`/api/libraries/${libraryId}/collections`)
}

export function listCollectionWorks(libraryId: number, collectionId: string) {
  const query = new URLSearchParams({ collectionId })
  return request<WorkCard[]>(`/api/libraries/${libraryId}/collections/works?${query}`)
}

export function getCollection(id: string) {
  return request<CollectionDetail>(`/api/collections/${encodeURIComponent(id)}`)
}

export function getPerson(provider: string, externalId: string) {
  return request<PersonDetail>(
    `/api/people/${encodeURIComponent(provider)}/${encodeURIComponent(externalId)}`,
  )
}

export function refreshPerson(provider: string, externalId: string) {
  return request<PersonDetail>(
    `/api/people/${encodeURIComponent(provider)}/${encodeURIComponent(externalId)}/refresh`,
    { method: 'POST' },
  )
}

export function getSeason(workId: number, seasonNumber: number) {
  return request<SeasonDetailView>(`/api/works/${workId}/seasons/${seasonNumber}`)
}

export function getFile(id: number) {
  return request<FileView>(`/api/library/files/${id}`)
}

export function getMediaSegments(fileId: number) {
  return request<MediaSegments>(`/api/library/files/${fileId}/segments`)
}

export function listSubtitles(fileId: number) {
  return request<string[]>(`/api/library/files/${fileId}/subtitles`)
}

export function listEmbeddedSubtitles(fileId: number) {
  return request<EmbeddedSubtitle[]>(`/api/library/files/${fileId}/embedded-subtitles`)
}

export async function fetchEmbeddedSubtitle(fileId: number, index: number): Promise<string> {
  const res = await fetch(`/api/library/files/${fileId}/embedded-subtitles/content?index=${index}`, {
    credentials: 'include',
  })
  if (res.status === 401) unauthorizedHandler?.()
  if (!res.ok) {
    let message = '内嵌字幕读取失败'
    try {
      const body = (await res.json()) as { msg?: string }
      if (body.msg) message = body.msg
    } catch {
      // 失败响应不一定是 JSON
    }
    throw new Error(message)
  }
  return res.text()
}

export async function fetchSubtitleBytes(fileId: number, name: string): Promise<Uint8Array> {
  const query = new URLSearchParams({ name })
  const res = await fetch(`/api/library/files/${fileId}/subtitles/content?${query}`, {
    credentials: 'include',
  })
  if (res.status === 401) unauthorizedHandler?.()
  if (!res.ok) throw new Error('字幕加载失败')
  return new Uint8Array(await res.arrayBuffer())
}

export function getFilePlayback(libraryFileId: number) {
  return requestNullable<PlaybackProgress>(`/api/playback/progress?libraryFileId=${libraryFileId}`)
}

export function getWorkPlayback(workId: number) {
  return requestNullable<PlaybackProgress>(`/api/playback/progress/work/${workId}`)
}

export function getWorkWatch(workId: number) {
  return request<WorkWatch>(`/api/playback/works/${workId}`)
}

export function putWorkWatch(workId: number, watched: boolean) {
  return request<WorkWatch>(`/api/playback/works/${workId}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ watched }),
  })
}

export function getWatchlist() {
  return request<WatchlistItem[]>('/api/watchlist')
}

export function getWorkWanted(workId: number) {
  return request<WatchlistFlag>(`/api/watchlist/works/${workId}`)
}

export function putWorkWanted(workId: number, wanted: boolean) {
  return request<WatchlistFlag>(`/api/watchlist/works/${workId}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ wanted }),
  })
}

export function listPlaylists(workId?: number) {
  const query = workId != null ? `?workId=${workId}&limit=100` : ''
  return request<PlaylistSummary[]>(`/api/playlists${query}`)
}

export function createPlaylist(name: string, workId?: number) {
  return request<PlaylistSummary>('/api/playlists', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, workId: workId ?? null }),
  })
}

export function getPlaylist(id: number) {
  return request<PlaylistDetail>(`/api/playlists/${id}`)
}

export function renamePlaylist(id: number, name: string) {
  return request<PlaylistDetail>(`/api/playlists/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name }),
  })
}

export function deletePlaylist(id: number) {
  return request<{ id: number }>(`/api/playlists/${id}`, { method: 'DELETE' })
}

export function getPlaylistQueue(id: number) {
  return request<PlaylistQueueEntry[]>(`/api/playlists/${id}/queue`)
}

export function addPlaylistItem(id: number, workId: number) {
  return request<PlaylistSummary>(`/api/playlists/${id}/items`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ workId }),
  })
}

export function removePlaylistItem(id: number, workId: number) {
  return request<PlaylistDetail>(`/api/playlists/${id}/items/${workId}`, { method: 'DELETE' })
}

export function reorderPlaylistItems(id: number, workIds: number[]) {
  return request<PlaylistDetail>(`/api/playlists/${id}/items/order`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ workIds }),
  })
}

export function putPlaybackProgress(body: {
  libraryFileId: number
  positionMs: number
  durationMs?: number
}) {
  return request<PlaybackProgress>('/api/playback/progress', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

export function getEpisode(workId: number, seasonNumber: number, episodeNumber: number) {
  return request<EpisodeDetailView>(
    `/api/works/${workId}/seasons/${seasonNumber}/episodes/${episodeNumber}`,
  )
}

export function listReviewFiles(params: { page?: number; size?: number } = {}) {
  const query = new URLSearchParams()
  query.set('status', 'needs_review')
  query.set('page', String(params.page ?? 0))
  query.set('size', String(params.size ?? 50))
  return request<PageResult<ReviewFileRow>>(`/api/library/files?${query}`)
}

export function searchMatchCandidates(
  fileId: number,
  params: { q?: string; kind?: string; year?: number } = {},
) {
  const query = new URLSearchParams()
  if (params.q) query.set('q', params.q)
  if (params.kind) query.set('kind', params.kind)
  if (params.year != null) query.set('year', String(params.year))
  const qs = query.toString()
  return request<MatchCandidate[]>(
    `/api/library/files/${fileId}/candidates${qs ? `?${qs}` : ''}`,
  )
}

export function refreshFileMedia(fileId: number) {
  return request<ReviewFileRow>(`/api/library/files/${fileId}/probe`, {
    method: 'POST',
  })
}

export function confirmManualMatch(
  fileId: number,
  body: { kind: string; tmdbId: number; year?: number; season?: number; episode?: number; scope?: 'file' | 'work' },
) {
  return request<ManualMatchResult>(`/api/library/files/${fileId}/match`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

export function getHome() {
  return request<HomeView>('/api/home')
}

export function listLibraries() {
  return request<MediaLibrary[]>('/api/libraries')
}

export function reorderLibraries(ids: number[]) {
  return request<{ status: string }>('/api/libraries/order', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ids }),
  })
}

export function deleteLibrary(id: number) {
  return request<{ id: number; status: string }>(`/api/libraries/${id}`, {
    method: 'DELETE',
  })
}

export function scanLibrary(id: number) {
  return request<{ id: number; status: string }>(`/api/libraries/${id}/scan`, {
    method: 'POST',
  })
}

export function createLibrary(body: CreateMediaLibraryBody) {
  return request<MediaLibrary>('/api/libraries', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

export function browseDirectories(path?: string) {
  const query = new URLSearchParams()
  if (path) query.set('path', path)
  const qs = query.toString()
  return request<BrowseResult>(`/api/libraries/browse${qs ? `?${qs}` : ''}`)
}

export function listScrapeJobs(params: { status?: string; page?: number; size?: number } = {}) {
  const query = new URLSearchParams()
  if (params.status) query.set('status', params.status)
  query.set('page', String(params.page ?? 0))
  query.set('size', String(params.size ?? 50))
  return request<PageResult<ScrapeJobRow>>(`/api/scrape-jobs?${query}`)
}

export function getScrapeJobStats() {
  return request<ScrapeJobStats>('/api/scrape-jobs/stats')
}

export function deleteScrapeJob(id: number) {
  return request<{ id: number }>(`/api/scrape-jobs/${id}`, {
    method: 'DELETE',
  })
}

export function retryScrapeJob(id: number) {
  return request<ScrapeJobRow>(`/api/scrape-jobs/${id}/retry`, {
    method: 'POST',
  })
}

export async function getAuthMe(): Promise<AuthUser | null> {
  try {
    const res = await fetch('/api/auth/me', {
      credentials: 'include',
      headers: { Accept: 'application/json' },
    })
    if (res.status === 401) return null
    let body: ApiResponse<AuthUser> | null = null
    try {
      body = (await res.json()) as ApiResponse<AuthUser>
    } catch {
      return null
    }
    if (!res.ok || !body || body.code !== 0 || !body.data) return null
    return body.data
  } catch {
    return null
  }
}

export async function getLoginPosters(): Promise<string[]> {
  try {
    const res = await fetch('/api/auth/posters', {
      credentials: 'include',
      headers: { Accept: 'application/json' },
    })
    let body: ApiResponse<string[]> | null = null
    try {
      body = (await res.json()) as ApiResponse<string[]>
    } catch {
      return []
    }
    if (!res.ok || !body || body.code !== 0 || !Array.isArray(body.data)) return []
    return body.data.filter((url) => typeof url === 'string' && url.length > 0)
  } catch {
    return []
  }
}

export function login(username: string, password: string) {
  return request<AuthUser>('/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
  })
}

export function logout() {
  return request<{ ok: boolean }>('/api/auth/logout', {
    method: 'POST',
  })
}

export function getServerIdentity() {
  return request<ServerIdentity>('/api/server/identity')
}

export function getServerConnections() {
  return request<ServerConnections>('/api/server/connections')
}

export function updateServerRemote(remoteUrl: string | null) {
  return request<ServerConnections>('/api/server/remote', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ remoteUrl }),
  })
}

export function getSettings() {
  return request<AppSettings>('/api/settings')
}

export function updateSettings(body: AppSettingsUpdate) {
  return request<AppSettings>('/api/settings', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

export function listServerLogs() {
  return request<ServerLogList>('/api/logs/server')
}

export function getServerLog(name: string) {
  const query = new URLSearchParams({ name })
  return request<ServerLogContent>(`/api/logs/server/content?${query}`)
}

export function updateAccount(body: {
  currentPassword: string
  username?: string
  newPassword?: string
}) {
  return request<AuthUser>('/api/auth/account', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

export function listUsers() {
  return request<AuthUser[]>('/api/users')
}

export function createUser(body: {
  username: string
  password: string
  role: string
  libraries?: LibraryPermission[]
}) {
  return request<AuthUser>('/api/users', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

export function updateUser(
  id: number,
  body: {
    username?: string
    newPassword?: string
    role?: string
    disabled?: boolean
    libraries?: LibraryPermission[]
  },
) {
  return request<AuthUser>(`/api/users/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

export function deleteUser(id: number) {
  return request<{ ok: boolean }>(`/api/users/${id}`, {
    method: 'DELETE',
  })
}
