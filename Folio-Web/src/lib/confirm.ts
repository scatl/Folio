import { reactive } from 'vue'

export type ConfirmOptions = {
  title?: string
  message: string
  confirmLabel?: string
  cancelLabel?: string
  danger?: boolean
}

type ConfirmState = {
  open: boolean
  title: string
  message: string
  confirmLabel: string
  cancelLabel: string
  danger: boolean
}

type Resolver = (value: boolean) => void

const state = reactive<ConfirmState>({
  open: false,
  title: '请确认',
  message: '',
  confirmLabel: '确定',
  cancelLabel: '取消',
  danger: false,
})

let resolveCurrent: Resolver | null = null

function close(result: boolean) {
  if (!state.open) return
  state.open = false
  const resolve = resolveCurrent
  resolveCurrent = null
  resolve?.(result)
}

export function confirmDialog(options: ConfirmOptions | string): Promise<boolean> {
  if (resolveCurrent) close(false)
  const opts = typeof options === 'string' ? { message: options } : options
  state.title = opts.title?.trim() || '请确认'
  state.message = opts.message
  state.confirmLabel = opts.confirmLabel?.trim() || '确定'
  state.cancelLabel = opts.cancelLabel?.trim() || '取消'
  state.danger = !!opts.danger
  state.open = true
  return new Promise<boolean>((resolve) => {
    resolveCurrent = resolve
  })
}

export function useConfirmDialog() {
  return {
    state,
    accept: () => close(true),
    cancel: () => close(false),
  }
}
