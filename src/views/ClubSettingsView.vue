<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'

import InviteComposer from '../components/InviteComposer.vue'
import KebabMenu from '../components/KebabMenu.vue'
import { supabase } from '../lib/supabase'
import { useAuthStore } from '../stores/auth'

const { t, locale } = useI18n()
const auth = useAuthStore()

const TABS = ['data', 'links', 'members', 'invites']

function readHashTab() {
  const h = window.location.hash.replace('#', '')
  return TABS.includes(h) ? h : 'data'
}

const activeTab = ref(readHashTab())

function setTab(tab) {
  activeTab.value = tab
  history.replaceState(null, '', `#${tab}`)
}

function onHashChange() {
  activeTab.value = readHashTab()
}

function onTabKeydown(event) {
  const idx = TABS.indexOf(activeTab.value)
  let next = -1
  if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
    next = (idx + 1) % TABS.length
  } else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
    next = (idx - 1 + TABS.length) % TABS.length
  } else if (event.key === 'Home') {
    next = 0
  } else if (event.key === 'End') {
    next = TABS.length - 1
  }
  if (next >= 0) {
    event.preventDefault()
    setTab(TABS[next])
    nextTick(() => {
      const btn = document.getElementById(`tab-${TABS[next]}`)
      btn?.focus()
    })
  }
}

const loading = ref(true)
const saving = ref(false)
const errorText = ref('')
const successText = ref('')

const org = ref(null)

const form = ref({
  slug: '',
  name: '',
  description: '',
  city: '',
  country: '',
  auto_approve_members: true,
})

const publicUrl = computed(() => {
  if (!form.value.slug) return ''
  return `${window.location.origin}/clubs/${form.value.slug}`
})

async function load() {
  loading.value = true
  await auth.loadPlayerContext({ force: true })
  const first = auth.ownedOrganizations.find((o) => o.type === 'club')
    ?? auth.ownedOrganizations[0]
    ?? null

  if (!first) {
    loading.value = false
    org.value = null
    return
  }

  const { data, error } = await supabase
    .from('organizations')
    .select('*')
    .eq('id', first.id)
    .maybeSingle()

  loading.value = false
  if (error) {
    errorText.value = error.message
    return
  }
  if (!data) {
    org.value = null
    return
  }

  org.value = data
  form.value = {
    slug: data.slug ?? '',
    name: data.name ?? '',
    description: data.description ?? '',
    city: data.city ?? '',
    country: data.country ?? '',
    auto_approve_members: !!data.auto_approve_members,
  }
}

function mapErrorKey(message = '') {
  if (/Slug must be 3\.\.40/i.test(message) || /Slug must be lowercase/i.test(message)) {
    return t('club.settings.invalidSlug')
  }
  if (/Slug already in use/i.test(message)) return t('club.settings.slugTaken')
  if (/reserved/i.test(message)) return t('club.settings.reservedSlug')
  return message
}

function flashSuccess(text, ms = 2500) {
  successText.value = text
  setTimeout(() => {
    if (successText.value === text) successText.value = ''
  }, ms)
}

async function onSubmit() {
  if (saving.value || !org.value) return
  saving.value = true
  errorText.value = ''
  successText.value = ''

  const payload = {
    p_org_id: org.value.id,
    p_slug: form.value.slug?.trim() ?? '',
    p_name: form.value.name?.trim() || null,
    p_description: form.value.description?.trim() || null,
    p_city: form.value.city?.trim() || null,
    p_country: form.value.country?.trim() || null,
    p_auto_approve_members: form.value.auto_approve_members,
  }

  const { data, error } = await supabase.rpc('update_organization', payload)
  saving.value = false

  if (error) {
    errorText.value = mapErrorKey(error.message)
    return
  }

  flashSuccess(t('club.settings.saved'))
  org.value = data ?? org.value
  if (data) {
    form.value.slug = data.slug ?? ''
  }
  await auth.loadPlayerContext({ force: true })
}

async function copyLink() {
  if (!publicUrl.value) return
  try {
    await navigator.clipboard.writeText(publicUrl.value)
    flashSuccess(t('club.settings.linkCopied'))
  } catch {
    // noop
  }
}

// ---------- Members tab ----------
const members = ref([])
const membersLoaded = ref(false)
const loadingMembers = ref(false)
const membersError = ref('')
const removingMembershipId = ref(null)

