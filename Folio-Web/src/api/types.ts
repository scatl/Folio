export type WorkKind = 'movie' | 'series'

export interface LibraryPermission {
  libraryId: number
  access: 'READ' | 'WRITE' | string
}

export interface AuthUser {
  id: number
  username: string
  role: string
  disabled: boolean
  libraries?: LibraryPermission[]
}

export interface ServerIdentity {
  serverId: string
}

export interface LocalEndpoint {
  name: string
  address: string
  url: string
}

export interface ServerConnections {
  serverId: string
  local: LocalEndpoint[]
  remoteUrl: string | null
}

export interface AppSettings {
  tmdbApiKeyConfigured: boolean
  tmdbBaseUrl: string
  tmdbImageBaseUrl: string
  tmdbLanguage: string
  tmdbSearchLanguage: string
  tmdbRequestsPerSecond: number
  omdbApiKeyConfigured: boolean
  omdbBaseUrl: string
  omdbRequestsPerSecond: number
  tvdbEnabled: boolean
  tvdbApiKeyConfigured: boolean
  tvdbPinConfigured: boolean
  tvdbBaseUrl: string
  tvdbRequestsPerSecond: number
  httpTimeoutSeconds: number
  matchAutoThreshold: number
  workerDelayMs: number
  workerMaxAttempts: number
  workerConcurrency: number
  scanIntervalMinutes: number
  watchEnabled: boolean
  playbackIgnoreBelowSeconds: number
  playbackCompleteRemainingSeconds: number
}

export interface AppSettingsUpdate {
  tmdbApiKey?: string | null
  tmdbBaseUrl: string
  tmdbImageBaseUrl: string
  tmdbLanguage: string
  tmdbSearchLanguage: string
  tmdbRequestsPerSecond: number
  omdbApiKey?: string | null
  omdbBaseUrl: string
  omdbRequestsPerSecond: number
  tvdbEnabled: boolean
  tvdbApiKey?: string | null
  tvdbPin?: string | null
  tvdbBaseUrl: string
  tvdbRequestsPerSecond: number
  httpTimeoutSeconds: number
  matchAutoThreshold: number
  workerDelayMs: number
  workerMaxAttempts: number
  workerConcurrency: number
  scanIntervalMinutes: number
  watchEnabled: boolean
  playbackIgnoreBelowSeconds: number
  playbackCompleteRemainingSeconds: number
}

export interface MediaLibraryFile {
  id: number
  fileName: string
  locator: string
  status: string
}

export interface MediaLibrary {
  id: number
  name: string
  kind: WorkKind | string
  rootPath: string
  files: MediaLibraryFile[]
  createdAt: string
  workCount?: number
  /** READ 或 WRITE；管理员对所有库为 WRITE。 */
  access?: string
}

export interface BrowseEntry {
  name: string
  path: string
}

export interface BrowseResult {
  path: string
  parent: string | null
  directories: BrowseEntry[]
}

export interface CreateMediaLibraryBody {
  name?: string
  kind: WorkKind
  rootPath: string
}

export type JobStatus = 'queued' | 'running' | 'succeeded' | 'failed'

export interface ScrapeJobRow {
  id: number
  status: JobStatus | string
  attempts: number
  maxAttempts: number
  nextRunAt: string
  lastError: string | null
  progress: string | null
  createdAt: string
  updatedAt: string
  fileId: number
  fileName: string
  locator: string
  matchStatus: string
  parsedTitle: string | null
  parsedYear: number | null
  parsedSeason: number | null
  parsedEpisode: number | null
  confidence: number | null
  message: string | null
  workId: number | null
  mediaLibraryId: number | null
  mediaLibraryName: string | null
}

export interface ScrapeJobStats {
  active: number
}

export interface CollectionCard {
  id: string
  name: string
  posterUrl: string | null
  count: number
}

export interface CollectionPart {
  tmdbId: string
  title: string
  originalTitle: string | null
  overview: string | null
  year: number | null
  releaseDate: string | null
  posterUrl: string | null
  backdropUrl: string | null
  workId: number | null
  hasLocalMedia: boolean
  rating: number | null
  voteCount: number | null
  genres: string[]
  originalLanguage: string | null
}

export interface CollectionDetail {
  id: string
  name: string
  overview: string | null
  posterUrl: string | null
  backdropUrl: string | null
  parts: CollectionPart[]
  localCount: number
}

export interface WorkCard {
  id: number
  kind: WorkKind | string
  originalTitle: string
  title: string
  year: number | null
  posterUrl: string | null
  backdropUrl: string | null
  rating: number | null
  voteCount: number | null
  genres: string[]
  popularity: number | null
  overview: string | null
  watchState?: 'unwatched' | 'watching' | 'watched' | string | null
}

