<script setup>
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'

const props = defineProps({
  match: {
    type: Object,
    required: true,
  },
  setsByMatch: {
    type: Object,
    default: () => ({}),
  },
  entriesMap: {
    type: Object,
    default: () => ({}),
  },
  editableSlots: {
    type: Boolean,
    default: false,
  },
})

const emit = defineEmits(['swap-slots'])

const { t } = useI18n()

const dragOverKey = ref(null)

function entryName(entryId) {
  if (!entryId) {
    return t('bracket.tbd')
  }
  return props.entriesMap[entryId]?.display_name || t('bracket.tbd')
}

function setSummary(matchId) {
  const sets = [...(props.setsByMatch[matchId] || [])].sort((a, b) => a.set_index - b.set_index)
  if (!sets.length) {
    return '—'
  }
  return sets.map((set) => `${set.side_a_games}:${set.side_b_games}`).join(' · ')
}

const matchFinished = () => props.match.status === 'finished'

function rowKey(side) {
  return `${props.match.id}-${side}`
}

function onDragStart(event, side, entryId) {
  if (!props.editableSlots || matchFinished() || !entryId) {
    event.preventDefault()
    return
  }
  event.dataTransfer.setData(
    'application/json',
    JSON.stringify({ matchId: props.match.id, side }),
  )
  event.dataTransfer.effectAllowed = 'move'
  try {
    event.dataTransfer.setDragImage(event.currentTarget, event.currentTarget.offsetWidth / 2, 16)
  } catch {
    /* ignore */
  }
}

function onDragEnd() {
  dragOverKey.value = null
}

function onDragOver(event, side) {
  if (!props.editableSlots || matchFinished()) {
    return
  }
  event.preventDefault()
  event.dataTransfer.dropEffect = 'move'
  dragOverKey.value = rowKey(side)
}

function onDragLeave(event, side) {
  if (event.currentTarget.contains(event.relatedTarget)) {
    return
  }
  if (dragOverKey.value === rowKey(side)) {
    dragOverKey.value = null
  }
}

function onDrop(event, toSide) {
  dragOverKey.value = null
  if (!props.editableSlots || matchFinished()) {
    return
  }
  event.preventDefault()
  let payload
  try {
    payload = JSON.parse(event.dataTransfer.getData('application/json') || '{}')
  } catch {
    return
  }
  if (!payload.matchId || !payload.side) {
    return
  }
  const fromSide = payload.side
  const fromMatchId = payload.matchId
  if (fromMatchId === props.match.id && fromSide === toSide) {
    return
  }
  emit('swap-slots', {
    fromMatchId,
    fromSide,
    toMatchId: props.match.id,
    toSide,
  })
}

function rowClass(side, entryId, winner) {
  const k = rowKey(side)
  return {
    'match-card__row--winner': winner,
    'match-card__row--slot-editable': props.editableSlots && !matchFinished(),
    'match-card__row--drag-over': dragOverKey.value === k && props.editableSlots && !matchFinished(),
    'match-card__row--draggable': props.editableSlots && !matchFinished() && Boolean(entryId),
  }
}
</script>

<template>
  <article class="match-card" :data-match-id="match.id">
    <div
      class="match-card__row"
      :class="rowClass('a', match.side_a_entry_id, match.winner_entry_id === match.side_a_entry_id)"
      :draggable="editableSlots && !matchFinished() && Boolean(match.side_a_entry_id)"
      @dragstart="onDragStart($event, 'a', match.side_a_entry_id)"
      @dragend="onDragEnd"
      @dragover="onDragOver($event, 'a')"
      @dragleave="onDragLeave($event, 'a')"
      @drop="onDrop($event, 'a')"
    >
      <span class="match-card__name">{{ entryName(match.side_a_entry_id) }}</span>
    </div>
    <div
      class="match-card__row"
      :class="rowClass('b', match.side_b_entry_id, match.winner_entry_id === match.side_b_entry_id)"
      :draggable="editableSlots && !matchFinished() && Boolean(match.side_b_entry_id)"
      @dragstart="onDragStart($event, 'b', match.side_b_entry_id)"
      @dragend="onDragEnd"
      @dragover="onDragOver($event, 'b')"
      @dragleave="onDragLeave($event, 'b')"
      @drop="onDrop($event, 'b')"
    >
      <span class="match-card__name">{{ entryName(match.side_b_entry_id) }}</span>
    </div>
    <div class="match-card__meta">
      {{ t('tournament.sets') }}: <span class="match-card__score">{{ setSummary(match.id) }}</span>
    </div>
  </article>
</template>
