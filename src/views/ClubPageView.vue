<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'

import JoinClubButton from '../components/JoinClubButton.vue'
import { clubContext, headerTitle } from '../lib/headerTitle'
import { supabase } from '../lib/supabase'
import { useAuthStore } from '../stores/auth'

const props = defineProps({
  slug: { type: String, required: true },
})

const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const auth = useAuthStore()

const loading = ref(true)
const data = ref(null)
const errorText = ref('')
const joinButton = ref(null)

const org = computed(() => data.value?.org ?? null)
const tournaments = computed(() => data.value?.tournaments ?? [])
const members = computed(() => data.value?.members_preview ?? [])
const memberCount = computed(() => data.value?.members_count ?? 0)
const myMembership = computed(() => data.value?.my_membership ?? null)

const extraMembers = computed(() => Math.max(0, memberCount.value - members.value.length))

const orgTypeLabel = computed(() => {
  const type = org.value?.type
  if (type === 'coach') return t('club.page.typeCoach')
  return t('club.page.typeClub')
})

async function load() {
  loading.value = true
  errorText.value = ''
  const { data: res, error } = await supabase.rpc('club_page_data', { p_slug: props.slug })
  loading.value = false
  if (error) {
    errorText.value = error.message
    return
  }
  data.value = res
}

function initials(name) {
  if (!name) return '?'
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part.charAt(0).toUpperCase())
    .join('')
}

