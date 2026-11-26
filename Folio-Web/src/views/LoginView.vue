<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getLoginPosters } from '../api/client'
import { signIn } from '../auth/session'

const ROW_COUNT = 5
const TILES_PER_ROW = 16

const router = useRouter()
const route = useRoute()

const username = ref('folio')
const password = ref('')
const showPassword = ref(false)
const submitting = ref(false)
const error = ref<string | null>(null)
const posterUrls = ref<string[]>([])

const canSubmit = computed(() => username.value.trim().length > 0 && password.value.length > 0 && !submitting.value)

const rows = computed(() => {
  const urls = posterUrls.value
  return Array.from({ length: ROW_COUNT }, (_, row) => {
    const tiles = Array.from({ length: TILES_PER_ROW }, (_, col) => {
      const index = row * TILES_PER_ROW + col
      return {
        key: `${row}-${col}`,
        url: urls.length ? urls[index % urls.length] : null,
        tone: (index * 17 + row * 11) % 360,
      }
    })
    return {
      key: row,
      reverse: row % 2 === 1,
      duration: 70 + row * 12,
      tiles: [
        ...tiles.map((tile) => ({ ...tile, key: `${tile.key}-a` })),
        ...tiles.map((tile) => ({ ...tile, key: `${tile.key}-b` })),
      ],
    }
  })
})

onMounted(() => {
  document.title = 'Folio · 登录'
  void getLoginPosters().then((urls) => {
    posterUrls.value = urls
  })
})

function hideBroken(event: Event) {
  const img = event.target as HTMLImageElement
  const tile = img.closest('.tile') as HTMLElement | null
  if (tile) tile.hidden = true
}

