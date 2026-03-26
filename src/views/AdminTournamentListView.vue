<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'

import { supabase } from '../lib/supabase'
import { copyTournamentLink } from '../lib/shareLink'
import { useAuthStore } from '../stores/auth'

const { t } = useI18n()
const router = useRouter()
const auth = useAuthStore()

const loading = ref(false)
const loadError = ref('')
const copySlug = ref('')
const copyFeedback = ref(false)

const tournaments = ref([])
const statusFilter = ref('active')

const filteredTournaments = computed(() => {
  const list = tournaments.value
  if (statusFilter.value === 'all') {
    return list
  }
  if (statusFilter.value === 'completed') {
    return list.filter((t) => t.status === 'completed')
  }
  return list.filter((t) => t.status !== 'completed')
})

async function loadTournaments() {
  if (!auth.user) {
    tournaments.value = []
    return
  }

  loading.value = true
  loadError.value = ''

  const { data, error } = await supabase
    .from('tournament_admins')
    .select(
      `
      tournament_id,
      tournaments (
        id,
        name,
        slug,
        category,
        status,
        set_format,
        doubles_pairing_mode,
        created_at
      )
    `,
    )
    .eq('user_id', auth.user.id)

  loading.value = false

  if (error) {
    loadError.value = error.message
    tournaments.value = []
    return
  }

  const rows = data || []
  const list = rows.map((row) => row.tournaments).filter((t) => t != null)
  list.sort((a, b) => new Date(b.created_at) - new Date(a.created_at))
  tournaments.value = list
}

function formatDate(iso) {
  if (!iso) {
    return '—'
  }
  try {
    return new Date(iso).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    })
  } catch {
    return iso
  }
}

function hasPublicShareLink(status) {
  return status === 'registration_open' || status === 'registration_closed'
}

async function onCopyLink(slug, e) {
  e?.stopPropagation?.()
  try {
    await copyTournamentLink(slug)
    copySlug.value = slug
    copyFeedback.value = true
    setTimeout(() => {
      copyFeedback.value = false
    }, 2000)
  } catch {
    copySlug.value = slug
    copyFeedback.value = true
    setTimeout(() => {
      copyFeedback.value = false
    }, 2000)
  }
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

watch(
  () => auth.user?.id,
  async (id) => {
    if (id) {
      await loadTournaments()
    } else {
      tournaments.value = []
    }
  },
)

onMounted(async () => {
  await auth.init()
  await loadTournaments()
})
</script>

<template>
  <div class="stack">
    <div class="admin-list-header">
      <h1 class="page-title" style="margin: 0">{{ t('admin.tournamentsListTitle') }}</h1>
      <div class="admin-list-header__actions">
        <!-- <button class="btn btn--ghost btn--sm" type="button" @click="loadTournaments">
          {{ t('actions.refresh') }}
        </button> -->
        <RouterLink class="btn btn--primary btn--sm" :to="{ name: 'admin-tournament-new' }">
          {{ t('admin.createTournament') }}
        </RouterLink>
      </div>
    </div>
    <p class="muted">{{ t('admin.tournamentsListHint') }}</p>

    <div class="filter-segment" role="group" :aria-label="t('admin.filterLabel')">
      <button
        type="button"
        class="filter-segment__btn"
        :class="{ 'filter-segment__btn--active': statusFilter === 'active' }"
        @click="statusFilter = 'active'"
      >
        {{ t('admin.filterActive') }}
      </button>
      <button
        type="button"
        class="filter-segment__btn"
        :class="{ 'filter-segment__btn--active': statusFilter === 'completed' }"
        @click="statusFilter = 'completed'"
      >
        {{ t('admin.filterCompleted') }}
      </button>
      <button
        type="button"
        class="filter-segment__btn"
        :class="{ 'filter-segment__btn--active': statusFilter === 'all' }"
        @click="statusFilter = 'all'"
      >
        {{ t('admin.filterAll') }}
      </button>
    </div>

    <p v-if="loading" class="muted">{{ t('actions.loading') }}</p>
    <p v-if="loadError" class="error-text">{{ loadError }}</p>

    <div v-if="!loading && filteredTournaments.length" class="stack stack--sm">
      <article
        v-for="item in filteredTournaments"
        :key="item.id"
        class="tournament-row tournament-row--clickable"
        tabindex="0"
        role="link"
        @click="router.push({ name: 'admin-tournament', params: { id: item.id } })"
        @keydown.enter="router.push({ name: 'admin-tournament', params: { id: item.id } })"
      >
        <div class="stack stack--sm" style="flex: 1; min-width: 0">
          <h2 class="tournament-row__title">{{ item.name }}</h2>
          <div class="badge-row">
            <span class="badge" :class="statusBadgeClass(item.status)">
              {{ t(`tournament.${item.status}`) }}
            </span>
            <span class="badge badge--neutral">{{ t(`tournament.${item.category}`) }}</span>
            <span class="muted" style="font-size: 0.8125rem">{{ formatDate(item.created_at) }}</span>
          </div>
        </div>
        <div class="tournament-row__actions">
          <button
            v-if="hasPublicShareLink(item.status)"
            class="btn btn--ghost btn--sm"
            type="button"
            @click.stop="onCopyLink(item.slug, $event)"
          >
            {{ copyFeedback && copySlug === item.slug ? t('share.copied') : t('share.copyLink') }}
          </button>
        </div>
      </article>
    </div>

    <p v-else-if="!loading && !loadError && tournaments.length && !filteredTournaments.length" class="muted">
      {{ t('admin.noTournamentsInFilter') }}
    </p>
    <p v-else-if="!loading && !loadError && !tournaments.length" class="muted">
      {{ t('admin.noTournaments') }}
    </p>
  </div>
</template>