function tournamentBadgeClass(status) {
  if (status === 'completed') return 'badge--success'
  if (status === 'in_progress' || status === 'registration_open') return 'badge--warn'
  if (status === 'registration_closed') return 'badge--danger'
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

function onMembershipChanged() {
  load()
}

// Auto-trigger join if we arrived via OAuth with ?action=join
async function handleAutoJoin() {
  if (route.query.action !== 'join' || !auth.user) return
  // Wait until data + player context loaded so JoinClubButton has the latest state
  await auth.loadPlayerContext()
  await load()
  await nextTick()

  // Skip if already active/pending
  const st = myMembership.value?.status
  if (st === 'active' || st === 'pending') {
    router.replace({ query: {} })
    return
  }

  try {
    await joinButton.value?.join()
  } finally {
    router.replace({ query: {} })
  }
}

onMounted(async () => {
  await auth.init()
  if (auth.user) await auth.loadPlayerContext()
  await load()
  await handleAutoJoin()
})

watch(() => props.slug, async () => {
  await load()
})

const defaultTitle = typeof document !== 'undefined' ? document.title : ''
watch(
  () => org.value?.name,
  (name) => {
    if (typeof document === 'undefined') return
    document.title = name ? `${orgTypeLabel.value}: ${name}` : defaultTitle
    headerTitle.value = name ?? ''
  },
  { immediate: true },
)
watch(
  [() => org.value?.id, () => myMembership.value],
  ([orgId, membership]) => {
    if (!orgId) {
      clubContext.value = null
      return
    }
    clubContext.value = {
      orgId,
      orgSlug: org.value?.slug ?? null,
      membership: membership ?? null,
      onChanged: onMembershipChanged,
    }
  },
  { immediate: true },
)
onUnmounted(() => {
  if (typeof document !== 'undefined') document.title = defaultTitle
  headerTitle.value = ''
  clubContext.value = null
})
</script>

<template>
  <div class="stack stack--lg">
    <div v-if="loading" class="muted">{{ t('club.page.loading') }}</div>

    <div v-else-if="!org" class="empty-state">
      <h2>{{ t('club.page.notFound') }}</h2>
      <p class="muted">{{ t('club.page.notFoundHint') }}</p>
      <p v-if="errorText" class="error-text">{{ errorText }}</p>
    </div>

    <template v-else>
      <!-- Hero -->
      <section class="card card--elevated stack">
        <div class="club-hero">
          <div class="club-hero__logo">
            <img v-if="org.logo_url" :src="org.logo_url" :alt="org.name" />
            <span v-else>{{ initials(org.name) }}</span>
          </div>
          <div class="stack stack--sm" style="flex:1; min-width:0;">
            <div class="badge-row">
              <span class="badge badge--neutral">{{ orgTypeLabel }}</span>
              <span v-if="org.auto_approve_members" class="badge badge--success">
                {{ t('club.page.openClubText') }}
              </span>
              <span v-else class="badge badge--warn">
                {{ t('club.page.closedClubText') }}
              </span>
              <span v-if="data?.is_owner" class="badge badge--neutral">
                {{ t('club.join.primary') }}
              </span>
            </div>
            <h1 class="page-title">{{ org.name }}</h1>
            <p v-if="org.city || org.country" class="muted">
              {{ [org.city, org.country].filter(Boolean).join(', ') }}
            </p>
            <p v-if="org.description">{{ org.description }}</p>
            <p class="muted">
              <strong>{{ memberCount }}</strong> {{ t('club.page.membersCount') }}
            </p>
          </div>
          <div class="club-hero__cta">
            <JoinClubButton
              ref="joinButton"
              :org-slug="org.slug"
              :auto-approve="org.auto_approve_members"
              :membership="myMembership"
              @updated="onMembershipChanged"
            />
          </div>
        </div>
      </section>

      <div class="grid-2">
        <!-- Tournaments -->
        <section class="card stack stack--sm">
          <h2 class="section-title">{{ t('club.page.tournamentsTitle') }}</h2>
          <p v-if="tournaments.length === 0" class="muted">{{ t('club.page.tournamentsEmpty') }}</p>
          <ul v-else class="club-tournaments">
            <li v-for="tr in tournaments" :key="tr.id">
              <RouterLink :to="{ name: 'public-tournament', params: { slug: tr.slug } }" class="club-tournament-card">
                <div class="club-tournament-card__head">
                  <span class="club-tournament-card__name">{{ tr.name }}</span>
                  <span class="badge" :class="tournamentBadgeClass(tr.status)">
                    {{ t(`tournament.${tr.status}`) }}
                  </span>
                </div>
                <div class="muted">{{ formatDate(tr.created_at) }}</div>
              </RouterLink>
            </li>
          </ul>
        </section>

        <!-- Members preview -->
        <section class="card stack stack--sm">
          <h2 class="section-title">{{ t('club.page.membersTitle') }}</h2>
          <p v-if="members.length === 0" class="muted">{{ t('club.page.membersEmpty') }}</p>
          <div v-else class="members-grid">
            <div v-for="m in members" :key="m.id" class="member-chip" :title="m.display_name">
              <img v-if="m.avatar_url" :src="m.avatar_url" :alt="m.display_name" />
              <span v-else>{{ initials(m.display_name) }}</span>
            </div>
            <div v-if="extraMembers > 0" class="member-chip member-chip--more">
              +{{ extraMembers }}
            </div>
          </div>
        </section>
      </div>
    </template>
  </div>
</template>

<style scoped>
.club-hero {
  display: flex;
  gap: var(--space-4);
  align-items: flex-start;
  flex-wrap: wrap;
}
.club-hero__logo {
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
.club-hero__logo img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.club-hero__cta {
  flex-shrink: 0;
}
@media (max-width: 640px) {
  .club-hero__cta {
    width: 100%;
  }
}

.club-tournaments {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}
.club-tournament-card {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: var(--space-2) var(--space-3);
  border-radius: var(--radius-sm);
  background: var(--surface-row, rgba(255, 255, 255, 0.03));
  text-decoration: none;
  color: inherit;
  border: 1px solid transparent;
  transition: border-color 0.15s, background 0.15s;
}
.club-tournament-card:hover {
  border-color: rgba(255, 255, 255, 0.12);
}
.club-tournament-card__head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: var(--space-2);
}
.club-tournament-card__name {
  font-weight: 600;
}

.members-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(56px, 1fr));
  gap: var(--space-2);
}
.member-chip {
  width: 56px;
  height: 56px;
  border-radius: 50%;
  background: var(--bg-elevated, rgba(255, 255, 255, 0.04));
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: var(--font-display);
  font-size: 1rem;
  color: var(--primary);
  overflow: hidden;
  border: 1px solid rgba(255, 255, 255, 0.05);
}
.member-chip img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.member-chip--more {
  font-size: 0.875rem;
  color: var(--muted);
  font-family: var(--font-body);
  background: transparent;
  border: 1px dashed rgba(255, 255, 255, 0.15);
}
</style>
