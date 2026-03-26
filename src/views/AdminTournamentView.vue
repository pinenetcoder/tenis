<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'

import BracketBoard from '../components/BracketBoard.vue'
import ScoreEditor from '../components/ScoreEditor.vue'
import { supabase } from '../lib/supabase'
import { copyTournamentLink } from '../lib/shareLink'
import { useAuthStore } from '../stores/auth'

const props = defineProps({
  id: {
    type: String,
    required: true,
  },
})

const { t } = useI18n()
const router = useRouter()
const auth = useAuthStore()

const tournament = ref(null)
const entries = ref([])
const matches = ref([])
const matchSets = ref([])
const admins = ref([])

const loading = ref(false)
const actionLoading = ref(false)
const errorText = ref('')
const copyFeedback = ref(false)

const statusValue = ref('draft')
const settingsForm = reactive({
  name: '',
  slug: '',
  description: '',
  category: 'singles',
  set_format: 'best_of_3',
})
const settingsBaseline = ref({
  status: 'draft',
  is_public: false,
  name: '',
  slug: '',
  description: '',
  category: 'singles',
  set_format: 'best_of_3',
})
const drawMode = ref('auto-random')

const addAdminForm = reactive({
  userId: '',
  role: 'editor',
})

const addEntryForm = reactive({
  memberOne: '',
  memberTwo: '',
  displayName: '',
  phoneOrEmail: '',
  asPending: false,
})

const addEntryError = ref('')
const addEntrySuccess = ref('')
const addEntryContactTouched = ref(false)
const addEntryAccordionOpen = ref(false)

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const phonePattern = /^\+?[\d\s\-()]{7,20}$/

function isValidContact(value) {
  const trimmed = String(value).trim()
  return emailPattern.test(trimmed) || phonePattern.test(trimmed)
}

const addEntryContactInvalid = computed(() => {
  const v = addEntryForm.phoneOrEmail.trim()
  return addEntryContactTouched.value && Boolean(v) && !isValidContact(addEntryForm.phoneOrEmail)
})

let addEntrySuccessTimer = null

let channel = null
let reloadTimer = null

const entriesMap = computed(() => {
  return entries.value.reduce((acc, entry) => {
    acc[entry.id] = entry
    return acc
  }, {})
})

const setsByMatch = computed(() => {
  return matchSets.value.reduce((acc, item) => {
    if (!acc[item.match_id]) {
      acc[item.match_id] = []
    }
    acc[item.match_id].push(item)
    return acc
  }, {})
})

const pendingEntries = computed(() => entries.value.filter((entry) => entry.status === 'pending'))
const approvedEntries = computed(() => entries.value.filter((entry) => entry.status === 'approved'))

const showPublicShareActions = computed(() => {
  return tournament.value?.status !== 'draft'
})

const hasTournamentSettingsChanges = computed(() => {
  if (!tournament.value) {
    return false
  }
  const b = settingsBaseline.value
  return (
    statusValue.value !== b.status ||
    Boolean(tournament.value.is_public) !== b.is_public ||
    settingsForm.name !== b.name ||
    settingsForm.slug !== b.slug ||
    settingsForm.description !== b.description ||
    settingsForm.category !== b.category ||
    settingsForm.set_format !== b.set_format
  )
})

const canStartTournament = computed(() => tournament.value?.status === 'registration_closed')
const isTournamentActive = computed(() => tournament.value?.status === 'in_progress')
const isTournamentFinished = computed(() => tournament.value?.status === 'completed')

const showStartButton = computed(() => {
  const s = tournament.value?.status
  return s === 'draft' || s === 'registration_open' || s === 'registration_closed'
})

const isSettingsDropdownDisabled = computed(() => isTournamentActive.value || isTournamentFinished.value)

async function startTournament() {
  if (!window.confirm(t('admin.startTournamentConfirm'))) {
    return
  }

  actionLoading.value = true
  errorText.value = ''

  const { error } = await supabase
    .from('tournaments')
    .update({ status: 'in_progress' })
    .eq('id', props.id)

  actionLoading.value = false

  if (error) {
    errorText.value = error.message
    return
  }

  await loadAll()
}

async function finishTournament() {
  if (!window.confirm(t('admin.finishTournamentConfirm'))) {
    return
  }

  actionLoading.value = true
  errorText.value = ''

  const { error } = await supabase
    .from('tournaments')
    .update({ status: 'completed' })
    .eq('id', props.id)

  actionLoading.value = false

  if (error) {
    errorText.value = error.message
    return
  }

  await loadAll()
}