export interface FacetOption {
  id: string
  label: string
  count: number
}

export interface WorkFacets {
  genres: FacetOption[]
  countries: FacetOption[]
  languages: FacetOption[]
  keywords: FacetOption[]
  companies: FacetOption[]
  collections: FacetOption[]
  videoCodecs: string[]
  dynamicRanges: string[]
  audioCodecs: string[]
  yearMin: number | null
  yearMax: number | null
  people: FacetOption[]
}

export interface WorkWatch {
  workId: number
  watchState: string
}

export interface PageResult<T> {
  items: T[]
  page: number
  size: number
  total: number
  totalPages: number
}

export interface HomeSetupView {
  tmdbConfigured: boolean
}

export interface ContinueWatchItem {
  workId: number
  workTitle: string
  kind: string
  posterUrl: string | null
  libraryFileId: number
  fileName?: string | null
  positionMs: number
  durationMs: number | null
  completed: boolean
  resumePositionMs: number | null
  progressRatio: number
  seasonNumber: number | null
  episodeNumber: number | null
  episodeTitle: string | null
  subtitle: string
}

export interface PlaybackProgress {
  libraryFileId: number
  workId: number | null
  episodeId: number | null
  fileName?: string | null
  positionMs: number
  durationMs: number | null
  completed: boolean
  resumePositionMs: number | null
  updatedAt: string
  seasonNumber?: number | null
  episodeNumber?: number | null
  episodeTitle?: string | null
}

export interface WorkSummary {
  id: number
  kind: string
  originalTitle: string
  year: number | null
  sourceProvider: string
  translations: TranslationView[]
}

export interface FileView {
  id: number
  fileName: string
  locator: string
  status: string
  parsedTitle: string | null
  parsedYear: number | null
  parsedSeason: number | null
  parsedEpisode: number | null
  parsedImdbId: string | null
  confidence: number | null
  message: string | null
  workId: number | null
  episodeId: number | null
  work: WorkSummary | null
}

export interface WatchlistFlag {
  workId: number
  wanted: boolean
}

export interface WatchlistItem {
  workId: number
  workTitle: string
  kind: string
  year: number | null
  posterUrl: string | null
  subtitle: string
}

export interface PlaylistSummary {
  id: number
  name: string
  itemCount: number
  posterUrl: string | null
  contains: boolean
}

export interface PlaylistItem {
  workId: number
  workTitle: string
  kind: string
  year: number | null
  posterUrl: string | null
  subtitle: string
  playFileId: number | null
  playFileName: string | null
  seasonNumber: number | null
  episodeNumber: number | null
  episodeTitle: string | null
}

export interface PlaylistDetail {
  id: number
  name: string
  items: PlaylistItem[]
}

export interface MediaSegment {
  kind: string
  startMs: number
  endMs: number | null
}

export interface MediaSegments {
  segments: MediaSegment[]
}

export interface PlaylistQueueEntry {
  workId: number
  workTitle: string
  kind: string
  posterUrl: string | null
  fileId: number
  fileName: string
  seasonNumber: number | null
  episodeNumber: number | null
  episodeTitle: string | null
  label: string
}

export interface HomeView {
  libraries: MediaLibrary[] | null
  recent: PageResult<WorkCard> | null
  continueWatching?: ContinueWatchItem[] | null
  watchlist?: WatchlistItem[] | null
  playlists?: PlaylistSummary[] | null
  setup: HomeSetupView | null
}

export interface AudioTrackView {
  codec: string | null
  channels: number | null
  language: string | null
  bitrate: number | null
  sampleRate?: number | null
  channelLayout?: string | null
  profile?: string | null
}

export interface SubtitleTrackView {
  codec: string | null
  language: string | null
}

export interface EmbeddedSubtitle {
  index: number
  codec: string | null
  language: string | null
  title: string | null
}

export interface ReviewFileRow {
  id: number
  fileName: string
  locator: string
  status: string
  parsedTitle: string | null
  parsedYear: number | null
  parsedSeason: number | null
  parsedEpisode: number | null
  confidence: number | null
  message: string | null
  fileSize?: number | null
  sourceModifiedAt?: string | null
  container?: string | null
  durationMs?: number | null
  videoCodec?: string | null
  videoWidth?: number | null
  videoHeight?: number | null
  videoFrameRate?: number | null
  videoBitrate?: number | null
  videoBitDepth?: number | null
  videoDynamicRange?: string | null
  videoProfile?: string | null
  videoPixelFormat?: string | null
  audioTracks?: AudioTrackView[]
  subtitleTracks?: SubtitleTrackView[]
}

