<script setup lang="ts">
defineProps<{
  label?: string
}>()
</script>

<template>
  <div class="loading-state" role="status" aria-live="polite">
    <svg class="mark" viewBox="0 0 96 88" aria-hidden="true">
      <defs>
        <radialGradient id="load-glow" cx="50%" cy="55%" r="55%">
          <stop offset="0%" stop-color="#D4A574" stop-opacity="0.2" />
          <stop offset="50%" stop-color="#5FB3A8" stop-opacity="0.08" />
          <stop offset="100%" stop-color="#5FB3A8" stop-opacity="0" />
        </radialGradient>
      </defs>
      <circle class="glow" cx="48" cy="48" r="42" fill="url(#load-glow)" />
      <g transform="translate(28 46) rotate(-10)">
        <g class="card c1">
          <rect x="-20" y="-30" width="40" height="56" rx="7" fill="rgba(18,21,28,0.75)" stroke="currentColor" stroke-width="1.2" />
          <path d="M-10 -4h20M-10 6h11" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.45" />
        </g>
      </g>
      <g transform="translate(66 44) rotate(8)">
        <g class="card c2">
          <rect x="-20" y="-30" width="40" height="56" rx="7" fill="rgba(18,21,28,0.75)" stroke="currentColor" stroke-width="1.2" />
          <path d="M-10 -4h20M-10 6h11" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.45" />
        </g>
      </g>
      <g transform="translate(48 48) rotate(-2)">
        <g class="card c3">
          <rect x="-22" y="-32" width="44" height="60" rx="8" fill="rgba(18,21,28,0.9)" stroke="currentColor" stroke-width="1.5" />
          <path d="M-12 -6h24M-12 5h14" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.5" />
        </g>
      </g>
      <circle class="dot" cx="66" cy="74" r="2.4" fill="#5FB3A8" />
    </svg>
    <p v-if="label">{{ label }}</p>
  </div>
</template>

<style scoped>
.loading-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 2.5rem 1.25rem;
  color: rgba(212, 165, 116, 0.55);
}

.mark {
  width: 6rem;
  height: 5.5rem;
}

.glow {
  animation: glow-pulse 1.4s ease-in-out infinite;
}

.card {
  transform-box: fill-box;
  transform-origin: center;
  animation: card-pulse 1.4s ease-in-out infinite;
}

.c1 {
  color: rgba(242, 239, 232, 0.28);
  animation-delay: 0s;
}

.c2 {
  color: rgba(95, 179, 168, 0.55);
  animation-delay: 0.2s;
}

.c3 {
  color: rgba(212, 165, 116, 0.85);
  animation-delay: 0.4s;
}

.dot {
  transform-box: fill-box;
  transform-origin: center;
  animation: dot-pulse 1.4s ease-in-out infinite;
  animation-delay: 0.3s;
}

p {
  margin: 1.1rem 0 0;
  color: var(--ink-muted);
  font-size: 0.92rem;
}

@keyframes glow-pulse {
  0%,
  100% {
    opacity: 0.55;
  }
  50% {
    opacity: 1;
  }
}

@keyframes card-pulse {
  0%,
  100% {
    opacity: 0.4;
    translate: 0 2px;
  }
  50% {
    opacity: 1;
    translate: 0 -2px;
  }
}

@keyframes dot-pulse {
  0%,
  100% {
    opacity: 0.35;
    transform: scale(0.85);
  }
  50% {
    opacity: 0.95;
    transform: scale(1.2);
  }
}
</style>
