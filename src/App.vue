<script setup>
import { computed, onMounted } from 'vue'
import { RouterLink, RouterView, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'

import LanguageSwitcher from './components/LanguageSwitcher.vue'
import { useAuthStore } from './stores/auth'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const { t } = useI18n()

onMounted(async () => {
  await auth.init()
})

const layout = computed(() => {
  if (route.name === 'home') {
    return 'login'
  }
  if (route.path.startsWith('/admin')) {
    return 'admin'
  }
  if (route.name === 'public-tournament') {
    return 'public'
  }
  return 'default'
})

async function handleSignOut() {
  await auth.signOut()
  await router.push({ name: 'home' })
}
</script>

<template>
  <div class="app-root">
    <header v-if="layout === 'admin'" class="app-header">
      <RouterLink class="app-header__brand" :to="{ name: 'admin-tournaments' }">
        {{ t('app.title') }}
      </RouterLink>
      <div class="app-header__actions">
        <LanguageSwitcher />
        <button v-if="auth.user" class="btn btn--ghost btn--sm" type="button" @click="handleSignOut">
          {{ t('auth.logout') }}
        </button>
      </div>
    </header>

    <header v-else-if="layout === 'public'" class="app-header">
      <span class="app-header__brand">{{ t('app.title') }}</span>
      <div class="app-header__actions">
        <LanguageSwitcher />
      </div>
    </header>

    <main
      class="app-main"
      :class="{
        'app-main--wide': layout === 'admin' || layout === 'public',
        'app-main--flush': layout === 'login',
      }"
    >
      <RouterView />
    </main>
  </div>
</template>
