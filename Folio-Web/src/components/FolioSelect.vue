<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import FolioCheck from './FolioCheck.vue'

const props = defineProps<{
  modelValue: string | string[]
  options: { id: string; label: string }[]
  multiple?: boolean
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string | string[]]
}>()

const open = ref(false)
const root = ref<HTMLElement | null>(null)
const menuStyle = ref<Record<string, string>>({})

const selectedIds = computed(() => (Array.isArray(props.modelValue) ? props.modelValue : props.modelValue ? [props.modelValue] : []))

const currentLabel = computed(() => {
  if (props.multiple) {
    const labels = selectedIds.value
      .map((id) => props.options.find((item) => item.id === id)?.label)
      .filter((label): label is string => Boolean(label))
    return labels.length ? labels.join('、') : '不限'
  }
  return props.options.find((item) => item.id === props.modelValue)?.label ?? '不限'
})

function place() {
  const el = root.value
  if (!el) return
  const rect = el.getBoundingClientRect()
  const width = rect.width
  const left = Math.max(8, Math.min(rect.left, window.innerWidth - width - 8))
  const spaceBelow = window.innerHeight - rect.bottom
  const openUp = spaceBelow < 220 && rect.top > spaceBelow
  menuStyle.value = openUp
    ? {
        left: `${left}px`,
        width: `${width}px`,
        bottom: `${window.innerHeight - rect.top + 6}px`,
      }
    : {
        left: `${left}px`,
        width: `${width}px`,
        top: `${rect.bottom + 6}px`,
      }
}

function toggle() {
  open.value = !open.value
  if (open.value) place()
}

function chosen(id: string) {
  if (!props.multiple) return props.modelValue === id
  if (!id) return selectedIds.value.length === 0
  return selectedIds.value.includes(id)
}

function choose(id: string) {
  if (!props.multiple) {
    emit('update:modelValue', id)
    open.value = false
    return
  }
  if (!id) {
    emit('update:modelValue', [])
    return
  }
  const next = selectedIds.value.includes(id)
    ? selectedIds.value.filter((item) => item !== id)
    : [...selectedIds.value, id]
  emit('update:modelValue', next)
}

function onDoc(event: PointerEvent) {
  const target = event.target
  if (!(target instanceof Node)) return
  if (root.value?.contains(target)) return
  if (target instanceof Element && target.closest('.folio-select-menu')) return
  open.value = false
}

function onKey(event: KeyboardEvent) {
  if (open.value && event.key === 'Escape') {
    event.preventDefault()
    open.value = false
  }
}

function onReflow() {
  if (open.value) place()
}

onMounted(() => {
  document.addEventListener('pointerdown', onDoc)
  window.addEventListener('keydown', onKey)
  window.addEventListener('resize', onReflow)
  window.addEventListener('scroll', onReflow, true)
})

onUnmounted(() => {
  document.removeEventListener('pointerdown', onDoc)
  window.removeEventListener('keydown', onKey)
  window.removeEventListener('resize', onReflow)
  window.removeEventListener('scroll', onReflow, true)
})
</script>

<template>
  <div ref="root" class="folio-select">
    <button
      type="button"
      class="folio-select-btn"
      :aria-expanded="open"
      aria-haspopup="listbox"
      @click="toggle"
    >
      <span>{{ currentLabel }}</span>
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 10l5 5 5-5z" /></svg>
    </button>
    <Teleport to="body">
      <ul v-if="open" class="folio-select-menu" role="listbox" :style="menuStyle">
        <li v-for="item in options" :key="item.id || 'empty'">
          <button
            type="button"
            role="option"
            :aria-selected="chosen(item.id)"
            :class="{ 'has-check': multiple }"
            @click="choose(item.id)"
          >
            <FolioCheck v-if="multiple" decorative :model-value="chosen(item.id)" />
            {{ item.label }}
          </button>
        </li>
      </ul>
    </Teleport>
  </div>
</template>

<style scoped>
.folio-select {
  position: relative;
  min-width: 0;
}

.folio-select-btn {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  width: 100%;
  height: 2.7rem;
  margin: 0;
  padding: 0 0.75rem 0 0.85rem;
  border: 1px solid var(--line-strong);
  border-radius: 12px;
  background: rgba(18, 21, 28, 0.86);
  color: var(--ink);
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.folio-select-btn span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.folio-select-btn svg {
  width: 1.15rem;
  height: 1.15rem;
  flex: none;
  fill: var(--ink-muted);
}

.folio-select-btn:focus-visible {
  border-color: rgba(212, 165, 116, 0.55);
  box-shadow: 0 0 0 3px var(--copper-soft);
}
</style>

<style>
.folio-select-menu {
  position: fixed;
  z-index: 120;
  max-height: min(16rem, 46vh);
  margin: 0;
  padding: 0.35rem 0;
  overflow: auto;
  list-style: none;
  border: 1px solid var(--line-strong);
  border-radius: 12px;
  background: rgba(16, 19, 26, 0.98);
  box-shadow: 0 16px 40px rgba(0, 0, 0, 0.45);
}

.folio-select-menu button {
  display: block;
  width: 100%;
  margin: 0;
  padding: 0.55rem 0.85rem;
  border: 0;
  background: transparent;
  color: var(--ink);
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.folio-select-menu button.has-check {
  display: flex;
  align-items: center;
  gap: 0.65rem;
}

.folio-select-menu button:hover,
.folio-select-menu button[aria-selected='true'] {
  background: rgba(212, 165, 116, 0.12);
  color: var(--copper);
}
</style>