async function submit() {
  if (!canSubmit.value) return
  submitting.value = true
  error.value = null
  try {
    await signIn(username.value.trim(), password.value)
    const redirect = typeof route.query.redirect === 'string' ? route.query.redirect : '/'
    await router.replace(redirect.startsWith('/') ? redirect : '/')
  } catch (e) {
    error.value = e instanceof Error ? e.message : '登录失败'
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div class="login">
    <div class="stage" aria-hidden="true">
      <div class="wall">
        <div
          v-for="row in rows"
          :key="row.key"
          class="strip"
          :class="{ reverse: row.reverse }"
          :style="{ '--dur': `${row.duration}s` }"
        >
          <div class="track">
            <div
              v-for="tile in row.tiles"
              :key="tile.key"
              class="tile"
              :style="{ '--tone': `${tile.tone}` }"
            >
              <img v-if="tile.url" :src="tile.url" alt="" @error="hideBroken" />
            </div>
          </div>
        </div>
      </div>
      <div class="veil" />
    </div>

    <main class="panel">
      <p class="eyebrow">Self-hosted library</p>
      <h1>Folio</h1>
      <p class="lede">进入你的私人影库。海报、刮削与整理都在这里。</p>

      <form class="form" @submit.prevent="submit">
        <label>
          <span>用户名</span>
          <input
            v-model="username"
            name="username"
            autocomplete="username"
            spellcheck="false"
            autofocus
          />
        </label>
        <label>
          <span>密码</span>
          <div class="secret">
            <input
              v-model="password"
              :type="showPassword ? 'text' : 'password'"
              name="password"
              autocomplete="current-password"
            />
            <button type="button" class="reveal" @click="showPassword = !showPassword">
              {{ showPassword ? '隐藏' : '显示' }}
            </button>
          </div>
        </label>
        <p v-if="error" class="err">{{ error }}</p>
        <button type="submit" class="go" :disabled="!canSubmit">
          {{ submitting ? '正在进入…' : '进入影库' }}
        </button>
      </form>
    </main>
  </div>
</template>

<style scoped>
.login {
  min-height: 100dvh;
  display: grid;
  place-items: center;
  padding: 2rem 1.25rem 3rem;
  position: relative;
  overflow-x: hidden;
  overflow-y: auto;
}

.stage {
  position: fixed;
  inset: 0;
  pointer-events: none;
  overflow: hidden;
}

.wall {
  position: absolute;
  inset: -6vh -8vw;
  display: flex;
  flex-direction: column;
  gap: 0.55rem;
  transform: rotate(-6deg) scale(1.12);
}

.strip {
  --dur: 80s;
  flex: 1 1 0;
  overflow: hidden;
}

.track {
  display: flex;
  gap: 0.55rem;
  height: 100%;
  width: max-content;
  animation: drift var(--dur) linear infinite;
}

.strip.reverse .track {
  animation-direction: reverse;
}

.tile {
  height: 100%;
  aspect-ratio: 2 / 3;
  flex: 0 0 auto;
  border-radius: 6px;
  overflow: hidden;
  background: #12151c;
}

.tile[hidden] {
  display: none;
}

.tile img {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.veil {
  position: absolute;
  inset: 0;
  background:
    radial-gradient(ellipse at 50% 42%, rgba(10, 12, 16, 0.42), rgba(10, 12, 16, 0.78) 62%, rgba(8, 10, 14, 0.92) 100%),
    linear-gradient(180deg, rgba(8, 10, 14, 0.55), rgba(8, 10, 14, 0.28) 36%, rgba(8, 10, 14, 0.4) 68%, rgba(8, 10, 14, 0.82));
}

.panel {
  position: relative;
  z-index: 1;
  width: min(420px, 100%);
  padding: 2.15rem 1.85rem 1.7rem;
  border-radius: 28px;
  border: 1px solid rgba(242, 239, 232, 0.12);
  background: rgba(12, 15, 20, 0.78);
  box-shadow: 0 30px 80px rgba(0, 0, 0, 0.45);
  backdrop-filter: blur(22px);
}

.eyebrow {
  margin: 0 0 0.45rem;
  color: var(--teal);
  letter-spacing: 0.16em;
  text-transform: uppercase;
  font-size: 0.72rem;
  font-weight: 650;
}

h1 {
  margin: 0;
  font-family: var(--font-display);
  font-size: clamp(2.4rem, 6vw, 3.3rem);
  letter-spacing: -0.04em;
  background: linear-gradient(120deg, var(--ink) 20%, var(--copper) 90%);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

.lede {
  margin: 0.7rem 0 1.5rem;
  color: var(--ink-muted);
  line-height: 1.55;
}

.form {
  display: grid;
  gap: 0.95rem;
}

label {
  display: grid;
  gap: 0.4rem;
}

label span {
  font-size: 0.82rem;
  color: var(--ink-muted);
  font-weight: 650;
}

input {
  width: 100%;
  height: 2.85rem;
  padding: 0 0.95rem;
  border-radius: 14px;
  border: 1px solid var(--line-strong);
  background: rgba(18, 21, 28, 0.86);
  color: var(--ink);
  outline: none;
}

input:focus {
  border-color: rgba(212, 165, 116, 0.55);
  box-shadow: 0 0 0 3px var(--copper-soft);
}

.secret {
  position: relative;
}

.secret input {
  padding-right: 4.2rem;
}

.reveal {
  position: absolute;
  right: 0.45rem;
  top: 50%;
  transform: translateY(-50%);
  border: 0;
  background: transparent;
  color: var(--ink-muted);
  cursor: pointer;
  font-size: 0.78rem;
  font-weight: 650;
}

.reveal:hover {
  color: var(--copper);
}

.err {
  margin: 0;
  color: var(--danger);
  font-size: 0.88rem;
}

.go {
  height: 2.95rem;
  border: 0;
  border-radius: 999px;
  cursor: pointer;
  font-weight: 700;
  color: #1a140e;
  background: linear-gradient(135deg, #e3bf96, var(--copper) 55%, #c08a58);
}

.go:hover:not(:disabled) {
  filter: brightness(1.06);
}

.go:disabled {
  opacity: 0.55;
  cursor: wait;
}

@keyframes drift {
  from {
    transform: translateX(0);
  }
  to {
    transform: translateX(-50%);
  }
}

@media (max-width: 640px) {
  .login {
    padding: calc(1.1rem + var(--safe-top)) 0.9rem calc(1.4rem + var(--safe-bottom));
    align-items: center;
  }

  .wall {
    gap: 0.4rem;
    inset: -4vh -16vw;
    transform: rotate(-8deg) scale(1.18);
  }

  .panel {
    width: 100%;
    padding: 1.45rem 1.15rem 1.25rem;
  }
}

@media (prefers-reduced-motion: reduce) {
  .track {
    animation: none;
  }
}
</style>
