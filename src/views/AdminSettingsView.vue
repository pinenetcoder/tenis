<script setup>
import { onMounted } from 'vue'
import { useI18n } from 'vue-i18n'

import LanguageSwitcher from '../components/LanguageSwitcher.vue'
import { useAuthStore } from '../stores/auth'

const { t } = useI18n()
const auth = useAuthStore()

onMounted(async () => {
  await auth.init()
})
</script>

<template>
  <div class="stack" style="max-width: 560px">
    <h1 class="page-title">{{ t('admin.settingsTitle') }}</h1>
    <p class="muted">{{ t('admin.settingsIntro') }}</p>

    <section class="card stack stack--sm">
      <h2 class="section-title">{{ t('admin.settingsLanguage') }}</h2>
      <p class="muted">{{ t('admin.settingsLanguageHint') }}</p>
      <LanguageSwitcher />
    </section>

    <section class="card stack stack--sm">
      <h2 class="section-title">{{ t('admin.settingsAccount') }}</h2>
      <div class="form-field">
        <span class="label">{{ t('admin.settingsEmail') }}</span>
        <p class="input input--readonly">
          {{ auth.user?.email || '—' }}
        </p>
      </div>
    </section>

    <section class="card stack stack--sm muted">
      <h2 class="section-title">{{ t('admin.settingsNotifications') }}</h2>
      <p>{{ t('admin.settingsNotificationsPlaceholder') }}</p>
    </section>
  </div>
</template>
