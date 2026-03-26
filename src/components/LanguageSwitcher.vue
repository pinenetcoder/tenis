<script setup>
import { useI18n } from 'vue-i18n'

const { locale } = useI18n()

const locales = [
  { code: 'ru', label: 'RU' },
  { code: 'en', label: 'EN' },
  { code: 'lt', label: 'LT' },
]

function setLocale(code) {
  locale.value = code
  try {
    localStorage.setItem('champ_locale', code)
  } catch {
    /* ignore */
  }
}
</script>

<template>
  <div class="lang-switcher" role="group" :aria-label="$t('nav.language')">
    <button
      v-for="item in locales"
      :key="item.code"
      type="button"
      :class="{ 'is-active': locale === item.code }"
      @click="setLocale(item.code)"
    >
      {{ item.label }}
    </button>
  </div>
</template>