function memberRoleLabel(role) {
  if (role === 'admin') return t('club.members.roleAdmin')
  if (role === 'student') return t('club.members.roleStudent')
  if (role === 'external') return t('club.members.roleExternal')
  return t('club.members.roleMember')
}

function formatJoined(dateStr) {
  if (!dateStr) return '—'
  try {
    return new Date(dateStr).toLocaleDateString(locale.value, {
      year: 'numeric', month: 'short', day: 'numeric',
    })
  } catch {
    return ''
  }
}

async function loadMembers() {
  if (!org.value) return
  loadingMembers.value = true
  membersError.value = ''
  const { data, error } = await supabase
    .from('org_memberships')
    .select('id, role, status, is_primary, joined_at, players(id, display_name, avatar_url, user_id)')
    .eq('org_id', org.value.id)
    .eq('status', 'active')
    .order('joined_at', { ascending: false })
  loadingMembers.value = false
  if (error) {
    membersError.value = error.message
    return
  }
  members.value = data ?? []
  membersLoaded.value = true
}

async function removeMember(membership) {
  if (removingMembershipId.value) return
  const name = membership.players?.display_name ?? ''
  if (!window.confirm(t('club.members.removeConfirm', { name }))) return
  removingMembershipId.value = membership.id
  membersError.value = ''
  const { error } = await supabase.rpc('remove_membership', {
    p_membership_id: membership.id,
    p_ban: false,
    p_note: null,
  })
  removingMembershipId.value = null
  if (error) {
    membersError.value = t('club.members.removeError')
    return
  }
  members.value = members.value.filter((m) => m.id !== membership.id)
  flashSuccess(t('club.members.removed'))
}

// ---------- Invites tab ----------
const invites = ref([])
const joinRequests = ref([])
const invitesLoaded = ref(false)
const loadingInvites = ref(false)
const invitesError = ref('')
const busyMembershipId = ref(null)
const composerOpen = ref(false)

const groupedInvites = computed(() => {
  const groups = { pending: [], other: [] }
  for (const inv of invites.value) {
    if (inv.status === 'pending' && new Date(inv.expires_at) > new Date()) {
      groups.pending.push(inv)
    } else {
      groups.other.push(inv)
    }
  }
  return groups
})

async function loadInvites() {
  if (!org.value) return
  loadingInvites.value = true
  invitesError.value = ''
  const [invitesRes, requestsRes] = await Promise.all([
    supabase.rpc('list_invites', { p_org_id: org.value.id }),
    supabase.rpc('list_join_requests', { p_org_id: org.value.id }),
  ])
  loadingInvites.value = false
  if (invitesRes.error) {
    invitesError.value = invitesRes.error.message
    return
  }
  if (requestsRes.error) {
    invitesError.value = requestsRes.error.message
    return
  }
  invites.value = invitesRes.data ?? []
  joinRequests.value = requestsRes.data ?? []
  invitesLoaded.value = true
}

async function approveJoinRequest(req) {
  if (busyMembershipId.value) return
  busyMembershipId.value = req.membership_id
  invitesError.value = ''
  const { error } = await supabase.rpc('approve_membership', {
    p_membership_id: req.membership_id,
  })
  busyMembershipId.value = null
  if (error) {
    invitesError.value = error.message
    return
  }
  flashSuccess(t('club.invites.joinApproved'))
  await loadInvites()
  if (membersLoaded.value) await loadMembers()
}

async function rejectJoinRequest(req) {
  if (busyMembershipId.value) return
  if (!window.confirm(t('club.invites.confirmRejectJoin'))) return
  busyMembershipId.value = req.membership_id
  invitesError.value = ''
  const { error } = await supabase.rpc('reject_membership', {
    p_membership_id: req.membership_id,
  })
  busyMembershipId.value = null
  if (error) {
    invitesError.value = error.message
    return
  }
  flashSuccess(t('club.invites.joinRejected'))
  await loadInvites()
}

function inviteRoleLabel(role) {
  if (role === 'coach') return t('club.invites.roleCoach')
  if (role === 'admin') return t('club.invites.roleAdmin')
  return t('club.invites.roleMember')
}

function statusLabel(status, expiresAt) {
  if (status === 'pending' && new Date(expiresAt) < new Date()) {
    return t('club.invites.statusExpired')
  }
  const key = `club.invites.status${status.charAt(0).toUpperCase()}${status.slice(1)}`
  return t(key)
}