async function stopTournament() {
  if (!window.confirm(t('admin.stopTournamentConfirm'))) {
    return
  }

  actionLoading.value = true
  errorText.value = ''

  const { error } = await supabase
    .from('tournaments')
    .update({ status: 'registration_closed' })
    .eq('id', props.id)

  actionLoading.value = false

  if (error) {
    errorText.value = error.message
    return
  }

  await loadAll()
}

async function assertAccess() {
  const { data, error } = await supabase
    .from('tournament_admins')
    .select('id')
    .eq('tournament_id', props.id)
    .eq('user_id', auth.user.id)
    .maybeSingle()

  if (error) {
    throw error
  }

  if (!data) {
    throw new Error(t('errors.noAccess'))
  }
}

async function loadTournament() {
  const { data, error } = await supabase
    .from('tournaments')
    .select('id, name, slug, description, category, status, set_format, is_public')
    .eq('id', props.id)
    .maybeSingle()

  if (error) {
    throw error
  }

  if (!data) {
    throw new Error(t('errors.notFound'))
  }

  tournament.value = data
  statusValue.value = data.status
  settingsForm.name = data.name
  settingsForm.slug = data.slug || ''
  settingsForm.description = data.description || ''
  settingsForm.category = data.category
  settingsForm.set_format = data.set_format
  settingsBaseline.value = {
    status: data.status,
    is_public: Boolean(data.is_public),
    name: data.name,
    slug: data.slug || '',
    description: data.description || '',
    category: data.category,
    set_format: data.set_format,
  }
}

async function loadEntries() {
  const { data, error } = await supabase
    .from('entries')
    .select('id, display_name, entry_type, status, created_at')
    .eq('tournament_id', props.id)
    .order('created_at', { ascending: true })

  if (error) {
    throw error
  }

  entries.value = data || []
}

async function loadMatchesAndSets() {
  const { data: matchesData, error: matchesError } = await supabase
    .from('matches')
    .select(
      'id, tournament_id, round_number, match_number, side_a_entry_id, side_b_entry_id, winner_entry_id, status, next_match_id, next_slot',
    )
    .eq('tournament_id', props.id)
    .order('round_number', { ascending: true })
    .order('match_number', { ascending: true })

  if (matchesError) {
    throw matchesError
  }

  matches.value = matchesData || []

  if (!matches.value.length) {
    matchSets.value = []
    return
  }

  const ids = matches.value.map((match) => match.id)

  const { data: setsData, error: setsError } = await supabase
    .from('match_sets')
    .select('id, match_id, set_index, side_a_games, side_b_games')
    .in('match_id', ids)
    .order('set_index', { ascending: true })

  if (setsError) {
    throw setsError
  }

  matchSets.value = setsData || []
}

async function loadAdmins() {
  const { data, error } = await supabase
    .from('tournament_admins')
    .select('id, user_id, role, created_at')
    .eq('tournament_id', props.id)
    .order('created_at', { ascending: true })

  if (error) {
    throw error
  }

  admins.value = data || []
}

async function loadAll() {
  if (!auth.user) {
    return
  }

  loading.value = true
  errorText.value = ''

  try {
    await assertAccess()
    await loadTournament()
    await Promise.all([loadEntries(), loadMatchesAndSets(), loadAdmins()])
    setupRealtime()
  } catch (error) {
    errorText.value = error.message || t('errors.generic')
  } finally {
    loading.value = false
  }
}

function scheduleReload() {
  clearTimeout(reloadTimer)
  reloadTimer = setTimeout(() => {
    loadAll()
  }, 300)
}

function onMatchSetsChange(payload) {
  const matchId = payload.new?.match_id || payload.old?.match_id
  if (!matchId) {
    return
  }
  const belongsToTournament = matches.value.some((m) => m.id === matchId)
  if (belongsToTournament) {
    scheduleReload()
  }
}

