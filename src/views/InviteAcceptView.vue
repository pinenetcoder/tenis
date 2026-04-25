<script setup>
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'

import { supabase } from '../lib/supabase'
import { useAuthStore } from '../stores/auth'

const props = defineProps({
  token: { type: String, required: true },
})

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const { t, locale } = useI18n()

const loading = ref(true)
const busy = ref(false)
const preview = ref(null)
const errorText = ref('')
const doneState = ref('') // 'accepted' | 'rejected'

const status = computed(() => preview.value?.status ?? null)
const org = computed(() => preview.value?.org ?? null)

const roleLabel = computed(() => {
  const role = preview.value?.role
  if (role === 'coach') return t('club.accept.roleAsCoach')
  if (role === 'admin') return t('club.accept.roleAsAdmin')
  return t('club.accept.roleAsMember')
})

function initials(name) {
  if (!name) return '?'
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p.charAt(0).toUpperCase())
    .join('')
}

function formatExpires(dateStr) {
  if (!dateStr) return ''
  try {
    return new Date(dateStr).toLocaleDateString(locale.value, {
      year: 'numeric', month: 'short', day: 'numeric',
    })
  } catch {
    return ''
  }
}

async function load() {
  loading.value = true
  errorText.value = ''
  const { data, error } = await supabase.rpc('get_invite_preview', { p_token: props.token })
  loading.value = false
  if (error) {
    errorText.value = error.message
    return
  }
  preview.value = data
  if (data?.found && route.query.action === 'reject') {
    await doReject()
  }
}

async function doAccept() {
  if (busy.value) return
  if (!auth.user) {
    const returnTo = `${window.location.origin}/invites/${props.token}`
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: returnTo },
    })
    if (error) errorText.value = error.message
    return
  }
  busy.value = true
  errorText.value = ''

  // Make sure a player row exists for the user before accept_invite.
  if (!auth.currentPlayer) {
    const fullName = auth.user?.user_metadata?.full_name
      || auth.user?.email
      || 'Player'
    const contact = auth.user?.email ?? null
    const { error: upErr } = await supabase.rpc('upsert_player', {
      p_display_name: fullName,
      p_contact: contact,
      p_user_id: auth.user.id,
    })
    if (upErr) {
      errorText.value = upErr.message
      busy.value = false
      return
    }
  }

  const { error } = await supabase.rpc('accept_invite', { p_token: props.token })
  busy.value = false
  if (error) {
    errorText.value = error.message
    return
  }
  doneState.value = 'accepted'
  await auth.loadPlayerContext({ force: true })
}

async function doReject() {
  if (busy.value) return
  busy.value = true
  errorText.value = ''
  const { error } = await supabase.rpc('reject_invite', { p_token: props.token })
  busy.value = false
  if (error) {
    errorText.value = error.message
    return
  }
  doneState.value = 'rejected'
}

function goToClub() {
  if (org.value?.slug) {
    router.push({ name: 'public-club', params: { slug: org.value.slug } })
  } else {
    router.push({ name: 'home' })
  }
}

onMounted(async () => {
  await auth.init()
  if (auth.user) await auth.loadPlayerContext()
  await load()
})
</script>

