import { ref } from 'vue'

export const headerTitle = ref('')

// { orgId, orgSlug, membership: { id, status, is_primary } | null, onChanged: () => void }
export const clubContext = ref(null)