function statusBadge(status, expiresAt) {
  if (status === 'accepted') return 'badge--success'
  if (status === 'pending' && new Date(expiresAt) > new Date()) return 'badge--warn'
  if (status === 'rejected' || status === 'revoked' || status === 'expired') return 'badge--danger'
  return 'badge--neutral'
}

function formatDate(dateStr) {
  if (!dateStr) return ''
  try {
    return new Date(dateStr).toLocaleDateString(locale.value, {
      year: 'numeric', month: 'short', day: 'numeric',
    })
  } catch {
    return ''
  }
}

function inviteUrl(token) {
  return `${window.location.origin}/invites/${token}`
}

async function copyInviteLink(token) {
  try {
    await navigator.clipboard.writeText(inviteUrl(token))
    flashSuccess(t('club.invites.linkCopied'))
  } catch {
    // noop
  }
}

async function revoke(invite) {
  if (!window.confirm(t('club.invites.confirmRevoke'))) return
  const { error } = await supabase.rpc('revoke_invite', { p_invite_id: invite.id })
  if (error) {
    invitesError.value = error.message
    return
  }
  await loadInvites()
}

function onInviteCreated() {
  composerOpen.value = false
  flashSuccess(t('club.invites.sent'), 3000)
  loadInvites()
}

// Lazy-load tab data when first opened (and org is ready).
watch([activeTab, org], ([tab, currentOrg]) => {
  if (!currentOrg) return
  if (tab === 'members' && !membersLoaded.value) loadMembers()
  if (tab === 'invites' && !invitesLoaded.value) loadInvites()
}, { immediate: true })

onMounted(async () => {
  window.addEventListener('hashchange', onHashChange)
  await load()
})

onBeforeUnmount(() => {
  window.removeEventListener('hashchange', onHashChange)
})
</script>

