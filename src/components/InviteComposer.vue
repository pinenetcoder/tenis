<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'

import { supabase } from '../lib/supabase'

const props = defineProps({
  orgId: { type: String, required: true },
})

const emit = defineEmits(['created', 'close'])

const { t } = useI18n()

const activeTab = ref('contact') // 'contact' | 'past'

const role = ref('member')
const message = ref('')
const busy = ref(false)
const errorText = ref('')

const contact = ref('')
const displayName = ref('')
const contactInputEl = ref(null)

const pastLoading = ref(false)
const pastPlayers = ref([])
const pastSearch = ref('')

const filteredPast = computed(() => {
  const q = pastSearch.value.trim().toLowerCase()
  if (!q) return pastPlayers.value
  return pastPlayers.value.filter((p) => p.display_name?.toLowerCase().includes(q))
})

async function loadPast() {
  pastLoading.value = true
  errorText.value = ''
  const { data, error } = await supabase.rpc('past_org_players', { p_org_id: props.orgId })
  pastLoading.value = false
  if (error) {
    errorText.value = error.message
    return
  }
  pastPlayers.value = data ?? []
}

async function pickPast(player) {
  if (player.has_pending_invite || player.has_pending_membership) return
  displayName.value = player.display_name ?? ''
  activeTab.value = 'contact'
  await nextTick()
  contactInputEl.value?.focus()
}

async function submitContact() {
  if (busy.value) return
  const value = contact.value.trim()
  if (!value) return
  busy.value = true
  errorText.value = ''

  const { data, error } = await supabase.rpc('create_invite', {
    p_org_id: props.orgId,
    p_contact: value,
    p_display_name: displayName.value.trim() || null,
    p_role: role.value,
    p_message: message.value.trim() || null,
  })

  busy.value = false
  if (error) {
    errorText.value = error.message
    return
  }
  if (data?.already_member) {
    errorText.value = t('club.invites.alreadyMember')
    return
  }
  contact.value = ''
  displayName.value = ''
  message.value = ''
  emit('created', data)
}

watch(activeTab, (v) => {
  if (v === 'past' && pastPlayers.value.length === 0) loadPast()
})

onMounted(() => {
  if (activeTab.value === 'past') loadPast()
})
</script>

<template>
  <div class="invite-composer stack stack--sm" @click.stop>
    <div class="tabs">
      <button
        type="button"
        class="tab"
        :class="{ 'tab--active': activeTab === 'contact' }"
        @click="activeTab = 'contact'"
      >
        {{ t('club.invites.tabContact') }}
      </button>
      <button
        type="button"
        class="tab"
        :class="{ 'tab--active': activeTab === 'past' }"
        @click="activeTab = 'past'"
      >
        {{ t('club.invites.tabPast') }}
      </button>
    </div>

    <form
      v-if="activeTab === 'contact'"
      class="stack stack--sm"
      @submit.prevent="submitContact"
    >
      <label class="form-field">
        <span>{{ t('club.invites.contactLabel') }}</span>
        <input
          ref="contactInputEl"
          v-model="contact"
          class="input"
          type="text"
          :placeholder="t('club.invites.contactPlaceholder')"
          required
        />
      </label>
      <label class="form-field">
        <span>{{ t('club.invites.displayNameLabel') }}</span>
        <input v-model="displayName" class="input" type="text" maxlength="80" />
        <small class="muted">{{ t('club.invites.displayNameHint') }}</small>
      </label>
      <label class="form-field">
        <span>{{ t('club.invites.roleLabel') }}</span>
        <select v-model="role" class="input">
          <option value="member">{{ t('club.invites.roleMember') }}</option>
          <option value="coach">{{ t('club.invites.roleCoach') }}</option>
          <option value="admin">{{ t('club.invites.roleAdmin') }}</option>
        </select>
      </label>
      <label class="form-field">
        <span>{{ t('club.invites.messageLabel') }}</span>
        <textarea
          v-model="message"
          class="input"
          rows="3"
          maxlength="500"
          :placeholder="t('club.invites.messagePlaceholder')"
        />
      </label>

      <div class="inline-actions">
        <button type="submit" class="btn btn--primary" :disabled="busy">
          {{ busy ? t('club.invites.sending') : t('club.invites.send') }}
        </button>
        <button type="button" class="btn btn--ghost" @click="emit('close')">
          {{ t('admin.cancel') }}
        </button>
      </div>
    </form>

    <div v-else class="stack stack--sm">
      <input
        v-model="pastSearch"
        class="input"
        type="text"
        :placeholder="t('club.invites.pastSearchPlaceholder')"
      />
      <div v-if="pastLoading" class="muted">{{ t('club.page.loading') }}</div>
      <div v-else-if="filteredPast.length === 0" class="muted">
        {{ t('club.invites.pastEmpty') }}
      </div>
      <ul v-else class="past-list">
        <li
          v-for="p in filteredPast"
          :key="p.player_id"
          class="past-item"
          :class="{ 'past-item--disabled': p.has_pending_invite || p.has_pending_membership }"
          @click="pickPast(p)"
        >
          <div class="past-item__avatar">
            <img v-if="p.avatar_url" :src="p.avatar_url" :alt="p.display_name" />
            <span v-else>{{ p.display_name?.charAt(0)?.toUpperCase() || '?' }}</span>
          </div>
          <div class="past-item__meta">
            <div class="past-item__name">{{ p.display_name }}</div>
            <div class="muted">
              {{ t('club.invites.pastTournaments', { count: p.tournaments_count }) }}
              <template v-if="p.has_pending_invite"> · {{ t('club.invites.pastPendingInvite') }}</template>
              <template v-else-if="p.has_pending_membership"> · {{ t('club.invites.pastPendingMembership') }}</template>
            </div>
          </div>
          <span v-if="!p.has_pending_invite && !p.has_pending_membership" class="past-item__action">
            {{ t('club.invites.selectToInvite') }}
          </span>
        </li>
      </ul>
    </div>

    <p v-if="errorText" class="error-text">{{ errorText }}</p>
  </div>
</template>

<style scoped>
.invite-composer {
  width: 100%;
}
.tabs {
  display: flex;
  gap: 2px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}
.tab {
  background: transparent;
  border: none;
  color: var(--muted);
  padding: 8px 16px;
  cursor: pointer;
  font: inherit;
  border-bottom: 2px solid transparent;
  margin-bottom: -1px;
}
.tab--active {
  color: var(--text);
  border-bottom-color: var(--primary);
}
.past-list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
  max-height: 320px;
  overflow-y: auto;
}
.past-item {
  display: flex;
  gap: var(--space-2);
  align-items: center;
  padding: var(--space-2);
  border-radius: var(--radius-sm);
  background: var(--surface-row, rgba(255, 255, 255, 0.03));
  cursor: pointer;
  transition: background 0.15s;
}
.past-item:hover:not(.past-item--disabled) {
  background: rgba(255, 255, 255, 0.06);
}
.past-item--disabled {
  opacity: 0.55;
  cursor: not-allowed;
}
.past-item__avatar {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background: var(--bg-elevated, rgba(255, 255, 255, 0.04));
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--primary);
  font-family: var(--font-display);
  overflow: hidden;
  flex-shrink: 0;
}
.past-item__avatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.past-item__meta {
  flex: 1;
  min-width: 0;
}
.past-item__name {
  font-weight: 600;
}
.past-item__action {
  color: var(--primary);
  font-size: 0.85rem;
}
</style>
