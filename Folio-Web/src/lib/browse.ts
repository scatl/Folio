import type { ListWorksParams } from '../api/client'

export interface WorkBrowseFilter {
  watch: string
  sort: string
  genreIds: string[]
  yearFrom: string
  yearTo: string
  ratingProvider: string
  ratingMin: string
  countries: string[]
  languages: string[]
  runtimes: string[]
  keywordIds: string[]
  personId: string
  personLabel: string
  companyIds: string[]
  collectionIds: string[]
  inCollection: boolean
  showStatuses: string[]
  resolutions: string[]
  dynamicRanges: string[]
  videoCodecs: string[]
  audioCodecs: string[]
  subtitle: string
}

export function emptyBrowseFilter(): WorkBrowseFilter {
  return {
    watch: '',
    sort: 'popularity',
    genreIds: [],
    yearFrom: '',
    yearTo: '',
    ratingProvider: '',
    ratingMin: '',
    countries: [],
    languages: [],
    runtimes: [],
    keywordIds: [],
    personId: '',
    personLabel: '',
    companyIds: [],
    collectionIds: [],
    inCollection: false,
    showStatuses: [],
    resolutions: [],
    dynamicRanges: [],
    videoCodecs: [],
    audioCodecs: [],
    subtitle: '',
  }
}

function selectionCount(key: string, value: WorkBrowseFilter[keyof WorkBrowseFilter]) {
  if (key === 'personLabel') return 0
  if (key === 'sort') return value !== 'popularity' ? 1 : 0
  if (Array.isArray(value)) return value.length
  if (typeof value === 'boolean') return value ? 1 : 0
  return value ? 1 : 0
}

export function browseActive(filter: WorkBrowseFilter) {
  return Object.entries(filter).some(([key, value]) => selectionCount(key, value) > 0)
}

export function browseCount(filter: WorkBrowseFilter) {
  return Object.entries(filter).reduce((sum, [key, value]) => sum + selectionCount(key, value), 0)
}

function num(value: string) {
  if (!value) return undefined
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : undefined
}

function csv(values: string[]) {
  return values.length ? values.join(',') : undefined
}

export function browseParams(filter: WorkBrowseFilter): ListWorksParams {
  return {
    sort: filter.sort !== 'popularity' ? filter.sort : undefined,
    watch: filter.watch || undefined,
    genreId: csv(filter.genreIds),
    yearFrom: num(filter.yearFrom),
    yearTo: num(filter.yearTo),
    ratingProvider: filter.ratingProvider || undefined,
    ratingMin: num(filter.ratingMin),
    country: csv(filter.countries),
    language: csv(filter.languages),
    runtime: csv(filter.runtimes),
    keywordId: csv(filter.keywordIds),
    personId: num(filter.personId),
    companyId: csv(filter.companyIds),
    collectionId: csv(filter.collectionIds),
    inCollection: filter.inCollection || undefined,
    showStatus: csv(filter.showStatuses),
    resolution: csv(filter.resolutions),
    dynamicRange: csv(filter.dynamicRanges),
    videoCodec: csv(filter.videoCodecs),
    audioCodec: csv(filter.audioCodecs),
    subtitle: filter.subtitle || undefined,
  }
}

export function watchLabel(state: string | null | undefined) {
  if (state === 'watched') return '已看'
  if (state === 'watching') return '在看'
  if (state === 'unwatched') return '未看'
  return ''
}
