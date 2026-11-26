<script setup lang="ts">
withDefaults(
  defineProps<{
    title: string
    body?: string
    error?: boolean
  }>(),
  { error: false },
)
</script>

<template>
  <div class="empty-state" :data-error="error || undefined">
    <!-- 空态：叠放海报 -->
    <svg v-if="!error" class="mark" viewBox="0 0 96 88" aria-hidden="true">
      <defs>
        <radialGradient id="empty-glow" cx="50%" cy="55%" r="55%">
          <stop offset="0%" stop-color="#D4A574" stop-opacity="0.18" />
          <stop offset="45%" stop-color="#5FB3A8" stop-opacity="0.08" />
          <stop offset="100%" stop-color="#5FB3A8" stop-opacity="0" />
        </radialGradient>
      </defs>
      <circle cx="48" cy="48" r="42" fill="url(#empty-glow)" />
      <g transform="translate(28 46) rotate(-10)">
        <rect x="-20" y="-30" width="40" height="56" rx="7" fill="rgba(18,21,28,0.72)" stroke="rgba(242,239,232,0.16)" stroke-width="1.2" />
        <path d="M-10 -4h20M-10 6h11" stroke="rgba(242,239,232,0.14)" stroke-width="1.2" stroke-linecap="round" />
      </g>
      <g transform="translate(66 44) rotate(8)">
        <rect x="-20" y="-30" width="40" height="56" rx="7" fill="rgba(18,21,28,0.72)" stroke="rgba(242,239,232,0.16)" stroke-width="1.2" />
        <path d="M-10 -4h20M-10 6h11" stroke="rgba(242,239,232,0.14)" stroke-width="1.2" stroke-linecap="round" />
      </g>
      <g transform="translate(48 48) rotate(-2)">
        <rect x="-22" y="-32" width="44" height="60" rx="8" fill="rgba(18,21,28,0.88)" stroke="rgba(212,165,116,0.72)" stroke-width="1.5" />
        <path d="M-12 -6h24M-12 5h14" stroke="rgba(212,165,116,0.35)" stroke-width="1.2" stroke-linecap="round" />
      </g>
      <circle cx="66" cy="74" r="2.4" fill="#5FB3A8" fill-opacity="0.7" />
    </svg>

    <!-- 错误态：裂开的海报框 -->
    <svg v-else class="mark" viewBox="0 0 96 88" aria-hidden="true">
      <defs>
        <radialGradient id="error-glow" cx="50%" cy="52%" r="55%">
          <stop offset="0%" stop-color="#E07A6B" stop-opacity="0.22" />
          <stop offset="50%" stop-color="#E07A6B" stop-opacity="0.06" />
          <stop offset="100%" stop-color="#E07A6B" stop-opacity="0" />
        </radialGradient>
      </defs>
      <circle cx="48" cy="46" r="42" fill="url(#error-glow)" />
      <g transform="translate(36 46) rotate(-7)">
        <rect x="-18" y="-28" width="36" height="54" rx="7" fill="rgba(18,21,28,0.82)" stroke="rgba(224,122,107,0.7)" stroke-width="1.5" />
        <path d="M-8 -6h16" stroke="rgba(224,122,107,0.28)" stroke-width="1.2" stroke-linecap="round" />
      </g>
      <g transform="translate(60 48) rotate(9)">
        <rect x="-18" y="-28" width="36" height="54" rx="7" fill="rgba(18,21,28,0.82)" stroke="rgba(224,122,107,0.55)" stroke-width="1.5" />
        <path d="M-8 2h16" stroke="rgba(224,122,107,0.22)" stroke-width="1.2" stroke-linecap="round" />
      </g>
      <path
        d="M46 18 L51 36 L44 52 L50 74"
        fill="none"
        stroke="#E07A6B"
        stroke-width="1.6"
        stroke-linecap="round"
        stroke-linejoin="round"
        opacity="0.9"
      />
      <circle cx="62" cy="28" r="2.2" fill="#E07A6B" fill-opacity="0.75" />
    </svg>

    <h2>{{ title }}</h2>
    <p v-if="body">{{ body }}</p>
    <div v-if="$slots.default" class="actions">
      <slot />
    </div>
  </div>
</template>

<style scoped>
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding: 2.5rem 1.25rem;
  max-width: 22rem;
  margin: 0 auto;
}

.mark {
  width: 6rem;
  height: 5.5rem;
  margin-bottom: 1.25rem;
}

h2 {
  margin: 0;
  font-family: var(--font-display);
  font-size: 1.25rem;
  font-weight: 400;
  color: var(--ink);
  letter-spacing: -0.02em;
}

p {
  margin: 0.5rem 0 0;
  color: var(--ink-muted);
  font-size: 0.92rem;
  line-height: 1.45;
}

.empty-state[data-error] p {
  color: color-mix(in srgb, var(--danger) 85%, transparent);
}

.actions {
  margin-top: 1.1rem;
}
</style>
