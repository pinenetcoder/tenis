<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'

import BracketBoard from '../components/BracketBoard.vue'
import RegistrationForm from '../components/RegistrationForm.vue'
import { supabase } from '../lib/supabase'

const props = defineProps({
  slug: {
    type: String,
    required: true,
  },
})

const { t } = useI18n()

const tournament = ref(null)
const entries = ref([])
const matches = ref([])
const matchSets = ref([])

const loading = ref(false)
const errorText = ref('')
const activeTab = ref('registration')

let channel = null
let reloadTimer = null

const entriesMap = computed(() => {
  return entries.value.reduce((acc, entry) => {
    acc[entry.id] = entry
    return acc
  }, {})
})

const approvedEntries = computed(() => entries.value.filter((entry) => entry.status === 'approved'))
/** Shown only after organizer approval; register_entry creates `pending` rows in `entries`. */
const pendingEntries = computed(() => entries.value.filter((entry) => entry.status === 'pending'))

const setsByMatch = computed(() => {
  return matchSets.value.reduce((acc, set) => {
    if (!acc[set.match_id]) {
      acc[set.match_id] = []
    }
    acc[set.match_id].push(set)
    return acc
  }, {})
})

function statusBadgeClass(status) {
  if (status === 'completed') {
    return 'badge--success'
  }
  if (status === 'in_progress' || status === 'registration_open') {
    return 'badge--warn'
  }
  if (status === 'registration_closed') {
    return 'badge--danger'
  }
  return 'badge--neutral'
}

function syncDefaultTab() {
  const s = tournament.value?.status
  if (s === 'registration_open') {
    activeTab.value = 'registration'
  } else {
    activeTab.value = 'bracket'
  }
}

async function loadEntriesAndMatches(tournamentId) {
  const [{ data: entriesData, error: entriesError }, { data: matchesData, error: matchesError }] = await Promise.all([
    supabase
      .from('entries')
      .select('id, display_name, entry_type, status, created_at')
      .eq('tournament_id', tournamentId)
      .order('created_at', { ascending: true }),
    supabase
      .from('matches')
      .select('id, tournament_id, round_number, match_number, side_a_entry_id, side_b_entry_id, winner_entry_id, status, next_match_id, next_slot')
      .eq('tournament_id', tournamentId)
      .order('round_number', { ascending: true })
      .order('match_number', { ascending: true }),
  ])

  if (entriesError) {
    throw entriesError
  }

  if (matchesError) {
    throw matchesError
  }

  const entryRows = entriesData || []
  const ids = entryRows.map((e) => e.id)

  if (ids.length) {
    const { data: members } = await supabase
      .from('entry_members')
      .select('entry_id, member_name, member_order')
      .in('entry_id', ids)
      .order('member_order', { ascending: true })

    const byEntry = {}
    for (const m of members || []) {
      ;(byEntry[m.entry_id] ??= []).push(m)
    }
    for (const entry of entryRows) {
      entry.entry_members = byEntry[entry.id] || []
    }
  }

  entries.value = entryRows
  matches.value = matchesData || []

  if (!matches.value.length) {
    matchSets.value = []
    return
  }

  const matchIds = matches.value.map((match) => match.id)

  const { data: setsData, error: setsError } = await supabase
    .from('match_sets')
    .select('id, match_id, set_index, side_a_games, side_b_games')
    .in('match_id', matchIds)
    .order('set_index', { ascending: true })

  if (setsError) {
    throw setsError
  }

  matchSets.value = setsData || []
}

