<script setup>
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'

import { supabase } from '../lib/supabase'
import { useAuthStore } from '../stores/auth'

const props = defineProps({
  orgSlug: { type: String, required: true },
  autoApprove: { type: Boolean, default: true },
  membership: { type: Object, default: null }, // { id, status, role, is_primary } | null
})

const emit = defineEmits(['updated'])

const { t } = useI18n()
const auth = useAuthStore()

const busy = ref(false)
const errorText = ref('')
const successText = ref('')
const menuOpen = ref(false)

const status = computed(() => props.membership?.status ?? null)

const state = computed(() => {
  if (!auth.user) return 'anonymous'
  if (!status.value) return 'none'
  if (status.value === 'active') return 'active'
  if (status.value === 'pending') return 'pending'
  if (status.value === 'banned') return 'banned'
  return 'none'
})

async function signInAndJoin() {
  // Come back to this exact page with ?action=join, then the page triggers join.
  const returnTo = `${window.location.origin}/clubs/${props.orgSlug}?action=join`
  const { error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: returnTo },
  })
  if (error) errorText.value = error.message
}

async function join() {
  if (busy.value) return
  busy.value = true
  errorText.value = ''
  successText.value = ''

  // Ensure a player row exists for the current user before join_organization.
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

  const { data, error } = await supabase.rpc('join_organization', {
    p_org_slug: props.orgSlug,
  })

  busy.value = false

  if (error) {
    errorText.value = error.message
    return
  }

  successText.value = data?.needs_approval
    ? t('club.join.successPending')
    : t('club.join.success')

  await auth.loadPlayerContext({ force: true })
  emit('updated')
}

async function leave() {
  if (busy.value || !props.membership) return
  if (!window.confirm(t('club.join.confirmLeave'))) return
  busy.value = true
  errorText.value = ''

  // Need org_id — membership has it via join
  const orgId = props.membership.org_id
  const { error } = await supabase.rpc('leave_organization', { p_org_id: orgId })
  busy.value = false
  menuOpen.value = false
  if (error) {
    errorText.value = error.message
    return
  }
  await auth.loadPlayerContext({ force: true })
  emit('updated')
}

async function makePrimary() {
  if (busy.value || !props.membership) return
  busy.value = true
  const { error } = await supabase.rpc('set_primary_club', {
    p_org_id: props.membership.org_id,
  })
  busy.value = false
  menuOpen.value = false
  if (error) {
    errorText.value = error.message
    return
  }
  await auth.loadPlayerContext({ force: true })
  emit('updated')
}

// Public: called by parent when ?action=join is in URL after OAuth return.
defineExpose({ join })
</script>

<template>
  <div class="join-club">
    <!-- Anonymous: log in + come back to join -->
    <button
      v-if="state === 'anonymous'"
      type="button"
      class="btn btn--primary btn--lg"
      :disabled="busy"
      @click="signInAndJoin"
    >
      {{ t('club.join.signInAndJoin') }}
    </button>

    <!-- Not a member yet: show Join (label depends on auto_approve) -->
    <button
      v-else-if="state === 'none'"
      type="button"
      class="btn btn--primary btn--lg"
      :disabled="busy"
      @click="join"
    >
      {{ busy ? t('club.join.joining') : (autoApprove ? t('club.join.join') : t('club.join.joinClosed')) }}
    </button>

    <!-- Pending: disabled badge -->
    <div v-else-if="state === 'pending'" class="stack stack--sm">
      <button type="button" class="btn btn--ghost btn--lg" disabled>
        {{ t('club.join.membershipPending') }}
      </button>
      <p class="muted">{{ t('club.join.pendingHint') }}</p>
    </div>

    <!-- Banned -->
    <div v-else-if="state === 'banned'" class="stack stack--sm">
      <button type="button" class="btn btn--ghost btn--lg" disabled>
        {{ t('club.join.banned') }}
      </button>
      <p class="muted">{{ t('club.join.bannedHint') }}</p>
    </div>

    <!-- Active state is rendered in the public-header profile dropdown. -->

    <p v-if="successText" class="success-text">{{ successText }}</p>
    <p v-if="errorText" class="error-text">{{ errorText }}</p>
  </div>
</template>

<style scoped>
.join-club {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  align-items: flex-start;
}
.join-club__active {
  position: relative;
}
.join-club__dropdown {
  position: absolute;
  top: calc(100% + 4px);
  left: 0;
  background: var(--surface);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: var(--radius-sm);
  box-shadow: var(--shadow-md);
  min-width: 200px;
  padding: 4px;
  z-index: 10;
}
.dropdown-item {
  display: block;
  width: 100%;
  text-align: left;
  padding: 8px 12px;
  border: none;
  background: transparent;
  color: var(--text);
  border-radius: calc(var(--radius-sm) - 4px);
  font: inherit;
  cursor: pointer;
}
.dropdown-item:hover:not(:disabled) {
  background: rgba(255, 255, 255, 0.06);
}
.dropdown-item--danger {
  color: var(--danger);
}
.dropdown-item:disabled {
  opacity: 0.5;
  cursor: wait;
}
</style>
