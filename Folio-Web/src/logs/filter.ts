export type LogLevel = 'all' | 'debug' | 'info' | 'warn' | 'error'

export type Severity = Exclude<LogLevel, 'all'>

export const logLevels: { id: LogLevel; label: string }[] = [
  { id: 'all', label: '全部' },
  { id: 'debug', label: '调试' },
  { id: 'info', label: '信息' },
  { id: 'warn', label: '警告' },
  { id: 'error', label: '错误' },
]

const recordStart = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}/

/** Spring Boot 文件日志：`时间 级别 进程 --- [应用名] [线程] logger : 正文` */
const serverLine =
  /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\s+(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL)(?:\s+(\d+))?(?:\s+---)?((?:\s+\[[^\]]*\])*)\s+(\S+)\s+:\s?(.*)$/

const levelHead =
  /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\s+(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL)\b\s*(.*)$/

/** 客户端诊断日志：`时间 [tag] 正文` */
const clientLine =
  /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\s+\[([^\]]+)\]\s?(.*)$/

const timestampLine =
  /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\s*(.*)$/

const bracket = /\[([^\]]*)\]/g

export interface LogEntry {
  level: Severity
  lines: string[]
  date: string | null
  time: string | null
  source: string
  detail: string | null
  message: string
  extra: string[]
}

export function levelName(level: Severity): string {
  switch (level) {
    case 'debug':
      return '调试'
    case 'warn':
      return '警告'
    case 'error':
      return '错误'
    default:
      return '信息'
  }
}

/** 把日志原文拆成记录。筛级别时堆栈跟所属记录走。 */
export function parseLog(text: string): LogEntry[] {
  if (!text) return []
  const records: LogEntry[] = []
  let current: LogEntry | null = null
  for (const raw of text.split('\n')) {
    const line = raw.replace(/\r$/, '')
    if (current == null || recordStart.test(line)) {
      trimExtra(current)
      current = entryFrom(line)
      records.push(current)
    } else {
      current.lines.push(line)
      current.extra.push(line)
    }
  }
  trimExtra(current)
  return records
}

export function filterRecords(text: string, level: LogLevel): LogEntry[] {
  const records = parseLog(text)
  if (level === 'all') return records
  return records.filter((record) => record.level === level)
}

export function filterLog(text: string, level: LogLevel): { text: string; count: number } {
  const records = filterRecords(text, level)
  return {
    text: records.map((record) => record.lines.join('\n')).join('\n'),
    count: records.length,
  }
}

function trimExtra(entry: LogEntry | null) {
  if (!entry) return
  while (entry.extra.length > 0 && entry.extra[entry.extra.length - 1].trim() === '') {
    entry.extra.pop()
    if (entry.lines.length > 0 && entry.lines[entry.lines.length - 1].trim() === '') {
      entry.lines.pop()
    }
  }
}

function entryFrom(line: string): LogEntry {
  const server = serverLine.exec(line)
  if (server) {
    const brackets = bracketsOf(server[5])
    const thread = brackets.length === 0 ? null : brackets[brackets.length - 1]
    const context = brackets.length <= 1 ? [] : brackets.slice(0, -1)
    return {
      level: severity(server[3]),
      lines: [line],
      date: server[1],
      time: server[2],
      source: '',
      detail: detailOf(server[4], context, thread),
      message: server[7] ?? '',
      extra: [],
    }
  }
  const leveled = levelHead.exec(line)
  if (leveled) {
    return {
      level: severity(leveled[3]),
      lines: [line],
      date: leveled[1],
      time: leveled[2],
      source: '',
      detail: null,
      message: (leveled[4] ?? '').trim(),
      extra: [],
    }
  }
  const client = clientLine.exec(line)
  if (client) {
    return {
      level: 'info',
      lines: [line],
      date: client[1],
      time: client[2],
      source: client[3] ?? '',
      detail: null,
      message: client[4] ?? '',
      extra: [],
    }
  }
  const plain = timestampLine.exec(line)
  if (plain) {
    return {
      level: 'info',
      lines: [line],
      date: plain[1],
      time: plain[2],
      source: '',
      detail: null,
      message: plain[3] ?? '',
      extra: [],
    }
  }
  return {
    level: 'info',
    lines: [line],
    date: null,
    time: null,
    source: '',
    detail: null,
    message: line,
    extra: [],
  }
}

function severity(token: string | undefined): Severity {
  switch (token) {
    case 'TRACE':
    case 'DEBUG':
      return 'debug'
    case 'WARN':
    case 'WARNING':
      return 'warn'
    case 'ERROR':
    case 'FATAL':
      return 'error'
    default:
      return 'info'
  }
}

function bracketsOf(raw: string | undefined): string[] {
  if (!raw) return []
  return [...raw.matchAll(bracket)].map((match) => match[1]).filter((name) => name.length > 0)
}

function detailOf(pid: string | undefined, context: string[], thread: string | null): string | null {
  const parts = [
    ...(pid ? [`进程 ${pid}`] : []),
    ...context,
    ...(thread ? [`线程 ${thread}`] : []),
  ]
  return parts.length === 0 ? null : parts.join(' · ')
}
