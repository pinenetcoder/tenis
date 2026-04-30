<script setup>
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'

import { pointLabel, scoreLine } from '../lib/useTennisScoring'
import { supabase } from '../lib/supabase'

const props = defineProps({
  match: {
    type: Object,
    required: true,
  },
  liveScore: {
    type: Object,
    default: null,
  },
  teamA: {
    type: String,
    required: true,
  },
  teamB: {
    type: String,
    required: true,
  },
})

const emit = defineEmits(['close', 'changed'])

const { t } = useI18n()

const currentLiveScore = ref(props.liveScore)
const loading = ref(false)
const errorText = ref('')

watch(
  () => props.liveScore,
  (next) => {
    if (next && next.match_id === props.match.id) {
      currentLiveScore.value = next
    }
  },
  { deep: true },
)

const state = computed(() => currentLiveScore.value?.state || null)
const revision = computed(() => currentLiveScore.value?.revision ?? 0)
const canUndo = computed(() => (currentLiveScore.value?.history || []).length > 0)
const isFinished = computed(() => currentLiveScore.value?.status === 'finished' || Boolean(state.value?.winner))
const isStopped = computed(() => currentLiveScore.value?.status === 'stopped')
const statusText = computed(() => {
  if (isFinished.value) return t('live.finished')
  if (isStopped.value) return t('live.stopped')
  return t('live.active')
})

async function ensureStarted() {
  if (currentLiveScore.value?.status === 'active' || currentLiveScore.value?.status === 'finished') {
    return
  }
  loading.value = true
  errorText.value = ''

  const { data, error } = await supabase.rpc('start_live_match', {
    p_match_id: props.match.id,
  })

  loading.value = false
  if (error) {
    errorText.value = error.message
    return
  }

  currentLiveScore.value = data
  emit('changed')
}

async function record(side) {
  if (loading.value || isFinished.value) return

  await ensureStarted()
  if (!currentLiveScore.value || currentLiveScore.value.status !== 'active') {
    return
  }

  loading.value = true
  errorText.value = ''

  const { data, error } = await supabase.rpc('record_point', {
    p_match_id: props.match.id,
    p_side: side,
    p_expected_revision: revision.value,
  })

  loading.value = false
  if (error) {
    errorText.value = error.message
    emit('changed')
    return
  }

  currentLiveScore.value = data
  emit('changed')
}

async function stopLive() {
  if (loading.value || !currentLiveScore.value || isFinished.value) return
  loading.value = true
  errorText.value = ''

  const { data, error } = await supabase.rpc('stop_live_match', {
    p_match_id: props.match.id,
  })

  loading.value = false
  if (error) {
    errorText.value = error.message
    return
  }

  currentLiveScore.value = data
  emit('changed')
}
</script>

<template>
  <div class="modal-backdrop" @click="emit('close')">
    <div class="modal-dialog live-modal" role="dialog" aria-modal="true" @click.stop>
      <div class="modal-dialog__head">
        <div>
          <h2>{{ t('live.scoringTitle') }}</h2>
          <p class="muted">{{ statusText }} · rev {{ revision }}</p>
        </div>
        <button class="modal-close" type="button" :aria-label="t('actions.close')" @click="emit('close')">×</button>
      </div>

      <div class="live-scoreboard">
        <div class="live-scoreboard__row">
          <strong>{{ teamA }}</strong>
          <span class="live-scoreboard__point">{{ pointLabel(state, 'a') }}</span>
        </div>
        <div class="live-scoreboard__row">
          <strong>{{ teamB }}</strong>
          <span class="live-scoreboard__point">{{ pointLabel(state, 'b') }}</span>
        </div>
      </div>

      <p class="live-scoreboard__sets">{{ scoreLine(state) }}</p>

      <div v-if="state?.isTiebreak" class="alert alert--info" role="status">
        {{ t('live.tiebreak') }}
      </div>

      <div class="live-controls">
        <button class="btn btn--primary" type="button" :disabled="loading || isFinished" @click="record('a')">
          + {{ teamA }}
        </button>
        <button class="btn btn--primary" type="button" :disabled="loading || isFinished" @click="record('b')">
          + {{ teamB }}
        </button>
        <button class="btn btn--ghost" type="button" :disabled="loading || !canUndo || isFinished" @click="record('undo')">
          {{ t('live.undo') }}
        </button>
        <button
          v-if="isStopped"
          class="btn btn--ghost"
          type="button"
          :disabled="loading"
          @click="ensureStarted"
        >
          {{ t('live.start') }}
        </button>
        <button
          v-else
          class="btn btn--ghost"
          type="button"
          :disabled="loading || isFinished"
          @click="stopLive"
        >
          {{ t('live.stop') }}
        </button>
      </div>

      <p v-if="errorText" class="error-text">{{ errorText }}</p>
    </div>
  </div>
</template>