async function loadAll() {
  loading.value = true
  errorText.value = ''

  try {
    const { data, error } = await supabase
      .from('tournaments')
      .select('id, name, slug, description, category, status, set_format, doubles_pairing_mode')
      .eq('slug', props.slug)
      .maybeSingle()

    if (error) {
      throw error
    }

    if (!data) {
      tournament.value = null
      entries.value = []
      matches.value = []
      matchSets.value = []
      errorText.value = t('errors.notFound')
      loading.value = false
      return
    }

    tournament.value = data
    await loadEntriesAndMatches(data.id)
    syncDefaultTab()
    setupRealtime(data.id)
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

function setupRealtime(tournamentId) {
  if (channel) {
    supabase.removeChannel(channel)
  }

  channel = supabase
    .channel(`public-${tournamentId}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'tournaments', filter: `id=eq.${tournamentId}` }, scheduleReload)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'entries', filter: `tournament_id=eq.${tournamentId}` }, scheduleReload)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'matches', filter: `tournament_id=eq.${tournamentId}` }, scheduleReload)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'match_sets' }, onMatchSetsChange)

  channel.subscribe()
}

onMounted(loadAll)

watch(
  () => props.slug,
  () => {
    loadAll()
  },
)

watch(
  () => tournament.value?.status,
  () => {
    syncDefaultTab()
  },
)

onBeforeUnmount(() => {
  clearTimeout(reloadTimer)
  if (channel) {
    supabase.removeChannel(channel)
  }
})
</script>

<template>
  <div class="stack">
    <section v-if="loading" class="card">
      <p class="muted">{{ t('actions.loading') }}</p>
    </section>

    <section v-else-if="errorText && !tournament" class="card">
      <p class="error-text">{{ errorText }}</p>
    </section>

    <template v-else-if="tournament">
      <section class="card card--elevated stack stack--sm">
        <h1 class="page-title">{{ tournament.name }}</h1>
        <p v-if="tournament.description">{{ tournament.description }}</p>
        <div class="badge-row">
          <span class="badge" :class="statusBadgeClass(tournament.status)">
            {{ t(`tournament.${tournament.status}`) }}
          </span>
          <span class="badge badge--neutral">{{ t(`tournament.${tournament.category}`) }}</span>
          <span class="badge badge--neutral">{{ t(`format.${tournament.set_format}`) }}</span>
        </div>
      </section>

      <div class="tab-group" role="tablist" :aria-label="t('tournament.tabsLabel')">
        <button
          type="button"
          class="tab"
          :class="{ 'tab--active': activeTab === 'registration' }"
          role="tab"
          :aria-selected="activeTab === 'registration'"
          @click="activeTab = 'registration'"
        >
          {{ t('tournament.tabRegistration') }}
        </button>
        <button
          type="button"
          class="tab"
          :class="{ 'tab--active': activeTab === 'bracket' }"
          role="tab"
          :aria-selected="activeTab === 'bracket'"
          @click="activeTab = 'bracket'"
        >
          {{ t('tournament.tabBracket') }}
        </button>
      </div>

      <div v-show="activeTab === 'registration'" role="tabpanel">
        <div class="grid-2">
          <div class="stack stack--sm">
            <RegistrationForm
              v-if="tournament.status === 'registration_open'"
              :tournament="tournament"
              @submitted="loadAll"
            />
            <div v-else class="card">
              <h3 class="section-title">{{ t('tournament.registration') }}</h3>
              <p class="muted">{{ t('tournament.registrationClosed') }}</p>
            </div>
          </div>

          <div class="card stack stack--sm">
            <h3 class="section-title">{{ t('tournament.participants') }} ({{ approvedEntries.length }})</h3>
            <div v-if="approvedEntries.length" class="participant-list">
              <div v-for="entry in approvedEntries" :key="entry.id" class="participant-item">
                <strong>{{ entry.display_name }}</strong>
                <span class="badge badge--success">{{ t('tournament.approved') }}</span>
              </div>
            </div>
            <p v-else-if="pendingEntries.length" class="alert alert--info">
              {{ t('tournament.pendingParticipantsHint', { count: pendingEntries.length }) }}
            </p>
            <p v-else class="muted">{{ t('bracket.noParticipants') }}</p>
          </div>
        </div>
      </div>

      <div v-show="activeTab === 'bracket'" role="tabpanel" class="card">
        <h3 class="section-title">{{ t('tournament.bracket') }}</h3>
        <BracketBoard :matches="matches" :sets-by-match="setsByMatch" :entries-map="entriesMap" />
      </div>
    </template>
  </div>
</template>