<template>
  <div class="stack stack--lg">
    <div class="stack stack--sm">
      <h1 class="page-title">{{ t('club.settings.title') }}</h1>
      <p class="muted">{{ t('club.settings.subtitle') }}</p>
    </div>

    <div v-if="loading" class="muted">{{ t('club.page.loading') }}</div>

    <div v-else-if="!org" class="empty-state">
      <p class="muted">{{ t('club.settings.notClubOwner') }}</p>
    </div>

    <template v-else>
      <p v-if="successText" class="success-text">{{ successText }}</p>
      <p v-if="errorText" class="error-text">{{ errorText }}</p>

      <div role="tablist" class="tab-group" @keydown="onTabKeydown">
        <button
          id="tab-data"
          role="tab"
          class="tab"
          :class="{ 'tab--active': activeTab === 'data' }"
          :aria-selected="activeTab === 'data'"
          :tabindex="activeTab === 'data' ? 0 : -1"
          aria-controls="panel-data"
          @click="setTab('data')"
        >
          {{ t('club.settings.tabData') }}
        </button>
        <button
          id="tab-links"
          role="tab"
          class="tab"
          :class="{ 'tab--active': activeTab === 'links' }"
          :aria-selected="activeTab === 'links'"
          :tabindex="activeTab === 'links' ? 0 : -1"
          aria-controls="panel-links"
          @click="setTab('links')"
        >
          {{ t('club.settings.tabLinks') }}
        </button>
        <button
          id="tab-members"
          role="tab"
          class="tab"
          :class="{ 'tab--active': activeTab === 'members' }"
          :aria-selected="activeTab === 'members'"
          :tabindex="activeTab === 'members' ? 0 : -1"
          aria-controls="panel-members"
          @click="setTab('members')"
        >
          {{ t('club.settings.tabMembers') }}
        </button>
        <button
          id="tab-invites"
          role="tab"
          class="tab"
          :class="{ 'tab--active': activeTab === 'invites' }"
          :aria-selected="activeTab === 'invites'"
          :tabindex="activeTab === 'invites' ? 0 : -1"
          aria-controls="panel-invites"
          @click="setTab('invites')"
        >
          {{ t('club.settings.tabInvites') }}
          <span v-if="joinRequests.length" class="tab__badge">{{ joinRequests.length }}</span>
        </button>
      </div>

      <!-- DATA TAB -->
      <section
        v-if="activeTab === 'data'"
        id="panel-data"
        role="tabpanel"
        aria-labelledby="tab-data"
      >
        <form class="card card--elevated stack stack--sm" @submit.prevent="onSubmit" style="max-width:560px;">
          <label class="form-field">
            <span>{{ t('club.settings.nameLabel') }}</span>
            <input v-model="form.name" class="input" type="text" maxlength="80" required />
          </label>

          <label class="form-field">
            <span>{{ t('club.settings.descriptionLabel') }}</span>
            <textarea v-model="form.description" class="input" rows="3" maxlength="500"></textarea>
          </label>

          <div class="grid-2" style="gap: var(--space-2);">
            <label class="form-field">
              <span>{{ t('club.settings.cityLabel') }}</span>
              <input v-model="form.city" class="input" type="text" maxlength="80" />
            </label>
            <label class="form-field">
              <span>{{ t('club.settings.countryLabel') }}</span>
              <input v-model="form.country" class="input" type="text" maxlength="80" />
            </label>
          </div>

          <label class="checkbox-row">
            <input v-model="form.auto_approve_members" type="checkbox" />
            <span>
              <strong>{{ t('club.settings.autoApproveLabel') }}</strong><br>
              <small class="muted">{{ t('club.settings.autoApproveHint') }}</small>
            </span>
          </label>

          <div class="inline-actions" style="margin-top: var(--space-2);">
            <button type="submit" class="btn btn--primary" :disabled="saving">
              {{ saving ? t('club.page.loading') : t('club.settings.save') }}
            </button>
          </div>
        </form>
      </section>

      <!-- LINKS TAB -->
      <section
        v-if="activeTab === 'links'"
        id="panel-links"
        role="tabpanel"
        aria-labelledby="tab-links"
      >
        <form class="card card--elevated stack stack--sm" @submit.prevent="onSubmit" style="max-width:560px;">
          <label class="form-field">
            <span>{{ t('club.settings.slugLabel') }}</span>
            <input
              v-model="form.slug"
              class="input"
              type="text"
              maxlength="40"
              pattern="[a-z0-9]+(-[a-z0-9]+)*"
              :placeholder="t('club.settings.slugPlaceholder')"
            />
            <small class="muted">{{ t('club.settings.slugHint') }}</small>
          </label>

          <div v-if="publicUrl" class="form-field">
            <span>{{ t('club.settings.publicLink') }}</span>
            <button
              type="button"
              class="public-link"
              :title="t('club.settings.copyLink')"
              @click="copyLink"
            >
              {{ publicUrl }}
            </button>
          </div>

          <div class="inline-actions" style="margin-top: var(--space-2);">
            <button type="submit" class="btn btn--primary" :disabled="saving">
              {{ saving ? t('club.page.loading') : t('club.settings.save') }}
            </button>
          </div>
        </form>
      </section>

      <!-- MEMBERS TAB -->
      <section
        v-if="activeTab === 'members'"
        id="panel-members"
        role="tabpanel"
        aria-labelledby="tab-members"
      >
        <div class="stack stack--sm">
          <p v-if="membersError" class="error-text">{{ membersError }}</p>

          <div v-if="loadingMembers" class="muted">{{ t('club.page.loading') }}</div>

          <div v-else-if="!members.length" class="empty-state">
            <p class="muted">{{ t('club.members.empty') }}</p>
          </div>

          <div v-else class="card members-card">
            <table class="members-table">
              <thead>
                <tr>
                  <th>{{ t('club.members.columnPlayer') }}</th>
                  <th>{{ t('club.members.columnRole') }}</th>
                  <th>{{ t('club.members.columnJoined') }}</th>
                  <th class="members-table__actions"><span class="visually-hidden">{{ t('club.members.actionsLabel') }}</span></th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="m in members" :key="m.id">
                  <td>
                    <div class="member-cell">
                      <span class="member-avatar" aria-hidden="true">
                        <img v-if="m.players?.avatar_url" :src="m.players.avatar_url" alt="" />
                        <span v-else>{{ (m.players?.display_name ?? '?').charAt(0).toUpperCase() }}</span>
                      </span>
                      <span class="member-name">{{ m.players?.display_name ?? '—' }}</span>
                    </div>
                  </td>
                  <td>{{ memberRoleLabel(m.role) }}</td>
                  <td>{{ formatJoined(m.joined_at) }}</td>
                  <td class="members-table__actions">
                    <KebabMenu :aria-label="t('club.members.actionsLabel')">
                      <button
                        type="button"
                        class="kebab__danger"
                        :disabled="removingMembershipId === m.id"
                        @click="removeMember(m)"
                      >
                        {{ t('club.members.remove') }}
                      </button>
                    </KebabMenu>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <!-- INVITES TAB -->
      <section
        v-if="activeTab === 'invites'"
        id="panel-invites"
        role="tabpanel"
        aria-labelledby="tab-invites"
      >
        <div class="stack stack--md">
          <div class="inline-actions" style="justify-content: space-between; align-items: center;">
            <p class="muted" style="margin:0;">{{ t('club.invites.subtitle') }}</p>
            <button type="button" class="btn btn--primary" @click="composerOpen = true">
              {{ t('club.invites.createButton') }}
            </button>
          </div>

          <p v-if="invitesError" class="error-text">{{ invitesError }}</p>

          <div v-if="loadingInvites" class="muted">{{ t('club.page.loading') }}</div>

          <template v-else>
            <section v-if="joinRequests.length > 0" class="card stack stack--sm">
              <h2 class="section-title">{{ t('club.invites.joinRequestsTitle') }}</h2>
              <p class="muted">{{ t('club.invites.joinRequestsHint') }}</p>
              <div class="invite-rows">
                <div v-for="req in joinRequests" :key="req.membership_id" class="invite-row">
                  <div class="invite-row__main">
                    <div class="invite-row__contact">
                      {{ req.display_name }}
                      <span v-if="req.user_email" class="muted">— {{ req.user_email }}</span>
                    </div>
                    <div class="invite-row__meta muted">
                      <span class="badge badge--warn">{{ t('club.invites.statusJoinPending') }}</span>
                      <span>{{ inviteRoleLabel(req.role) }}</span>
                      <span>{{ formatDate(req.created_at) }}</span>
                    </div>
                  </div>
                  <div class="invite-row__actions">
                    <button
                      type="button"
                      class="btn btn--primary btn--sm"
                      :disabled="busyMembershipId === req.membership_id"
                      @click="approveJoinRequest(req)"
                    >
                      {{ t('club.invites.approveJoin') }}
                    </button>
                    <button
                      type="button"
                      class="btn btn--ghost btn--sm"
                      :disabled="busyMembershipId === req.membership_id"
                      @click="rejectJoinRequest(req)"
                    >
                      {{ t('club.invites.rejectJoin') }}
                    </button>
                  </div>
                </div>
              </div>
            </section>

            <div v-if="invites.length === 0 && joinRequests.length === 0" class="empty-state">
              <h2>{{ t('club.invites.emptyTitle') }}</h2>
              <p class="muted">{{ t('club.invites.emptyHint') }}</p>
            </div>

            <template v-if="invites.length > 0">
              <section v-if="groupedInvites.pending.length > 0" class="card stack stack--sm">
                <h2 class="section-title">{{ t('club.invites.statusPending') }}</h2>
                <div class="invite-rows">
                  <div v-for="inv in groupedInvites.pending" :key="inv.id" class="invite-row">
                    <div class="invite-row__main">
                      <div class="invite-row__contact">
                        {{ inv.contact_email || inv.contact_phone }}
                        <span v-if="inv.player_display_name" class="muted">
                          — {{ inv.player_display_name }}
                        </span>
                      </div>
                      <div class="invite-row__meta muted">
                        <span class="badge badge--neutral">{{ inviteRoleLabel(inv.role) }}</span>
                        <span>{{ formatDate(inv.created_at) }}</span>
                      </div>
                    </div>
                    <div class="invite-row__actions">
                      <button type="button" class="btn btn--ghost btn--sm" @click="copyInviteLink(inv.token)">
                        {{ t('club.invites.copyLink') }}
                      </button>
                      <button type="button" class="btn btn--ghost btn--sm" @click="revoke(inv)">
                        {{ t('club.invites.revoke') }}
                      </button>
                    </div>
                  </div>
                </div>
              </section>

              <section v-if="groupedInvites.other.length > 0" class="card stack stack--sm">
                <h2 class="section-title">{{ t('club.invites.listTitle') }}</h2>
                <div class="invite-rows">
                  <div v-for="inv in groupedInvites.other" :key="inv.id" class="invite-row invite-row--done">
                    <div class="invite-row__main">
                      <div class="invite-row__contact">
                        {{ inv.contact_email || inv.contact_phone }}
                        <span v-if="inv.player_display_name" class="muted">
                          — {{ inv.player_display_name }}
                        </span>
                      </div>
                      <div class="invite-row__meta muted">
                        <span class="badge" :class="statusBadge(inv.status, inv.expires_at)">
                          {{ statusLabel(inv.status, inv.expires_at) }}
                        </span>
                        <span>{{ inviteRoleLabel(inv.role) }}</span>
                        <span>{{ formatDate(inv.created_at) }}</span>
                      </div>
                    </div>
                  </div>
                </div>
              </section>
            </template>
          </template>
        </div>
      </section>
    </template>

    <!-- Composer modal -->
    <div v-if="composerOpen" class="modal-backdrop" @click="composerOpen = false">
      <div class="modal-dialog" @click.stop>
        <div class="modal-dialog__head">
          <h2>{{ t('club.invites.createButton') }}</h2>
          <button
            type="button"
            class="modal-close"
            aria-label="Close"
            @click="composerOpen = false"
          >
            &times;
          </button>
        </div>
        <InviteComposer
          v-if="org"
          :org-id="org.id"
          @created="onInviteCreated"
          @close="composerOpen = false"
        />
      </div>
    </div>
  </div>
