<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import LanguageSwitcher from '../components/LanguageSwitcher.vue'
import { useAuthStore } from '../stores/auth'
import { supabase } from '../lib/supabase'

const { t } = useI18n()
const router = useRouter()
const auth = useAuthStore()

const club = ref(null)
const loading = ref(true)

const statusIcon = computed(() => {
  if (!club.value) return ''
  const map = { pending: 'clock', active: 'check', rejected: 'x', approved: 'check' }
  return map[club.value.status] || 'clock'
})

const statusClass = computed(() => {
  if (!club.value) return ''
  const map = { pending: 'warning', active: 'success', rejected: 'danger', approved: 'success' }
  return map[club.value.status] || 'warning'
})

onMounted(async () => {
  await auth.init()
  if (!auth.user) {
    router.replace({ name: 'home' })
    return
  }
  await loadClub()
})

async function loadClub() {
  loading.value = true
  const { data } = await supabase.rpc('my_club_registration')
  club.value = Array.isArray(data) ? (data[0] ?? null) : data
  loading.value = false
}

function goHome() {
  router.push({ name: 'home' })
}

function goAdmin() {
  router.push({ name: 'admin-tournaments' })
}
</script>

<template>
  <div class="reg-page">
    <nav class="landing-nav">
      <div class="landing-nav__inner">
        <button class="landing-nav__brand" type="button" @click="goHome" style="cursor:pointer; background:none; border:none; padding:0;">
          <svg class="landing-nav__logo" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="10" />
            <path d="M18.5 5.5c-3 3-6 5-10 7" />
            <path d="M5.5 18.5c3-3 6-5 10-7" />
            <path d="M2 12h20" />
          </svg>
          {{ t('app.title') }}
        </button>
        <div class="landing-nav__actions">
          <LanguageSwitcher />
        </div>
      </div>
    </nav>

    <div class="reg-container">
      <div class="reg-card reg-card--status" v-if="!loading && club">
        <div class="reg-status-icon" :class="`reg-status-icon--${statusClass}`">
          <svg v-if="statusIcon === 'clock'" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
          <svg v-else-if="statusIcon === 'check'" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>
          <svg v-else-if="statusIcon === 'x'" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>
        </div>

        <h1 class="reg-title">{{ t(`clubRegistration.status.${club.status}.title`) }}</h1>
        <p class="reg-subtitle">{{ t(`clubRegistration.status.${club.status}.description`) }}</p>

        <div class="reg-status-details">
          <div class="reg-status-row">
            <span class="reg-status-label">{{ t('clubRegistration.fields.clubName') }}</span>
            <span class="reg-status-value">{{ club.name }}</span>
          </div>
          <div class="reg-status-row">
            <span class="reg-status-label">{{ t('clubRegistration.fields.clubCity') }}</span>
            <span class="reg-status-value">{{ club.city }}</span>
          </div>
        </div>

        <p v-if="club.status === 'rejected' && club.rejection_reason" class="alert alert--error">
          {{ club.rejection_reason }}
        </p>

        <button v-if="club.status === 'active'" class="btn btn--primary btn--lg" @click="goAdmin">
          {{ t('clubRegistration.goToAdmin') }}
        </button>
      </div>

      <div class="reg-card" v-else-if="!loading && !club">
        <h1 class="reg-title">{{ t('clubRegistration.noClub') }}</h1>
        <button class="btn btn--primary btn--lg" @click="router.push({ name: 'club-register' })">
          {{ t('clubRegistration.registerNow') }}
        </button>
      </div>

      <div class="reg-card" v-else>
        <span class="spinner spinner--lg" />
      </div>
    </div>
  </div>
</template>
