<script setup>
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'

import LanguageSwitcher from '../components/LanguageSwitcher.vue'
import { useAuthStore } from '../stores/auth'

const { t } = useI18n()
const router = useRouter()
const auth = useAuthStore()

const loading = ref(false)
const errorText = ref('')

onMounted(async () => {
  await auth.init()
  if (auth.user) {
    router.replace({ name: 'admin-tournaments' })
  }
})

async function signIn() {
  loading.value = true
  errorText.value = ''
  try {
    await auth.signInWithGoogle()
  } catch (e) {
    errorText.value = e.message || t('errors.generic')
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="login-page">
    <div class="login-card">
      <h1>{{ t('app.title') }}</h1>
      <p class="subtitle">{{ t('login.subtitle') }}</p>

      <button class="btn btn--primary" type="button" :disabled="loading" @click="signIn">
        <span v-if="loading" class="spinner" aria-hidden="true" />
        {{ t('auth.login') }}
      </button>

      <p v-if="errorText" class="error-text">{{ errorText }}</p>

      <div class="inline-actions" style="justify-content: center">
        <LanguageSwitcher />
      </div>
    </div>
  </div>
</template>
