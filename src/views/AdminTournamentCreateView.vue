<script setup>
import { onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'

import { supabase } from '../lib/supabase'
import { useAuthStore } from '../stores/auth'

const { t } = useI18n()
const router = useRouter()
const auth = useAuthStore()

const saving = ref(false)
const errorText = ref('')

const form = reactive({
  name: '',
  slug: '',
  description: '',
  category: 'singles',
  set_format: 'best_of_3',
  is_public: true,
})

function slugify(value) {
  const normalized = value
    .toLowerCase()
    .trim()
    .replace(/\s+/g, '-')
    .replace(/[^a-z0-9-]/g, '')

  if (normalized) {
    return normalized
  }

  return `tournament-${Date.now()}`
}

async function createTournament() {
  if (!auth.user) {
    return
  }

  saving.value = true
  errorText.value = ''

  const slug = slugify(form.slug || form.name)

  const { data: newId, error } = await supabase.rpc('create_tournament', {
    p_name: form.name,
    p_slug: slug,
    p_description: form.description || null,
    p_category: form.category,
    p_set_format: form.set_format,
    p_is_public: form.is_public,
  })

  saving.value = false

  if (error) {
    errorText.value = error.message
    return
  }

  if (newId) {
    await router.replace({ name: 'admin-tournament', params: { id: newId } })
  } else {
    await router.replace({ name: 'admin-tournaments' })
  }
}

function cancel() {
  router.push({ name: 'admin-tournaments' })
}

onMounted(async () => {
  await auth.init()
})
</script>

<template>
  <div class="stack" style="max-width: 560px">
    <h1 class="page-title">{{ t('admin.createPageTitle') }}</h1>
    <p class="muted">{{ t('admin.createPageHint') }}</p>

    <form class="card stack stack--sm" @submit.prevent="createTournament">
      <div class="form-field">
        <label for="create-name">{{ t('admin.name') }}</label>
        <input id="create-name" v-model="form.name" class="input" type="text" required />
      </div>

      <div class="form-field">
        <label for="create-slug">{{ t('admin.slug') }}</label>
        <input id="create-slug" v-model="form.slug" class="input" type="text" placeholder="summer-cup-2026" />
      </div>

      <div class="form-field">
        <label for="create-desc">{{ t('admin.description') }}</label>
        <textarea id="create-desc" v-model="form.description" class="input" rows="3" />
      </div>

      <div class="form-field">
        <label for="create-cat">{{ t('admin.category') }}</label>
        <select id="create-cat" v-model="form.category" class="input">
          <option value="singles">{{ t('tournament.singles') }}</option>
          <option value="doubles">{{ t('tournament.doubles') }}</option>
        </select>
      </div>

      <div class="form-field">
        <label for="create-format">{{ t('admin.setFormat') }}</label>
        <select id="create-format" v-model="form.set_format" class="input">
          <option value="best_of_3">{{ t('format.best_of_3') }}</option>
          <option value="best_of_5">{{ t('format.best_of_5') }}</option>
        </select>
      </div>

      <label class="checkbox-row">
        <input v-model="form.is_public" type="checkbox" />
        {{ t('admin.isPublic') }}
      </label>

      <div class="inline-actions" style="margin-top: var(--space-2)">
        <button class="btn btn--primary" type="submit" :disabled="saving">
          {{ t('admin.create') }}
        </button>
        <button class="btn btn--ghost" type="button" :disabled="saving" @click="cancel">
          {{ t('actions.cancel') }}
        </button>
      </div>

      <p v-if="errorText" class="error-text">{{ errorText }}</p>
    </form>
  </div>
</template>
