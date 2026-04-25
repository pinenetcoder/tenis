<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '../stores/auth'
import { supabase } from '../lib/supabase'

const { t } = useI18n()
const auth = useAuthStore()

const clubs = ref([])
const loading = ref(true)
const filter = ref('pending')
const rejectingId = ref(null)
const rejectReason = ref('')
const actionLoading = ref(null)
const errorText = ref('')

const filteredClubs = computed(() => {
  if (filter.value === 'all') return clubs.value
  return clubs.value.filter(c => c.status === filter.value)
})

const counts = computed(() => {
  const all = clubs.value
  return {
    pending: all.filter(c => c.status === 'pending').length,
    active: all.filter(c => c.status === 'active').length,
    rejected: all.filter(c => c.status === 'rejected').length,
    all: all.length,
  }
})

onMounted(async () => {
  await loadClubs()
})

async function loadClubs() {
  loading.value = true
  errorText.value = ''
  const { data, error } = await supabase.rpc('list_organizations_for_review')
  if (error) {
    errorText.value = error.message
    console.error('list_organizations_for_review error:', error)
  } else {
    clubs.value = data || []
  }
  loading.value = false
}

async function approveClub(id) {
  actionLoading.value = id
  errorText.value = ''
  const { error } = await supabase.rpc('approve_organization', { p_org_id: id })
  if (error) {
    errorText.value = error.message
  }
  if (!error) {
    await loadClubs()
  }
  actionLoading.value = null
}

function startReject(id) {
  rejectingId.value = id
  rejectReason.value = ''
}

function cancelReject() {
  rejectingId.value = null
  rejectReason.value = ''
}

async function confirmReject() {
  if (!rejectingId.value) return
  actionLoading.value = rejectingId.value
  errorText.value = ''
  const { error } = await supabase.rpc('reject_organization', {
    p_org_id: rejectingId.value,
    p_reason: rejectReason.value.trim() || null,
  })
  if (error) {
    errorText.value = error.message
  }
  if (!error) {
    rejectingId.value = null
    rejectReason.value = ''
    await loadClubs()
  }
  actionLoading.value = null
}

function formatDate(dateStr) {
  if (!dateStr) return '—'
  return new Date(dateStr).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}
</script>

<template>
  <div class="sa-dashboard">
    <div class="sa-header">
      <h1 class="sa-title">{{ t('superAdmin.title') }}</h1>
      <p class="sa-subtitle">{{ t('superAdmin.subtitle') }}</p>
    </div>

    <!-- Filter tabs -->
    <div class="tab-group sa-tabs">
      <button
        v-for="f in ['pending', 'active', 'rejected', 'all']"
        :key="f"
        class="tab"
        :class="{ 'tab--active': filter === f }"
        @click="filter = f"
      >
        {{ t(`superAdmin.filter.${f}`) }}
        <span class="sa-tab-count">{{ counts[f] }}</span>
      </button>
    </div>

    <!-- Error -->
    <div v-if="errorText" class="alert alert--error" style="margin-top: var(--space-4)">
      {{ errorText }}
    </div>

    <!-- Loading -->
    <div v-if="loading" class="sa-loading">
      <span class="spinner spinner--lg" />
    </div>

    <!-- Empty state -->
    <div v-else-if="filteredClubs.length === 0" class="sa-empty">
      <p>{{ t('superAdmin.empty') }}</p>
    </div>

    <!-- Club list -->
    <div v-else class="sa-list">
      <div
        v-for="club in filteredClubs"
        :key="club.id"
        class="sa-club-card"
        :class="{ 'sa-club-card--duplicate': club.duplicate_count > 0 }"
      >
        <div class="sa-club-header">
          <div>
            <h3 class="sa-club-name">{{ club.name }}</h3>
            <span class="sa-club-city">{{ club.city }}</span>
            <span v-if="club.address" class="sa-club-address">&middot; {{ club.address }}</span>
          </div>
          <span class="badge" :class="`badge--${club.status === 'active' ? 'success' : club.status === 'rejected' ? 'danger' : 'warning'}`">
            {{ t(`superAdmin.status.${club.status}`) }}
          </span>
        </div>

        <div v-if="club.duplicate_count > 0" class="alert alert--warning sa-duplicate-alert">
          {{ t('superAdmin.duplicateWarning', { count: club.duplicate_count }) }}
        </div>

        <div class="sa-club-details">
          <div class="sa-detail">
            <span class="sa-detail-label">{{ t('superAdmin.owner') }}</span>
            <span class="sa-detail-value">{{ club.owner_first_name }} {{ club.owner_last_name }}</span>
          </div>
          <div class="sa-detail">
            <span class="sa-detail-label">{{ t('clubRegistration.fields.email') }}</span>
            <span class="sa-detail-value">{{ club.owner_email }}</span>
          </div>
          <div class="sa-detail" v-if="club.owner_phone">
            <span class="sa-detail-label">{{ t('clubRegistration.fields.phone') }}</span>
            <span class="sa-detail-value">{{ club.owner_phone }}</span>
          </div>
          <div class="sa-detail">
            <span class="sa-detail-label">{{ t('superAdmin.submittedAt') }}</span>
            <span class="sa-detail-value">{{ formatDate(club.created_at) }}</span>
          </div>
          <div class="sa-detail" v-if="club.contact_phone">
            <span class="sa-detail-label">{{ t('superAdmin.contactPhone') }}</span>
            <span class="sa-detail-value">{{ club.contact_phone }}</span>
          </div>
        </div>

        <p v-if="club.status === 'rejected' && club.rejection_reason" class="sa-rejection-reason">
          {{ t('superAdmin.rejectionReason') }}: {{ club.rejection_reason }}
        </p>

        <!-- Actions for pending clubs -->
        <div v-if="club.status === 'pending'" class="sa-club-actions">
          <template v-if="rejectingId === club.id">
            <div class="form-field sa-reject-field">
              <textarea
                v-model="rejectReason"
                class="input"
                rows="2"
                :placeholder="t('superAdmin.rejectReasonPlaceholder')"
              />
            </div>
            <div class="sa-reject-actions">
              <button class="btn btn--ghost btn--sm" @click="cancelReject">{{ t('superAdmin.cancel') }}</button>
              <button class="btn btn--danger btn--sm" :disabled="actionLoading === club.id" @click="confirmReject">
                <span v-if="actionLoading === club.id" class="spinner" aria-hidden="true" />
                {{ t('superAdmin.confirmReject') }}
              </button>
            </div>
          </template>
          <template v-else>
            <button class="btn btn--success btn--sm" :disabled="actionLoading === club.id" @click="approveClub(club.id)">
              <span v-if="actionLoading === club.id" class="spinner" aria-hidden="true" />
              {{ t('superAdmin.approve') }}
            </button>
            <button class="btn btn--danger btn--sm" @click="startReject(club.id)">
              {{ t('superAdmin.reject') }}
            </button>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