<template>
  <div class="invite-accept stack stack--lg">
    <div v-if="loading" class="muted">{{ t('club.accept.loading') }}</div>

    <!-- Done state: after accept/reject in this session -->
    <template v-else-if="doneState === 'accepted'">
      <section class="card card--elevated stack stack--sm invite-done">
        <h1 class="page-title">{{ t('club.accept.successTitle') }}</h1>
        <p class="muted">{{ t('club.accept.successHint') }}</p>
        <div class="inline-actions">
          <button type="button" class="btn btn--primary btn--lg" @click="goToClub">
            {{ t('club.accept.goToClub') }}
          </button>
        </div>
      </section>
    </template>
    <template v-else-if="doneState === 'rejected'">
      <section class="card card--elevated stack stack--sm invite-done">
        <h1 class="page-title">{{ t('club.accept.rejectedDoneTitle') }}</h1>
        <p class="muted">{{ t('club.accept.rejectedDoneHint') }}</p>
      </section>
    </template>

    <!-- Not found / status-based empty states -->
    <section v-else-if="!preview?.found" class="empty-state">
      <h2>{{ t('club.accept.notFoundTitle') }}</h2>
      <p class="muted">{{ t('club.accept.notFoundHint') }}</p>
      <p v-if="errorText" class="error-text">{{ errorText }}</p>
    </section>

    <section v-else-if="status === 'expired'" class="empty-state">
      <h2>{{ t('club.accept.expiredTitle') }}</h2>
      <p class="muted">{{ t('club.accept.expiredHint') }}</p>
    </section>

    <section v-else-if="status === 'revoked'" class="empty-state">
      <h2>{{ t('club.accept.revokedTitle') }}</h2>
      <p class="muted">{{ t('club.accept.revokedHint') }}</p>
    </section>

    <section v-else-if="status === 'rejected'" class="empty-state">
      <h2>{{ t('club.accept.rejectedTitle') }}</h2>
      <p class="muted">{{ t('club.accept.rejectedHint') }}</p>
    </section>

    <section v-else-if="status === 'accepted'" class="empty-state">
      <h2>{{ t('club.accept.acceptedTitle') }}</h2>
      <p class="muted">{{ t('club.accept.acceptedHint') }}</p>
      <div class="inline-actions" style="justify-content:center;">
        <button type="button" class="btn btn--primary" @click="goToClub">
          {{ t('club.accept.goToClub') }}
        </button>
      </div>
    </section>

    <!-- Pending: main CTA -->
    <template v-else-if="status === 'pending' && org">
      <section class="card card--elevated stack stack--sm">
        <div class="invite-hero">
          <div class="invite-hero__logo">
            <img v-if="org.logo_url" :src="org.logo_url" :alt="org.name" />
            <span v-else>{{ initials(org.name) }}</span>
          </div>
          <div class="stack stack--sm" style="flex:1; min-width:0;">
            <p class="muted">
              <template v-if="preview.inviter_name">
                {{ t('club.accept.intro', { inviter: preview.inviter_name }) }}
              </template>
              <template v-else>
                {{ t('club.accept.introAnon') }}
              </template>
              — {{ roleLabel }}
            </p>
            <h1 class="page-title">{{ org.name }}</h1>
            <p v-if="org.city || org.country" class="muted">
              {{ [org.city, org.country].filter(Boolean).join(', ') }}
            </p>
            <p v-if="org.description">{{ org.description }}</p>
          </div>
        </div>

        <div v-if="preview.message" class="card invite-message">
          <strong>{{ t('club.accept.messageTitle') }}</strong>
          <p>{{ preview.message }}</p>
        </div>

        <p v-if="preview.expires_at" class="muted">
          {{ formatExpires(preview.expires_at) }}
        </p>

        <div class="inline-actions" style="gap: var(--space-2);">
          <button
            v-if="auth.user"
            type="button"
            class="btn btn--primary btn--lg"
            :disabled="busy"
            @click="doAccept"
          >
            {{ busy ? t('club.accept.accepting') : t('club.accept.accept') }}
          </button>
          <button
            v-else
            type="button"
            class="btn btn--primary btn--lg"
            :disabled="busy"
            @click="doAccept"
          >
            {{ t('club.accept.signInAndAccept') }}
          </button>

          <button
            type="button"
            class="btn btn--ghost btn--lg"
            :disabled="busy"
            @click="doReject"
          >
            {{ busy ? t('club.accept.rejecting') : t('club.accept.reject') }}
          </button>
        </div>

        <p v-if="errorText" class="error-text">{{ errorText }}</p>
      </section>
    </template>
  </div>
</template>

<style scoped>
.invite-accept {
  max-width: 640px;
  margin: 0 auto;
}
.invite-hero {
  display: flex;
  gap: var(--space-4);
  align-items: flex-start;
  flex-wrap: wrap;
}
.invite-hero__logo {
  width: 88px;
  height: 88px;
  border-radius: var(--radius);
  background: var(--bg-elevated, rgba(255, 255, 255, 0.04));
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: var(--font-display);
  font-size: 2rem;
  color: var(--primary);
  flex-shrink: 0;
  overflow: hidden;
}
.invite-hero__logo img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.invite-message {
  background: var(--surface-row, rgba(255, 255, 255, 0.03));
  padding: var(--space-3);
  border-radius: var(--radius-sm);
}
.invite-message p {
  margin: 4px 0 0;
  white-space: pre-wrap;
}
.invite-done {
  text-align: center;
  align-items: center;
}
</style>