</template>

<style scoped>
.public-link {
  display: block;
  width: 100%;
  text-align: left;
  padding: 10px 14px;
  background: var(--surface-row, rgba(255, 255, 255, 0.03));
  border: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: var(--radius-sm);
  color: var(--text);
  font-family: var(--font-mono, monospace);
  font-size: 0.9rem;
  cursor: pointer;
  transition: border-color 0.15s, background 0.15s;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.public-link:hover {
  border-color: var(--primary);
  background: rgba(255, 255, 255, 0.06);
}

.tab__badge {
  display: inline-block;
  margin-left: 6px;
  min-width: 20px;
  padding: 0 6px;
  border-radius: 999px;
  font-size: 0.75rem;
  background: var(--primary, #f5b400);
  color: #000;
  line-height: 18px;
  text-align: center;
}

/* Members table */
.members-card {
  padding: 0;
  overflow: hidden;
}
.members-table {
  width: 100%;
  border-collapse: collapse;
}
.members-table th,
.members-table td {
  padding: 12px 16px;
  text-align: left;
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);
  font-size: 0.9375rem;
}
.members-table thead th {
  font-weight: 600;
  color: var(--muted);
  font-size: 0.8125rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
.members-table tbody tr:last-child td {
  border-bottom: none;
}
.members-table__actions {
  width: 56px;
  text-align: right;
}
.member-cell {
  display: flex;
  align-items: center;
  gap: 10px;
}
.member-avatar {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.08);
  color: var(--muted);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  font-size: 0.875rem;
  overflow: hidden;
  flex-shrink: 0;
}
.member-avatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.member-name {
  font-weight: 500;
}
.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
}

