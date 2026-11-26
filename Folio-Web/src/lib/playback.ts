import type { ReviewFileRow } from '../api/types'

const textSubtitleExtensions = new Set(['srt', 'vtt'])
const assSubtitleExtensions = new Set(['ass', 'ssa'])

export function isAssSubtitle(name: string): boolean {
  return assSubtitleExtensions.has(subtitleExtension(name))
}

function subtitleExtension(name: string): string {
  const dot = name.lastIndexOf('.')
  return dot >= 0 ? name.slice(dot + 1).toLowerCase() : ''
}

export interface SubtitleCandidate {
  name: string
  ext: string
  score: number
}

export function formatClock(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000))
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const seconds = total % 60
  if (hours > 0) {
    return `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
  }
  return `${minutes}:${String(seconds).padStart(2, '0')}`
}

export function localizedTitle(
  originalTitle: string,
  translations: { locale: string; title: string }[],
): string {
  const zh = translations.find((item) => item.locale === 'zh-CN' && item.title.trim())
  return zh?.title.trim() || originalTitle
}

export function resolutionLabel(width: number | null | undefined, height: number | null | undefined): string {
  const h = height ?? 0
  const w = width ?? 0
  if (h >= 1600 || w >= 3000) return '4K'
  if (h >= 900 || w >= 1600) return '1080p'
  if (h >= 650 || w >= 1100) return '720p'
  if (h > 0) return `${h}p`
  return ''
}

export function codecLabel(codec: string | null | undefined): string {
  const key = (codec ?? '').trim().toLowerCase()
  if (!key) return ''
  if (key === 'hevc' || key === 'h265' || key === 'h.265') return 'HEVC'
  if (key === 'h264' || key === 'avc' || key === 'h.264') return 'H.264'
  if (key === 'av1') return 'AV1'
  if (key === 'vp9') return 'VP9'
  if (key === 'mpeg4' || key === 'mpeg2video') return key === 'mpeg2video' ? 'MPEG-2' : 'MPEG-4'
  return key.toUpperCase()
}

export function containerLabel(file: Pick<ReviewFileRow, 'container' | 'fileName'>): string {
  const container = file.container?.trim()
  if (container) return container.toLowerCase()
  const ext = file.fileName.includes('.') ? file.fileName.slice(file.fileName.lastIndexOf('.') + 1) : ''
  return ext.toLowerCase()
}

export function fileQualityLabel(file: Pick<ReviewFileRow, 'videoWidth' | 'videoHeight' | 'videoCodec'>): string {
  return [resolutionLabel(file.videoWidth, file.videoHeight), codecLabel(file.videoCodec)].filter(Boolean).join(' · ')
}

export function playbackFailureDetail(
  file: Pick<ReviewFileRow, 'container' | 'fileName' | 'videoCodec'> | null,
): string {
  if (!file) return ''
  return [containerLabel(file), codecLabel(file.videoCodec)].filter(Boolean).join(' · ')
}

export function rankSubtitles(videoFileName: string, names: string[]): SubtitleCandidate[] {
  const stem = fileStem(videoFileName).toLowerCase()
  const ranked: SubtitleCandidate[] = []
  for (const raw of names) {
    const name = raw.trim()
    if (!name) continue
    const ext = subtitleExtension(name)
    if (!textSubtitleExtensions.has(ext) && !assSubtitleExtensions.has(ext)) continue
    ranked.push({ name, ext, score: subtitleScore(stem, name) })
  }
  ranked.sort((a, b) => b.score - a.score || a.name.localeCompare(b.name, 'zh-CN'))
  return ranked
}

export function decodeSubtitle(bytes: Uint8Array): string {
  if (bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xfe) {
    return new TextDecoder('utf-16le').decode(bytes.subarray(2))
  }
  if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) {
    return new TextDecoder('utf-16be').decode(bytes.subarray(2))
  }
  if (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    return new TextDecoder('utf-8').decode(bytes.subarray(3))
  }
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes)
  } catch {
    try {
      return new TextDecoder('gbk').decode(bytes)
    } catch {
      return new TextDecoder('utf-8').decode(bytes)
    }
  }
}

export function toWebVtt(text: string): string {
  const cleaned = text.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim()
  if (cleaned.startsWith('WEBVTT')) return `${cleaned}\n`
  const body = cleaned.replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2')
  return `WEBVTT\n\n${body}\n`
}

function fileStem(fileName: string): string {
  const slash = fileName.replaceAll('\\', '/').lastIndexOf('/')
  const base = slash >= 0 ? fileName.slice(slash + 1) : fileName
  const dot = base.lastIndexOf('.')
  if (dot <= 0) return base
  return base.slice(0, dot)
}

function subtitleScore(videoStem: string, subtitleName: string): number {
  if (!videoStem) return 0
  const subStem = fileStem(subtitleName).toLowerCase()
  if (subStem === videoStem) return 100
  if (
    subStem.startsWith(`${videoStem}.`) ||
    subStem.startsWith(`${videoStem}_`) ||
    subStem.startsWith(`${videoStem} `)
  ) {
    return 80
  }
  if (subStem.startsWith(videoStem)) return 60
  if (subStem.includes(videoStem)) return 40
  return 0
}
