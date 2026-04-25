<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import LanguageSwitcher from '../components/LanguageSwitcher.vue'
import { useAuthStore } from '../stores/auth'
import { supabase } from '../lib/supabase'

const { t } = useI18n()
const router = useRouter()
const route = useRoute()
const auth = useAuthStore()

const authMethod = ref(null) // 'google' | 'email'
const loading = ref(false)
const googleLoading = ref(false)
const errorText = ref('')
const step = ref('auth') // 'auth' | 'form'

const form = reactive({
  email: '',
  password: '',
  firstName: '',
  lastName: '',
  phone: '',
  clubName: '',
  clubCity: '',
  clubAddress: '',
})

const touched = reactive({
  email: false,
  password: false,
  firstName: false,
  lastName: false,
  phone: false,
  clubName: false,
  clubCity: false,
})

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const phonePattern = /^\+?[\d\s\-()]{7,20}$/

const isValidEmail = computed(() => emailPattern.test(form.email))
const isValidPassword = computed(() => form.password.length >= 6)
const isValidPhone = computed(() => !form.phone || phonePattern.test(form.phone))

const canSubmit = computed(() => {
  if (authMethod.value === 'email' && step.value === 'auth') {
    return isValidEmail.value && isValidPassword.value
  }
  return (
    form.firstName.trim() &&
    form.lastName.trim() &&
    form.clubName.trim() &&
    form.clubCity.trim() &&
    isValidPhone.value
  )
})

onMounted(async () => {
  await auth.init()
  // Returning from Google OAuth
  if (route.query.step === 'complete' && auth.user) {
    authMethod.value = 'google'
    form.email = auth.user.email || ''
    step.value = 'form'
  }
})

async function chooseGoogle() {
  googleLoading.value = true
  errorText.value = ''
  try {
    await auth.signInWithGoogleForRegistration()
  } catch (e) {
    errorText.value = e.message || t('errors.generic')
    googleLoading.value = false
  }
}

function chooseEmail() {
  authMethod.value = 'email'
  step.value = 'auth'
}

async function submitEmailAuth() {
  if (!canSubmit.value) return
  loading.value = true
  errorText.value = ''
  try {
    await auth.signUpWithEmail(form.email, form.password)
    step.value = 'form'
  } catch (e) {
    errorText.value = e.message || t('errors.generic')
  } finally {
    loading.value = false
  }
}

async function submitRegistration() {
  if (!canSubmit.value) return
  loading.value = true
  errorText.value = ''
  try {
    const { error } = await supabase.rpc('register_organization', {
      p_first_name: form.firstName.trim(),
      p_last_name: form.lastName.trim(),
      p_phone: form.phone.trim() || null,
      p_org_name: form.clubName.trim(),
      p_org_city: form.clubCity.trim(),
      p_org_address: form.clubAddress.trim() || null,
      p_contact_email: form.email || null,
      p_contact_phone: form.phone.trim() || null,
    })
    if (error) {
      if (error.message?.includes('CLUB_DUPLICATE')) {
        errorText.value = t('clubRegistration.errors.duplicate')
      } else if (error.message?.includes('CLUB_ALREADY_EXISTS')) {
        errorText.value = t('clubRegistration.errors.alreadyExists')
      } else {
        errorText.value = error.message || t('errors.generic')
      }
      return
    }
    router.push({ name: 'club-registration-status' })
  } catch (e) {
    errorText.value = e.message || t('errors.generic')
  } finally {
    loading.value = false
  }
}

