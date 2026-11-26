<script setup lang="ts">
import { onMounted, onUnmounted, watch } from 'vue'
import { useConfirmDialog } from '../lib/confirm'

const { state, accept, cancel } = useConfirmDialog()

function onKey(e: KeyboardEvent) {
  if (!state.open) return
  if (e.key === 'Escape') {
    e.preventDefault()
    cancel()
  } else if (e.key === 'Enter') {
    e.preventDefault()
    accept()
  }
}

watch(
  () => state.open,
  (open) => {
    document.body.style.overflow = open ? 'hidden' : ''
  },
)

onMounted(() => window.addEventListener('keydown', onKey))
onUnmounted(() => {
  window.removeEventListener('keydown', onKey)
  document.body.style.overflow = ''
})
</script>

<template>
  <Teleport to="body">
    <div
      v-if="state.open"
      class="overlay"
      role="dialog"
      aria-modal="true"
      :aria-labelledby="'confirm-title'"
      @click.self="cancel"
    >
      <div class="dialog">
        <h2 id="confirm-title">{{ state.title }}</h2>
        <p class="message">{{ state.message }}</p>
        <div class="actions">
          <button type="button" class="ghost" @click="cancel">{{ state.cancelLabel }}</button>
          <button
            type="button"
            class="primary"
            :class="{ danger: state.danger }"
            autofocus
            @click="accept"
          >
            {{ state.confirmLabel }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.overlay {
  position: fixed;
  inset: 0;
  z-index: 80;
  display: grid;
  place-items: center;
  padding: 1.25rem;
  background: rgba(4, 6, 10, 0.45);
  backdrop-filter: blur(18px);
  -webkit-backdrop-filter: blur(18px);
  animation: fade-in 0.16s ease both;
}

.dialog {
  width: min(420px, 100%);
  border: 1px solid var(--line-strong);
  border-radius: var(--radius);
  background: linear-gradient(180deg, rgba(26, 31, 42, 0.98), rgba(14, 17, 24, 0.98));
  box-shadow: var(--shadow);
  padding: 1.25rem 1.35rem 1.2rem;
  animation: rise 0.2s cubic-bezier(0.22, 1, 0.36, 1) both;
}

.dialog h2 {
  margin: 0;
  font-family: var(--font-display);
  font-size: 1.25rem;
  line-height: 1.25;
}

.message {
  margin: 0.85rem 0 0;
  color: var(--ink-muted);
  font-size: 0.95rem;
  line-height: 1.55;
  white-space: pre-line;
}

.actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.6rem;
  margin-top: 1.25rem;
}

.ghost,
.primary {
  border-radius: 999px;
  padding: 0.55rem 1.05rem;
  cursor: pointer;
  border: 1px solid var(--line-strong);
  transition:
    background 0.18s ease,
    border-color 0.18s ease,
    color 0.18s ease;
}

.ghost {
  background: transparent;
  color: var(--ink);
}

.ghost:hover {
  border-color: rgba(212, 165, 116, 0.45);
  background: rgba(212, 165, 116, 0.1);
}

.primary {
  background: rgba(212, 165, 116, 0.18);
  border-color: rgba(212, 165, 116, 0.45);
  color: var(--copper);
  font-weight: 600;
}

.primary:hover {
  background: rgba(212, 165, 116, 0.28);
}

.primary.danger {
  background: rgba(224, 122, 107, 0.16);
  border-color: rgba(224, 122, 107, 0.45);
  color: var(--danger);
}

.primary.danger:hover {
  background: rgba(224, 122, 107, 0.26);
}

@keyframes fade-in {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}

@keyframes rise {
  from {
    opacity: 0;
    transform: translateY(10px) scale(0.98);
  }
  to {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}
</style>
