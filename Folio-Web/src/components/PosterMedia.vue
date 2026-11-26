<script setup lang="ts">
import { computed, ref, watch } from 'vue'

const props = withDefaults(
  defineProps<{
    src?: string | null
    alt?: string
    loading?: 'lazy' | 'eager'
    /** cover：海报裁切；contain：横图 / logo 完整显示 */
    fit?: 'cover' | 'contain'
  }>(),
  {
    src: null,
    alt: '',
    loading: 'lazy',
    fit: 'cover',
  },
)

const failed = ref(false)
const ready = ref(false)

watch(
  () => props.src,
  () => {
    failed.value = false
    ready.value = false
  },
)

const hasSrc = computed(() => !!props.src?.trim())
const showPlaceholder = computed(() => !hasSrc.value || failed.value || !ready.value)

function onLoad() {
  ready.value = true
}

function onError() {
  failed.value = true
  ready.value = false
}

/** 缓存命中时可能不触发 load，需同步一次。 */
function bindImg(el: unknown) {
  const img = el as HTMLImageElement | null
  if (!img || failed.value) return
  if (img.complete && img.naturalWidth > 0) {
    ready.value = true
  } else if (img.complete && img.naturalWidth === 0) {
    failed.value = true
  }
}
</script>

<template>
  <div class="poster-media">
    <div v-if="showPlaceholder" class="poster-placeholder" aria-hidden="true">
      <img class="poster-mark" src="/folio-mark.svg" alt="" />
    </div>
    <img
      v-if="hasSrc && !failed"
      :ref="bindImg"
      class="poster-media-img"
      :class="[fit === 'contain' ? 'fit-contain' : 'fit-cover', { 'is-ready': ready }]"
      :src="src!"
      :alt="alt"
      :loading="loading"
      @load="onLoad"
      @error="onError"
    />
  </div>
</template>

<style scoped>
.poster-media {
  position: relative;
  display: block;
  width: 100%;
  height: 100%;
  min-height: 0;
  overflow: hidden;
  background: var(--bg-soft);
}

.poster-media-img,
.poster-placeholder {
  width: 100%;
  height: 100%;
  display: block;
}

.poster-placeholder {
  position: absolute;
  inset: 0;
  z-index: 0;
  display: grid;
  place-items: center;
  /* Match Folio-Client PosterImage.placeholder: opaque soft wash, no translucent band. */
  background: linear-gradient(135deg, #1a2422, var(--bg-soft), #221e1a);
}

.poster-media-img {
  position: absolute;
  inset: 0;
  z-index: 1;
  opacity: 0;
  transition: opacity 0.18s ease;
}

.poster-media-img.is-ready {
  opacity: 1;
}

.poster-media-img.fit-cover {
  object-fit: cover;
}

.poster-media-img.fit-contain {
  object-fit: contain;
}

.poster-mark {
  width: 36%;
  min-width: 22px;
  height: auto;
  pointer-events: none;
}

@media (prefers-reduced-motion: reduce) {
  .poster-media-img {
    transition: none;
  }
}
</style>
