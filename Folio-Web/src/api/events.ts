import type { ScrapeJobRow, ScrapeJobStats } from './types'

type JobHandler = (job: ScrapeJobRow) => void
type StatsHandler = (stats: ScrapeJobStats) => void
type DeletedHandler = (id: number) => void
type DoneHandler = (job: ScrapeJobRow) => void
type WorkRemovedHandler = (workId: number) => void

const jobHandlers = new Set<JobHandler>()
const statsHandlers = new Set<StatsHandler>()
const deletedHandlers = new Set<DeletedHandler>()
const doneHandlers = new Set<DoneHandler>()
const workRemovedHandlers = new Set<WorkRemovedHandler>()

let source: EventSource | null = null
let refCount = 0

function ensureConnected() {
  if (source && source.readyState !== EventSource.CLOSED) return
  source = new EventSource('/api/events')

  source.addEventListener('scrape.job', (ev) => {
    const job = parseJson<ScrapeJobRow>((ev as MessageEvent).data)
    if (!job) return
    jobHandlers.forEach((handler) => handler(job))
  })

  source.addEventListener('scrape.stats', (ev) => {
    const stats = parseJson<ScrapeJobStats>((ev as MessageEvent).data)
    if (!stats) return
    statsHandlers.forEach((handler) => handler(stats))
  })

  source.addEventListener('scrape.done', (ev) => {
    const job = parseJson<ScrapeJobRow>((ev as MessageEvent).data)
    if (!job) return
    doneHandlers.forEach((handler) => handler(job))
  })

  source.addEventListener('scrape.deleted', (ev) => {
    const payload = parseJson<{ id: number }>((ev as MessageEvent).data)
    if (!payload) return
    deletedHandlers.forEach((handler) => handler(payload.id))
  })

  source.addEventListener('work.removed', (ev) => {
    const payload = parseJson<{ workId: number }>((ev as MessageEvent).data)
    if (!payload) return
    workRemovedHandlers.forEach((handler) => handler(payload.workId))
  })

  source.onerror = () => {
    // 浏览器会自动重连；保持 source 引用即可
  }
}

function parseJson<T>(raw: string): T | null {
  try {
    return JSON.parse(raw) as T
  } catch {
    return null
  }
}

function retain() {
  refCount += 1
  ensureConnected()
}

function release() {
  refCount = Math.max(0, refCount - 1)
  if (refCount === 0 && source) {
    source.close()
    source = null
  }
}

export function subscribeScrapeEvents(handlers: {
  onJob?: JobHandler
  onStats?: StatsHandler
  onDeleted?: DeletedHandler
  onDone?: DoneHandler
  onWorkRemoved?: WorkRemovedHandler
}) {
  retain()
  if (handlers.onJob) jobHandlers.add(handlers.onJob)
  if (handlers.onStats) statsHandlers.add(handlers.onStats)
  if (handlers.onDeleted) deletedHandlers.add(handlers.onDeleted)
  if (handlers.onDone) doneHandlers.add(handlers.onDone)
  if (handlers.onWorkRemoved) workRemovedHandlers.add(handlers.onWorkRemoved)

  return () => {
    if (handlers.onJob) jobHandlers.delete(handlers.onJob)
    if (handlers.onStats) statsHandlers.delete(handlers.onStats)
    if (handlers.onDeleted) deletedHandlers.delete(handlers.onDeleted)
    if (handlers.onDone) doneHandlers.delete(handlers.onDone)
    if (handlers.onWorkRemoved) workRemovedHandlers.delete(handlers.onWorkRemoved)
    release()
  }
}
