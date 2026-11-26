<script setup lang="ts">
import { computed } from 'vue'
import { RouterLink, useRoute } from 'vue-router'

const route = useRoute()
const productCurrent = computed(() => route.name === 'home' && route.hash === '#product')
</script>

<template>
  <header class="header">
    <a class="skip" href="#main">跳到内容</a>
    <div class="wrap bar">
      <RouterLink class="brand" :to="{ name: 'home' }" aria-label="Folio 首页">
        <svg viewBox="0 0 64 64" aria-hidden="true">
          <rect width="64" height="64" rx="16" fill="#12151c" />
          <g transform="translate(5 0)">
            <path
              fill="#D4A574"
              d="M19 14H43a3 3 0 0 1 3 3v2a3 3 0 0 1-3 3H24v25a3 3 0 0 1-3 3h-2a3 3 0 0 1-3-3V17a3 3 0 0 1 3-3z"
            />
            <path fill="#D4A574" d="M20 28h8v8H20z" />
            <path fill="#5FB3A8" d="M24 28h11.5a2.5 2.5 0 0 1 2.5 2.5v3a2.5 2.5 0 0 1-2.5 2.5H24z" />
          </g>
        </svg>
        <span>Folio</span>
      </RouterLink>
      <nav class="nav" aria-label="站点">
        <RouterLink :to="{ name: 'home', hash: '#product' }" custom v-slot="{ href, navigate }">
          <a
            :href="href"
            :class="{ 'is-active': productCurrent }"
            :aria-current="productCurrent ? 'location' : undefined"
            @click="navigate"
          >
            产品
          </a>
        </RouterLink>
        <RouterLink :to="{ name: 'deploy' }" active-class="is-active">部署</RouterLink>
      </nav>
    </div>
  </header>
</template>

<style scoped>
.header {
  position: sticky;
  top: 0;
  z-index: 10;
  padding-top: env(safe-area-inset-top, 0px);
  background: rgba(9, 11, 15, 0.78);
  border-bottom: 1px solid var(--line);
  backdrop-filter: blur(16px);
}

.bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-height: 4.25rem;
  gap: 1rem;
}

.brand {
  display: inline-flex;
  align-items: center;
  gap: 0.65rem;
  font-family: var(--font-display);
  font-weight: 700;
  font-size: 1.2rem;
  letter-spacing: -0.03em;
}

.brand svg {
  width: 1.85rem;
  height: 1.85rem;
  display: block;
}

.nav {
  display: flex;
  align-items: center;
  gap: 1.35rem;
}

.nav a {
  color: var(--ink-muted);
  font-weight: 600;
  font-size: 0.95rem;
}

.nav a:hover,
.nav a.is-active {
  color: var(--ink);
}

.nav a.is-active {
  color: var(--copper-hot);
}

.skip {
  position: absolute;
  left: 1rem;
  top: calc(0.7rem + env(safe-area-inset-top, 0px));
  transform: translateY(-160%);
  padding: 0.45rem 0.75rem;
  border-radius: 999px;
  background: var(--copper);
  color: #1a120a;
  font-weight: 700;
}

.skip:focus {
  transform: none;
}
</style>
