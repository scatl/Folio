import { createRouter, createWebHistory } from 'vue-router'
import { loadSession } from '../auth/session'
import LoginView from '../views/LoginView.vue'
import PosterWallView from '../views/PosterWallView.vue'
import ScrapeTasksView from '../views/ScrapeTasksView.vue'
import LogsView from '../views/LogsView.vue'
import SettingsView from '../views/SettingsView.vue'
import CollectionDetailView from '../views/CollectionDetailView.vue'
import EpisodeDetailView from '../views/EpisodeDetailView.vue'
import PersonDetailView from '../views/PersonDetailView.vue'
import SeasonDetailView from '../views/SeasonDetailView.vue'
import WorkDetailView from '../views/WorkDetailView.vue'
import PlayerView from '../views/PlayerView.vue'
import PlaylistDetailView from '../views/PlaylistDetailView.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'login',
      component: LoginView,
      meta: { public: true },
    },
    {
      path: '/',
      name: 'wall',
      component: PosterWallView,
    },
    {
      path: '/tasks',
      name: 'tasks',
      component: ScrapeTasksView,
      meta: { admin: true },
    },
    {
      path: '/settings',
      name: 'settings',
      component: SettingsView,
    },
    {
      path: '/logs',
      name: 'logs',
      component: LogsView,
      meta: { admin: true },
    },
    {
      path: '/review',
      redirect: { name: 'tasks' },
    },
    {
      path: '/play/:fileId',
      name: 'play',
      component: PlayerView,
    },
    {
      path: '/works/detail',
      name: 'work-external',
      component: WorkDetailView,
    },
    {
      path: '/works/:id',
      name: 'work',
      component: WorkDetailView,
    },
    {
      path: '/works/:id/seasons/:seasonNumber',
      name: 'season',
      component: SeasonDetailView,
    },
    {
      path: '/works/:id/seasons/:seasonNumber/episodes/:episodeNumber',
      name: 'episode',
      component: EpisodeDetailView,
    },
    {
      path: '/collections/:id',
      name: 'collection',
      component: CollectionDetailView,
    },
    {
      path: '/people/:provider/:externalId',
      name: 'person',
      component: PersonDetailView,
    },
    {
      path: '/playlists/:id',
      name: 'playlist',
      component: PlaylistDetailView,
    },
  ],
  scrollBehavior(to, from) {
    if (
      to.name === 'wall' &&
      (from.name === 'work' ||
        from.name === 'work-external' ||
        from.name === 'season' ||
        from.name === 'episode' ||
        from.name === 'collection' ||
        from.name === 'person' ||
        from.name === 'playlist' ||
        from.name === 'play')
    ) {
      return false
    }
    return { top: 0 }
  },
})

router.beforeEach(async (to) => {
  const session = await loadSession()
  if (to.meta.public) {
    if (session && to.name === 'login') {
      const redirect = typeof to.query.redirect === 'string' ? to.query.redirect : '/'
      return redirect.startsWith('/') ? redirect : '/'
    }
    return true
  }
  if (!session) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }
  if (to.meta.admin && session.role !== 'ADMIN') {
    return { name: 'wall' }
  }
  return true
})

export default router