function setupRealtime() {
  if (channel) {
    supabase.removeChannel(channel)
  }

  channel = supabase
    .channel(`admin-${props.id}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'tournaments', filter: `id=eq.${props.id}` }, scheduleReload)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'entries', filter: `tournament_id=eq.${props.id}` }, scheduleReload)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'matches', filter: `tournament_id=eq.${props.id}` }, scheduleReload)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'match_sets' }, onMatchSetsChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'tournament_admins', filter: `tournament_id=eq.${props.id}` }, scheduleReload)

  channel.subscribe()
}

async function updateEntryStatus(entryId, status) {
  actionLoading.value = true
  errorText.value = ''

  const { error } = await supabase.from('entries').update({ status }).eq('id', entryId)

  actionLoading.value = false

  if (error) {
    errorText.value = error.message
    return
  }

  await loadAll()
}

async function approveAllPending() {
  if (pendingEntries.value.length < 2) {
    return
  }
  if (!window.confirm(t('admin.approveAllConfirm'))) {
    return
  }

  actionLoading.value = true
  errorText.value = ''

  const { error } = await supabase
    .from('entries')
    .update({ status: 'approved' })
    .eq('tournament_id', props.id)
    .eq('status', 'pending')

  actionLoading.value = false

  if (error) {
    errorText.value = error.message
    return
  }

  await loadAll()
}

function resetAddEntryFeedback() {
  addEntryError.value = ''
  addEntrySuccess.value = ''
  clearTimeout(addEntrySuccessTimer)
  addEntrySuccessTimer = null
}

async function addEntryManually() {
  resetAddEntryFeedback()
  addEntryContactTouched.value = true

  const category = tournament.value?.category
  const m1 = addEntryForm.memberOne.trim()
  const m2 = addEntryForm.memberTwo.trim()

  if (!m1 || (category === 'doubles' && !m2)) {
    addEntryError.value = t('admin.addEntryInvalidMembers')
    return
  }

  if (addEntryForm.phoneOrEmail.trim() && !isValidContact(addEntryForm.phoneOrEmail)) {
    addEntryError.value = t('registrationForm.invalidContact')
    return
  }

  let phoneOrEmail = addEntryForm.phoneOrEmail.trim()
  if (!phoneOrEmail) {
    phoneOrEmail = `admin-entry-${crypto.randomUUID()}@local.tenis`
  }

  const customName = addEntryForm.displayName.trim()
  const displayName =
    customName || (category === 'singles' ? m1 : `${m1} / ${m2}`)

  actionLoading.value = true

  const { data: entryRow, error: insertError } = await supabase
    .from('entries')
    .insert({
      tournament_id: props.id,
      entry_type: category,
      display_name: displayName,
      phone_or_email: phoneOrEmail,
      status: addEntryForm.asPending ? 'pending' : 'approved',
    })
    .select('id')
    .single()

  if (insertError || !entryRow) {
    actionLoading.value = false
    const msg = insertError?.message || ''
    const dup =
      /duplicate key|unique constraint|already exists/i.test(msg) ||
      insertError?.code === '23505'
    addEntryError.value = dup ? t('admin.addEntryDuplicateContact') : msg || t('errors.generic')
    return
  }

  const memberRows = [{ entry_id: entryRow.id, member_name: m1, member_order: 1 }]
  if (category === 'doubles') {
    memberRows.push({ entry_id: entryRow.id, member_name: m2, member_order: 2 })
  }

  const { error: membersError } = await supabase.from('entry_members').insert(memberRows)

  if (membersError) {
    await supabase.from('entries').delete().eq('id', entryRow.id)
    actionLoading.value = false
    addEntryError.value = membersError.message || t('errors.generic')
    return
  }

  actionLoading.value = false
  addEntryForm.memberOne = ''
  addEntryForm.memberTwo = ''
  addEntryForm.displayName = ''
  addEntryForm.phoneOrEmail = ''
  addEntryForm.asPending = false
  addEntryContactTouched.value = false

  addEntrySuccess.value = t('admin.addEntrySuccess')
  addEntrySuccessTimer = setTimeout(() => {
    addEntrySuccess.value = ''
    addEntrySuccessTimer = null
  }, 5000)

  await loadEntries()
}

async function saveTournamentSettings() {
  actionLoading.value = true
  errorText.value = ''

  const categoryChanged = settingsForm.category !== settingsBaseline.value.category
  const formatChanged = settingsForm.set_format !== settingsBaseline.value.set_format

  const { error } = await supabase
    .from('tournaments')
    .update({
      status: statusValue.value,
      is_public: tournament.value.is_public,
      name: settingsForm.name,
      slug: settingsForm.slug,
      description: settingsForm.description || null,
      category: settingsForm.category,
      set_format: settingsForm.set_format,
    })
    .eq('id', props.id)

  if (error) {
    actionLoading.value = false
    errorText.value = error.message
    return
  }

  if (categoryChanged && hasBracket.value) {
    const matchIds = matches.value.map((m) => m.id)
    if (matchIds.length) {
      await supabase.from('match_sets').delete().in('match_id', matchIds)
      await supabase.from('matches').delete().eq('tournament_id', props.id)
    }
  } else if (formatChanged && hasBracket.value) {
    const matchIds = matches.value.map((m) => m.id)
    if (matchIds.length) {
      await supabase.from('match_sets').delete().in('match_id', matchIds)
      await supabase
        .from('matches')
        .update({ winner_entry_id: null, status: 'ready' })
        .eq('tournament_id', props.id)
        .neq('status', 'pending')
    }
  }

  actionLoading.value = false
  await loadAll()
}

const hasBracket = computed(() => matches.value.length > 0)

async function generateBracket() {
  const fn = hasBracket.value ? 'rebuild_bracket' : 'generate_bracket'

  if (hasBracket.value && !window.confirm(t('admin.rebuildConfirm'))) {
    return
  }

  actionLoading.value = true
  errorText.value = ''

  const { error } = await supabase.rpc(fn, {
    p_tournament_id: props.id,
    p_mode: drawMode.value,
    p_manual_order: null,
  })

  actionLoading.value = false

  if (error) {
    errorText.value = error.message
    return
  }

  await loadAll()
}

async function swapBracketSlots(payload) {
  if (!payload?.fromMatchId || !payload?.toMatchId || !payload?.fromSide || !payload?.toSide) {
    return
  }

  actionLoading.value = true
  errorText.value = ''

  const { error } = await supabase.rpc('swap_bracket_slots', {
    p_tournament_id: props.id,
    p_from_match_id: payload.fromMatchId,
    p_from_slot: payload.fromSide === 'a' ? 'A' : 'B',
    p_to_match_id: payload.toMatchId,
    p_to_slot: payload.toSide === 'a' ? 'A' : 'B',
  })

  actionLoading.value = false

  if (error) {
    errorText.value = error.message
    return
  }

  await loadAll()
}

async function addAdmin() {
  if (!addAdminForm.userId) {
    return
  }

  actionLoading.value = true
  errorText.value = ''

  const { error } = await supabase.from('tournament_admins').insert({
    tournament_id: props.id,
    user_id: addAdminForm.userId,
    role: addAdminForm.role,
  })

  actionLoading.value = false

  if (error) {
    errorText.value = error.message
    return
  }

  addAdminForm.userId = ''
  addAdminForm.role = 'editor'
  await loadAll()
}

async function onCopyShareLink() {
  if (!tournament.value?.slug) {
    return
  }
  try {
    await copyTournamentLink(tournament.value.slug)
  } catch {
    /* still show feedback */
  }
  copyFeedback.value = true
  setTimeout(() => {
    copyFeedback.value = false
  }, 2000)
}

async function deleteTournament() {
  if (!window.confirm(t('admin.deleteTournamentConfirm'))) {
    return
  }

  actionLoading.value = true
  errorText.value = ''

  if (channel) {
    supabase.removeChannel(channel)
    channel = null
  }

  const { error } = await supabase.from('tournaments').delete().eq('id', props.id)

  actionLoading.value = false

  if (error) {
    errorText.value = error.message
    return
  }

  await router.replace({ name: 'admin-tournaments' })
}

function statusBadgeClass(status) {
  if (status === 'completed') {
    return 'badge--success'
  }
  if (status === 'in_progress' || status === 'registration_open') {
    return 'badge--warn'
  }
  return 'badge--neutral'
}

const TABS = ['entries', 'bracket', 'scores', 'settings']

function readHashTab() {
  const h = window.location.hash.replace('#', '')
  return TABS.includes(h) ? h : 'entries'
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

onMounted(async () => {
  window.addEventListener('hashchange', onHashChange)
  await auth.init()
  await loadAll()
})

onBeforeUnmount(() => {
  window.removeEventListener('hashchange', onHashChange)
  clearTimeout(reloadTimer)
  clearTimeout(addEntrySuccessTimer)
  if (channel) {
    supabase.removeChannel(channel)
  }
})
</script>

<template>
  <div class="stack">
    <RouterLink class="admin-back-link" :to="{ name: 'admin-tournaments' }">
      {{ t('admin.backToList') }}
    </RouterLink>

    <section v-if="loading" class="card">
      <p class="muted">{{ t('actions.loading') }}</p>
    </section>

    <section v-else-if="errorText && !tournament" class="card">
      <p class="error-text">{{ errorText }}</p>
    </section>

    <template v-else-if="tournament && !loading">
      <div v-if="errorText" class="alert alert--error admin-page-alert" role="alert">
        {{ errorText }}
      </div>

      <section class="card card--elevated admin-tournament-overview stack stack--sm" aria-labelledby="adm-tournament-title">
        <div class="admin-tournament-overview__top">
          <div class="admin-tournament-overview__title-block stack stack--sm">
            <h1 id="adm-tournament-title" class="page-title" style="margin: 0">{{ tournament.name }}</h1>
            <div class="badge-row">
              <span class="badge" :class="statusBadgeClass(tournament.status)">
                {{ t(`tournament.${tournament.status}`) }}
              </span>
              <span class="badge badge--neutral">{{ t(`tournament.${tournament.category}`) }}</span>
              <span class="badge badge--neutral">{{ t(`format.${tournament.set_format}`) }}</span>
            </div>
            <p v-if="tournament.description" class="muted">{{ tournament.description }}</p>
          </div>
          <div class="admin-tournament-overview__actions">
            <button
              v-if="showPublicShareActions"
              class="btn btn--ghost btn--sm"
              type="button"
              @click="onCopyShareLink"
            >
              {{ copyFeedback ? t('share.copied') : t('share.copyLink') }}
            </button>

            <span
              v-if="showStartButton"
              class="tooltip-wrapper"
              :data-tooltip="!canStartTournament ? t('admin.startTournamentTooltip') : undefined"
            >
              <button
                class="btn btn--primary btn--sm"
                type="button"
                :disabled="!canStartTournament || actionLoading"
                @click="startTournament"
              >
                {{ t('admin.startTournament') }}
              </button>
            </span>

            <button
              v-if="isTournamentActive"
              class="btn btn--ghost btn--sm"
              type="button"
              :disabled="actionLoading"
              @click="stopTournament"
            >
              {{ t('admin.stopTournament') }}
            </button>
          </div>
        </div>

        <p v-if="showPublicShareActions" class="muted admin-share-hint">{{ t('share.hint') }}</p>
      </section>

      <div role="tablist" class="tab-group" @keydown="onTabKeydown">
        <button
          id="tab-entries"
          role="tab"
          class="tab"
          :class="{ 'tab--active': activeTab === 'entries' }"
          :aria-selected="activeTab === 'entries'"
          :tabindex="activeTab === 'entries' ? 0 : -1"
          aria-controls="panel-entries"
          @click="setTab('entries')"
        >
          {{ t('admin.tabEntries') }}
          <span v-if="pendingEntries.length" class="tab__badge">{{ pendingEntries.length }}</span>
        </button>
        <button
          id="tab-bracket"
          role="tab"
          class="tab"
          :class="{ 'tab--active': activeTab === 'bracket' }"
          :aria-selected="activeTab === 'bracket'"
          :tabindex="activeTab === 'bracket' ? 0 : -1"
          aria-controls="panel-bracket"
          @click="setTab('bracket')"
        >
          {{ t('admin.tabBracket') }}
        </button>
        <button
          id="tab-scores"
          role="tab"
          class="tab"
          :class="{ 'tab--active': activeTab === 'scores' }"
          :aria-selected="activeTab === 'scores'"
          :tabindex="activeTab === 'scores' ? 0 : -1"
          aria-controls="panel-scores"
          @click="setTab('scores')"
        >
          {{ t('admin.tabScores') }}
        </button>
        <button
          id="tab-settings"
          role="tab"
          class="tab"
          :class="{ 'tab--active': activeTab === 'settings' }"
          :aria-selected="activeTab === 'settings'"
          :tabindex="activeTab === 'settings' ? 0 : -1"
          aria-controls="panel-settings"
          @click="setTab('settings')"
        >
          {{ t('admin.tabSettings') }}
        </button>
      </div>

      <div
        id="panel-entries"
        role="tabpanel"
        aria-labelledby="tab-entries"
        class="tab-panel"
        :class="{ 'tab-panel--active': activeTab === 'entries' }"
      >
        <section class="card stack stack--sm">
          <h2 class="section-title">{{ t('tournament.registration') }} — {{ t('admin.entriesSection') }}</h2>

          <div class="admin-add-entry" :class="{ 'admin-add-entry--open': addEntryAccordionOpen }">
            <h3 class="admin-add-entry__heading">
              <button
                id="adm-add-entry-trigger"
                type="button"
                class="admin-add-entry__trigger"
                :aria-expanded="addEntryAccordionOpen"
                aria-controls="adm-add-entry-panel"
                @click="addEntryAccordionOpen = !addEntryAccordionOpen"
              >
                <span class="admin-add-entry__trigger-text">{{ t('admin.addEntryTitle') }}</span>
                <svg
                  class="admin-add-entry__chevron"
                  width="20"
                  height="20"
                  viewBox="0 0 20 20"
                  fill="none"
                  aria-hidden="true"
                >
                  <path
                    d="M5 7.5 10 12.5 15 7.5"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
              </button>
            </h3>

            <div
              v-show="addEntryAccordionOpen"
              id="adm-add-entry-panel"
              class="admin-add-entry__panel stack stack--sm"
              role="region"
              aria-labelledby="adm-add-entry-trigger"
            >
              <p class="muted admin-add-entry__hint">{{ t('admin.addEntryHint') }}</p>

              <form class="stack stack--sm" @submit.prevent="addEntryManually">
                <div class="grid-2 grid-2--admin">
                  <div class="form-field">
                    <label for="adm-add-m1">{{ t('registrationForm.memberOne') }}</label>
                    <input
                      id="adm-add-m1"
                      v-model="addEntryForm.memberOne"
                      class="input"
                      type="text"
                      autocomplete="name"
                      :disabled="actionLoading"
                      required
                    />
                  </div>
                  <div v-if="tournament.category === 'doubles'" class="form-field">
                    <label for="adm-add-m2">{{ t('registrationForm.memberTwo') }}</label>
                    <input
                      id="adm-add-m2"
                      v-model="addEntryForm.memberTwo"
                      class="input"
                      type="text"
                      autocomplete="name"
                      :disabled="actionLoading"
                      required
                    />
                  </div>
                  <div class="form-field">
                    <label for="adm-add-display">{{ t('registrationForm.displayName') }}</label>
                    <input
                      id="adm-add-display"
                      v-model="addEntryForm.displayName"
                      class="input"
                      type="text"
                      :disabled="actionLoading"
                    />
                  </div>
                  <div class="form-field">
                    <label for="adm-add-contact">{{ t('admin.addEntryContactOptional') }}</label>
                    <input
                      id="adm-add-contact"
                      v-model="addEntryForm.phoneOrEmail"
                      class="input"
                      type="text"
                      inputmode="email"
                      autocomplete="off"
                      :class="{ 'input--error': addEntryContactInvalid }"
                      :disabled="actionLoading"
                      @blur="addEntryContactTouched = true"
                    />
                  </div>
                </div>

                <label class="checkbox-row" for="adm-add-pending">
                  <input id="adm-add-pending" v-model="addEntryForm.asPending" type="checkbox" :disabled="actionLoading" />
                  {{ t('admin.addEntryAsPending') }}
                </label>

                <div class="inline-actions">
                  <button class="btn btn--primary btn--sm" type="submit" :disabled="actionLoading">
                    {{ t('admin.addEntrySubmit') }}
                  </button>
                </div>

                <div v-if="addEntrySuccess" class="alert alert--success" role="status">{{ addEntrySuccess }}</div>
                <div v-if="addEntryError" class="alert alert--error" role="alert">{{ addEntryError }}</div>
              </form>
            </div>
          </div>

          <div class="divider" />

          <div>
            <div class="admin-list-header" style="margin-bottom: var(--space-3)">
              <h3 class="section-title" style="font-size: 1rem; margin: 0">
                {{ t('admin.pendingEntries') }}
                <span class="badge badge--warn">{{ pendingEntries.length }}</span>
              </h3>
              <button
                v-if="pendingEntries.length > 1"
                class="btn btn--primary btn--sm"
                type="button"
                :disabled="actionLoading"
                @click="approveAllPending"
              >
                {{ t('admin.approveAll') }}
              </button>
            </div>
            <div v-if="pendingEntries.length" class="stack stack--sm">
              <div v-for="entry in pendingEntries" :key="entry.id" class="participant-item">
                <strong>{{ entry.display_name }}</strong>
                <div class="inline-actions">
                  <button
                    class="btn btn--primary btn--sm"
                    type="button"
                    :disabled="actionLoading"
                    @click="updateEntryStatus(entry.id, 'approved')"
                  >
                    {{ t('admin.approve') }}
                  </button>
                  <button
                    class="btn btn--danger btn--sm"
                    type="button"
                    :disabled="actionLoading"
                    @click="updateEntryStatus(entry.id, 'rejected')"
                  >
                    {{ t('admin.reject') }}
                  </button>
                </div>
              </div>
            </div>
            <p v-else class="muted">{{ t('admin.noPending') }}</p>
          </div>

          <div class="divider" />

          <div>
            <h3 class="section-title" style="font-size: 1rem">
              {{ t('admin.approvedList') }}
              <span class="badge badge--success">{{ approvedEntries.length }}</span>
            </h3>
            <div v-if="approvedEntries.length" class="stack stack--sm">
              <div v-for="entry in approvedEntries" :key="entry.id" class="participant-item">
                <strong>{{ entry.display_name }}</strong>
                <button class="btn btn--ghost btn--sm" type="button" :disabled="actionLoading" @click="updateEntryStatus(entry.id, 'pending')">
                  {{ t('admin.reopen') }}
                </button>
              </div>
            </div>
            <p v-else class="muted">{{ t('admin.noApproved') }}</p>
          </div>
        </section>
      </div>

      <div
        id="panel-bracket"
        role="tabpanel"
        aria-labelledby="tab-bracket"
        class="tab-panel"
        :class="{ 'tab-panel--active': activeTab === 'bracket' }"
      >
        <section class="card stack stack--sm">
          <h2 class="section-title">{{ t('tournament.bracket') }} — {{ t('admin.drawSection') }}</h2>

          <div class="form-field" style="max-width: 280px">
            <label for="adm-draw">{{ t('admin.drawMode') }}</label>
            <select id="adm-draw" v-model="drawMode" class="input">
              <option value="auto-random">{{ t('admin.drawRandom') }}</option>
              <option value="manual">{{ t('admin.drawManual') }}</option>
            </select>
          </div>

          <button
            class="btn btn--sm"
            :class="hasBracket ? 'btn--danger' : 'btn--primary'"
            type="button"
            :disabled="actionLoading"
            @click="generateBracket"
          >
            {{ hasBracket
              ? t('admin.rebuild')
              : drawMode === 'manual' ? t('admin.generateManual') : t('admin.generateRandom')
            }}
          </button>

          <p v-if="drawMode === 'manual'" class="muted">{{ t('admin.manualBracketDnDHint') }}</p>
        </section>

        <section class="card stack stack--sm" style="margin-top: var(--space-4)">
          <BracketBoard
            :matches="matches"
            :sets-by-match="setsByMatch"
            :entries-map="entriesMap"
            :editable-slots="drawMode === 'manual' && !actionLoading"
            @swap-slots="swapBracketSlots"
          />
        </section>
      </div>

      <div
        id="panel-scores"
        role="tabpanel"
        aria-labelledby="tab-scores"
        class="tab-panel"
        :class="{ 'tab-panel--active': activeTab === 'scores' }"
      >
        <ScoreEditor
          :matches="matches"
          :sets-by-match="setsByMatch"
          :entries-map="entriesMap"
          :set-format="tournament.set_format"
          @saved="loadAll"
        />
      </div>

      <div
        id="panel-settings"
        role="tabpanel"
        aria-labelledby="tab-settings"
        class="tab-panel"
        :class="{ 'tab-panel--active': activeTab === 'settings' }"
      >
        <section class="card admin-settings-card stack stack--sm" aria-labelledby="adm-settings-heading">
          <div>
            <h2 id="adm-settings-heading" class="section-title" style="margin-bottom: var(--space-2)">
              {{ t('admin.tournamentSettings') }}
            </h2>
            <p class="muted admin-settings-card__hint">{{ t('admin.tournamentSettingsHint') }}</p>
          </div>

          <div class="form-field">
            <label for="adm-name">{{ t('admin.name') }}</label>
            <input
              id="adm-name"
              v-model="settingsForm.name"
              class="input"
              type="text"
              required
              :disabled="isSettingsDropdownDisabled"
            />
          </div>

          <div class="form-field">
            <label for="adm-slug">{{ t('admin.slug') }}</label>
            <input
              id="adm-slug"
              v-model="settingsForm.slug"
              class="input"
              type="text"
              :disabled="isSettingsDropdownDisabled"
            />
          </div>

          <div class="form-field">
            <label for="adm-desc">{{ t('admin.description') }}</label>
            <textarea
              id="adm-desc"
              v-model="settingsForm.description"
              class="input"
              rows="3"
              :disabled="isSettingsDropdownDisabled"
            />
          </div>

          <div class="grid-2">
            <div class="form-field">
              <label for="adm-cat">{{ t('admin.category') }}</label>
              <select id="adm-cat" v-model="settingsForm.category" class="input" :disabled="isSettingsDropdownDisabled">
                <option value="singles">{{ t('tournament.singles') }}</option>
                <option value="doubles">{{ t('tournament.doubles') }}</option>
              </select>
            </div>

            <div class="form-field">
              <label for="adm-format">{{ t('admin.setFormat') }}</label>
              <select id="adm-format" v-model="settingsForm.set_format" class="input" :disabled="isSettingsDropdownDisabled">
                <option value="best_of_3">{{ t('format.best_of_3') }}</option>
                <option value="best_of_5">{{ t('format.best_of_5') }}</option>
              </select>
            </div>
          </div>

          <div class="admin-settings-fields">
            <div class="form-field admin-settings-fields__status">
              <label for="adm-status">{{ t('admin.status') }}</label>
              <select id="adm-status" v-model="statusValue" class="input">
                <option value="draft" :disabled="isSettingsDropdownDisabled">{{ t('tournament.draft') }}</option>
                <option value="registration_open" :disabled="isSettingsDropdownDisabled">{{ t('tournament.registration_open') }}</option>
                <option value="registration_closed" :disabled="isSettingsDropdownDisabled">{{ t('tournament.registration_closed') }}</option>
                <option v-if="isTournamentActive" value="in_progress" disabled>{{ t('tournament.in_progress') }}</option>
                <option v-if="isTournamentFinished" value="completed" disabled>{{ t('tournament.completed') }}</option>
              </select>
            </div>

            <label class="checkbox-row admin-settings-fields__public" for="adm-public">
              <input id="adm-public" v-model="tournament.is_public" type="checkbox" :disabled="isSettingsDropdownDisabled" />
              {{ t('admin.isPublic') }}
            </label>
          </div>

          <footer class="admin-settings-card__footer">
            <button
              class="btn btn--primary"
              type="button"
              :disabled="actionLoading || !hasTournamentSettingsChanges"
              @click="saveTournamentSettings"
            >
              {{ t('admin.saveStatus') }}
            </button>
          </footer>
        </section>

        <section class="card stack stack--sm" style="margin-top: var(--space-4)">
          <h2 class="section-title">{{ t('admin.admins') }}</h2>
          <div class="stack stack--sm">
            <div v-for="admin in admins" :key="admin.id" class="participant-item">
              <code style="font-size: 0.8125rem; word-break: break-all">{{ admin.user_id }}</code>
              <span class="badge badge--neutral">{{ t(`admin.${admin.role}`) }}</span>
            </div>
          </div>

          <div class="grid-2" style="margin-top: var(--space-3)">
            <div class="form-field">
              <label for="adm-uid">{{ t('admin.userId') }}</label>
              <input id="adm-uid" v-model="addAdminForm.userId" class="input" type="text" />
            </div>
            <div class="form-field">
              <label for="adm-role">{{ t('admin.role') }}</label>
              <select id="adm-role" v-model="addAdminForm.role" class="input">
                <option value="owner">{{ t('admin.owner') }}</option>
                <option value="editor">{{ t('admin.editor') }}</option>
              </select>
            </div>
          </div>
          <button class="btn btn--primary btn--sm" type="button" :disabled="actionLoading" @click="addAdmin">
            {{ t('admin.add') }}
          </button>
        </section>

        <section class="admin-delete-zone">
          <button
            v-if="isTournamentActive"
            class="btn btn--danger btn--sm"
            type="button"
            :disabled="actionLoading"
            @click="finishTournament"
          >
            {{ t('admin.finishTournament') }}
          </button>
          <button
            class="btn btn--danger btn--sm"
            type="button"
            :disabled="actionLoading"
            @click="deleteTournament"
          >
            {{ t('admin.deleteTournament') }}
          </button>
        </section>
      </div>
    </template>
  </div>
</template>
