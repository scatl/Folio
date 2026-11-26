import { computed, ref, watch, type Ref, type StyleValue } from 'vue'

/** Matches Folio-Client FolioColors.bgDeep / artworkBackground fallback. */
export const ARTWORK_BG_FALLBACK = '#0a0c10'

type Rgb = { r: number; g: number; b: number }

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n))
}

function rgbToHsl(r: number, g: number, b: number) {
  const nr = r / 255
  const ng = g / 255
  const nb = b / 255
  const max = Math.max(nr, ng, nb)
  const min = Math.min(nr, ng, nb)
  const lightness = (max + min) / 2
  if (max === min) return { h: 0, s: 0, l: lightness }
  const d = max - min
  const saturation = lightness > 0.5 ? d / (2 - max - min) : d / (max + min)
  let hue = 0
  switch (max) {
    case nr:
      hue = ((ng - nb) / d + (ng < nb ? 6 : 0)) / 6
      break
    case ng:
      hue = ((nb - nr) / d + 2) / 6
      break
    default:
      hue = ((nr - ng) / d + 4) / 6
      break
  }
  return { h: hue, s: saturation, l: lightness }
}

function hslToRgb(h: number, s: number, l: number): Rgb {
  if (s === 0) {
    const v = Math.round(l * 255)
    return { r: v, g: v, b: v }
  }
  const hue2rgb = (p: number, q: number, t: number) => {
    let tt = t
    if (tt < 0) tt += 1
    if (tt > 1) tt -= 1
    if (tt < 1 / 6) return p + (q - p) * 6 * tt
    if (tt < 1 / 2) return q
    if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6
    return p
  }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s
  const p = 2 * l - q
  return {
    r: Math.round(hue2rgb(p, q, h + 1 / 3) * 255),
    g: Math.round(hue2rgb(p, q, h) * 255),
    b: Math.round(hue2rgb(p, q, h - 1 / 3) * 255),
  }
}

function backgroundTone(data: Uint8ClampedArray, width: number, height: number): string {
  const step = Math.max(1, Math.floor(Math.max(width, height) / 40))
  let red = 0
  let green = 0
  let blue = 0
  let weight = 0
  for (let y = 0; y < height; y += step) {
    for (let x = 0; x < width; x += step) {
      const index = (y * width + x) * 4
      if (index + 3 >= data.length) continue
      const alpha = data[index + 3]!
      if (alpha < 160) continue
      const r = data[index]!
      const g = data[index + 1]!
      const b = data[index + 2]!
      const hsl = rgbToHsl(r, g, b)
      if (hsl.l < 0.06 || hsl.l > 0.94) continue
      const sample = 0.2 + hsl.s
      red += r * sample
      green += g * sample
      blue += b * sample
      weight += sample
    }
  }
  if (weight <= 0) return ARTWORK_BG_FALLBACK
  const avg = rgbToHsl(Math.round(red / weight), Math.round(green / weight), Math.round(blue / weight))
  const tone = hslToRgb(avg.h, clamp(avg.s, 0.18, 0.72), 0.16)
  return `rgb(${tone.r}, ${tone.g}, ${tone.b})`
}

function decodeImage(src: string, cors: boolean): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image()
    if (cors) {
      img.crossOrigin = 'anonymous'
      img.referrerPolicy = 'no-referrer'
    }
    img.decoding = 'async'
    img.onload = () => resolve(img)
    img.onerror = () => reject(new Error('artwork load failed'))
    img.src = src
  })
}

/**
 * Load artwork for canvas sampling. Prefer blob URL so getImageData is not tainted.
 * TMDB CDN often needs referrerPolicy=no-referrer for CORS.
 */
async function loadImage(url: string): Promise<HTMLImageElement> {
  try {
    const res = await fetch(url, {
      mode: 'cors',
      credentials: 'omit',
      referrerPolicy: 'no-referrer',
    })
    if (!res.ok) throw new Error(`artwork http ${res.status}`)
    const blob = await res.blob()
    const objectUrl = URL.createObjectURL(blob)
    try {
      return await decodeImage(objectUrl, false)
    } finally {
      URL.revokeObjectURL(objectUrl)
    }
  } catch {
    return decodeImage(url, true)
  }
}

/** Sample a poster/backdrop into a dark page tint, matching Folio-Client artworkBackground. */
export async function artworkBackground(url: string): Promise<string> {
  const img = await loadImage(url)
  const targetW = 48
  const scale = targetW / Math.max(img.naturalWidth || img.width, 1)
  const width = Math.max(1, Math.round((img.naturalWidth || img.width) * scale))
  const height = Math.max(1, Math.round((img.naturalHeight || img.height) * scale))
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext('2d', { willReadFrequently: true })
  if (!ctx) return ARTWORK_BG_FALLBACK
  ctx.drawImage(img, 0, 0, width, height)
  let pixels: Uint8ClampedArray
  try {
    pixels = ctx.getImageData(0, 0, width, height).data
  } catch {
    return ARTWORK_BG_FALLBACK
  }
  return backgroundTone(pixels, width, height)
}

export function useArtworkTint(source: Ref<string | null | undefined>) {
  const tint = ref(ARTWORK_BG_FALLBACK)
  let token = 0

  watch(
    source,
    async (url) => {
      const current = ++token
      const trimmed = url?.trim()
      if (!trimmed) {
        tint.value = ARTWORK_BG_FALLBACK
        return
      }
      try {
        const next = await artworkBackground(trimmed)
        if (current === token) tint.value = next
      } catch {
        if (current === token) tint.value = ARTWORK_BG_FALLBACK
      }
    },
    { immediate: true },
  )

  /** Inline style for root detail page — always a plain string so CSS var applies. */
  const pageStyle = computed(
    (): StyleValue => ({
      '--detail-bg': tint.value,
    }),
  )

  return { tint, pageStyle }
}
