import './assets/main.css'

import { createApp } from 'vue'
import { createPinia } from 'pinia'

import { setUnauthenticatedHandler } from './api/client'
import App from './App.vue'
import router from './router'
import { useAuthStore } from './stores/auth'

const app = createApp(App)

app.use(createPinia())
app.use(router)

// A 401 from any screen means the session is gone (expired, or signed out in another tab):
// back to the login, returning here afterwards.
setUnauthenticatedHandler(() => {
  useAuthStore().reset()
  const current = router.currentRoute.value
  if (!current.meta.public) {
    router.replace({ name: 'login', query: { redirect: current.fullPath } })
  }
})

// Mount once the first navigation (and its session check) settled, so a signed-out visitor
// never sees the back-office shell flash before the login.
router.isReady().then(() => app.mount('#app'))
