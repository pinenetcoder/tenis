<script setup>
import { computed, reactive, watch } from 'vue'
import { useI18n } from 'vue-i18n'

import { supabase } from '../lib/supabase'

const props = defineProps({
  matches: {
    type: Array,
    default: () => [],
  },
  setsByMatch: {
    type: Object,
    default: () => ({}),
  },
  entriesMap: {
    type: Object,
    default: () => ({}),
  },
  setFormat: {
    type: String,
    default: 'best_of_3',
  },
})

const emit = defineEmits(['saved'])

const { t } = useI18n()
const setForms = reactive({})
const savedFlash = reactive({})

const totalSetRows = () => (props.setFormat === 'best_of_5' ? 5 : 3)

function initializeRows(matchId) {
  const existing = [...(props.setsByMatch[matchId] || [])].sort((a, b) => a.set_index - b.set_index)
  const rows = []

  for (let i = 1; i <= totalSetRows(); i += 1) {
    const saved = existing.find((item) => item.set_index === i)
    rows.push({
      set_index: i,
      side_a_games: saved ? saved.side_a_games : '',
      side_b_games: saved ? saved.side_b_games : '',
      saving: false,
      error: '',
    })
  }

  setForms[matchId] = rows
}

watch(
  () => [props.matches, props.setsByMatch, props.setFormat],
  () => {
    props.matches.forEach((match) => {
      initializeRows(match.id)
    })
  },
  { immediate: true, deep: true },
)

const matchesByRound = computed(() => {
  const map = new Map()
  for (const m of props.matches) {
    if (!map.has(m.round_number)) {
      map.set(m.round_number, [])
    }
    map.get(m.round_number).push(m)
  }
  return [...map.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([roundNumber, list]) => ({
      roundNumber,
      matches: list.sort((a, b) => a.match_number - b.match_number),
    }))
})

function entryName(entryId) {
  if (!entryId) {
    return t('bracket.tbd')
  }
  return props.entriesMap[entryId]?.display_name || t('bracket.tbd')
}

function canScore(match) {
  return Boolean(match.side_a_entry_id && match.side_b_entry_id)
}

async function save(match) {
  const rows = setForms[match.id] || []
  rows.forEach((row) => {
    row.error = ''
  })

  const payload = rows
    .filter((row) => row.side_a_games !== '' && row.side_b_games !== '' && row.side_a_games != null && row.side_b_games != null)
    .map((row) => ({
      set_index: row.set_index,
      side_a_games: Number(row.side_a_games),
      side_b_games: Number(row.side_b_games),
    }))

  rows.forEach((row) => {
    row.saving = true
  })

  const { error } = await supabase.rpc('update_match_sets', {
    p_match_id: match.id,
    p_sets: payload,
  })

  rows.forEach((row) => {
    row.saving = false
  })

  if (error) {
    if (rows[0]) {
      rows[0].error = error.message
    }
    return
  }

  savedFlash[match.id] = true
  setTimeout(() => {
    savedFlash[match.id] = false
  }, 1200)

  emit('saved')
}
</script>

<template>
  <section class="card score-editor">
    <h2 class="section-title">{{ t('admin.saveScore') }}</h2>
    <p class="muted">{{ t('admin.setsHint') }}</p>

    <template v-for="group in matchesByRound" :key="group.roundNumber">
      <h3 class="section-title" style="font-size: 1rem; margin-top: var(--space-3)">
        {{ t('bracket.roundN', { n: group.roundNumber }) }}
      </h3>

      <article
        v-for="match in group.matches"
        :key="match.id"
        class="score-match"
        :class="{ 'score-match--saved': savedFlash[match.id] }"
      >
        <div class="score-match__head">
          {{ entryName(match.side_a_entry_id) }}
          <span class="muted" style="margin: 0 0.35rem">vs</span>
          {{ entryName(match.side_b_entry_id) }}
        </div>

        <div class="score-match__sets">
          <div
            v-for="row in setForms[match.id] || []"
            :key="`${match.id}-${row.set_index}`"
            class="score-set-row"
          >
            <span class="score-set-row__label">{{ t('tournament.sets') }} {{ row.set_index }}</span>
            <div class="score-set-row__inputs">
              <label class="score-set">
                <span class="label">A</span>
                <input
                  v-model="row.side_a_games"
                  type="number"
                  min="0"
                  max="7"
                  class="input"
                  :disabled="!canScore(match) || row.saving"
                />
              </label>
              <span class="muted" aria-hidden="true">:</span>
              <label class="score-set">
                <span class="label">B</span>
                <input
                  v-model="row.side_b_games"
                  type="number"
                  min="0"
                  max="7"
                  class="input"
                  :disabled="!canScore(match) || row.saving"
                />
              </label>
            </div>
          </div>
        </div>

        <button class="btn btn--primary btn--sm" type="button" :disabled="!canScore(match)" @click="save(match)">
          {{ t('admin.saveScore') }}
        </button>

        <p v-if="(setForms[match.id] || [])[0]?.error" class="error-text" style="margin-top: var(--space-2)">
          {{ (setForms[match.id] || [])[0]?.error }}
        </p>
      </article>
    </template>

    <p v-if="!matches.length" class="muted">{{ t('bracket.empty') }}</p>
  </section>
</template>