/* Invite rows (copied from previous ClubAdminInvitesView) */
.invite-rows {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}
.invite-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  padding: var(--space-2) var(--space-3);
  background: var(--surface-row, rgba(255, 255, 255, 0.03));
  border-radius: var(--radius-sm);
  flex-wrap: wrap;
}
.invite-row--done {
  opacity: 0.85;
}
.invite-row__main {
  flex: 1;
  min-width: 220px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.invite-row__contact {
  font-weight: 600;
  word-break: break-word;
}
.invite-row__meta {
  display: flex;
  gap: var(--space-2);
  flex-wrap: wrap;
  font-size: 0.875rem;
  align-items: center;
}
.invite-row__actions {
  display: flex;
  gap: var(--space-1);
  flex-wrap: wrap;
}

.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.6);
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding: var(--space-4);
  z-index: 100;
  overflow-y: auto;
}
.modal-dialog {
  background: var(--surface);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: var(--radius);
  padding: var(--space-4);
  max-width: 560px;
  width: 100%;
  margin-top: var(--space-6);
  box-shadow: var(--shadow-lg);
}
.modal-dialog__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: var(--space-3);
}
.modal-dialog__head h2 {
  margin: 0;
  font-size: 1.25rem;
}
.modal-close {
  background: transparent;
  border: none;
  color: var(--muted);
  font-size: 1.5rem;
  cursor: pointer;
  padding: 0;
  line-height: 1;
}
</style>