export interface MatchCandidate {
  provider: string
  kind: string
  externalId: string
  title: string | null
  originalTitle: string | null
  year: number | null
  overview: string | null
  posterUrl: string | null
  score: number
}

export interface ManualMatchResult {
  fileId: number
  workId: number | null
  status: string
}

export interface TranslationView {
  locale: string
  title: string
  overview: string | null
  tagline: string | null
}

export interface ArtworkView {
  provider: string
  kind: string
  locale: string | null
  remoteUrl: string
}

export interface CreditView {
  provider: string
  externalId: string
  name: string
  profileUrl: string | null
  department: string | null
  job: string | null
  character: string | null
  order: number
}

export interface PersonView {
  provider: string
  externalId: string
  name: string
  profileUrl: string | null
  images: ArtworkView[]
}

export interface PersonWorkCredit {
  mediaType: string
  tmdbId: string
  title: string
  originalTitle: string | null
  year: number | null
  releaseDate: string | null
  posterUrl: string | null
  character: string | null
  job: string | null
  department: string | null
  workId: number | null
  hasLocalMedia: boolean
}

export interface PersonDetail {
  provider: string
  externalId: string
  name: string
  biography: string | null
  birthday: string | null
  deathday: string | null
  placeOfBirth: string | null
  profileUrl: string | null
  knownForDepartment: string | null
  alsoKnownAs: string[]
  credits: PersonWorkCredit[]
  localCount: number
  detailFetchedAt: string | null
}

export interface EpisodeView {
  id: number
  episodeNumber: number
  absoluteNumber: number | null
  title: string | null
  overview: string | null
  airDate: string | null
  runtimeMinutes: number | null
  voteAverage: number | null
  voteCount: number | null
  artworks: ArtworkView[]
  files: ReviewFileRow[]
}

export interface SeasonView {
  id: number
  seasonNumber: number
  name: string | null
  episodeCount: number | null
  localEpisodeCount: number
  airDate: string | null
  overview: string | null
  artworks: ArtworkView[]
  episodes: EpisodeView[]
}

export interface SeasonDetailView {
  workId: number
  workKind: string
  workTitle: string
  originalTitle: string
  season: SeasonView
}

export interface EpisodeDetailView {
  workId: number
  workKind: string
  workTitle: string
  originalTitle: string
  seasonNumber: number
  seasonName: string | null
  episode: EpisodeView
  productionCode?: string | null
  credits?: CreditView[]
  externalIds?: ExternalIdView[]
  videos?: VideoView[]
}

export interface RatingView {
  provider: string
  value: number
  votes: number | null
  scale: number
  logoUrl: string | null
}

export interface ExternalIdView {
  provider: string
  externalId: string
  logoUrl: string | null
}

export interface NameView {
  externalId: string
  name: string
}

export interface CompanyView {
  externalId: string
  name: string
  originCountry: string | null
  logoUrl: string | null
  role: string
}

export interface CountryView {
  code: string
  name: string | null
  kind: string
}

export interface LanguageView {
  code: string
  name: string | null
}

export interface VideoView {
  externalId: string
  site: string | null
  type: string | null
  name: string | null
  key: string | null
  language: string | null
  official: boolean | null
}

export interface WorkView {
  id: number
  kind: WorkKind | string
  originalTitle: string
  originalLanguage: string | null
  year: number | null
  premiereDate: string | null
  runtimeMinutes: number | null
  status: string | null
  homepage: string | null
  popularity: number | null
  budget: number | null
  revenue: number | null
  adult: boolean | null
  showType: string | null
  inProduction: boolean | null
  lastAirDate: string | null
  numberOfSeasons: number | null
  numberOfEpisodes: number | null
  collectionExternalId: string | null
  collectionName: string | null
  awards: string | null
  sourceProvider: string
  translations: TranslationView[]
  externalIds: ExternalIdView[]
  ratings: RatingView[]
  artworks: ArtworkView[]
  credits: CreditView[]
  people: PersonView[]
  genres: NameView[]
  companies: CompanyView[]
  countries: CountryView[]
  spokenLanguages: LanguageView[]
  keywords: NameView[]
  videos: VideoView[]
  seasons: SeasonView[]
  libraryFiles: ReviewFileRow[]
}

export interface ServerLogFile {
  name: string
  label: string
  size: number
  compressed: boolean
  modifiedAt: string
}

export interface ServerLogList {
  directory: string | null
  available: boolean
  message: string | null
  files: ServerLogFile[]
}

export interface ServerLogContent {
  name: string
  label: string
  size: number
  compressed: boolean
  modifiedAt: string
  truncated: boolean
  lineCount: number
  totalLines: number
  text: string
}