function goHome() {
  router.push({ name: 'home' })
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
      <div class="reg-card">
        <h1 class="reg-title">{{ t('clubRegistration.title') }}</h1>
        <p class="reg-subtitle">{{ t('clubRegistration.subtitle') }}</p>

        <!-- Step 1: Choose auth method -->
        <template v-if="!authMethod">
          <div class="reg-auth-methods">
            <button class="btn btn--primary btn--lg reg-auth-btn" @click="chooseGoogle" :disabled="googleLoading">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4"/><path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/><path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/><path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/></svg>
              {{ t('clubRegistration.withGoogle') }}
            </button>
            <div class="reg-divider">
              <span>{{ t('clubRegistration.or') }}</span>
            </div>
            <button class="btn btn--ghost btn--lg reg-auth-btn" @click="chooseEmail">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/></svg>
              {{ t('clubRegistration.withEmail') }}
            </button>
          </div>
        </template>

        <!-- Step 1b: Email auth form -->
        <template v-else-if="authMethod === 'email' && step === 'auth'">
          <form class="reg-form" @submit.prevent="submitEmailAuth">
            <div class="form-field">
              <label class="form-label" for="reg-email">{{ t('clubRegistration.fields.email') }} *</label>
              <input
                id="reg-email"
                v-model="form.email"
                type="email"
                class="input"
                :class="{ 'input--error': touched.email && !isValidEmail }"
                autocomplete="email"
                required
                @blur="touched.email = true"
              />
            </div>
            <div class="form-field">
              <label class="form-label" for="reg-password">{{ t('clubRegistration.fields.password') }} *</label>
              <input
                id="reg-password"
                v-model="form.password"
                type="password"
                class="input"
                :class="{ 'input--error': touched.password && !isValidPassword }"
                autocomplete="new-password"
                :placeholder="t('clubRegistration.fields.passwordHint')"
                required
                @blur="touched.password = true"
              />
            </div>
            <div class="reg-form__actions">
              <button type="button" class="btn btn--ghost" @click="authMethod = null">
                {{ t('clubRegistration.back') }}
              </button>
              <button type="submit" class="btn btn--primary" :disabled="!canSubmit || loading">
                <span v-if="loading" class="spinner" aria-hidden="true" />
                {{ t('clubRegistration.continue') }}
              </button>
            </div>
          </form>
        </template>

        <!-- Step 2: Profile + Club info -->
        <template v-else-if="step === 'form'">
          <form class="reg-form" @submit.prevent="submitRegistration">
            <fieldset class="reg-fieldset">
              <legend class="reg-legend">{{ t('clubRegistration.sections.personal') }}</legend>
              <div class="form-field" v-if="authMethod === 'google'">
                <label class="form-label" for="reg-email-ro">{{ t('clubRegistration.fields.email') }}</label>
                <input id="reg-email-ro" :value="form.email" class="input input--readonly" readonly tabindex="-1" />
              </div>
              <div class="reg-row">
                <div class="form-field">
                  <label class="form-label" for="reg-first">{{ t('clubRegistration.fields.firstName') }} *</label>
                  <input
                    id="reg-first"
                    v-model="form.firstName"
                    type="text"
                    class="input"
                    :class="{ 'input--error': touched.firstName && !form.firstName.trim() }"
                    autocomplete="given-name"
                    required
                    @blur="touched.firstName = true"
                  />
                </div>
                <div class="form-field">
                  <label class="form-label" for="reg-last">{{ t('clubRegistration.fields.lastName') }} *</label>
                  <input
                    id="reg-last"
                    v-model="form.lastName"
                    type="text"
                    class="input"
                    :class="{ 'input--error': touched.lastName && !form.lastName.trim() }"
                    autocomplete="family-name"
                    required
                    @blur="touched.lastName = true"
                  />
                </div>
              </div>
              <div class="form-field">
                <label class="form-label" for="reg-phone">{{ t('clubRegistration.fields.phone') }}</label>
                <input
                  id="reg-phone"
                  v-model="form.phone"
                  type="tel"
                  class="input"
                  :class="{ 'input--error': touched.phone && !isValidPhone }"
                  autocomplete="tel"
                  placeholder="+370..."
                  @blur="touched.phone = true"
                />
              </div>
            </fieldset>

            <fieldset class="reg-fieldset">
              <legend class="reg-legend">{{ t('clubRegistration.sections.club') }}</legend>
              <div class="form-field">
                <label class="form-label" for="reg-club">{{ t('clubRegistration.fields.clubName') }} *</label>
                <input
                  id="reg-club"
                  v-model="form.clubName"
                  type="text"
                  class="input"
                  :class="{ 'input--error': touched.clubName && !form.clubName.trim() }"
                  required
                  @blur="touched.clubName = true"
                />
              </div>
              <div class="form-field">
                <label class="form-label" for="reg-city">{{ t('clubRegistration.fields.clubCity') }} *</label>
                <input
                  id="reg-city"
                  v-model="form.clubCity"
                  type="text"
                  class="input"
                  :class="{ 'input--error': touched.clubCity && !form.clubCity.trim() }"
                  required
                  @blur="touched.clubCity = true"
                />
              </div>
              <div class="form-field">
                <label class="form-label" for="reg-addr">{{ t('clubRegistration.fields.clubAddress') }}</label>
                <input
                  id="reg-addr"
                  v-model="form.clubAddress"
                  type="text"
                  class="input"
                  autocomplete="street-address"
                />
              </div>
            </fieldset>

            <div class="reg-form__actions">
              <button type="button" class="btn btn--ghost" @click="authMethod = null; step = 'auth'">
                {{ t('clubRegistration.back') }}
              </button>
              <button type="submit" class="btn btn--primary" :disabled="!canSubmit || loading">
                <span v-if="loading" class="spinner" aria-hidden="true" />
                {{ t('clubRegistration.submit') }}
              </button>
            </div>
          </form>
        </template>

        <p v-if="errorText" class="alert alert--error" style="margin-top: var(--space-4)">{{ errorText }}</p>
      </div>
    </div>
  </div>
</template>
