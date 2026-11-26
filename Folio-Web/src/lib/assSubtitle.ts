import type JASSUB from 'jassub'
import fallbackFontUrl from '../assets/fonts/DroidSansFallback.ttf?url'

let renderer: JASSUB | null = null
let boundVideo: HTMLVideoElement | null = null
let ticket = 0
let pending: Promise<void> = Promise.resolve()

function enqueue(task: () => Promise<void>) {
  pending = pending.then(task, task)
  return pending
}

export function dropAssSubtitle() {
  ticket += 1
  return enqueue(async () => {
    const current = renderer
    renderer = null
    boundVideo = null
    if (current) await current.destroy()
  })
}

export function showAssSubtitle(video: HTMLVideoElement, content: string) {
  const currentTicket = ++ticket
  return enqueue(async () => {
    if (currentTicket !== ticket) return
    const JASSUB = (await import('jassub')).default
    if (currentTicket !== ticket) return
    if (!renderer || boundVideo !== video) {
      if (renderer) await renderer.destroy()
      const created = new JASSUB({
        video,
        subContent: content,
        fonts: [fallbackFontUrl],
        defaultFont: 'Droid Sans Fallback',
      })
      created._canvas.style.zIndex = '1'
      renderer = created
      boundVideo = video
    }
    const active = renderer
    await active.ready
    if (currentTicket !== ticket || renderer !== active) return
    await active.renderer.setTrack(content)
  })
}
