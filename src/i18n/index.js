import { createI18n } from 'vue-i18n'
import { messages } from './messages'

const savedLocale = localStorage.getItem('champ_locale')

const i18n = createI18n({
  legacy: false,
  locale: savedLocale || 'ru',
  fallbackLocale: 'en',
  messages,
})

export default i18n
