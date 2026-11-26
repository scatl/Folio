<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from 'vue'
import { RouterView, useRoute, useRouter } from 'vue-router'
import { subscribeScrapeEvents } from './api/events'
import { currentUser, sessionEpoch } from './auth/session'
import ConfirmDialog from './components/ConfirmDialog.vue'

const route = useRoute()
const router = useRouter()

const reviewCount = ref(0)
const failedCount = ref(0)
const visible = ref(false)

let unsubscribe: (() => void) | null = null
let settleTimer: number | null = null
let hideTimer: number | null = null
let batchOpen = false
let batchReview = 0
let batchFailed = 0
const seen = new Set<number>()

function resetBatch() {
  batchReview = 0
  batchFailed = 0
  seen.clear()
}

function hideNotice() {
  visible.value = false
  if (hideTimer != null) {
    window.clearTimeout(hideTimer)
    hideTimer = null
  }
}

function finishBatch() {
  settleTimer = null
  if (!batchOpen) return
  batchOpen = false
  const review = batchReview
  const failed = batchFailed
  resetBatch()
  if (review === 0 && failed === 0) return
  reviewCount.value = review
  failedCount.value = failed
  visible.value = true
  if (hideTimer != null) window.clearTimeout(hideTimer)
  hideTimer = window.setTimeout(() => {
    visible.value = false
    hideTimer = null
  }, 6000)
}

function start() {
  if (unsubscribe) return
  unsubscribe = subscribeScrapeEvents({
    onStats: (stats) => {
      if (stats.active > 0) {
        if (settleTimer != null) {
          window.clearTimeout(settleTimer)
          settleTimer = null
        }
        if (!batchOpen) {
          batchOpen = true
          resetBatch()
        }
        return
      }
      if (!batchOpen) return
      if (settleTimer != null) window.clearTimeout(settleTimer)
      settleTimer = window.setTimeout(finishBatch, 400)
    },
    onDone: (job) => {
      if (!batchOpen || seen.has(job.id)) return
      seen.add(job.id)
      if (job.matchStatus === 'needs_review') batchReview += 1
      else if (job.matchStatus === 'failed' || job.status === 'failed') batchFailed += 1
    },
  })
}

function stop() {
  unsubscribe?.()
  unsubscribe = null
  if (settleTimer != null) {
    window.clearTimeout(settleTimer)
    settleTimer = null
  }
  batchOpen = false
  resetBatch()
  hideNotice()
}

watch(
  () => route.name,
  (name) => {
    if (name && name !== 'login' && currentUser.value?.role === 'ADMIN') start()
    else stop()
  },
  { immediate: true },
)

function openTasks() {
  hideNotice()
  void router.push({ name: 'tasks' })
}

onBeforeUnmount(stop)
</script>

<template>
  <RouterView v-slot="{ Component }">
    <KeepAlive include="PosterWallView" :max="1">
      <component :is="Component" :key="sessionEpoch" />
    </KeepAlive>
  </RouterView>
  <button v-if="visible" type="button" class="scrape-notice" @click="openTasks">
    <span v-if="reviewCount" class="warn">{{ reviewCount }} 项待人工确认</span>
    <span v-if="failedCount" class="fail">{{ failedCount }} 项刮削失败</span>
  </button>
  <ConfirmDialog />
</template>

<style>
.scrape-notice {
  position: fixed;
  left: 50%;
  bottom: calc(1.25rem + var(--safe-bottom));
  z-index: 50;
  transform: translateX(-50%);
  display: grid;
  gap: 0.2rem;
  justify-items: start;
  max-width: min(32rem, calc(100% - 2rem));
  margin: 0;
  padding: 0.75rem 1rem;
  border: 1px solid var(--line-strong);
  border-radius: 12px;
  background: var(--bg-soft);
  color: var(--ink);
  box-shadow: var(--shadow);
  cursor: pointer;
  font: inherit;
  text-align: left;
}

.scrape-notice .warn {
  color: var(--copper);
  font-weight: 700;
}

.scrape-notice .fail {
  color: var(--danger);
  font-weight: 700;
}
</style>
