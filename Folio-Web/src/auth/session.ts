import { ref } from 'vue'
import { getAuthMe, login as loginRequest, logout as logoutRequest, updateAccount } from '../api/client'
import type { AuthUser } from '../api/types'

export const currentUser = ref<AuthUser | null>(null)

/** 登录/退出时递增，用来拆掉 KeepAlive 里旧用户的海报墙缓存。 */
export const sessionEpoch = ref(0)

let inflight: Promise<AuthUser | null> | null = null

export function clearSession() {
  currentUser.value = null
  inflight = null
  sessionEpoch.value += 1
}

export async function loadSession(): Promise<AuthUser | null> {
  if (currentUser.value) return currentUser.value
  if (!inflight) {
    inflight = getAuthMe()
      .then((user) => {
        currentUser.value = user
        return user
      })
      .catch(() => {
        currentUser.value = null
        return null
      })
      .finally(() => {
        inflight = null
      })
  }
  return inflight
}

export async function signIn(username: string, password: string): Promise<AuthUser> {
  const user = await loginRequest(username, password)
  currentUser.value = user
  sessionEpoch.value += 1
  return user
}

export async function signOut() {
  try {
    await logoutRequest()
  } catch {
    // 会话可能已失效，本地仍退出
  } finally {
    clearSession()
  }
}

export async function changeAccount(body: {
  currentPassword: string
  username?: string
  newPassword?: string
}): Promise<AuthUser> {
  const user = await updateAccount(body)
  currentUser.value = user
  return user
}
