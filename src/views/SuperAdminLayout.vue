<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '../stores/auth'
import { supabase } from '../lib/supabase'

const { t } = useI18n()
const auth = useAuthStore()

const loading = ref(true)
const googleLoading = ref(false)
const loginError = ref('')

const isAuthorized = computed(() => auth.user && auth.platformRole === 'superadmin')

onMounted(async () => {
  if (!auth.ready) await auth.init()
  if (auth.user) {
    await auth.checkPlatformRole()
    if (auth.user && auth.platformRole !== 'superadmin') {
      loginError.value = t('superAdmin.login.notAuthorized')
      await supabase.auth.signOut()
      auth.user = null
      auth.session = null
      auth.platformRole = null
    }
  }
  loading.value = false
})

async function handleGoogleLogin() {
  googleLoading.value = true
  loginError.value = ''
  try {
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: `${window.location.origin}/superadmin` },
    })
    if (error) {
      loginError.value = error.message
      googleLoading.value = false
    }
  } catch (e) {
    loginError.value = e.message
    googleLoading.value = false
  }
}
</script>

<template>
  <div class="sa-page">
    <!-- Loading -->
    <div v-if="loading" class="sa-login-page">
      <div class="sa-login-card">
        <span class="spinner spinner--lg" />
      </div>
    </div>

    <!-- Login form -->
    <div v-else-if="!isAuthorized" class="sa-login-page">
      <div class="sa-login-card">
        <div class="sa-login-icon">
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
          </svg>
        </div>
        <h1 class="sa-login-title">{{ t('superAdmin.login.title') }}</h1>
        <p class="sa-login-subtitle">{{ t('superAdmin.login.subtitle') }}</p>

        <button class="btn btn--primary btn--lg sa-login-btn" :disabled="googleLoading" @click="handleGoogleLogin">
          <span v-if="googleLoading" class="spinner" aria-hidden="true" />
          <svg v-else width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4"/><path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/><path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/><path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/></svg>
          {{ t('superAdmin.login.withGoogle') }}
        </button>

        <p v-if="loginError" class="alert alert--error sa-login-error">{{ loginError }}</p>
      </div>
    </div>

    <!-- Authorized: show dashboard -->
    <div v-else>
      <RouterView />
    </div>
  </div>
</template>
