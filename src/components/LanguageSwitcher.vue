<script setup>
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'

const { locale } = useI18n()
const open = ref(false)

const locales = [
  { code: 'ru', label: 'RU', name: 'Русский' },
  { code: 'en', label: 'EN', name: 'English' },
  { code: 'lt', label: 'LT', name: 'Lietuvių' },
]

const currentLocale = () => locales.find((l) => l.code === locale.value) || locales[0]

function setLocale(code) {
  locale.value = code
  open.value = false
  try {
    localStorage.setItem('champ_locale', code)
  } catch {
    /* ignore */
  }
}

function toggle() {
  open.value = !open.value
}

function close() {
  open.value = false
}
</script>

<template>
  <div class="lang-dropdown" @click.stop>
    <button
      class="lang-dropdown__trigger"
      type="button"
      :aria-expanded="open"
      aria-haspopup="listbox"
      @click="toggle"
      @blur="close"
    >
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="6.5"/><path d="M1.5 8h13"/><ellipse cx="8" cy="8" rx="3" ry="6.5"/></svg>
      <span>{{ currentLocale().label }}</span>
      <svg class="lang-dropdown__chevron" :class="{ 'lang-dropdown__chevron--open': open }" width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 5l3 3 3-3"/></svg>
    </button>
    <div v-if="open" class="lang-dropdown__menu" role="listbox">
      <button
        v-for="item in locales"
        :key="item.code"
        type="button"
        class="lang-dropdown__item"
        :class="{ 'lang-dropdown__item--active': locale === item.code }"
        role="option"
        :aria-selected="locale === item.code"
        @mousedown.prevent="setLocale(item.code)"
      >
        <span class="lang-dropdown__item-label">{{ item.label }}</span>
        <span class="lang-dropdown__item-name">{{ item.name }}</span>
      </button>
    </div>
  </div>
</template>
