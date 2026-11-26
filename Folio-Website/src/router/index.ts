import { createRouter, createWebHistory } from 'vue-router'
import DeployView from '../views/DeployView.vue'
import HomeView from '../views/HomeView.vue'
import MissingView from '../views/MissingView.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/',
      name: 'home',
      component: HomeView,
      meta: { title: 'Folio · 自托管媒体库' },
    },
    {
      path: '/deploy',
      name: 'deploy',
      component: DeployView,
      meta: { title: 'Folio · 部署' },
    },
    {
      path: '/:pathMatch(.*)*',
      name: 'missing',
      component: MissingView,
      meta: { title: 'Folio · 未找到页面' },
    },
  ],
  scrollBehavior(to) {
    if (to.hash) return { el: to.hash, top: 80 }
    return { top: 0 }
  },
})

router.afterEach((to) => {
  const title = to.meta.title
  document.title = typeof title === 'string' ? title : 'Folio'
})

export default router
