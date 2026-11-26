<script setup lang="ts">
withDefaults(
  defineProps<{
    count?: number
  }>(),
  { count: 12 },
)
</script>

<template>
  <div class="skel-grid" aria-hidden="true">
    <div v-for="n in count" :key="n" class="skel-card" :style="{ '--i': n }">
      <div class="skel-poster shimmer" />
      <div class="skel-line shimmer" />
      <div class="skel-line short shimmer" />
    </div>
  </div>
</template>

<style scoped>
.skel-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(148px, 1fr));
  gap: 1.35rem 1rem;
}

.skel-card {
  display: flex;
  flex-direction: column;
  gap: 0.7rem;
  animation: rise 0.55s cubic-bezier(0.22, 1, 0.36, 1) both;
  animation-delay: calc(min(var(--i), 12) * 40ms);
}

.skel-poster {
  aspect-ratio: 2 / 3;
  border-radius: calc(var(--radius) - 2px);
  border: 1px solid var(--line);
}

.skel-line {
  height: 0.72rem;
  border-radius: 999px;
  width: 78%;
}

.skel-line.short {
  width: 48%;
  height: 0.58rem;
  opacity: 0.8;
}

@keyframes rise {
  from {
    opacity: 0;
    transform: translateY(14px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@media (max-width: 720px) {
  .skel-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 0.9rem 0.65rem;
  }
}

@media (prefers-reduced-motion: reduce) {
  .skel-card {
    animation: none;
  }
}
</style>
