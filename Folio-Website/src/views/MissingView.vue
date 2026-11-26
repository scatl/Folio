<script setup lang="ts">
import { RouterLink } from 'vue-router'
</script>

<template>
  <div class="wrap missing">
    <p class="section-label">404</p>
    <h1 class="display">没有这个页面</h1>
    <p class="lede">这个地址不存在。</p>
    <RouterLink class="btn btn-primary" :to="{ name: 'home' }">回首页</RouterLink>
  </div>
</template>

<style scoped>
.missing {
  padding: clamp(2.75rem, 8vw, 4.5rem) 0 clamp(4rem, 12vw, 6.5rem);
}

.btn {
  margin-top: 1.5rem;
}
</style>
