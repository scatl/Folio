<script setup lang="ts">
import { computed } from 'vue'
import { RouterLink, useRoute } from 'vue-router'

const route = useRoute()
const productCurrent = computed(() => route.name === 'home' && route.hash === '#product')
</script>

<template>
  <footer class="footer">
    <div class="wrap foot">
      <div>
        <p class="name">Folio</p>
        <p class="blurb">自托管媒体库。目录在你的机器上，元数据写进你自己的库。</p>
      </div>
      <nav aria-label="页脚">
        <RouterLink :to="{ name: 'home', hash: '#product' }" custom v-slot="{ href, navigate }">
          <a
            :href="href"
            :aria-current="productCurrent ? 'location' : undefined"
            @click="navigate"
          >
            产品
          </a>
        </RouterLink>
        <RouterLink :to="{ name: 'deploy' }">部署</RouterLink>
      </nav>
    </div>
  </footer>
</template>

<style scoped>
.footer {
  margin-top: auto;
  padding: 1.5rem 0 calc(1.75rem + env(safe-area-inset-bottom, 0px));
  border-top: 1px solid var(--line);
}

.foot {
  display: flex;
  justify-content: space-between;
  align-items: end;
  gap: 1.5rem 2rem;
}

.name {
  margin: 0;
  font-family: var(--font-display);
  font-weight: 700;
  letter-spacing: -0.03em;
}

.blurb {
  margin: 0.4rem 0 0;
  max-width: 24rem;
  color: var(--ink-muted);
  font-size: 0.92rem;
  line-height: 1.6;
}

nav {
  display: flex;
  gap: 1.15rem;
}

nav a {
  color: var(--ink-soft);
  font-weight: 600;
  font-size: 0.92rem;
}

nav a:hover {
  color: var(--copper-hot);
}

@media (max-width: 640px) {
  .foot {
    flex-direction: column;
    align-items: start;
  }
}
</style>
