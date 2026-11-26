export type SkipMode = 'off' | 'button' | 'auto'

export type MediaSegment = {
  kind: string
  startMs: number
  endMs: number | null
}

export type SkipAction = {
  key: string
  label: string
  targetMs: number
  advance: boolean
}

const STORAGE_KEY = 'folio.player.skipSegments'
const INTRO = new Set(['intro', 'recap'])
const CREDITS = new Set(['credits', 'preview'])
const MIN_MS = 5000
const GAP_MS = 2000

export function readSkipMode(): SkipMode {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw === 'off' || raw === 'button' || raw === 'auto') return raw
  } catch {
    // 无痕模式写不了本地设置时，保持默认。
  }
  return 'button'
}

export function writeSkipMode(mode: SkipMode) {
  try {
    localStorage.setItem(STORAGE_KEY, mode)
  } catch {
    // 忽略
  }
}

export function skipModeLabel(mode: SkipMode): string {
  if (mode === 'off') return '关闭'
  if (mode === 'auto') return '自动跳过'
  return '显示按钮'
}

type Range = { start: number; end: number }

function resolveEnd(endMs: number | null, durationMs: number): number | null {
  if (endMs != null) return endMs
  if (durationMs > 0) return durationMs
  return null
}

function mergeRanges(segments: MediaSegment[], kinds: Set<string>, durationMs: number): Range[] {
  const ranges: Range[] = []
  const rows = segments
    .filter((item) => kinds.has(item.kind))
    .map((item) => ({ start: Math.max(0, item.startMs), end: resolveEnd(item.endMs, durationMs) }))
    .filter((item): item is Range => item.end != null && item.end - item.start >= MIN_MS)
    .sort((a, b) => a.start - b.start)
  for (const row of rows) {
    const last = ranges[ranges.length - 1]
    if (last && row.start <= last.end + GAP_MS) last.end = Math.max(last.end, row.end)
    else ranges.push({ start: row.start, end: row.end })
  }
  return ranges
}

function postCreditStart(segments: MediaSegment[]): number | null {
  const rows = segments.filter(
    (item) => item.kind === 'post_credits' && item.endMs != null && item.endMs - item.startMs >= MIN_MS,
  )
  if (!rows.length) return null
  return Math.min(...rows.map((item) => item.startMs))
}

function insidePostCredits(positionMs: number, segments: MediaSegment[]): boolean {
  return segments.some((item) => {
    if (item.kind !== 'post_credits' || item.endMs == null) return false
    return positionMs >= item.startMs && positionMs < item.endMs
  })
}

export function skipAction(
  positionMs: number,
  durationMs: number,
  segments: MediaSegment[],
  series: boolean,
  dismissed: ReadonlySet<string>,
): SkipAction | null {
  if (!segments.length || positionMs < 0 || insidePostCredits(positionMs, segments)) return null
  const post = postCreditStart(segments)
  const groups = [
    { label: '跳过片头', ranges: mergeRanges(segments, INTRO, durationMs), credits: false },
    { label: '跳过片尾', ranges: mergeRanges(segments, CREDITS, durationMs), credits: true },
  ]
  for (const group of groups) {
    for (const range of group.ranges) {
      if (positionMs < range.start || positionMs >= range.end - 400) continue
      const key = `${group.label}:${range.start}`
      if (dismissed.has(key)) continue
      let targetMs = range.end
      if (group.credits && post != null && post > range.start + 1000 && post < range.end + 1500) {
        targetMs = post
      }
      const atEnd = durationMs > 0 && targetMs >= durationMs - 3000
      return {
        key,
        label: group.label,
        targetMs,
        advance: group.credits && series && atEnd && targetMs === range.end,
      }
    }
  }
  return null
}
